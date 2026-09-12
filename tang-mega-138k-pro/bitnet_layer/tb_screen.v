`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=1;
  wire lcd_clk,lcd_en; wire [5:0] lcd_r,lcd_g,lcd_b; wire [2:0] state_led;
  mlgru_screen uut(.clk(clk),.rst_n(rst_n),.lcd_clk(lcd_clk),.lcd_en(lcd_en),
    .lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b),.state_led(state_led));
  integer nl=0;
  always @(posedge clk) if(uut.usend) begin
    $write("%c",uut.ud);
    if(uut.ud==8'h0A) begin nl=nl+1; if(nl==4) $finish; end
  end
  initial begin #2000000000; $finish; end
endmodule
