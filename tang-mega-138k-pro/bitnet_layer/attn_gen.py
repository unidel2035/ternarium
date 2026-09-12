# Упрощённое троичное внимание: Q/K/V — реальные тернарные веса BitNet, hardmax (целочисленно).
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
    def trit(k):
        i,j=k//128,k%128; b=int(raw[i*32+(j%32)]); return ((b>>(6-2*(j//32)))&3)-1
    return nc,trit
D, S = 8, 4    # d_model=8, seq_len=4
def mat(name,R,C):
    nc,tr=tensor(name); return np.array([[tr(r*nc+c) for c in range(C)] for r in range(R)],dtype=np.int32)
Wq=mat("blk.0.attn_q.weight",D,D); Wk=mat("blk.0.attn_k.weight",D,D); Wv=mat("blk.0.attn_v.weight",D,D)
X = np.array([[((t*13+i*7+3)%11)-5 for i in range(D)] for t in range(S)],dtype=np.int32)  # 4 токена int8
Q = X@Wq.T; K = X@Wk.T; V = X@Wv.T          # проекции (тернарный матмул)
scores = Q@K.T                               # QKᵀ
sel = scores.argmax(axis=1)                  # hardmax (целочисленно, бит-проверяемо)
out = V[sel]                                 # выбранные строки V
print("реальные тернарные веса BitNet: attn_q/k/v[8x8], 4 токена")
print("argmax по строкам (на какой токен смотрит каждый):", sel.tolist())
print("out[0] =", out[0].tolist())
enc={-1:0,0:1,1:2}
def packrow(v): return sum(enc[int(t)]<<(2*i) for i,t in enumerate(v))
with open("vectors_attn.vh","w") as f:
    f.write(f"localparam D={D}, S={S};\n")
    for nm,Wm in (("WQ",Wq),("WK",Wk),("WV",Wv)):
        for r in range(D): f.write(f"localparam [2*D-1:0] {nm}_{r}=16'h{packrow(Wm[r]):04x};\n")
    f.write("integer gi;\n initial begin\n")
    for t in range(S):
        for i in range(D): f.write(f"  X[{t*D+i}]={int(X[t][i])};\n")
    f.write(" end\n")
    f.write("function integer gsel; input integer t; begin case(t)\n")
    for t in range(S): f.write(f"  {t}: gsel={int(sel[t])};\n")
    f.write("  default: gsel=0; endcase end endfunction\n")
    f.write("function signed [31:0] gout; input integer t; input integer i; begin gout=0;\n")
    for t in range(S):
        for i in range(D): f.write(f"  if(t=={t}&&i=={i}) gout={int(out[t][i])};\n")
    f.write(" end endfunction\n")
print("vectors_attn.vh ok")
