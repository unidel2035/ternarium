import numpy as np, math
D=8
x=np.array([-2,6,-1,7,0,-7,1,-6],dtype=np.int64)   # реальный вход
SCALE=256
ss=int((x*x).sum()); ms=ss//D
# integer isqrt (floor) — точно повторяемо в RTL
def isqrt(n):
    if n<=0: return 0
    r=int(n**0.5)
    while r*r>n: r-=1
    while (r+1)*(r+1)<=n: r+=1
    return r
inv_den=isqrt(ms*SCALE*SCALE)
y_fix=np.array([ (int(xi)*SCALE*SCALE)//inv_den if xi>=0 else -((-int(xi)*SCALE*SCALE)//inv_den) for xi in x],dtype=np.int64)
y_float=x/math.sqrt(ms)*SCALE
err=np.abs(y_fix-y_float).max(); rel=err/(np.abs(y_float).max()+1e-9)
print("x=",x.tolist()); print("RMSNorm float (×256):",np.round(y_float,1).tolist())
print("RMSNorm fixed (×256):",y_fix.tolist())
print(f"max|fixed-float|={err:.1f}, отн={rel*100:.1f}%")
with open("vectors_rms.vh","w") as f:
    f.write(f"localparam D={D}, SCALE={SCALE};\n initial begin\n")
    for i in range(D): f.write(f"  X[{i}]={int(x[i])};\n")
    f.write(" end\n")
    f.write(f"localparam signed [31:0] MS={ms};\n")
    f.write("function signed [31:0] gy; input integer i; begin gy=0;\n")
    for i in range(D): f.write(f"  if(i=={i}) gy={int(y_fix[i])};\n")
    f.write(" end endfunction\n")
print("vectors_rms.vh ok")
