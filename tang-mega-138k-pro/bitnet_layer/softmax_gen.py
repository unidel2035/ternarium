# Fixed-point softmax-внимание: те же троичные Q/K/V, но мягкий softmax (не hardmax).
# Спека fixed-point (exp-LUT, целочисленно) + float-эталон. RTL повторит LUT бит-в-бит.
import struct, numpy as np
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
T=[]
for _ in range(nt):
    nm=rstr(); nd=rd("I"); dims=[rd("Q") for _ in range(nd)]; tt=rd("I"); to=rd("Q"); T.append((nm,dims,tt,to))
ds=(off+al-1)//al*al
def tensor(name):
    nm,dims,tt,to=next(t for t in T if t[0]==name); nc=dims[0]
    raw=np.frombuffer(buf,dtype=np.uint8,count=(dims[0]*dims[1])//4,offset=ds+to)
    return nc, lambda k:(((int(raw[(k//128)*32+((k%128)%32)])>>(6-2*((k%128)//32)))&3)-1)
D,S=8,4
def mat(n,R,C):
    nc,tr=tensor(n); return np.array([[tr(r*nc+c) for c in range(C)] for r in range(R)],dtype=np.int64)
Wq=mat("blk.0.attn_q.weight",D,D);Wk=mat("blk.0.attn_k.weight",D,D);Wv=mat("blk.0.attn_v.weight",D,D)
X=np.array([[((t*13+i*7+3)%11)-5 for i in range(D)] for t in range(S)],dtype=np.int64)
Q=X@Wq.T; K=X@Wk.T; V=X@Wv.T
scores=Q@K.T                                  # целые
# --- float-эталон softmax ---
sc=scores/32.0
e=np.exp(sc-sc.max(1,keepdims=True)); P=e/e.sum(1,keepdims=True)
out_float=P@V
# --- fixed-point спека: exp-LUT, целочисленно ---
SCALE=8     # температура: diff//SCALE индексирует LUT
LUTLEN=32
EXPLUT=[max(1,round(4096*np.exp(-k/4.0))) for k in range(LUTLEN)]   # Q12 exp(-k/4)
def fixed_attn():
    out=np.zeros((S,D),dtype=np.int64)
    for t in range(S):
        mx=scores[t].max()
        w=np.array([EXPLUT[min(LUTLEN-1, int((mx-scores[t][j])//SCALE))] for j in range(S)],dtype=np.int64)
        num=np.zeros(D,dtype=np.int64)
        for j in range(S): num += w[j]*V[j]
        den=w.sum()
        q=np.where(num>=0, num//den, -((-num)//den)); out[t]=q  # trunc к нулю (как Verilog)
    return out, EXPLUT
out_fix,_=fixed_attn()
# ошибка спеки против float
err=np.abs(out_fix-out_float); rel=err.max()/ (np.abs(out_float).max()+1e-9)
print("scores range:",int(scores.min()),"..",int(scores.max()))
print("out_float[0]:",np.round(out_float[0],2).tolist())
print("out_fixed[0]:",out_fix[0].tolist())
print(f"max|fixed-float|={err.max():.2f}, отн.ошибка={rel*100:.1f}%  → softmax fixed-point ≈ float")
# вектора для RTL (повторит LUT и целочисленную арифметику)
enc={-1:0,0:1,1:2}
def pk(v):return sum(enc[int(t)]<<(2*i) for i,t in enumerate(v))
with open("vectors_softmax.vh","w") as f:
    f.write(f"localparam D={D},S={S},SCALE={SCALE},LUTLEN={LUTLEN};\n")
    for nm,M in (("WQ",Wq),("WK",Wk),("WV",Wv)):
        for r in range(D): f.write(f"localparam [2*D-1:0] {nm}_{r}=16'h{pk(M[r]):04x};\n")
    f.write("integer gi;\n initial begin\n")
    for t in range(S):
        for i in range(D): f.write(f"  X[{t*D+i}]={int(X[t][i])};\n")
    for k in range(LUTLEN): f.write(f"  EXPLUT[{k}]={EXPLUT[k]};\n")
    f.write(" end\n")
    f.write("function signed [31:0] gfix; input integer t; input integer i; begin gfix=0;\n")
    for t in range(S):
        for i in range(D): f.write(f"  if(t=={t}&&i=={i}) gfix={int(out_fix[t][i])};\n")
    f.write(" end endfunction\n")
print("vectors_softmax.vh ok")
