`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk; reg rst_n=1;
  wire lcd_clk,lcd_en; wire [5:0] lcd_r,lcd_g,lcd_b; wire [2:0] sl;
  mlgru_screen uut(.clk(clk),.rst_n(rst_n),.lcd_clk(lcd_clk),.lcd_en(lcd_en),.lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),.state_led(sl));
  reg prevdone=0; integer seen=0;
  always @(posedge clk) begin
    if(uut.mdone && !prevdone) begin
      $display("СИТУАЦИЯ %0d → решение токены: %0d %0d %0d %0d %0d %0d",
        uut.cur_sit, uut.u.gtok[0],uut.u.gtok[1],uut.u.gtok[2],uut.u.gtok[3],uut.u.gtok[4],uut.u.gtok[5]);
      seen=seen+1; if(seen==4) $finish;
    end
    prevdone<=uut.mdone;
  end
  initial begin #20000000000; $display("timeout seen=%0d",seen); $finish; end
endmodule
