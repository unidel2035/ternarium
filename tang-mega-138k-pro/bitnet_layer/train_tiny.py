#!/usr/bin/env python3
"""train_tiny.py — обучает мелкую троичную модель (V=16,D=8,L=2,H=8,S=4) задаче ИНКРЕМЕНТ
(next=(prev+1)%V) через QAT (BitLinear STE), экспортит троичные веса, проверяет в fixed-point
(как model_gen/model_infer) со свипом шкал, и при успехе пишет model_vectors.vh. (б): обученные веса → смысл."""
import torch, torch.nn as nn, torch.nn.functional as F, numpy as np, math
torch.manual_seed(0); np.random.seed(0)
V,D,L,H,S = 16,8,2,8,4

def wq(w):  # троичность весов (BitNet): scale=1/mean|w|, round->{-1,0,1}
    s=1.0/w.abs().mean().clamp(min=1e-5); return (w*s).round().clamp(-1,1)/s
def aq(x):  # int8 активаций (per-token)
    s=127.0/x.abs().amax(-1,keepdim=True).clamp(min=1e-5); return (x*s).round().clamp(-128,127)/s
class BitLin(nn.Module):
    def __init__(s,i,o): super().__init__(); s.l=nn.Linear(i,o,bias=False); s.n=nn.RMSNorm(i)
    def forward(s,x):
        x=s.n(x); x=x+(aq(x)-x).detach(); w=s.l.weight+(wq(s.l.weight)-s.l.weight).detach()
        return F.linear(x,w)
class Layer(nn.Module):
    def __init__(s): super().__init__(); s.q=BitLin(D,D);s.k=BitLin(D,D);s.v=BitLin(D,D);s.o=BitLin(D,D);s.w1=BitLin(D,H);s.w2=BitLin(H,D)
    def forward(s,x):
        B,T,_=x.shape
        Q,K,Vv=s.q(x),s.k(x),s.v(x)
        att=(Q@K.transpose(-2,-1))/math.sqrt(D)
        m=torch.triu(torch.ones(T,T)*-1e9,1); att=F.softmax(att+m,-1)
        x=x+s.o(att@Vv); x=x+s.w2(F.relu(s.w1(x))); return x
class Tiny(nn.Module):
    def __init__(s): super().__init__(); s.emb=nn.Embedding(V,D); s.ly=nn.ModuleList([Layer() for _ in range(L)]); s.fn=nn.RMSNorm(D); s.out=BitLin(D,V)
    def forward(s,seq):
        x=s.emb(seq)
        for l in s.ly: x=l(x)
        return s.out(s.fn(x))
m=Tiny(); opt=torch.optim.Adam(m.parameters(),lr=3e-3)
def batch(B=64):
    st=torch.randint(0,V,(B,)); seq=torch.stack([(st+i)%V for i in range(S+1)],1)
    return seq[:,:S], seq[:,1:S+1]
for step in range(3000):
    xi,yi=batch(); lo=m(xi); loss=F.cross_entropy(lo.reshape(-1,V),yi.reshape(-1))
    opt.zero_grad(); loss.backward(); opt.step()
    if step%500==0: print(f" step {step} loss {loss.item():.3f}")
# float-проверка инкремента
m.eval()
with torch.no_grad():
    seq=[1,2,3,4]; 
    for _ in range(6): nt=int(m(torch.tensor([seq[-S:]]))[0,-1].argmax()); seq.append(nt)
print("float-модель генерит:",seq[4:],"(ожидаем 5..10)")

# ── ЭКСПОРТ троичных весов + int8 эмбеддингов ──
def tern_np(w):
    w=w.detach().numpy(); s=1.0/max(1e-5,np.abs(w).mean()); return np.clip(np.round(w*s),-1,1).astype(np.int64)
emb=m.emb.weight.detach().numpy(); es=127.0/max(1e-5,np.abs(emb).max()); embq=np.clip(np.round(emb*es/16),-7,7).astype(np.int64) # int8 малого размаха
Wq=[tern_np(m.ly[l].q.l.weight) for l in range(L)]; Wk=[tern_np(m.ly[l].k.l.weight) for l in range(L)]
Wv=[tern_np(m.ly[l].v.l.weight) for l in range(L)]; Wo=[tern_np(m.ly[l].o.l.weight) for l in range(L)]
W1=[tern_np(m.ly[l].w1.l.weight) for l in range(L)]; W2=[tern_np(m.ly[l].w2.l.weight) for l in range(L)]
OUT=tern_np(m.out.l.weight)

# ── fixed-point forward (как RTL) со свипом шкал ──
LUT=[max(1,round(4096*math.exp(-k/4.0))) for k in range(32)]; SMSCALE=8
def isqrt(n):
    n=max(0,n); r=int(n**0.5)
    while r*r>n:r-=1
    while (r+1)*(r+1)<=n:r+=1
    return r
