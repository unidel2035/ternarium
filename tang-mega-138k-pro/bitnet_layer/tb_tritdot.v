`default_nettype none
`timescale 1ns/1ps
module tb;
  // M,N и данные приедут из vectors.vh
  reg [1:0] W [0:8*16-1];
  reg [1:0] X [0:16-1];
  `include "vectors.vh"

  // собрать плоские шины для нейрона r
  reg  [2*16-1:0] wbus, xbus;
  wire signed [15:0] sum;
  reg  [31:0] r;
  integer c, fails;
  tritdot #(.N(16)) DUT(.w_flat(wbus), .x_flat(xbus), .sum(sum));

  always @(*) begin
    for (c=0;c<N;c=c+1) begin
      wbus[2*c +: 2] = W[r*N + c];
      xbus[2*c +: 2] = X[c];
    end
  end

  initial begin
    #1; fails = 0;
    $display("=== BitNet слой blk.0.ffn_down на балансной троичной логике (iverilog) ===");
    for (r=0;r<M;r=r+1) begin
      #1;
      if (sum === golden(r))
        $display("нейрон %0d: RTL=%0d  эталон=%0d  ✓", r, sum, golden(r));
      else begin
        $display("нейрон %0d: RTL=%0d  эталон=%0d  ✗ РАСХОЖДЕНИЕ", r, sum, golden(r));
        fails = fails + 1;
      end
    end
    if (fails==0) $display("ИТОГ: ВСЕ %0d НЕЙРОНОВ СОВПАЛИ С numpy-ЭТАЛОНОМ ✓✓✓", M);
    else          $display("ИТОГ: расхождений %0d", fails);
    $finish;
  end
endmodule
