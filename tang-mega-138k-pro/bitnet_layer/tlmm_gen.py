# TLMM (table-lookup matmul) для троичных весов — приём TeLLMe/T-MAC.
# Группы по 2 входа: LUT[9] частичных сумм (3^2 паттернов весов), строится 1 раз на токен.
# Каждый нейрон = сумма выборок из LUT по индексу пары весов. Умножений в матмуле НЕТ.
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
    if vt==8:n=rd("Q");off+=n
    elif vt==9:
        et=rd("I");ln=rd("Q")
        for _ in range(ln):
            if et==8:n=rd("Q");off+=n
            else:off+=struct.calcsize(VT[et])
    else:off+=struct.calcsize(VT[vt])
al=32
for _ in range(nkv):
    k=rstr();vt=rd("I")
    if k=="general.alignment" and vt==4: al=struct.unpack_from("<I",buf,off)[0]
    skip(vt)
TS=[]
for _ in range(nt):
    nm=rstr();nd=rd("I");dims=[rd("Q") for _ in range(nd)];tt=rd("I");to=rd("Q");TS.append((nm,dims,tt,to))
ds=(off+al-1)//al*al
nm,dims,tt,to=next(t for t in TS if t[0]=="blk.0.ffn_down.weight"); nc=dims[0]
raw=np.frombuffer(buf,dtype=np.uint8,count=(dims[0]*dims[1])//4,offset=ds+to)
def trit(k):
    i,j=k//128,k%128;b=int(raw[i*32+(j%32)]);return ((b>>(6-2*(j//32)))&3)-1
N_OUT, N_IN = 8, 16
Wt=np.array([[trit(r*nc+c) for c in range(N_IN)] for r in range(N_OUT)],dtype=np.int64)   # тернарные веса
x =np.array([((i*23+5)%15)-7 for i in range(N_IN)],dtype=np.int64)                          # int8 вход
# прямой MAC (эталон)
y_direct = Wt @ x
# TLMM: группы по 2, код трита 0,1,2 (=-1,0,+1); idx = c0*3+c1
G=2; CH=N_IN//G
enc={-1:0,0:1,1:2}
LUT=np.zeros((CH,9),dtype=np.int64)
for p in range(CH):
    a0,a1=int(x[2*p]),int(x[2*p+1])
    for c0 in range(3):
        for c1 in range(3):
            LUT[p][c0*3+c1]=(c0-1)*a0+(c1-1)*a1
y_tlmm=np.zeros(N_OUT,dtype=np.int64)
for r in range(N_OUT):
    s=0
    for p in range(CH):
        c0=enc[int(Wt[r][2*p])]; c1=enc[int(Wt[r][2*p+1])]
        s+=LUT[p][c0*3+c1]
    y_tlmm[r]=s
print("прямой MAC:", y_direct.tolist())
print("TLMM      :", y_tlmm.tolist())
print("совпадает:", bool((y_direct==y_tlmm).all()))
# веса как ИНДЕКСЫ пар (по 4 бита: c0*3+c1, 0..8) — компактное хранение
with open("vectors_tlmm.vh","w") as f:
    f.write(f"localparam N_OUT={N_OUT}, N_IN={N_IN}, CH={CH};\n")
    # индексы пар весов на нейрон (CH индексов, по 4 бита)
    for r in range(N_OUT):
        idxs=0
        for p in range(CH):
            c0=enc[int(Wt[r][2*p])]; c1=enc[int(Wt[r][2*p+1])]
            idxs |= (c0*3+c1) << (4*p)
        f.write(f"localparam [4*CH-1:0] WIDX_{r}=32'h{idxs:08x};\n")
    f.write("integer gi;\n initial begin\n")
    for i in range(N_IN): f.write(f"  X[{i}]={int(x[i])};\n")
    f.write(" end\n")
    f.write("function signed [31:0] gy; input integer r; begin gy=0;\n")
    for r in range(N_OUT): f.write(f"  if(r=={r}) gy={int(y_direct[r])};\n")
    f.write(" end endfunction\n")
print("vectors_tlmm.vh ok")
