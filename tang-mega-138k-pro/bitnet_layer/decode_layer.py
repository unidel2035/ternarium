#!/usr/bin/env python3
# GGUF-парсер (без внешних либ): реальный слой BitNet-2B → блок M×N тернарных весов
# + реальный тернарный вход → золотой вектор. Готовит vectors.vh для iverilog.
import struct, sys, numpy as np
GGUF="/home/unidel/tang/bitnet-2b-model/ggml-model-i2_s.gguf"
M, N = 8, 16            # 8 нейронов, 16 входов
buf=open(GGUF,"rb").read(); off=0
def rd(f):
    global off; sz=struct.calcsize(f); v=struct.unpack_from("<"+f,buf,off); off+=sz
    return v[0] if len(v)==1 else v
def rstr():
    global off; n=rd("Q"); s=buf[off:off+n].decode("utf-8","replace"); off+=n; return s
assert buf[:4]==b"GGUF"; off=4
rd("I"); n_tensors=rd("Q"); n_kv=rd("Q")
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
alignment=32
for _ in range(n_kv):
    k=rstr(); vt=rd("I")
    if k=="general.alignment" and vt==4: alignment=struct.unpack_from("<I",buf,off)[0]
    skip(vt)
tensors=[]
for _ in range(n_tensors):
    nm=rstr(); nd=rd("I"); dims=[rd("Q") for _ in range(nd)]; tt=rd("I"); to=rd("Q")
    tensors.append((nm,dims,tt,to))
data_start=(off+alignment-1)//alignment*alignment
nm,dims,tt,to=next((t for t in tensors if t[2]==36 and len(t[1])==2),(None,)*4)
ncols=dims[0]
raw=np.frombuffer(buf,dtype=np.uint8,count=(dims[0]*dims[1])//4,offset=data_start+to)
def trit(k):
    i,j=k//128,k%128; b=int(raw[i*32+(j%32)]); return ((b>>(6-2*(j//32)))&3)-1
def row(r): return np.array([trit(r*ncols+c) for c in range(N)],dtype=np.int8)
W=np.stack([row(r) for r in range(M)])     # 8×16 реальные веса
X=row(100)                                  # реальная строка как вход
print(f"тензор {nm} {dims}; блок {M}×{N}")
G=(W.astype(int)@X.astype(int))
print("W[0] =",W[0].tolist()); print("X    =",X.tolist())
print("ЭТАЛОН (numpy):",G.tolist())
enc={-1:0,0:1,1:2}
with open(f"{__import__('os').path.dirname(__file__)}/vectors.vh","w") as f:
    f.write(f"// реальный слой BitNet-2B: {nm}, блок {M}x{N}\n")
    f.write(f"localparam M={M}, N={N};\n")
    f.write("integer gi;\n")
    f.write("initial begin\n")
    for r in range(M):
        for c in range(N): f.write(f"  W[{r*N+c}]=2'd{enc[int(W[r][c])]};\n")
    for c in range(N): f.write(f"  X[{c}]=2'd{enc[int(X[c])]};\n")
    f.write("end\n")
    f.write("// golden\n")
    f.write("function signed [31:0] golden; input integer k; begin case(k)\n")
    for r in range(M): f.write(f"  {r}: golden={int(G[r])};\n")
    f.write("  default: golden=0; endcase end endfunction\n")
print("vectors.vh ok")
