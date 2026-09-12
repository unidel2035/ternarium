`default_nettype none
module beacon(input wire clk, output reg uart_tx_pin=1'b0);
  reg [14:0] c = 0;
  always @(posedge clk) begin c <= c + 1'b1; if (c==0) uart_tx_pin <= ~uart_tx_pin; end
endmodule
