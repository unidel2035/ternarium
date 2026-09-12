#!/usr/bin/env python3
"""model_gen.py — ЭТАЛОН полного inference мелкой троичной модели + golden токены.
Конвейер: token→embed→[L слоёв block]→финальный RMSNorm→логиты(out_proj)→argmax→авторегрессия.
Fixed-point ровно как block_layer.v. Веса сгенерены (seeded) — модель не обучена (токены = доказательство
КОНВЕЙЕРА, не языка). Эмитит model_vectors.vh (веса + golden последовательность)."""
import numpy as np, math
np.random.seed(20260613)
V,D,L,H,S,NGEN = 16,8,2,8,4,6        # vocab, dim, слои, FFN hidden, окно контекста, сколько токенов сгенерить
SC=64; SMSCALE=8; SH_A,SH_F=9,12
LUT=[max(1,round(4096*math.exp(-k/4.0))) for k in range(32)]

def tern(r,c): return np.random.choice([-1,0,1],size=(r,c),p=[0.33,0.34,0.33]).astype(np.int64)
embed = np.random.randint(-5,6,size=(V,D)).astype(np.int64)         # int8 эмбеддинги
Wq=[tern(D,D) for _ in range(L)]; Wk=[tern(D,D) for _ in range(L)]; Wv=[tern(D,D) for _ in range(L)]
Wo=[tern(D,D) for _ in range(L)]; W1=[tern(H,D) for _ in range(L)]; W2=[tern(D,H) for _ in range(L)]
out_proj = tern(V,D)                                                # логиты

def isqrt(n):
    n=max(0,n); r=int(n**0.5)
    while r*r>n:r-=1
    while (r+1)*(r+1)<=n:r+=1
    return r
def tdiv(a,b): b=b or 1; return a//b if a>=0 else -((-a)//b)
def clamp(v): return max(-127,min(127,v))
def mv(W,x): return np.array([int(sum(int(W[r][c])*int(x[c]) for c in range(len(x)))) for r in range(W.shape[0])],dtype=np.int64)
def rms(x):
    ms=int((x*x).sum())//len(x); den=isqrt(ms*SC*SC) or 1
    return np.array([tdiv(int(xi)*SC*SC,den) for xi in x],dtype=np.int64)
def attn(Q,K,Vv):
    out=np.zeros((S,D),dtype=np.int64)
    for t in range(S):
        sc=np.array([int(Q[t]@K[j]) for j in range(S)]); mx=int(sc.max())
        w=np.array([LUT[min(31,(mx-int(sc[j]))//SMSCALE)] for j in range(S)],dtype=np.int64)
        num=np.zeros(D,dtype=np.int64)
        for j in range(S): num+=w[j]*Vv[j]
        out[t]=np.array([tdiv(int(num[d]),int(w.sum())) for d in range(D)])
    return out
def layer(X,l):
    n1=np.array([rms(X[t]) for t in range(S)])
    Q=np.array([mv(Wq[l],n1[t]) for t in range(S)]);K=np.array([mv(Wk[l],n1[t]) for t in range(S)]);Vv=np.array([mv(Wv[l],n1[t]) for t in range(S)])
    ctx=attn(Q,K,Vv); Hh=np.zeros((S,D),dtype=np.int64); Y=np.zeros((S,D),dtype=np.int64)
    for t in range(S):
        ao=np.array([clamp(tdiv(int(v),1<<SH_A)) for v in mv(Wo[l],ctx[t])])
        Hh[t]=np.array([clamp(int(X[t][d]+ao[d])) for d in range(D)])
    for t in range(S):
        n2=rms(Hh[t]); g=np.maximum(0,mv(W1[l],n2))
        fo=np.array([clamp(tdiv(int(v),1<<SH_F)) for v in mv(W2[l],g)])
        Y[t]=np.array([clamp(int(Hh[t][d]+fo[d])) for d in range(D)])
    return Y
def forward(seq):                         # seq: список из S токенов → логиты последней позиции
    X=np.array([embed[seq[t]] for t in range(S)],dtype=np.int64)
    for l in range(L): X=layer(X,l)
    xn=rms(X[S-1])
    return mv(out_proj,xn)                 # V логитов
def generate(seed):
    seq=list(seed); gen=[]
    for _ in range(NGEN):
        nt=int(np.argmax(forward(seq[-S:])))
        gen.append(nt); seq.append(nt)
    return gen

seed=[1,2,3,4]
toks=generate(seed)
print(f"V={V} D={D} L={L} H={H} S={S}")
print("seed:",seed,"→ сгенерённые токены:",toks)

# эмит весов + golden в model_vectors.vh
enc={-1:0,0:1,1:2}
def pk(v): return sum(enc[int(t)]<<(2*i) for i,t in enumerate(v))
with open("model_vectors.vh","w") as f:
    f.write(f"localparam V={V},D={D},L={L},H={H},S={S},NGEN={NGEN},SC={SC},SMSCALE={SMSCALE},SH_A={SH_A},SH_F={SH_F};\n")
    # эмбеддинги (int8) и out_proj
    for r in range(V):
        for c in range(D): f.write(f"localparam signed [7:0] EMB_{r}_{c}={int(embed[r][c])};\n")
    for r in range(V): f.write(f"localparam [2*D-1:0] OUTP_{r}=16'h{pk(out_proj[r]):04x};\n")
    for l in range(L):
        for nm,M in (("WQ",Wq[l]),("WK",Wk[l]),("WV",Wv[l]),("WO",Wo[l]),("W1",W1[l]),("W2",W2[l])):
            for r in range(M.shape[0]): f.write(f"localparam [2*D-1:0] {nm}_{l}_{r}=16'h{pk(M[r]):04x};\n")
    for k in range(32): f.write(f"localparam EXP_{k}={LUT[k]};\n")
    f.write(f"// golden токены\n")
    for i,t in enumerate(toks): f.write(f"localparam GTOK_{i}={t};\n")
    for i,t in enumerate(seed): f.write(f"localparam SEED_{i}={t};\n")
print("model_vectors.vh записан")
