// uart_beacon.v — минимальный тест UART-тракта: шлёт 0x55 ('U') непрерывно на P15.
`default_nettype none
module uart_beacon #(parameter DIV=434) (input wire clk, output wire tx);
  reg [15:0] pc=0; always @(posedge clk) pc<=pc+1'b1;
  wire rst = (pc<16'd8);
  wire busy; reg send;
  always @(posedge clk) send <= ~busy;
  uart_tx #(.DIV(DIV)) u(.clk(clk),.rst(rst),.data(8'h55),.send(send),.tx(tx),.busy(busy));
endmodule
