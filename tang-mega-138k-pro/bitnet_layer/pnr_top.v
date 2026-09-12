// pnr_top.v — обёртка для P&R: слой как on-chip блок, минимум внешних пинов.
// Веса/активации — ROM/RAM в BRAM; rst/start генерятся внутри; наружу только clk + led.
`default_nettype none
module pnr_top (input wire clk, output wire led);
  reg [7:0] pcnt = 8'd0;                 // power-on последовательность
  wire rst   = (pcnt < 8'd4);
  wire start = (pcnt == 8'd8);
  always @(posedge clk) if (pcnt != 8'hFF) pcnt <= pcnt + 1'b1;

  wire done;
  wire signed [31:0] o_data;
  reg [8:0] o_addr;
  always @(posedge clk) o_addr <= o_addr + 1'b1;

  // мини-загрузчик активаций (даёт amem реальный порт записи → RAM, не ROM)
  reg ld; reg [8:0] la; reg signed [7:0] lda;
  always @(posedge clk) begin
    ld  <= start & ~done;
    la  <= la + 1'b1;
    lda <= la[7:0] - 8'sd128;
  end

  tlmm_layer #(.NIN(256),.NOUT(256)) u (
    .clk(clk), .rst(rst), .start(start),
    .wr_a(ld),   .a_addr(la),   .a_data(lda),
    .wr_w(1'b0), .w_addr(16'd0), .w_data(4'd0),
    .o_addr(o_addr), .o_data(o_data), .done(done));
  assign led = (^o_data) ^ done;   // наблюдаем выход → датапас не выпиливается
endmodule
