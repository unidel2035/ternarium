module tx3(input wire clk,input wire [7:0] b0,input wire [7:0] b1,input wire [7:0] b2,output reg tx=1);
  reg [15:0] div=0; reg [3:0] cnt=0; reg [1:0] idx=0; reg [9:0] sh=10'h3FF;
  wire [7:0] cur=(idx==0)?b0:(idx==1)?b1:b2;
  always @(posedge clk) begin
    if(cnt==0) begin sh<={1'b1,cur,1'b0}; cnt<=10; div<=16'd433; tx<=1'b1; idx<=(idx==2)?2'd0:idx+2'd1; end
    else if(div==0) begin tx<=sh[0]; sh<={1'b1,sh[9:1]}; cnt<=cnt-1; div<=16'd433; end
    else div<=div-1; end
endmodule
module uart_scan(input wire clk,
  input wire c0,input wire c1,input wire c2,input wire c3,input wire c4,input wire c5,input wire c6,input wire c7,
  input wire c8,input wire c9,input wire c10,input wire c11,input wire c12,input wire c13,input wire c14,input wire c15,
  output wire tx,output wire [2:0] state_led);
  wire [15:0] cand={c15,c14,c13,c12,c11,c10,c9,c8,c7,c6,c5,c4,c3,c2,c1,c0};
  reg [15:0] s0=0,s1=0,prev=0,act=0; reg [21:0] win=0;
  wire [15:0] edges=s1^prev;
  always @(posedge clk) begin s0<=cand; s1<=s0; prev<=s1;
    if(win==22'd2000000) begin win<=0; act<=0; end else begin win<=win+1; act<=act|edges; end end
  tx3 t0(.clk(clk),.b0(8'hAA),.b1(act[7:0]),.b2(act[15:8]),.tx(tx));
  reg [24:0] bl=0; always @(posedge clk) bl<=bl+1;
  assign state_led={2'b11,~bl[23]};
endmodule
