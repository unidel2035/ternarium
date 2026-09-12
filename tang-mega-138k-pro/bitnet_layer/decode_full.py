#!/usr/bin/env python3
# Полный реальный нейрон BitNet: одна строка ffn_down (N входов), тернарный вес × int8-активация.
import struct, numpy as np, os
GGUF="/home/unidel/tang/bitnet-2b-model/ggml-model-i2_s.gguf"
buf=open(GGUF,"rb").read(); off=0
def rd(f):
    global off; sz=struct.calcsize(f); v=struct.unpack_from("<"+f,buf,off); off+=sz; return v[0] if len(v)==1 else v
def rstr():
    global off; n=rd("Q"); s=buf[off:off+n].decode("utf-8","replace"); off+=n; return s
assert buf[:4]==b"GGUF"; off=4
rd("I"); nt=rd("Q"); nkv=rd("Q")
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
nm,dims,tt,to=next(t for t in T if t[2]==36 and len(t[1])==2)
ncols=dims[0]; nrows=dims[1]; N=ncols           # полная строка = 6912 входов
npack=(ncols*nrows)//4
raw=np.frombuffer(buf,dtype=np.uint8,count=npack,offset=ds+to)
# scale хранится f32 сразу после упакованных весов
scale=struct.unpack_from("<f",buf,ds+to+npack)[0]
def trit(k):
    i,j=k//128,k%128; b=int(raw[i*32+(j%32)]); return ((b>>(6-2*(j//32)))&3)-1
w=np.array([trit(c) for c in range(N)],dtype=np.int32)     # реальный нейрон 0
# детерминированная int8-активация (как квант BitNet: целые в [-127,127])
a=np.array([((i*37+11)%255)-127 for i in range(N)],dtype=np.int32)
mac=int(np.dot(w,a))                                        # целочисленный троичный MAC
print(f"тензор {nm} dims={dims}  N(входов)={N}  weight_scale={scale:.6g}")
print(f"ненулевых весов: {int((w!=0).sum())}/{N}   (+1: {int((w==1).sum())}, -1: {int((w==-1).sum())}, 0: {int((w==0).sum())})")
print(f"целочисленный MAC Σ w·a = {mac}")
print(f"float-выход нейрона ≈ scale·MAC = {scale*mac:.6g}")
enc={-1:0,0:1,1:2}
with open("vectors_full.vh","w") as f:
    f.write(f"// полный нейрон BitNet-2B: {nm}, N={N}\n")
    f.write(f"localparam N={N};\n")
    f.write(f"localparam signed [31:0] GOLDEN_MAC = {mac};\n")
    f.write("initial begin\n")
    for i in range(N): f.write(f"  W[{i}]=2'd{enc[int(w[i])]}; A[{i}]={int(a[i])};\n")
    f.write("end\n")
print("vectors_full.vh ok")
