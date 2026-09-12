// uart_echo.v — диагностика UART: приём на rx, эхо на tx (115200 @ 50МГц)
module uart_rx_e(input wire clk,input wire rx,output reg [7:0] data=0,output reg ready=0);
  localparam CLKDIV=434; reg [15:0] div=0; reg [3:0] cnt=0; reg active=0; reg [7:0] sr=0;
  always @(posedge clk) begin ready<=0;
    if(!active) begin if(!rx) begin active<=1; div<=CLKDIV/2; cnt<=8; end end
    else if(div==0) begin div<=CLKDIV-1;
      if(cnt==0) begin data<=sr; ready<=1; active<=0; end
      else begin sr<={rx,sr[7:1]}; cnt<=cnt-1; end
    end else div<=div-1; end
endmodule
module uart_tx_e(input wire clk,input wire [7:0] data,input wire start,output reg tx=1,output wire ready);
  localparam CLKDIV=434; reg [9:0] sr=10'h3FF; reg [15:0] div=0; reg [3:0] cnt=0;
  assign ready=(cnt==0);
  always @(posedge clk) begin
    if(cnt==0) begin tx<=1; if(start) begin sr<={1'b1,data,1'b0}; cnt<=10; div<=CLKDIV-1; end end
    else if(div==0) begin div<=CLKDIV-1; tx<=sr[0]; sr<={1'b1,sr[9:1]}; cnt<=cnt-1; end
    else div<=div-1; end
endmodule
module uart_echo(input wire clk,input wire rst_n,input wire rx,output wire tx,output wire [2:0] state_led);
  wire [7:0] rxd; wire rxv;
  uart_rx_e urx(.clk(clk),.rx(rx),.data(rxd),.ready(rxv));
  reg [7:0] tb=0; reg ts=0; wire tready;
  uart_tx_e utx(.clk(clk),.data(tb),.start(ts),.tx(tx),.ready(tready));
  reg act=0;
  always @(posedge clk) begin ts<=0; if(rxv && tready) begin tb<=rxd; ts<=1; act<=~act; end end
  reg [24:0] bl=0; always @(posedge clk) bl<=bl+1;
  assign state_led[0]=~bl[23]; assign state_led[1]=~act; assign state_led[2]=1'b1;
endmodule
