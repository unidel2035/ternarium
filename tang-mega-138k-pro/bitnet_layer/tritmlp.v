// tritmlp.v — 2-слойная троичная сеть на ПЛИС: XOR из тернарных нейронов.
// Шаг к LLM: один слой = линейно (рефлекс), ДВА слоя+нелинейность = нелинейно (XOR) = блок FFN.
// Скрытый слой: 2 нейрона, входы [x0,x1,bias=+1], веса тернарные. Тернаризация sign между слоями.
// Выход: 1 нейрон от [h0,h1,bias]. y = XOR(x0,x1).  Всё на вашем tritdot.
// Кодировка: +1=2'b10, -1=2'b00, 0=2'b01.
`default_nettype none
module tritmlp(input wire x0b, input wire x1b,   // входы ±1 (b=1→+1)
               output wire y, output wire h0o, output wire h1o);
  localparam [1:0] P=2'b10, M=2'b00;             // +1, -1
  wire [1:0] x0 = x0b?P:M, x1 = x1b?P:M, BIAS=P;
  // скрытый слой
  wire signed [15:0] s0,s1;
  tritdot #(.N(3)) H0(.w_flat({M,P,P}), .x_flat({BIAS,x1,x0}), .sum(s0)); // w=[+1,+1,-1] → AND
  tritdot #(.N(3)) H1(.w_flat({M,M,M}), .x_flat({BIAS,x1,x0}), .sum(s1)); // w=[-1,-1,-1] → NOR
  wire h0 = (s0>0), h1 = (s1>0);                  // тернаризация (sign)
  wire [1:0] h0c = h0?P:M, h1c = h1?P:M;
  // выходной слой: y = sign(-h0 -h1 -1)
  wire signed [15:0] sy;
  tritdot #(.N(3)) Y(.w_flat({M,M,M}), .x_flat({BIAS,h1c,h0c}), .sum(sy));
  assign y = (sy>0);
  assign h0o=h0; assign h1o=h1;
endmodule
