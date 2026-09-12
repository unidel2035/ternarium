// mlgru_board_led.v — РЕКОНСТРУКЦИЯ исходной LED-only версии (baseline для stat-сравнения).
// top = mlgru_board, чтобы прогнать тем же потоком и сравнить RAM16SDP4/LUT4.
`default_nettype none
module mlgru_board (input wire clk, output reg [5:0] leds, output wire uart_tx_pin);
  `include "mlgru_vectors.vh"
  assign uart_tx_pin = 1'b1;
  reg [1:0] cdiv=0; always @(posedge clk) cdiv<=cdiv+1'b1;
  wire mclk = cdiv[1];
  reg [27:0] pc=0; always @(posedge mclk) pc<=pc+1'b1;
  wire rst   = (pc < 28'd64);
  wire start = (pc == 28'd100);
  reg [7:0] taddr; wire [7:0] tout; wire done;
  model_mlgru u(.clk(mclk),.rst(rst),.start(start),.tok_addr(taddr),.tok_out(tout),.done(done));
  reg done_latch; reg [3:0] dg; reg [7:0] cur; reg prev_tick;
  wire tick = pc[23];
  always @(posedge mclk) begin
    if(rst) begin done_latch<=1'b0; dg<=4'd0; cur<=8'd0; prev_tick<=1'b0; taddr<=8'd0; end
    else begin
      if(done) done_latch<=1'b1;
      taddr <= dg; cur <= tout; prev_tick <= tick;
      if(tick & ~prev_tick) dg <= (dg==NGEN-1) ? 4'd0 : dg+1'b1;
    end
  end
  always @(posedge mclk)
    leds <= done_latch ? {1'b1, ~cur[4:0]} : {6{pc[22]}};
endmodule
