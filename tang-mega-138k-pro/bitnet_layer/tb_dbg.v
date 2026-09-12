`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk; reg rst_n=1;
  wire lcd_clk,lcd_en; wire [5:0] lcd_r,lcd_g,lcd_b; wire [2:0] sl;
  mlgru_screen uut(.clk(clk),.rst_n(rst_n),.lcd_clk(lcd_clk),.lcd_en(lcd_en),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),.state_led(sl));
  integer k;
  initial begin
    for(k=0;k<40;k=k+1) begin #200000;
      $display("t=%0t st=%0d mstart=%b mdone=%b cur_sit=%0d hold=%0d mstt=%0d g=%0d usend=%b",
        $time, uut.st, uut.mstart, uut.mdone, uut.cur_sit, uut.hold, uut.u.stt, uut.u.g, uut.usend);
    end
    $finish;
  end
endmodule
