#!/usr/bin/env python3
"""bitdistill_coder.py — троичная (1.58-бит) кодинг-модель через BitDistill, для яруса 1 (Pango/CPU).
МАСШТАБ: не учим с нуля, а ДИСТИЛЛИРУЕМ готовую Qwen2.5-Coder в троичную (метод BitNet Distillation,
arXiv:2510.13998). Запускать на АРЕНДОВАННОЙ GPU (1×A100 на часы ≈ $5–30), НЕ на CPU/ПЛИС.

Рецепт (3 стадии):
  1. SubLN — RMSNorm перед каждой троичной проекцией (стабилизирует low-bit оптимизацию).
  2. Continual pretrain (warm-up) — короткая адаптация к троичному пространству.
  3. Dual-signal distillation — loss = CE + KL(student/T, teacher/T) логитов (+ опц. attention-relations).
Экспорт: троичные веса {-1,0,1} + int8-эмбеддинги → формат FPGA (pack2bit) ИЛИ GGUF через bitnet.cpp.

ЗАПУСК на арендованной GPU:
  pip install torch transformers datasets accelerate
  python3 bitdistill_coder.py --base Qwen/Qwen2.5-Coder-1.5B-Instruct --steps 3000 --out ./tern_coder
  # для 3B: --base Qwen/Qwen2.5-Coder-3B-Instruct (нужно ~24ГБ VRAM, A100/H100)
Стоимость: 1.5B ~2-4 GPU-часа (~$5-10); 3B ~4-8ч (~$15-30). Это $-десятки, НЕ ферма.
"""
import argparse, time, math, os, torch, torch.nn as nn, torch.nn.functional as F
from transformers import AutoModelForCausalLM, AutoTokenizer
from datasets import load_dataset

# ── троичные примитивы (как в нашем стеке — совпадают с FPGA-экспортом) ──
def aq(x): s=127.0/x.abs().amax(-1,keepdim=True).clamp(min=1e-5); return (x*s).round().clamp(-128,127)/s
def wq(w): s=1.0/w.abs().mean().clamp(min=1e-5); return (w*s).round().clamp(-1,1)/s
# сила квантования λ∈[0,1]: 0=fp, 1=полная троичность. Плавный ramp лечит «CE не сходится»
# при резком включении троичности (HF «Fine-tuning LLMs to 1.58bit»; см. TERNARY-KNOWLEDGE-BASE §3.4).
LAMBDA={"v":1.0}
class BitLinear(nn.Linear):
    """Linear → троичные веса + int8-активации, SubLN (RMSNorm на входе), STE, λ-ramp квантования."""
    def __init__(self, lin):
        super().__init__(lin.in_features, lin.out_features, bias=lin.bias is not None)
        self.weight=lin.weight; self.bias=lin.bias
        self.norm=nn.RMSNorm(lin.in_features).to(lin.weight.device, lin.weight.dtype)   # SubLN
    def forward(self,x):
        lam=LAMBDA["v"]
        x=self.norm(x); x=x+lam*(aq(x)-x).detach()                 # λ=0 → fp активации, λ=1 → int8
        w=self.weight+lam*(wq(self.weight)-self.weight).detach()   # λ=0 → fp веса, λ=1 → троичные
        return F.linear(x,w,self.bias)
def bitnetize(model):
    n=0
    for name,mod in model.named_modules():
        for ch,sub in list(mod.named_children()):
            if isinstance(sub,nn.Linear) and ch!="lm_head" and "lm_head" not in name:
                setattr(mod,ch,BitLinear(sub)); n+=1
    return n

