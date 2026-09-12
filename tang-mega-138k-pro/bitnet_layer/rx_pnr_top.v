// rx_pnr_top.v — обёртка P&R для rx_hdc: словарь и пакет из ROM-паттерна по счётчику,
// recog/rx_done на led. Наружу clk+led.
`default_nettype none
module rx_pnr_top #(parameter D=384, parameter M=8, parameter LANES=8) (input wire clk, output wire led);
  localparam NCH=(D+LANES-1)/LANES, W=2*LANES, NMEM=M*NCH;
  reg [15:0] t=0; always @(posedge clk) t<=t+1'b1;
  wire rst=(t<4);
  reg [31:0] lfsr=32'h1; always @(posedge clk) lfsr<={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};
  // словарь: пишем непрерывно паттерном (порт записи жив, датапас не выпиливается)
  reg wr; reg [$clog2(NMEM)-1:0] waddr; reg [W-1:0] wdata;
  always @(posedge clk) begin wr<=1'b1; waddr<=(waddr==NMEM-1)?0:waddr+1'b1; wdata<=lfsr[W-1:0]; end
  // байты пакета по счётчику
  reg bv; reg [7:0] bin;
  wire rx_ready, rx_done; wire [$clog2(M)-1:0] recog;
  always @(posedge clk) begin bv<=rx_ready; bin<=lfsr[7:0]; end   // шлём байт когда приёмник готов
  rx_hdc #(.D(D),.M(M),.LANES(LANES)) u (.clk(clk),.rst(rst),
    .wr(wr),.waddr(waddr),.wdata(wdata),.byte_valid(bv),.byte_in(bin),
    .rx_ready(rx_ready),.rx_done(rx_done),.recog(recog));
  assign led = (^recog) ^ rx_done ^ rx_ready;
endmodule