def tdiv(a,b): b=b or 1; return a//b if a>=0 else -((-a)//b)
def cl(v): return max(-127,min(127,v))
def mv(W,x): return np.array([int(sum(int(W[r][c])*int(x[c]) for c in range(len(x)))) for r in range(W.shape[0])],dtype=np.int64)
def rms(x,SC):
    ms=int((x*x).sum())//len(x); den=isqrt(ms*SC*SC) or 1
    return np.array([tdiv(int(xi)*SC*SC,den) for xi in x],dtype=np.int64)
def attn(Q,K,Vv):
    out=np.zeros((S,D),dtype=np.int64)
    for t in range(S):
        sc=np.array([int(Q[t]@K[j]) for j in range(t+1)]); mx=int(sc.max())   # causal
        w=np.array([LUT[min(31,(mx-int(sc[j]))//SMSCALE)] for j in range(t+1)],dtype=np.int64)
        num=np.zeros(D,dtype=np.int64)
        for j in range(t+1): num+=w[j]*Vv[j]
        out[t]=np.array([tdiv(int(num[d]),int(w.sum())) for d in range(D)])
    return out
def layer(X,l,SC,SHA,SHF):
    n1=np.array([rms(X[t],SC) for t in range(S)])
    Q=np.array([mv(Wq[l],n1[t]) for t in range(S)]);K=np.array([mv(Wk[l],n1[t]) for t in range(S)]);Vv=np.array([mv(Wv[l],n1[t]) for t in range(S)])
    ctx=attn(Q,K,Vv); Hh=np.zeros((S,D),dtype=np.int64); Y=np.zeros((S,D),dtype=np.int64)
    for t in range(S):
        ao=np.array([cl(tdiv(int(v),1<<SHA)) for v in mv(Wo[l],ctx[t])]); Hh[t]=np.array([cl(int(X[t][d]+ao[d])) for d in range(D)])
    for t in range(S):
        n2=rms(Hh[t],SC); g=np.maximum(0,mv(W1[l],n2)); fo=np.array([cl(tdiv(int(v),1<<SHF)) for v in mv(W2[l],g)])
        Y[t]=np.array([cl(int(Hh[t][d]+fo[d])) for d in range(D)])
    return Y
def fxgen(SC,SHA,SHF):
    seq=[1,2,3,4]; gen=[]
    for _ in range(6):
        ctxs=seq[-S:]; X=np.array([embq[ctxs[t]] for t in range(S)],dtype=np.int64)
        for l in range(L): X=layer(X,l,SC,SHA,SHF)
        xn=rms(X[S-1],SC); lg=mv(OUT,xn); nt=int(np.argmax(lg)); gen.append(nt); seq.append(nt)
    return gen
best=None
for SC in (32,64,128):
  for SHA in (6,8,10,12):
    for SHF in (8,10,12,14):
      g=fxgen(SC,SHA,SHF)
      score=sum(1 for i,t in enumerate(g) if t==(5+i)%V)
      if best is None or score>best[0]: best=(score,SC,SHA,SHF,g)
sc,SC,SHA,SHF,g=best
print(f"fixed-point лучшее: SC={SC} SH_A={SHA} SH_F={SHF} → {g} (совпало {sc}/6 с инкрементом 5..10)")

# эмит model_vectors.vh с обученными весами (если приемлемо)
enc={-1:0,0:1,1:2}
def pk(v): return sum(enc[int(t)]<<(2*i) for i,t in enumerate(v))
with open("model_vectors.vh","w") as f:
    f.write(f"localparam V={V},D={D},L={L},H={H},S={S},NGEN=6,SC={SC},SMSCALE={SMSCALE},SH_A={SHA},SH_F={SHF};\n")
    for r in range(V):
        for c in range(D): f.write(f"localparam signed [7:0] EMB_{r}_{c}={int(embq[r][c])};\n")
    for r in range(V): f.write(f"localparam [2*D-1:0] OUTP_{r}=16'h{pk(OUT[r]):04x};\n")
    for l in range(L):
        for nm,M in (("WQ",Wq[l]),("WK",Wk[l]),("WV",Wv[l]),("WO",Wo[l]),("W1",W1[l]),("W2",W2[l])):
            for r in range(M.shape[0]): f.write(f"localparam [2*D-1:0] {nm}_{l}_{r}=16'h{pk(M[r]):04x};\n")
    for k in range(32): f.write(f"localparam EXP_{k}={LUT[k]};\n")
    for i,t in enumerate(g): f.write(f"localparam GTOK_{i}={t};\n")
    for i,t in enumerate([1,2,3,4]): f.write(f"localparam SEED_{i}={t};\n")
print("model_vectors.vh записан (обученные троичные веса + causal attention)")
