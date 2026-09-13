// tb_neutral.v — проверка model_mlgru.v (нейтральная байтовая MLGRU, CP1251) против golden.
//
// Схема проверки:
//   * затравка — S=48 байт SEED_0..SEED_47 ("...Сетунь — "), подаётся через ситуация-ROM
//     seedrom.hex (sit=0, use_ext=0: seed_flat в RTL всего 64 бита, 48 байт туда не влезают);
//   * RTL генерит NGEN=64 токенов; каждый сгенерированный байт снимается иерархически
//     в состоянии NXT (stt=20), где RTL делает gtok[g]=barg (массив gtok в RTL всего 16 слов,
//     поэтому через порт tok_out читаются только первые 16 токенов — это отдельная
//     контрольная проверка интерфейса);
//   * golden — GTOK_* из mlgru_vectors.vh: первые 9 байт — это хвост затравки (промпт),
//     поэтому сравнивается gen[i] с GTOK_{9+i} (файл gold_gen.hex, см. gen_gold.py).
//
// Запуск: iverilog -g2005 -o sim.vvp model_mlgru.v fxops.v tb_neutral.v && vvp sim.vvp
// Трасса: iverilog -g2005 -DTRACE ... && vvp a.out
`timescale 1ns/1ps
module tb_neutral;
  `include "mlgru_vectors.vh"

  reg clk = 1'b0;
  reg ce = 1'b1, rst = 1'b1, start = 1'b0, use_ext = 1'b0;
  reg [1:0] sit = 2'd0;
  reg [63:0] seed_flat = 64'd0;
  reg [7:0] tok_addr = 8'd0;
  wire [7:0] tok_out;
  wire done;

  model_mlgru dut (.clk(clk), .ce(ce), .rst(rst), .start(start), .sit(sit),
                   .use_ext(use_ext), .seed_flat(seed_flat),
                   .tok_addr(tok_addr), .tok_out(tok_out), .done(done));

  always #5 clk = ~clk;                       // 100 МГц, модель шагает по ce=1 каждый такт

  // ── golden: сгенерированная часть GTOK (gold_gen.hex) ──
  reg [7:0] goldgen [0:NGEN-1];
  initial $readmemh("gold_gen.hex", goldgen);

  // ── та же затравка, что читает DUT (seedrom.hex = 4 x SEED) ──
  reg [7:0] seedr [0:4*S-1];
  initial $readmemh("seedrom.hex", seedr);

  // ── захват NGEN сгенерированных байтов ──
  reg [7:0] gen [0:NGEN-1];
  integer ncap;
  initial ncap = 0;
  always @(posedge clk)
    if (!rst && ce && dut.stt == 5'd20) begin  // 20 = NXT: такт записи gtok[g]=barg
      gen[dut.g] <= dut.barg[7:0];
      ncap       <= ncap + 1;
    end

  integer i, match, mism, cmp, cnt, timeout;
  reg [7:0] gb;
  integer fhex, fbin;

`ifdef TRACE
  integer cyc; initial cyc = 0;
  integer sttcnt [0:31];
  initial for (i = 0; i < 32; i = i + 1) sttcnt[i] = 0;
  always @(posedge clk) sttcnt[dut.stt] = sttcnt[dut.stt] + 1;
  always @(posedge clk) begin
    cyc = cyc + 1;
    if (cyc % 500000 == 0)
      $display("cyc=%0d stt=%0d rst=%b start=%b g=%0d t=%0d l=%0d dd=%0d mvo=%0d done=%b ncap=%0d",
               cyc, dut.stt, rst, start, dut.g, dut.t, dut.l, dut.dd, dut.mvo, done, ncap);
  end
`endif

  initial begin
    match = 0; mism = 0; cmp = 0; timeout = 0;
    // сброс и старт (все входы DUT — через NBA, чтобы не было гонки на сэмплировании)
    repeat (4) @(posedge clk);
    rst <= 1'b0;
    repeat (4) @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    // ждём done (порядка ~3.5k тактов на токен x 64 токена)
    while (done !== 1'b1 && timeout < 50000000) begin @(posedge clk); timeout = timeout + 1; end
    if (done !== 1'b1) begin
      $display("FAIL: done не пришёл за %0d тактов (stt=%0d ncap=%0d)", timeout, dut.stt, ncap);
      $finish;
    end
    #1;
    $display("done через %0d тактов, захвачено %0d токенов", timeout, ncap);

    // контроль интерфейса: первые 16 токенов обязаны читаться через tok_out
    cnt = 0;
    for (i = 0; i < 16; i = i + 1) begin
      tok_addr <= i[7:0]; repeat (2) @(posedge clk); #1;
      if (tok_out !== gen[i]) begin
        $display("  интерфейс: tok_out[%0d]=%02x != gen=%02x", i, tok_out, gen[i]);
        cnt = cnt + 1;
      end
    end
    if (cnt == 0) $display("интерфейс tok_addr/tok_out: первые 16 токенов совпадают с захватом");

    // сверка с golden
    for (i = 0; i < NGEN; i = i + 1) begin
      gb = goldgen[i];
      if (gb === 8'hxx) begin end            // за пределами golden (NGEN > golden-хвоста)
      else begin
        cmp = cmp + 1;
        if (gen[i] === gb) match = match + 1;
        else begin
          mism = mism + 1;
          if (mism <= 12) $display("  расхождение tok[%0d]: RTL=%02x (%c)  golden=%02x (%c)",
                                   i, gen[i], gen[i], gb, gb);
        end
      end
    end

    // дамп: out_gen.hex (по байту на строку) и out_full.bin (затравка + генерация, cp1251)
    fhex = $fopen("out_gen.hex", "w");
    for (i = 0; i < NGEN; i = i + 1) $fdisplay(fhex, "%02x", gen[i]);
    $fclose(fhex);
    fbin = $fopen("out_full.bin", "wb");
    for (i = 0; i < S; i = i + 1) $fwrite(fbin, "%c", seedr[i]);
    for (i = 0; i < NGEN; i = i + 1) $fwrite(fbin, "%c", gen[i]);
    $fclose(fbin);

    $display("генерация (hex): %02x %02x %02x %02x ...", gen[0], gen[1], gen[2], gen[3]);
`ifdef TRACE
    $display("циклов по состояниям FSM (IDLE=0,LD=1,RMS=2,SQW=3,DVV=4,DVR=5,DVW=6,MV=7,MVR=8,GSET=9,GCP=10,REC=11,GHSET=12,FRMS=13,FSET=14,FUSET=15,FCP=16,FGU=17,NEXTL=18,LARG=19,NXT=20,FIN=21,LOG=22,MVR2=23):");
    for (i = 0; i < 24; i = i + 1) if (sttcnt[i] != 0) $display("  stt=%0d: %0d циклов", i, sttcnt[i]);
`endif
    $display("=== ИТОГ: сравнимо %0d, совпало %0d, расхождений %0d ===", cmp, match, mism);
    if (mism == 0 && cmp > 0) $display("PASS");
    else $display("FAIL");
    $finish;
  end

  // сторожевой тайм-аут (глобальный, больше лимита цикла ожидания выше)
  initial begin
    #600000000;
    $display("FAIL: глобальный таймаут"); $finish;
  end
endmodule
