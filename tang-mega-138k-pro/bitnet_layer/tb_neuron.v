`default_nettype none
`timescale 1ns/1ps
module tb;
  reg [1:0]        W [0:6911];
  reg signed [7:0] A [0:6911];
  `include "vectors_full.vh"
  reg  [2*6912-1:0] wbus; reg [8*6912-1:0] abus;
  wire signed [31:0] acc;
  integer k;
  tritneuron #(.N(6912)) DUT(.w_flat(wbus), .a_flat(abus), .acc(acc));
  initial begin
    #1;
    for (k=0;k<N;k=k+1) begin wbus[2*k +: 2]=W[k]; abus[8*k +: 8]=A[k]; end
    #1;
    $display("=== Полный нейрон BitNet blk.0.ffn_down (N=%0d) на троичной логике ===", N);
    $display("RTL  Σ w·a = %0d", acc);
    $display("numpy Σ w·a = %0d", GOLDEN_MAC);
    if (acc===GOLDEN_MAC) $display("СОВПАЛО ✓  (float-выход = weight_scale · %0d)", acc);
    else                  $display("РАСХОЖДЕНИЕ ✗");
    $finish;
  end
endmodule
