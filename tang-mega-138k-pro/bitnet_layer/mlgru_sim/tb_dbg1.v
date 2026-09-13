// tb_dbg1.v — отладка: один шаг генерации, дамп x/xn после LOG и argmax.
`timescale 1ns/1ps
module tb_dbg1;
  `include "mlgru_vectors.vh"
  reg clk = 1'b0;
  reg ce = 1'b1, rst = 1'b1, start = 1'b0, use_ext = 1'b0;
  reg [1:0] sit = 2'd0;
  reg [63:0] seed_flat = 64'd0;
  wire [7:0] tok_out; wire done;
  model_mlgru dut (.clk(clk), .ce(ce), .rst(rst), .start(start), .sit(sit), .use_ext(use_ext),
                   .seed_flat(seed_flat), .tok_addr(8'd0), .tok_out(tok_out), .done(done));
  always #5 clk = ~clk;
  integer i;
  always @(posedge clk)
    if (!rst && ce && dut.stt == 5'd11 && dut.l == 2 && dut.t == S-1) begin   // REC, посл. токен, слой 2
      #1;
      $write("REC fg ="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.fg[i]); $write("\n");
      $write("REC cg ="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.cg[i]); $write("\n");
      $write("REC gg ="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.gg2[i]); $write("\n");
      $write("REC hs_prev ="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.hs[2*D+i]); $write("\n");
    end
  always @(posedge clk)
    if (!rst && ce && dut.stt == 5'd20) begin
      #1;
      $display("barg=%0d best=%0d", dut.barg, dut.best);
      $write("x  ="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.x[i]); $write("\n");
      $write("xn ="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.xn[i]); $write("\n");
      $write("hs2="); for (i = 0; i < D; i = i + 1) $write(" %0d", dut.hs[2*D+i]); $write("\n");
      $write("logits(pre) первые 8 строк OUT:");
      for (i = 0; i < 8; i = i + 1) $write(" %0d", dut.mvw(dut.wrom[dut.B_OUT+i], D));
      $write("\n");
      $finish;
    end
  initial begin
    repeat (4) @(posedge clk); rst <= 1'b0;
    repeat (4) @(posedge clk); start <= 1'b1;
    @(posedge clk); start <= 1'b0;
    #100000000 $display("FAIL: таймаут первого токена");
    $finish;
  end
endmodule
