// tlmm_layer.v — синтезируемый троичный линейный слой через TLMM (NIN→NOUT).
// Веса = индексы пар в BRAM (4 бита/пара). LUT частичных сумм строится 1 раз/токен в BRAM.
// Compute: на нейрон CH тактов (выборка+сложение). НИ ОДНОГО умножителя.
//
// BRAM-карта (выверено под Gowin BSRAM):
//   wmem (NOUT*CH*4 бит = 128 Кбит) — block, 1 порт записи (загрузка), 1 синхр. чтение
//   lut  (CH*9*20  бит ≈  23 Кбит)  — block, 1 порт записи (BUILD 1 entry/такт), 1 синхр. чтение
//   amem (NIN*8    бит =   2 Кбит)  — distributed (асинхр. парное чтение a0/a1)
//   omem (NOUT*32  бит =   8 Кбит)  — distributed (асинхр. чтение наружу)
`default_nettype none
module tlmm_layer #(parameter NIN=256, parameter NOUT=256, parameter CH=NIN/2) (
  input  wire clk, input wire rst, input wire start,
  input  wire        wr_a, input wire [8:0]  a_addr, input wire signed [7:0] a_data, // загрузка активаций
  input  wire        wr_w, input wire [15:0] w_addr, input wire [3:0]        w_data, // загрузка весов(индексы)
  input  wire [8:0]  o_addr, output wire signed [31:0] o_data,                       // чтение выхода
  output reg  done
);
  (* ram_style="distributed" *) reg signed [7:0]  amem [0:NIN-1];
  (* ram_style="block" *)       reg [3:0]         wmem [0:NOUT*CH-1];  // индекс пары 0..8
  (* ram_style="block" *)       reg signed [19:0] lut  [0:CH*9-1];
  (* ram_style="distributed" *) reg signed [31:0] omem [0:NOUT-1];

  assign o_data = omem[o_addr];

  localparam IDLE=0, BUILD=1, COMP=2, FIN=3;
  reg [1:0] st;
  reg [15:0] p, n;            // индекс чанка / нейрона
  reg [3:0]  k;               // entry внутри чанка 0..8
  reg [19:0] lbase;           // = p*9 (аккумулятор, без умножителя)
  reg [23:0] wbase;           // = n*CH (аккумулятор)
  reg signed [31:0] acc;
  reg [1:0]  ph;              // микрофаза COMP

  wire signed [19:0] a0 = {{12{amem[2*p][7]}},   amem[2*p]};
  wire signed [19:0] a1 = {{12{amem[2*p+1][7]}}, amem[2*p+1]};
  function signed [19:0] sel; input [1:0] c; input signed [19:0] a;
    begin sel=(c==0)?-a:(c==2)?a:20'sd0; end endfunction
  reg [1:0] c0, c1;
  always @* begin
    case (k)
      0:{c0,c1}={2'd0,2'd0}; 1:{c0,c1}={2'd0,2'd1}; 2:{c0,c1}={2'd0,2'd2};
      3:{c0,c1}={2'd1,2'd0}; 4:{c0,c1}={2'd1,2'd1}; 5:{c0,c1}={2'd1,2'd2};
      6:{c0,c1}={2'd2,2'd0}; 7:{c0,c1}={2'd2,2'd1}; default:{c0,c1}={2'd2,2'd2};
    endcase
  end

  reg [3:0]         widx_r;
  reg signed [19:0] lval_r;
  reg [19:0] laddr;

  // on-chip ROM-инициализация (так веса/активации реально лежат в BRAM; load-порты переписывают)
  integer ii;
  initial begin
    for (ii=0; ii<NIN;      ii=ii+1) amem[ii] = ii-128;
    for (ii=0; ii<NOUT*CH;  ii=ii+1) wmem[ii] = ii % 9;
    for (ii=0; ii<CH*9;     ii=ii+1) lut[ii]  = 0;
    for (ii=0; ii<NOUT;     ii=ii+1) omem[ii] = 0;
  end

  always @(posedge clk) begin
    if (wr_a) amem[a_addr] <= a_data;
    if (wr_w) wmem[w_addr] <= w_data;
    widx_r <= wmem[wbase + p];
    lval_r <= lut[laddr];

    if (rst) begin st<=IDLE; done<=0; p<=0; n<=0; k<=0; lbase<=0; wbase<=0; acc<=0; ph<=0; end
    else case (st)
      IDLE: if (start) begin st<=BUILD; p<=0; k<=0; lbase<=0; done<=0; end
      BUILD: begin
        lut[lbase+k] <= sel(c0,a0) + sel(c1,a1);
        if (k==8) begin
          k<=0;
          if (p==CH-1) begin st<=COMP; n<=0; p<=0; wbase<=0; acc<=0; lbase<=0; ph<=0; end
          else begin p<=p+1; lbase<=lbase+9; end
        end else k<=k+1;
      end
      // 4 фазы/чанк: цепочка из двух зависимых BRAM-чтений (wmem->lut) по такту латентности
      COMP: case (ph)
        0: ph<=1;                              // widx_r <= wmem[wbase+p] защёлкнулся в конце ph0
        1: begin laddr<=lbase+widx_r; ph<=2; end
        2: ph<=3;                              // lval_r <= lut[laddr] защёлкнётся в конце ph2
        3: begin
          acc <= acc + lval_r;
          if (p==CH-1) begin
            omem[n] <= acc + lval_r;
            if (n==NOUT-1) st<=FIN;
            else begin n<=n+1; wbase<=wbase+CH; p<=0; lbase<=0; acc<=0; ph<=0; end
          end else begin p<=p+1; lbase<=lbase+9; ph<=0; end
        end
      endcase
      FIN: begin done<=1; st<=IDLE; end
    endcase
  end
endmodule
