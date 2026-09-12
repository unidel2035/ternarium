# Реальный троичный FFN-блок: W1,W2 — реальные тернарные веса BitNet, int8 вход.
# y = W2 · ReLU(W1 · x). Эталон numpy + вектор для RTL.
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
    nm,dims,tt,to=next(t for t in T if t[0]==name)
    nc=dims[0]; raw=np.frombuffer(buf,dtype=np.uint8,count=(dims[0]*dims[1])//4,offset=ds+to)
    def trit(k):
        i,j=k//128,k%128; b=int(raw[i*32+(j%32)]); return ((b>>(6-2*(j//32)))&3)-1
    return nc, trit
IN, HID, OUT = 8, 8, 8
ncg, tg = tensor("blk.0.ffn_gate.weight")   # W1: HID×IN
ncd, td = tensor("blk.0.ffn_down.weight")    # W2: OUT×HID
W1=np.array([[tg(r*ncg+c) for c in range(IN)]  for r in range(HID)],dtype=np.int32)
W2=np.array([[td(r*ncd+c) for c in range(HID)] for r in range(OUT)],dtype=np.int32)
x =np.array([((i*23+5)%15)-7 for i in range(IN)],dtype=np.int32)   # int8-вход (детерминир.)
h = np.maximum(0, W1 @ x)        # ReLU(W1·x) — нелинейность
y = W2 @ h                       # W2·h
print("реальные веса BitNet: W1=ffn_gate[8x8], W2=ffn_down[8x8]")
print("x =", x.tolist()); print("h=ReLU(W1x) =", h.tolist()); print("y=W2h =", y.tolist())
enc={-1:0,0:1,1:2}
def packrow(v): return sum(enc[int(t)]<<(2*i) for i,t in enumerate(v))
with open("vectors_ffn.vh","w") as f:
    f.write(f"localparam IN={IN}, HID={HID}, OUT={OUT};\n")
    for r in range(HID): f.write(f"localparam [2*IN-1:0] W1_{r}=16'h{packrow(W1[r]):04x};\n")
    for r in range(OUT): f.write(f"localparam [2*HID-1:0] W2_{r}=16'h{packrow(W2[r]):04x};\n")
    f.write("integer gi;\n initial begin\n")
    for i in range(IN): f.write(f"  X[{i}]={int(x[i])};\n")
    f.write(" end\n")
    f.write("function signed [31:0] gy; input integer k; begin case(k)\n")
    for r in range(OUT): f.write(f"  {r}: gy={int(y[r])};\n")
    f.write("  default: gy=0; endcase end endfunction\n")
print("vectors_ffn.vh ok")
