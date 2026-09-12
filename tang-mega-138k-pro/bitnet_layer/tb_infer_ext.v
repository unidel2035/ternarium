`timescale 1ns/1ps
`default_nettype none
// tb_infer_ext.v — проверка ext-режима model_infer_dom (Трек C, п.3).
// Подаёт несколько тестовых контекстов в ctx_in при ext=1, делает ОДИН forward,
// сверяет команду gtok[0] с software-эталоном (integ_demo.py → vectors_ext.vh). Бит-в-бит.
module tb_infer_ext;
  `include "model_vectors.vh"     // V,D,L,H,S,... (конфиг) — тот же, что в RTL
  `include "vectors_ext.vh"       // NS, CTX_k, ECMD_k (golden из integ_demo.py)

  reg clk=0, rst=1, start=0, ext=0; reg [7:0] taddr=0; reg [8*S-1:0] ctx=0;
  wire [7:0] tout; wire done;
  model_infer_dom dut(.clk(clk),.rst(rst),.start(start),.tok_addr(taddr),
    .tok_out(tout),.done(done),.ext(ext),.ctx_in(ctx));
  always #5 clk=~clk;

  // golden в массивы (localparam → reg[] для индексации в цикле)
  reg [8*S-1:0] CTX [0:NS-1];
  reg [7:0]     ECMD[0:NS-1];

  integer k, ok, cyc; reg [7:0] got;
  initial begin
    CTX[0]=CTX_0; CTX[1]=CTX_1; CTX[2]=CTX_2; CTX[3]=CTX_3;
    CTX[4]=CTX_4; CTX[5]=CTX_5; CTX[6]=CTX_6; CTX[7]=CTX_7;
    ECMD[0]=ECMD_0; ECMD[1]=ECMD_1; ECMD[2]=ECMD_2; ECMD[3]=ECMD_3;
    ECMD[4]=ECMD_4; ECMD[5]=ECMD_5; ECMD[6]=ECMD_6; ECMD[7]=ECMD_7;

    repeat(3)@(posedge clk); rst<=0; @(posedge clk);
    ok=0;
    $display("ext-режим: контекст (S=%0d токенов) → ОДНА команда (gtok[0])",S);
    for (k=0;k<NS;k=k+1) begin
      // подать контекст и запустить один forward
      @(posedge clk); ext<=1; ctx<=CTX[k]; start<=1;
      @(posedge clk); start<=0;
      // start уже снял done в IDLE; ждём фронта done этого прогона
      cyc=0; while(done) @(posedge clk);        // дождаться спада done от старта
      while(!done) begin @(posedge clk); cyc=cyc+1; end
      taddr=0; #1; got=tout;
      $display("  case %0d: cmd=%0d  (эталон %0d)  %s  [%0d цикл]",
        k, got, ECMD[k], (got===ECMD[k])?"OK":"MISMATCH", cyc);
      if (got===ECMD[k]) ok=ok+1;
      @(posedge clk);   // вернуться в IDLE до следующего start
    end
    $display("совпало %0d/%0d", ok, NS);
    if (ok==NS) $display("EXT-РЕЖИМ == software-эталон (integ_demo) ✓ бит-в-бит сквозной конвейер");
    else        $display("РАСХОЖДЕНИЕ ✗");
    $finish;
  end
endmodule
