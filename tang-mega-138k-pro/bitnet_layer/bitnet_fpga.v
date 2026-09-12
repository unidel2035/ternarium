// bitnet_fpga.v — реальный BitNet-блок на ПЛИС, результаты по UART.
// FSM устойчив к любому стартовому состоянию (default->0) — не зависит от init FF.
`default_nettype none
module uart_tx(input wire clk, input wire [7:0] data, input wire start,
               output reg tx=1, output wire ready);
  localparam CLKDIV=434; reg [7:0] sr=8'hFF; reg [8:0] div=0; reg [3:0] cnt=0;
  assign ready=(cnt==0);
  always @(posedge clk) begin
    if(cnt==0) begin tx<=1; if(start) begin sr<=data; cnt<=9; tx<=0; div<=0; end end
    else begin if(div==CLKDIV-1) begin div<=0;
        if(cnt==1) begin tx<=1; cnt<=0; end
        else begin tx<=sr[0]; sr<={1'b1,sr[7:1]}; cnt<=cnt-1; end
      end else div<=div+1; end
  end
endmodule
module bitnet_fpga(input wire clk, output wire uart_tx_pin);
  `include "bake.vh"
  wire signed [15:0] r [0:7];
  tritdot #(.N(16)) n0(.w_flat(WROW0),.x_flat(XV),.sum(r[0]));
  tritdot #(.N(16)) n1(.w_flat(WROW1),.x_flat(XV),.sum(r[1]));
  tritdot #(.N(16)) n2(.w_flat(WROW2),.x_flat(XV),.sum(r[2]));
  tritdot #(.N(16)) n3(.w_flat(WROW3),.x_flat(XV),.sum(r[3]));
  tritdot #(.N(16)) n4(.w_flat(WROW4),.x_flat(XV),.sum(r[4]));
  tritdot #(.N(16)) n5(.w_flat(WROW5),.x_flat(XV),.sum(r[5]));
  tritdot #(.N(16)) n6(.w_flat(WROW6),.x_flat(XV),.sum(r[6]));
  tritdot #(.N(16)) n7(.w_flat(WROW7),.x_flat(XV),.sum(r[7]));
  reg [7:0] tob=0; reg start=0; wire tx_ready;
  uart_tx u(.clk(clk),.data(tob),.start(start),.tx(uart_tx_pin),.ready(tx_ready));
  reg [3:0] idx=0; reg [1:0] st=0; reg [22:0] cnt=0;
  always @(posedge clk) cnt<=cnt+1;
  wire tick=(cnt==0);
  reg [7:0] bsel;
  always @(*) case(idx)
    4'd0:bsel=8'hAA; 4'd1:bsel=r[0][7:0]; 4'd2:bsel=r[1][7:0]; 4'd3:bsel=r[2][7:0];
    4'd4:bsel=r[3][7:0]; 4'd5:bsel=r[4][7:0]; 4'd6:bsel=r[5][7:0]; 4'd7:bsel=r[6][7:0];
    4'd8:bsel=r[7][7:0]; default:bsel=8'h55; endcase
  always @(posedge clk) begin
    start<=0;
    case(st)
      2'd0: if(tick) begin idx<=0; st<=2'd1; end
      2'd1: if(tx_ready && !start) begin tob<=bsel; start<=1; st<=2'd2; end
      2'd2: if(!tx_ready) st<=2'd3;
      2'd3: if(tx_ready) begin if(idx==4'd8) st<=2'd0; else begin idx<=idx+1; st<=2'd1; end end
      default: st<=2'd0;
    endcase
  end
endmodule