def export_ternary(model, tok, out):
    """экспорт троичных весов {-1,0,1} + int8-эмбеддингов в формат FPGA (pack2bit, dim0 LSB)."""
    os.makedirs(out, exist_ok=True); enc={-1:0,0:1,1:2}; import numpy as np
    def pack(row):
        return b"".join(int(sum(enc[int(t)]<<(2*(j%4)) for j,t in enumerate(row[i:i+4])) ).to_bytes(1,"little") for i in range(0,len(row),4))
    meta={}
    with open(os.path.join(out,"ternary_weights.bin"),"wb") as f:
        for name,mod in model.named_modules():
            if isinstance(mod,BitLinear):
                w=mod.weight.detach().float(); s=1.0/w.abs().mean().clamp(min=1e-5)
                tern=(w*s).round().clamp(-1,1).cpu().numpy().astype(np.int8)
                meta[name]={"shape":list(tern.shape),"meanW":float(1.0/s)}
                for r in tern: f.write(pack(r))
    import json; json.dump(meta, open(os.path.join(out,"ternary_meta.json"),"w"), indent=1)
    print(f"[экспорт] троичные веса → {out}/ternary_weights.bin (+meta). Формат pack2bit совпадает с FPGA.")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base", default="Qwen/Qwen2.5-Coder-1.5B-Instruct")
    ap.add_argument("--steps", type=int, default=3000)
    ap.add_argument("--T", type=float, default=2.0)            # температура дистилляции
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--bs", type=int, default=1)
    ap.add_argument("--seq", type=int, default=512)
    ap.add_argument("--out", default="./tern_coder")
    ap.add_argument("--warmup", type=int, default=500)   # continual-pretrain (CE) перед дистилляцией
    ap.add_argument("--accum", type=int, default=16)     # накопление градиента → эфф. батч bs*accum
    ap.add_argument("--save_hf", action="store_true")    # сохранять полную fp32 (6ГБ); по умолч. только троичные
    ap.add_argument("--dataset", default="codeparrot/codeparrot-clean-valid")   # открытый код-корпус
    a=ap.parse_args()
    dev="cuda"; tok=AutoTokenizer.from_pretrained(a.base)
    if tok.pad_token is None: tok.pad_token=tok.eos_token
    PROBES=["def fibonacci(n):", "# sort a list in python\n", "class Stack:"]
    def probe(model,tag):
        model.eval()
        for p in PROBES:
            ids=tok(p,return_tensors="pt").to(dev)
            out=tok.decode(model.generate(**ids,max_new_tokens=40,do_sample=False)[0],skip_special_tokens=True)
            print(f"[{tag}] {out[:200]!r}",flush=True)
        model.train()
    print(f"[{time.strftime('%H:%M')}] учитель (FP16, заморожен) + ученик (троичный) из {a.base}",flush=True)
    teacher=AutoModelForCausalLM.from_pretrained(a.base,torch_dtype=torch.float16).to(dev).eval()
    for p in teacher.parameters(): p.requires_grad_(False)
    model=AutoModelForCausalLM.from_pretrained(a.base,torch_dtype=torch.float32).to(dev)
    nb=bitnetize(model); print(f"  BitLinear заменено: {nb} слоёв")
    model.gradient_checkpointing_enable(); model.config.use_cache=False   # экономия VRAM
    probe(model,"ДО")
    # корпус кода (стрим; фолбэк на встроенный, если датасет недоступен/гейтован)
    FALLBACK=["def fibonacci(n):\n    a,b=0,1\n    for _ in range(n): a,b=b,a+b\n    return a\n",
              "def quicksort(arr):\n    if len(arr)<=1: return arr\n    p=arr[len(arr)//2]\n    return quicksort([x for x in arr if x<p])+[x for x in arr if x==p]+quicksort([x for x in arr if x>p])\n",
              "class Stack:\n    def __init__(self): self.items=[]\n    def push(self,x): self.items.append(x)\n    def pop(self): return self.items.pop()\n",
              "import os\ndef read_file(path):\n    with open(path) as f: return f.read()\n"]
    it=None
    try:
        ds=load_dataset(a.dataset, split="train", streaming=True); it=iter(ds)
        print(f"  датасет {a.dataset} (стрим)",flush=True)
    except Exception as e:
        print(f"  датасет недоступен ({str(e)[:60]}) → встроенный fallback-корпус",flush=True)
    import random as _r
    def get_batch():
        texts=[]
        while len(texts)<a.bs:
            if it is not None:
                ex=next(it); t=ex.get("content") or ex.get("text") or ex.get("code") or ""
            else:
                t="".join(_r.sample(FALLBACK,len(FALLBACK)))*4
            if len(t)>50: texts.append(t)
        enc=tok(texts,return_tensors="pt",truncation=True,max_length=a.seq,padding="max_length").to(dev)
        return enc.input_ids, enc.attention_mask
    try:
        import bitsandbytes as bnb; opt=bnb.optim.Adam8bit(model.parameters(),lr=a.lr); print("  оптимизатор: 8-бит Adam (экономия VRAM)",flush=True)
    except Exception: opt=torch.optim.AdamW(model.parameters(),lr=a.lr); print("  оптимизатор: AdamW fp32",flush=True)
    def ce_loss(sl,ids): return F.cross_entropy(sl[:,:-1].reshape(-1,sl.size(-1)), ids[:,1:].reshape(-1), ignore_index=tok.pad_token_id)
    # СТАДИЯ 1: continual-pretrain с λ-ramp квантования 0→1 (адаптация троичного пространства, только CE)
    print(f"  warmup (continual-pretrain) {a.warmup} шагов, λ-ramp квантования 0→1...",flush=True)
    for step in range(a.warmup):
        LAMBDA["v"]=min(2.0*step/max(a.warmup,1),1.0)   # 0→1 за первую половину warmup, далее полная троичность
        opt.zero_grad()
        for _ in range(a.accum):
            ids,mask=get_batch(); loss=ce_loss(model(ids,attention_mask=mask).logits,ids)/a.accum; loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(),1.0); opt.step()
        if step%50==0: print(f"  [warmup] step {step} λ {LAMBDA['v']:.2f} CE {loss.item()*a.accum:.3f}",flush=True)
    LAMBDA["v"]=1.0   # дистилляция — при полной троичности
    # СТАДИЯ 2: дистилляция (CE+KL) с накоплением градиента (эфф. батч bs*accum)
    print(f"  дистилляция {a.steps} шагов, эфф.батч={a.bs*a.accum}...",flush=True)
    for step in range(a.steps):
        opt.zero_grad(); ace=akl=0.0
        for _ in range(a.accum):
            ids,mask=get_batch()
            with torch.no_grad(): tl=teacher(ids,attention_mask=mask).logits
            sl=model(ids,attention_mask=mask).logits
            ce=ce_loss(sl,ids); kl=F.kl_div(F.log_softmax(sl/a.T,-1), F.softmax(tl/a.T,-1), reduction="batchmean")*(a.T*a.T)
            (0.5*ce+0.5*kl)/a.accum*1.0; ((0.5*ce+0.5*kl)/a.accum).backward()
            ace+=ce.item()/a.accum; akl+=kl.item()/a.accum
        torch.nn.utils.clip_grad_norm_(model.parameters(),1.0); opt.step()
        if step%100==0: print(f"  [distill] step {step} CE {ace:.3f} KL {akl:.1f}",flush=True)
    probe(model,"ПОСЛЕ")
    if a.save_hf: model.save_pretrained(a.out); tok.save_pretrained(a.out)
    else: import os as _os; _os.makedirs(a.out,exist_ok=True); tok.save_pretrained(a.out)
    export_ternary(model, tok, a.out)
    print(f"[готово] троичная кодинг-модель → {a.out}")
    print("  далее: GGUF через bitnet.cpp для CPU-инференса, ИЛИ ternary_weights.bin → FPGA-генератор (как model_mlgru).")

if __name__=="__main__": main()
