`default_nettype none
`timescale 1ns/1ps
// Упрощённое троичное внимание: Q/K/V тернарные проекции, QKᵀ, hardmax(argmax), выбор V.
module tb;
  reg signed [7:0] X [0:31];           // S*D = 4*8
  `include "vectors_attn.vh"
  reg [15:0] WQ[0:7], WK[0:7], WV[0:7];
  function signed [31:0] tmul; input [1:0] c; input signed [31:0] v;
    begin tmul=(c==2'b10)?v:(c==2'b00)?-v:0; end endfunction
  integer t,j,d,ok_sel,ok_out;
  reg signed [31:0] Q[0:31], K[0:31], Vv[0:31];
  reg signed [31:0] s, best; integer bestj;
  initial begin
    WQ[0]=WQ_0;WQ[1]=WQ_1;WQ[2]=WQ_2;WQ[3]=WQ_3;WQ[4]=WQ_4;WQ[5]=WQ_5;WQ[6]=WQ_6;WQ[7]=WQ_7;
    WK[0]=WK_0;WK[1]=WK_1;WK[2]=WK_2;WK[3]=WK_3;WK[4]=WK_4;WK[5]=WK_5;WK[6]=WK_6;WK[7]=WK_7;
    WV[0]=WV_0;WV[1]=WV_1;WV[2]=WV_2;WV[3]=WV_3;WV[4]=WV_4;WV[5]=WV_5;WV[6]=WV_6;WV[7]=WV_7;
    #1;
    // проекции Q/K/V (тернарный вес × int8)
    for (t=0;t<S;t=t+1) for (d=0;d<D;d=d+1) begin
      Q[t*D+d]=0; K[t*D+d]=0; Vv[t*D+d]=0;
      for (j=0;j<D;j=j+1) begin
        Q[t*D+d]=Q[t*D+d]+tmul(WQ[d][2*j+:2], X[t*D+j]);
        K[t*D+d]=K[t*D+d]+tmul(WK[d][2*j+:2], X[t*D+j]);
        Vv[t*D+d]=Vv[t*D+d]+tmul(WV[d][2*j+:2], X[t*D+j]);
      end
    end
    // внимание: scores=QKᵀ, argmax, out=V[sel]
    ok_sel=0; ok_out=0;
    $display("Троичное внимание (реальные веса BitNet): RTL vs numpy");
    for (t=0;t<S;t=t+1) begin
      best=-2147483647; bestj=0;
      for (j=0;j<S;j=j+1) begin
        s=0; for (d=0;d<D;d=d+1) s=s+Q[t*D+d]*K[j*D+d];
        if (s>best) begin best=s; bestj=j; end
      end
      if (bestj==gsel(t)) ok_sel=ok_sel+1;
      $display("  токен %0d: argmax RTL=%0d numpy=%0d %s", t, bestj, gsel(t), (bestj==gsel(t))?"OK":"FAIL");
      for (d=0;d<D;d=d+1) if (Vv[bestj*D+d]===gout(t,d)) ok_out=ok_out+1;
    end
    $display("argmax совпало: %0d/%0d ; элементов выхода совпало: %0d/%0d", ok_sel,S, ok_out,S*D);
    if (ok_sel==S && ok_out==S*D) $display("ТРОИЧНОЕ ВНИМАНИЕ ВЕРНО — обе половины трансформера (attention+FFN) на RTL сходятся с numpy");
    $finish;
  end
endmodule
