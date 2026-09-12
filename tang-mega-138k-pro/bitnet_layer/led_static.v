// led_static.v — стабильный silicon-witness: результат нейрона 0 реального BitNet-слоя
// (blk.0.ffn_down, =4) термометром на 5 LED. Чистая комбинаторика, без таймеров.
// Должны ровно гореть 4 из 5 (led0..3), led4 погашен. Активные LOW.
`default_nettype none
module led_static(input wire clk,
  output wire led0, output wire led1, output wire led2, output wire led3, output wire led4);
  `include "bake.vh"
  wire signed [15:0] r0;
  tritdot #(.N(16)) g0(.w_flat(WROW0), .x_flat(XV), .sum(r0));
  wire signed [15:0] mag = r0[15] ? -r0 : r0;   // |4| = 4
  assign led0 = ~(mag > 16'sd0);
  assign led1 = ~(mag > 16'sd1);
  assign led2 = ~(mag > 16'sd2);
  assign led3 = ~(mag > 16'sd3);
  assign led4 = ~(mag > 16'sd4);
endmodule
