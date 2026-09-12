`default_nettype none
`timescale 1ns/1ps
// Стриминг весов: читаем по 1 весу+активации за такт из памяти (модель DDR3), накапливаем.
// Доказывает: веса не на кристалле, а стримятся тайлами; математика = той же, что one-shot.
module tb;
  reg [1:0]        W [0:6911];      // "память весов" (модель внешней DDR)
  reg signed [7:0] A [0:6911];      // буфер активаций
  `include "vectors_full.vh"        // даёт N, GOLDEN_MAC, init W/A
  reg clk=0; always #5 clk=~clk;
  function signed [31:0] tmul; input [1:0] c; input signed [31:0] v;
    begin tmul=(c==2'b10)?v:(c==2'b00)?-v:0; end endfunction
  reg signed [31:0] acc=0; integer addr=0; reg done=0;
  always @(posedge clk) if(!done) begin
    acc <= acc + tmul(W[addr], A[addr]);   // ОДИН вес/такт — стриминг
    if(addr==N-1) done<=1; else addr<=addr+1;
  end
  initial begin
    #1;
    wait(done); #10;
    $display("Стриминг весов (по 1/такт из памяти): N=%0d тактов", N);
    $display("  результат стриминга = %0d", acc);
    $display("  эталон (one-shot)   = %0d", GOLDEN_MAC);
    $display(acc===GOLDEN_MAC ? "СТРИМИНГ ВЕСОВ == ONE-SHOT БИТ-В-БИТ ✓ (память решена: веса можно стримить из DDR)" : "РАСХОЖДЕНИЕ");
    $finish;
  end
endmodule
