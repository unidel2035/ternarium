// tlmm_engine.v — синтезируемый Table-Lookup Matmul движок (троичные веса).
// LUT частичных сумм пар активаций (комбинационно), нейрон = последовательное накопление
// выборок из LUT. НИ ОДНОГО умножителя (DSP=0) — троичность + таблица.
`default_nettype none
module tlmm_engine #(parameter NIN=64, parameter CH=NIN/2) (
  input  wire                 clk,
  input  wire                 rst,
  input  wire                 start,
  input  wire [8*NIN-1:0]     x_flat,      // NIN активаций int8
  input  wire [4*CH-1:0]      widx,        // индексы пар весов нейрона (4 бита/пара)
  output reg  signed [31:0]   result,
  output reg                  done
);
  // ── LUT: на пару p и паттерн (c0,c1) частичная сумма (c0-1)*a0 + (c1-1)*a1 ──
  wire signed [31:0] lut [0:CH*9-1];
  genvar p,a,b;
  generate for (p=0;p<CH;p=p+1) begin: gp
    wire signed [7:0] a0 = x_flat[8*(2*p)   +: 8];
    wire signed [7:0] a1 = x_flat[8*(2*p+1) +: 8];
    wire signed [31:0] a0e = {{24{a0[7]}},a0};
    wire signed [31:0] a1e = {{24{a1[7]}},a1};
    for (a=0;a<3;a=a+1) for (b=0;b<3;b=b+1) begin: gpat
      // (a-1),(b-1) — константы генвара {-1,0,+1} → чистый выбор ±/0, без умножителя
      assign lut[p*9 + a*3 + b] = ((a==0)? -a0e : (a==2)? a0e : 32'sd0)
                                + ((b==0)? -a1e : (b==2)? a1e : 32'sd0);
    end
  end endgenerate
  // ── последовательное накопление по парам ──
  reg [15:0] pi;
  reg [15:0] base;                       // = pi*9, ведём аккумулятором (без умножителя)
  wire [3:0] idx = widx[4*pi +: 4];
  always @(posedge clk) begin
    if (rst) begin result<=0; pi<=0; base<=0; done<=0; end
    else if (start && !done) begin
      result <= result + lut[base + idx];
      if (pi==CH-1) done<=1; else begin pi<=pi+1; base<=base+9; end
    end
  end
endmodule
