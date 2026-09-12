// tritlayer.v — слой BitNet: M нейронов × N входов, тернарные веса × int8-активации.
// Каждый нейрон — свой tritneuron-лейн; активации общие. Без умножителей.
`default_nettype none
module tritneuron #(parameter N=64) (
  input  wire [2*N-1:0] w_flat, input wire [8*N-1:0] a_flat,
  output wire signed [31:0] acc
);
  integer k; reg signed [31:0] s; reg signed [7:0] ai; reg [1:0] wi;
  always @(*) begin s=0;
    for (k=0;k<N;k=k+1) begin wi=w_flat[2*k +:2]; ai=a_flat[8*k +:8];
      case(wi) 2'b10:s=s+ai; 2'b00:s=s-ai; default:s=s; endcase end end
  assign acc=s;
endmodule
module tritlayer #(parameter M=16, N=64) (
  input  wire [2*M*N-1:0] W,   input wire [8*N-1:0] A,
  output wire [32*M-1:0]  Y
);
  genvar m;
  generate for (m=0;m<M;m=m+1) begin: neu
    tritneuron #(.N(N)) u(.w_flat(W[2*N*m +: 2*N]), .a_flat(A), .acc(Y[32*m +: 32]));
  end endgenerate
endmodule
