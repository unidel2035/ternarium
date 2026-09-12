localparam IN=8, HID=8, OUT=8;
localparam [2*IN-1:0] W1_0=16'ha669;
localparam [2*IN-1:0] W1_1=16'h2629;
localparam [2*IN-1:0] W1_2=16'h915a;
localparam [2*IN-1:0] W1_3=16'h598a;
localparam [2*IN-1:0] W1_4=16'h2261;
localparam [2*IN-1:0] W1_5=16'h9552;
localparam [2*IN-1:0] W1_6=16'h9886;
localparam [2*IN-1:0] W1_7=16'h401a;
localparam [2*HID-1:0] W2_0=16'h6124;
localparam [2*HID-1:0] W2_1=16'h894a;
localparam [2*HID-1:0] W2_2=16'h888a;
localparam [2*HID-1:0] W2_3=16'h06a8;
localparam [2*HID-1:0] W2_4=16'h182a;
localparam [2*HID-1:0] W2_5=16'h1581;
localparam [2*HID-1:0] W2_6=16'h2a89;
localparam [2*HID-1:0] W2_7=16'h2692;
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
 end
function signed [31:0] gy; input integer k; begin case(k)
  0: gy=0;
  1: gy=3;
  2: gy=1;
  3: gy=19;
  4: gy=-5;
  5: gy=-8;
  6: gy=9;
  7: gy=4;
  default: gy=0; endcase end endfunction
