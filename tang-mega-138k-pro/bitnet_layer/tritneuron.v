// tritneuron.v — полный нейрон BitNet: тернарный вес × int8-активация, без умножителя.
// Вес {-1,0,+1} (коды 00/01/10) ВЫБИРАЕТ +a / -a / 0 → знаковое накопление.
`default_nettype none
module tritneuron #(parameter N=6912) (
  input  wire [2*N-1:0]       w_flat,   // N тернарных кодов
  input  wire [8*N-1:0]       a_flat,   // N int8 активаций
  output wire signed [31:0]   acc
);
  integer k; reg signed [31:0] s;
  reg signed [7:0] ai; reg [1:0] wi;
  always @(*) begin
    s = 0;
    for (k=0;k<N;k=k+1) begin
      wi = w_flat[2*k +: 2];
      ai = a_flat[8*k +: 8];
      case (wi)
        2'b10:  s = s + ai;       // +1 → +a
        2'b00:  s = s - ai;       // -1 → -a
        default: s = s;           // 0  → пропуск (кенозис)
      endcase
    end
  end
  assign acc = s;
endmodule
