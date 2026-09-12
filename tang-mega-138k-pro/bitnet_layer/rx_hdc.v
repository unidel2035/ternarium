// rx_hdc.v — бортовой приёмник «языка геометрии»: радио-пакет (base-3, 5 тритов/байт, формат
// pack() из ternary_comms.py) → распаковка ROM (3^5=243, без делений) → сборка чанков запроса →
// SEARCH по словарю смыслов → распознанный индекс. Единый RTL-блок поверх движка hdc.
`default_nettype none
module rx_hdc #(parameter D=384, parameter M=8, parameter LANES=16) (
  input  wire clk, input wire rst,
  input  wire wr, input wire [$clog2(M*((D+LANES-1)/LANES))-1:0] waddr, input wire [2*LANES-1:0] wdata, // словарь
  input  wire byte_valid, input wire [7:0] byte_in,    // радио-байт
  output wire rx_ready,                                 // готов принять байт
  output reg  rx_done,                                  // приём+поиск завершён
  output wire [$clog2(M)-1:0] recog                     // распознанный смысл
);
  localparam NCH=(D+LANES-1)/LANES, W=2*LANES;
  `include "unpack3_rom.vh"

  reg setq; reg [$clog2(NCH)-1:0] qaddr; reg [W-1:0] qdata;
  reg eng_start; wire eng_done; wire [$clog2(M)-1:0] eng_arg;
  hdc #(.D(D),.M(M),.LANES(LANES)) u (.clk(clk),.rst(rst),
    .wr(wr),.waddr(waddr),.wdata(wdata),.setq(setq),.qaddr(qaddr),.qdata(qdata),
    .oaddr({$clog2(NCH){1'b0}}),.odata(),.op(2'd3),.aidx(3'd0),.bidx(3'd0),.mask({M{1'b1}}),
    .start(eng_start),.out_sim(),.out_arg(eng_arg),.done(eng_done));
  assign recog = eng_arg;

  localparam RXIDLE=0, PUSH=1, SRCH=2, WAIT=3, DONE=4;
  reg [2:0] st;
  reg [9:0] codes; reg [2:0] bi;             // 5 тритов байта, индекс 0..4
  reg [W-1:0] cw; reg [$clog2(LANES)-1:0] tc;
  reg [$clog2(NCH)-1:0] chunk; reg [$clog2(D+1)-1:0] tcnt;
  reg [1:0] trit; reg [W-1:0] word;
  assign rx_ready = (st==RXIDLE);

  always @(posedge clk) begin
    if (rst) begin st<=RXIDLE; bi<=0; cw<=0; tc<=0; chunk<=0; tcnt<=0; setq<=0; eng_start<=0; rx_done<=0; end
    else begin
      setq<=0; eng_start<=0;
      case (st)
        RXIDLE: if (byte_valid) begin codes<=unpack3(byte_in); bi<=0; st<=PUSH; end
        PUSH: begin
          trit = codes[2*bi +: 2];
          if (tcnt < D) begin
            word = cw; word[2*tc +: 2] = trit;
            if (tc==LANES-1) begin setq<=1; qaddr<=chunk; qdata<=word; chunk<=chunk+1'b1; cw<=0; tc<=0; end
            else begin cw<=word; tc<=tc+1'b1; end
            tcnt<=tcnt+1'b1;
          end
          if (bi==4) begin
            if (tcnt+1 >= D || chunk==NCH-1 && tc==LANES-1) st<=SRCH;  // словарь-вектор собран
            else st<=RXIDLE;
          end else bi<=bi+1'b1;
        end
        SRCH: begin eng_start<=1; st<=WAIT; end
        WAIT: if (eng_done) begin rx_done<=1; st<=DONE; end
        DONE: ;
      endcase
    end
  end
endmodule
