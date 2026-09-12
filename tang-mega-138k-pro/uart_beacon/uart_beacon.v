// маяк: каждый пин непрерывно шлёт свой символ (115200@50МГц). Читаем ttyUSB1.
module txchar(input wire clk,input wire [7:0] ch,output reg tx=1);
  reg [15:0] div=0; reg [3:0] cnt=0; reg [9:0] sh=10'h3FF;
  always @(posedge clk) begin
    if(cnt==0) begin sh<={1'b1,ch,1'b0}; cnt<=10; div<=16'd433; tx<=1'b1; end
    else if(div==0) begin tx<=sh[0]; sh<={1'b1,sh[9:1]}; cnt<=cnt-1; div<=16'd433; end
    else div<=div-1;
  end
endmodule
module uart_beacon(input wire clk,
  output wire p_u16,output wire p_v16,output wire p_p15,output wire p_v22,
  output wire [2:0] state_led);
  txchar tU(.clk(clk),.ch(8'h55),.tx(p_u16)); // 'U'
  txchar tW(.clk(clk),.ch(8'h57),.tx(p_v16)); // 'W'
  txchar tP(.clk(clk),.ch(8'h50),.tx(p_p15)); // 'P'
  txchar tV(.clk(clk),.ch(8'h56),.tx(p_v22)); // 'V'
  reg [24:0] bl=0; always @(posedge clk) bl<=bl+1;
  assign state_led={2'b11,~bl[23]};
endmodule
