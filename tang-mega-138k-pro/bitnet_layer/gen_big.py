#!/usr/bin/env python3
"""gen_big.py — генерация из спасённого чекпойнта mlgru_big.pt (D192/L4 байтовый MLGRU)."""
import torch, torch.nn as nn, torch.nn.functional as F, numpy as np
V,D,L,S=256,192,4,64; H=2*D
def wq(w): s=1.0/w.abs().mean().clamp(min=1e-5); return (w*s).round().clamp(-1,1)/s
AQ_S=32.0
def aq(x): return (x*AQ_S).round().clamp(-127,127)/AQ_S
class BitLin(nn.Module):
    def __init__(s,i,o,norm=True): super().__init__(); s.l=nn.Linear(i,o,bias=False); s.n=nn.RMSNorm(i,elementwise_affine=False) if norm else None
    def forward(s,x):
        if s.n is not None: x=s.n(x)
        x=x+(aq(x)-x).detach(); w=s.l.weight+(wq(s.l.weight)-s.l.weight).detach(); return F.linear(x,w)
class MLGRU(nn.Module):
    def __init__(s): super().__init__(); s.f=BitLin(D,D); s.c=BitLin(D,D); s.g=BitLin(D,D); s.o=BitLin(D,D,norm=False)
    def forward(s,x):
        B,T,_=x.shape; f=torch.sigmoid(s.f(x)); c=F.silu(s.c(x)); g=torch.sigmoid(s.g(x))
        h=torch.zeros(B,D,device=x.device); outs=[]
        for t in range(T): h=f[:,t]*h+(1-f[:,t])*c[:,t]; outs.append(g[:,t]*h)
        return s.o(torch.stack(outs,1))
class GLU(nn.Module):
    def __init__(s): super().__init__(); s.g=BitLin(D,H); s.u=BitLin(D,H); s.d=BitLin(H,D,norm=False)
    def forward(s,x): return s.d(F.silu(s.g(x))*s.u(x))
class Block(nn.Module):
    def __init__(s): super().__init__(); s.mix=MLGRU(); s.ffn=GLU()
    def forward(s,x): x=x+s.mix(x); return x+s.ffn(x)
class Net(nn.Module):
    def __init__(s): super().__init__(); s.emb=nn.Embedding(V,D); s.ly=nn.ModuleList([Block() for _ in range(L)]); s.fn=nn.RMSNorm(D,elementwise_affine=False); s.out=BitLin(D,V,norm=False)
    def forward(s,seq):
        x=s.emb(seq)
        for l in s.ly: x=l(x)
        return s.out(s.fn(x))
m=Net(); m.load_state_dict(torch.load("mlgru_big.pt")); m.eval()
print(f"загружен mlgru_big.pt | параметров {sum(p.numel() for p in m.parameters())}")
def gen(prompt,n=200,temp=0.6):
    ids=list(np.frombuffer(prompt.encode(),dtype=np.uint8))
    for _ in range(n):
        ctx=torch.tensor([ids[-S:]],dtype=torch.long)
        lo=m(ctx)[0,-1]/temp; p=F.softmax(lo,-1); nt=int(torch.multinomial(p,1)); ids.append(nt)
        if nt==10 and len(ids)>len(prompt)+50: break
    return bytes(ids).decode("utf-8","replace")
print("\n── генерация D192/L4 (модель пишет ТЕКСТ по байтам) ──")
for pr in ["contact: ","contact: tank ","action: ","contact: enemy drone "]:
    print(f"  «{pr}» → {gen(pr)!r}")
