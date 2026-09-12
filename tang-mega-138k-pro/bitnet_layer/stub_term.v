`default_nettype none
module tritterm(input wire clk,input wire rst_n,input wire rx,
  output wire lcd_clk,output wire lcd_en,output wire [5:0] lcd_r,output wire [5:0] lcd_g,output wire [5:0] lcd_b,output wire [2:0] state_led);
  assign lcd_clk=1'b0; assign lcd_en=1'b0; assign lcd_r=6'd0; assign lcd_g=6'd0; assign lcd_b=6'd0; assign state_led=3'd0;
endmodule
