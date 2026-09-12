// led_witness.v — silicon-witness: 8 результатов реального BitNet-слоя термометром на 5 LED.
// Нейрон выбирается СТАРШИМИ битами свободного счётчика (как в blink — init-независимо, без FSM).
// Число горящих LED = |значение|. Последовательность: 4,2,0,1,5,3,3,1 (~1.3с на шаг).
`default_nettype none
module led_witness(input wire clk,
  output wire led0, output wire led1, output wire led2, output wire led3, output wire led4);
  `include "bake.vh"
  wire signed [15:0] r [0:7];
  tritdot #(.N(16)) g0(.w_flat(WROW0),.x_flat(XV),.sum(r[0]));
  tritdot #(.N(16)) g1(.w_flat(WROW1),.x_flat(XV),.sum(r[1]));
  tritdot #(.N(16)) g2(.w_flat(WROW2),.x_flat(XV),.sum(r[2]));
  tritdot #(.N(16)) g3(.w_flat(WROW3),.x_flat(XV),.sum(r[3]));
  tritdot #(.N(16)) g4(.w_flat(WROW4),.x_flat(XV),.sum(r[4]));
  tritdot #(.N(16)) g5(.w_flat(WROW5),.x_flat(XV),.sum(r[5]));
  tritdot #(.N(16)) g6(.w_flat(WROW6),.x_flat(XV),.sum(r[6]));
  tritdot #(.N(16)) g7(.w_flat(WROW7),.x_flat(XV),.sum(r[7]));
  reg [28:0] cnt = 0;
  always @(posedge clk) cnt <= cnt + 1'b1;     // свободный счётчик, как blink
  wire [2:0] sel = cnt[28:26];                 // ~1.34с на нейрон
  reg signed [15:0] v;
  always @(*) case(sel)
    3'd0:v=r[0]; 3'd1:v=r[1]; 3'd2:v=r[2]; 3'd3:v=r[3];
    3'd4:v=r[4]; 3'd5:v=r[5]; 3'd6:v=r[6]; 3'd7:v=r[7]; endcase
  wire signed [15:0] mag = v[15] ? -v : v;
  assign led0 = ~(mag > 16'sd0);
  assign led1 = ~(mag > 16'sd1);
  assign led2 = ~(mag > 16'sd2);
  assign led3 = ~(mag > 16'sd3);
  assign led4 = ~(mag > 16'sd4);
endmodule
