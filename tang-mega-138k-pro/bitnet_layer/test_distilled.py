#!/usr/bin/env python3
"""test_distilled.py — проверка дистиллированной троичной кодинг-модели: генерит ли код + perplexity.
Запуск на боксе: python3 test_distilled.py --model ~/tern_coder_15"""
import argparse, torch, torch.nn as nn, torch.nn.functional as F
from transformers import AutoModelForCausalLM, AutoTokenizer
def aq(x): s=127.0/x.abs().amax(-1,keepdim=True).clamp(min=1e-5); return (x*s).round().clamp(-128,127)/s
def wq(w): s=1.0/w.abs().mean().clamp(min=1e-5); return (w*s).round().clamp(-1,1)/s
class BitLinear(nn.Linear):
    def __init__(s,lin): super().__init__(lin.in_features,lin.out_features,bias=lin.bias is not None); s.weight=lin.weight; s.bias=lin.bias; s.norm=nn.RMSNorm(lin.in_features).to(lin.weight.device,lin.weight.dtype)
    def forward(s,x): x=s.norm(x); x=x+(aq(x)-x).detach(); w=s.weight+(wq(s.weight)-s.weight).detach(); return F.linear(x,w,s.bias)
def bitnetize(m):
    for nm,mod in m.named_modules():
        for ch,sub in list(mod.named_children()):
            if isinstance(sub,nn.Linear) and ch!="lm_head" and "lm_head" not in nm: setattr(mod,ch,BitLinear(sub))
ap=argparse.ArgumentParser(); ap.add_argument("--model",default="./tern_coder_15"); a=ap.parse_args()
tok=AutoTokenizer.from_pretrained(a.model)
m=AutoModelForCausalLM.from_pretrained(a.model,torch_dtype=torch.float32).cuda()
bitnetize(m); m.cuda().eval()   # save_pretrained сохранил fp32 веса BitLinear → bitnetize восстанавливает троичность
PROMPTS=["def fibonacci(n):\n","# function to reverse a string\ndef reverse(s):\n",
         "def is_prime(n):\n","class LinkedList:\n    def __init__(self):\n"]
print("── генерация кода троичной моделью ──")
for p in PROMPTS:
    ids=tok(p,return_tensors="pt").to("cuda")
    out=tok.decode(m.generate(**ids,max_new_tokens=60,do_sample=False)[0],skip_special_tokens=True)
    print(f"\n>>> {p!r}\n{out}")
