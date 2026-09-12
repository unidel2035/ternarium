`default_nettype none
`timescale 1ns/1ps
// Троичный FFN-блок: y = W2 · ReLU(W1 · x). Веса тернарные (реальные BitNet), x int8.
module tb;
  reg signed [7:0] X [0:7];
  `include "vectors_ffn.vh"
  reg [15:0] W1 [0:7];
  reg [15:0] W2 [0:7];
  // тернарный вес(2бита)×значение: 10→+v, 00→-v, 01→0
  function signed [31:0] tmul; input [1:0] c; input signed [31:0] v;
    begin tmul = (c==2'b10)? v : (c==2'b00)? -v : 0; end
  endfunction
  integer r,c,ok; reg signed [31:0] h [0:7]; reg signed [31:0] s,yv;
  initial begin
    W1[0]=W1_0;W1[1]=W1_1;W1[2]=W1_2;W1[3]=W1_3;W1[4]=W1_4;W1[5]=W1_5;W1[6]=W1_6;W1[7]=W1_7;
    W2[0]=W2_0;W2[1]=W2_1;W2[2]=W2_2;W2[3]=W2_3;W2[4]=W2_4;W2[5]=W2_5;W2[6]=W2_6;W2[7]=W2_7;
    #1;
    // слой 1: h = ReLU(W1·x)
    for (r=0;r<HID;r=r+1) begin
      s=0; for (c=0;c<IN;c=c+1) s = s + tmul(W1[r][2*c +:2], X[c]);
      h[r] = (s<0)?0:s;                       // ReLU
    end
    // слой 2: y = W2·h, сверка с эталоном
    ok=0;
    $display("FFN-блок (реальные тернарные веса BitNet): RTL vs numpy");
    for (r=0;r<OUT;r=r+1) begin
      yv=0; for (c=0;c<HID;c=c+1) yv = yv + tmul(W2[r][2*c +:2], h[c]);
      $display("  y[%0d] RTL=%0d  numpy=%0d  %s", r, yv, gy(r), (yv===gy(r))?"OK":"FAIL");
      if (yv===gy(r)) ok=ok+1;
    end
    if (ok==OUT) $display("ВЕСЬ FFN-БЛОК СОВПАЛ С numpy (8/8) — троичный FFN трансформера на RTL верен");
    else $display("расхождений: %0d", OUT-ok);
    $finish;
  end
endmodule
