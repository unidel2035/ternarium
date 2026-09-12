`timescale 1ns/1ps
`default_nettype none
module tb_block_layer;
  reg signed [31:0] X[0:31]; integer EXPLUT[0:31];
  `include "vectors_block.vh"          // D,S,..., fills X/EXPLUT, gy()
  reg clk=0, rst=1, start=0;
  reg [$clog2(S*D)-1:0] yaddr=0; wire signed [31:0] yout; wire done;
  block_layer dut(.clk(clk),.rst(rst),.start(start),.y_addr(yaddr),.y_out(yout),.done(done));
  always #5 clk=~clk;
  integer t,i,ok,fail;
  initial begin
    repeat(3) @(posedge clk); rst<=0; @(posedge clk);
    start<=1; @(posedge clk); start<=0;
    while(!done) @(posedge clk);
    @(posedge clk);
    ok=0; fail=0;
    for(t=0;t<S;t=t+1) for(i=0;i<D;i=i+1) begin
      yaddr = t*D+i; #1;
      if(yout===gy(t,i)) ok=ok+1;
      else begin fail=fail+1; $display("  t%0d d%0d SEQ=%0d golden=%0d FAIL",t,i,yout,gy(t,i)); end
    end
    $display("СЕКВЕНСЕР СЛОЯ: совпало %0d/%0d с golden", ok, S*D);
    if(fail==0) $display("BLOCK_LAYER == fixed-спека БИТ-В-БИТ ✓ — один слой исполняется целиком через FSM");
    else $display("FAIL: %0d расхождений", fail);
    $finish;
  end
endmodule
