localparam N_OUT=8, N_IN=16, CH=8;
localparam [4*CH-1:0] WIDX_0=32'h56247361;
localparam [4*CH-1:0] WIDX_1=32'h07352518;
localparam [4*CH-1:0] WIDX_2=32'h67732228;
localparam [4*CH-1:0] WIDX_3=32'h65870782;
localparam [4*CH-1:0] WIDX_4=32'h10453268;
localparam [4*CH-1:0] WIDX_5=32'h61053423;
localparam [4*CH-1:0] WIDX_6=32'h88116825;
localparam [4*CH-1:0] WIDX_7=32'h17826756;
integer gi;
 initial begin
  X[0]=-2;
  X[1]=6;
  X[2]=-1;
  X[3]=7;
  X[4]=0;
  X[5]=-7;
  X[6]=1;
  X[7]=-6;
  X[8]=2;
  X[9]=-5;
  X[10]=3;
  X[11]=-4;
  X[12]=4;
  X[13]=-3;
  X[14]=5;
  X[15]=-2;
 end
function signed [31:0] gy; input integer r; begin gy=0;
  if(r==0) gy=0;
  if(r==1) gy=-9;
  if(r==2) gy=17;
  if(r==3) gy=24;
  if(r==4) gy=-16;
  if(r==5) gy=7;
  if(r==6) gy=13;
  if(r==7) gy=-3;
 end endfunction
