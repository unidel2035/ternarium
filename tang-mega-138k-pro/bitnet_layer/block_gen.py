# Полный троичный трансформер-блок (fixed-point спека = то, что повторит RTL):
#  h = x + Oproj(Attn(RMSNorm(x))) ;  y = h + FFN(RMSNorm(h))
# Все веса тернарные (реальные BitNet), активации int, между под-слоями реквант (shift+clamp, как int8 BitNet).
import struct, numpy as np, math
GGUF="/home/unidel/tang/bitnet-2b-model/ggml-model-i2_s.gguf"; buf=open(GGUF,"rb").read(); off=0
def rd(f):
    global off; s=struct.calcsize(f); v=struct.unpack_from("<"+f,buf,off); off+=s; return v[0] if len(v)==1 else v
def rstr():
    global off; n=rd("Q"); s=buf[off:off+n].decode("utf-8","replace"); off+=n; return s
assert buf[:4]==b"GGUF"; off=4; rd("I"); nt=rd("Q"); nkv=rd("Q")
VT={0:"B",1:"b",2:"H",3:"h",4:"I",5:"i",6:"f",7:"B",10:"Q",11:"q",12:"d"}
def skip(vt):
    global off
    if vt==8: n=rd("Q"); off+=n
    elif vt==9:
        et=rd("I"); ln=rd("Q")
        for _ in range(ln):
            if et==8: n=rd("Q"); off+=n
            else: off+=struct.calcsize(VT[et])
    else: off+=struct.calcsize(VT[vt])
al=32
for _ in range(nkv):
    k=rstr(); vt=rd("I")
    if k=="general.alignment" and vt==4: al=struct.unpack_from("<I",buf,off)[0]
    skip(vt)
TS=[]
for _ in range(nt):
    nm=rstr(); nd=rd("I"); dims=[rd("Q") for _ in range(nd)]; tt=rd("I"); to=rd("Q"); TS.append((nm,dims,tt,to))
ds=(off+al-1)//al*al
def tensor(name):
    nm,dims,tt,to=next(t for t in TS if t[0]==name); nc=dims[0]
    raw=np.frombuffer(buf,dtype=np.uint8,count=(dims[0]*dims[1])//4,offset=ds+to)
    return nc, lambda k:(((int(raw[(k//128)*32+((k%128)%32)])>>(6-2*((k%128)//32)))&3)-1)
D,S=8,4
def mat(n):
    nc,tr=tensor(n); return np.array([[tr(r*nc+c) for c in range(D)] for r in range(D)],dtype=np.int64)
Wq=mat("blk.0.attn_q.weight");Wk=mat("blk.0.attn_k.weight");Wv=mat("blk.0.attn_v.weight")
Wo=mat("blk.0.attn_output.weight");Wg=mat("blk.0.ffn_gate.weight");Wd=mat("blk.0.ffn_down.weight")
# ── fixed-point примитивы (точно как RTL) ──
SC=64; LUT=[max(1,round(4096*math.exp(-k/4.0))) for k in range(32)]; SMSCALE=8
def isqrt(n):
    r=int(max(0,n)**0.5)
    while r*r>n:r-=1
    while (r+1)*(r+1)<=n:r+=1
    return r
def tdiv(a,b): return a//b if a>=0 else -((-a)//b)     # trunc к нулю
def clamp(v,lo=-127,hi=127): return max(lo,min(hi,v))
def matvec(W,x): return np.array([int(sum(int(W[r][c])*int(x[c]) for c in range(D))) for r in range(D)],dtype=np.int64)
def rmsnorm(x):
    ms=int((x*x).sum())//D; den=isqrt(ms*SC*SC) or 1
    return np.array([tdiv(int(xi)*SC*SC,den) for xi in x],dtype=np.int64)
def softmax_attn(Q,K,V):
    out=np.zeros((S,D),dtype=np.int64)
    for t in range(S):
        sc=np.array([int(Q[t]@K[j]) for j in range(S)]); mx=sc.max()
        w=np.array([LUT[min(31,(mx-sc[j])//SMSCALE)] for j in range(S)],dtype=np.int64)
        num=np.zeros(D,dtype=np.int64)
        for j in range(S): num+=w[j]*V[j]
        den=int(w.sum()); out[t]=np.array([tdiv(int(num[d]),den) for d in range(D)])
    return out
def requant(v,sh): return np.array([clamp(tdiv(int(vi),1<<sh)) for vi in v],dtype=np.int64)
# ── блок ──
X=np.array([[((t*13+i*7+3)%11)-5 for i in range(D)] for t in range(S)],dtype=np.int64)
SH_A, SH_F = 9, 12
H=np.zeros((S,D),dtype=np.int64); Y=np.zeros((S,D),dtype=np.int64)
n1=np.array([rmsnorm(X[t]) for t in range(S)])
Q=np.array([matvec(Wq,n1[t]) for t in range(S)]); K=np.array([matvec(Wk,n1[t]) for t in range(S)]); V=np.array([matvec(Wv,n1[t]) for t in range(S)])
ctx=softmax_attn(Q,K,V)
for t in range(S):
    ao=requant(matvec(Wo,ctx[t]),SH_A); H[t]=np.array([clamp(int(X[t][d]+ao[d])) for d in range(D)])
for t in range(S):
    n2=rmsnorm(H[t]); g=np.maximum(0,matvec(Wg,n2)); fo=requant(matvec(Wd,g),SH_F)
    Y[t]=np.array([clamp(int(H[t][d]+fo[d])) for d in range(D)])
print("ПОЛНЫЙ ТРОИЧНЫЙ ТРАНСФОРМЕР-БЛОК (fixed-point спека)")
print("вход  X[0]=",X[0].tolist())
print("выход Y[0]=",Y[0].tolist(),"  Y[3]=",Y[3].tolist())
# вектора + golden для RTL
enc={-1:0,0:1,1:2}
def pk(v):return sum(enc[int(t)]<<(2*i) for i,t in enumerate(v))
with open("vectors_block.vh","w") as f:
    f.write(f"localparam D={D},S={S},SC={SC},SMSCALE={SMSCALE},SH_A={SH_A},SH_F={SH_F};\n")
    for nm,M in (("WQ",Wq),("WK",Wk),("WV",Wv),("WO",Wo),("WG",Wg),("WD",Wd)):
        for r in range(D): f.write(f"localparam [2*D-1:0] {nm}_{r}=16'h{pk(M[r]):04x};\n")
    f.write("integer gi;\n initial begin\n")
    for t in range(S):
        for i in range(D): f.write(f"  X[{t*D+i}]={int(X[t][i])};\n")
    for k in range(32): f.write(f"  EXPLUT[{k}]={LUT[k]};\n")
    f.write(" end\n")
    f.write("function signed [31:0] gy; input integer t; input integer i; begin gy=0;\n")
    for t in range(S):
        for i in range(D): f.write(f"  if(t=={t}&&i=={i}) gy={int(Y[t][i])};\n")
    f.write(" end endfunction\n")
print("vectors_block.vh ok")
