// tritdot.v — троичный dot-product (ядро нейрона BitNet) на балансной троичной логике.
// Кодировка тритов (как в tritnet/tritmul): -1=2'b00, 0=2'b01, +1=2'b10.
`default_nettype none

// Таблица умножения тритов — 1:1 из вашего tritmul.v
module trit_mul(input wire [1:0] a, input wire [1:0] b, output reg [1:0] p);
  always @(*) begin
    if (a==2'b01 || b==2'b01) p = 2'b01;   // 0*x=0
    else if (a==b)            p = 2'b10;   // одинаковые знаки → +1
    else                      p = 2'b00;   // разные → -1
  end
endmodule

// dot = Σ wᵢ·xᵢ, вход — N тритов (по 2 бита), выход — знаковая сумма
module tritdot #(parameter N=16) (
  input  wire [2*N-1:0]      w_flat,
  input  wire [2*N-1:0]      x_flat,
  output wire signed [15:0]  sum
);
  wire [1:0] p [0:N-1];
  genvar i;
  generate for (i=0;i<N;i=i+1) begin: lane
    trit_mul u(.a(w_flat[2*i +: 2]), .b(x_flat[2*i +: 2]), .p(p[i]));
  end endgenerate
  // код произведения → знаковое значение и накопление
  integer k; reg signed [15:0] acc;
  always @(*) begin
    acc = 0;
    for (k=0;k<N;k=k+1)
      acc = acc + ((p[k]==2'b10) ? 16'sd1 : (p[k]==2'b00) ? -16'sd1 : 16'sd0);
  end
  assign sum = acc;
endmodule
