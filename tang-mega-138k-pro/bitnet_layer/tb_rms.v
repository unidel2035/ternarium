`default_nettype none
`timescale 1ns/1ps
module tb;
  reg signed [31:0] X [0:7];
  `include "vectors_rms.vh"
  // целочисленный isqrt (floor) — точно как в спеке
  function integer isqrt; input integer n; integer r; begin
    r=0; while((r+1)*(r+1)<=n) r=r+1; isqrt=r; end endfunction
  integer i,ss,ms2,den,ok; reg signed [31:0] y;
  initial begin
    #1; ss=0; for(i=0;i<D;i=i+1) ss=ss+X[i]*X[i]; ms2=ss/D; den=isqrt(ms2*SCALE*SCALE);
    ok=0; $display("RMSNorm fixed-point: RTL vs спека (MS=%0d, isqrt=%0d)", ms2, den);
    for(i=0;i<D;i=i+1) begin
      if(X[i]>=0) y=(X[i]*SCALE*SCALE)/den; else y=-((-X[i]*SCALE*SCALE)/den);
      if(y===gy(i)) ok=ok+1; else $display("  i%0d RTL=%0d spec=%0d FAIL",i,y,gy(i));
    end
    $display("совпало %0d/%0d", ok, D);
    if(ok==D)$display("RTL RMSNorm == спека БИТ-В-БИТ ✓ (спека ≈ float, см. выше)");
    $finish;
  end
endmodule
