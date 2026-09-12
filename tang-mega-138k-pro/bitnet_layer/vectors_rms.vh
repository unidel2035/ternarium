localparam D=8, SCALE=256;
 initial begin
  X[0]=-2;
  X[1]=6;
  X[2]=-1;
  X[3]=7;
  X[4]=0;
  X[5]=-7;
  X[6]=1;
  X[7]=-6;
 end
localparam signed [31:0] MS=22;
function signed [31:0] gy; input integer i; begin gy=0;
  if(i==0) gy=-109;
  if(i==1) gy=327;
  if(i==2) gy=-54;
  if(i==3) gy=382;
  if(i==4) gy=0;
  if(i==5) gy=-382;
  if(i==6) gy=54;
  if(i==7) gy=-327;
 end endfunction
