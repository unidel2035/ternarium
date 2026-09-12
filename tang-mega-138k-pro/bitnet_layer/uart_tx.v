// uart_tx.v — 8N1 передатчик. DIV = CLK/BAUD.
`default_nettype none
module uart_tx #(parameter DIV=434) (
  input wire clk, input wire rst, input wire [7:0] data, input wire send,
  output reg tx, output reg busy);
  reg [15:0] cnt; reg [3:0] idx; reg [9:0] sh;
  always @(posedge clk) begin
    if (rst) begin tx<=1'b1; busy<=1'b0; cnt<=0; idx<=0; end
    else if (!busy) begin
      tx<=1'b1;
      if (send) begin sh<={1'b1,data,1'b0}; idx<=0; cnt<=0; busy<=1'b1; tx<=1'b0; end
    end else if (cnt==DIV-1) begin
      cnt<=0;
      if (idx==9) begin busy<=1'b0; tx<=1'b1; end
      else begin idx<=idx+1'b1; tx<=sh[idx+1]; end
    end else cnt<=cnt+1'b1;
  end
endmodule
