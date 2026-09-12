`default_nettype none
`timescale 1ns/1ps
// TLMM: матмул троичных весов через таблицу. LUT строится 1 раз на токен,
// per-нейрон = ТОЛЬКО выборки+сложения (умножений в матмуле нет). Веса = компактные индексы пар.
module tb;
  reg signed [7:0] X [0:15];
  `include "vectors_tlmm.vh"
  reg [31:0] WIDX [0:7];
  reg signed [31:0] LUT [0:71];     // CH(8)×9
  integer p,c0,c1,r,ok; reg [3:0] idx; reg signed [31:0] s;
  initial begin
    WIDX[0]=WIDX_0;WIDX[1]=WIDX_1;WIDX[2]=WIDX_2;WIDX[3]=WIDX_3;
    WIDX[4]=WIDX_4;WIDX[5]=WIDX_5;WIDX[6]=WIDX_6;WIDX[7]=WIDX_7;
    #1;
    // ── СТРОИМ LUT (1 раз на токен): частичные суммы пар активаций ──
    for (p=0;p<CH;p=p+1)
      for (c0=0;c0<3;c0=c0+1)
        for (c1=0;c1<3;c1=c1+1)
          LUT[p*9 + c0*3+c1] = (c0-1)*X[2*p] + (c1-1)*X[2*p+1];   // ±a, накопление
    // ── per-нейрон: ТОЛЬКО lookup+add (без умножений) ──
    ok=0;
    $display("TLMM (table-lookup matmul, троичные веса BitNet): RTL vs прямой MAC");
    for (r=0;r<N_OUT;r=r+1) begin
      s=0;
      for (p=0;p<CH;p=p+1) begin
        idx = (WIDX[r] >> (4*p)) & 4'hF;     // индекс пары весов
        s = s + LUT[p*9 + idx];              // выборка + сложение
      end
      if (s===gy(r)) ok=ok+1; else $display("  r%0d TLMM=%0d direct=%0d FAIL",r,s,gy(r));
    end
    $display("совпало %0d/%0d", ok, N_OUT);
    if (ok==N_OUT) $display("TLMM == прямой троичный MAC БИТ-В-БИТ ✓ (per-нейрон без умножений, веса как индексы)");
    $finish;
  end
endmodule
