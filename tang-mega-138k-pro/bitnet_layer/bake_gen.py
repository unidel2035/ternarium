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
nm,dims,tt,to=next(t for t in T if t[2]==36 and len(t[1])==2); nc=dims[0]
raw=np.frombuffer(buf,dtype=np.uint8,count=(dims[0]*dims[1])//4,offset=ds+to)
def trit(k):
    i,j=k//128,k%128; b=int(raw[i*32+(j%32)]); return ((b>>(6-2*(j//32)))&3)-1
def row(r,N=16): return [trit(r*nc+c) for c in range(N)]
W=[row(r) for r in range(8)]; X=row(100)
enc={-1:0,0:1,1:2}
def pack(v): return sum(enc[t]<<(2*i) for i,t in enumerate(v))
G=[int(np.dot(np.array(W[r]),np.array(X))) for r in range(8)]
with open("bake.vh","w") as f:
    f.write(f"// вшитый реальный блок BitNet-2B {nm}: 8 нейронов × 16 входов\n")
    for r in range(8): f.write(f"localparam [31:0] WROW{r} = 32'h{pack(W[r]):08x};\n")
    f.write(f"localparam [31:0] XV = 32'h{pack(X):08x};\n")
print("golden:",G); print("bake.vh ok")
