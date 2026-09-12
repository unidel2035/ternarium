`default_nettype none
`timescale 1ns/1ps
module tb;
  reg a,b; wire y,h0,h1; integer i,ok;
  tritmlp dut(.x0b(a),.x1b(b),.y(y),.h0o(h0),.h1o(h1));
  initial begin
    ok=0; $display("x0 x1 | h0 h1 | y | XOR");
    for(i=0;i<4;i=i+1) begin
      {b,a}=i[1:0]; #1;
      $display(" %0d  %0d |  %0d  %0d | %0d |  %0d  %s", a,b,h0,h1,y,(a^b),(y==(a^b))?"OK":"FAIL");
      if(y==(a^b)) ok=ok+1;
    end
    $display(ok==4?"\n2-СЛОЙНАЯ ТРОИЧНАЯ СЕТЬ СЧИТАЕТ XOR ✓ (нелинейно — один слой так не может)":"\nОШИБКА");
    $finish;
  end
endmodule
