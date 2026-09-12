// uart_rx.v — приёмник 8N1, DIV=CLK/BAUD. Логика как в проверенном tritterm.uart_rx_term.
`default_nettype none
module uart_rx #(parameter DIV=434) (
  input wire clk, input wire rst, input wire rx,
  output reg [7:0] data, output reg ready);
  reg [15:0] div; reg [3:0] cnt; reg active; reg [7:0] sr;
  always @(posedge clk) begin
    if (rst) begin active<=1'b0; ready<=1'b0; end
    else begin
      ready<=1'b0;
      if (!active) begin
        if (!rx) begin active<=1'b1; div<=DIV+DIV/2; cnt<=8; end   // 1.5 бита → центр d0
      end else if (div==0) begin
        div<=DIV-1;
        if (cnt==0) begin data<=sr; ready<=1'b1; active<=1'b0; end
        else begin sr<={rx,sr[7:1]}; cnt<=cnt-1; end
      end else div<=div-1;
    end
  end
endmodule
