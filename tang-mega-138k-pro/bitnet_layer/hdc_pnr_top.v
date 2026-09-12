// hdc_pnr_top.v — обёртка для P&R движка hdc: непрерывно обновляет память, гоняет op по счётчику
// (BIND/BUNDLE/SIM/SEARCH достижимы → датапас не выпиливается), все выходы на led. Наружу clk+led.
`default_nettype none
module hdc_pnr_top #(parameter D=384, parameter M=8, parameter LANES=16) (
  input wire clk, output wire led);
  localparam NCH=(D+LANES-1)/LANES, W=2*LANES, NMEM=M*NCH;
  reg [15:0] t=0; always @(posedge clk) t<=t+1'b1;
  wire rst = (t < 4);
  reg [31:0] lfsr=32'h1; always @(posedge clk) lfsr<={lfsr[30:0], lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};

  reg wr, setq, start; reg [$clog2(NMEM)-1:0] waddr; reg [$clog2(NCH)-1:0] qaddr;
  reg [W-1:0] wdata, qdata; reg [1:0] op; reg [$clog2(M)-1:0] aidx, bidx; reg [M-1:0] mask;
  always @(posedge clk) begin
    wr<=1'b1;  waddr<=(waddr==NMEM-1)?0:waddr+1'b1; wdata<=lfsr[W-1:0];
    setq<=1'b1; qaddr<=(qaddr==NCH-1)?0:qaddr+1'b1; qdata<={lfsr[15:0],lfsr[31:16]};
    op<=t[13:12]; aidx<=t[2:0]; bidx<=t[5:3]; mask<=t[7:0];
    start<=(t[7:0]==8'h80);                                  // периодический пуск
  end

  wire signed [31:0] out_sim; wire [$clog2(M)-1:0] out_arg; wire done; wire [W-1:0] odata;
  reg [$clog2(NCH)-1:0] oaddr; always @(posedge clk) oaddr<=(oaddr==NCH-1)?0:oaddr+1'b1;
  hdc #(.D(D),.M(M),.LANES(LANES)) u (.clk(clk),.rst(rst),
    .wr(wr),.waddr(waddr),.wdata(wdata),.setq(setq),.qaddr(qaddr),.qdata(qdata),
    .oaddr(oaddr),.odata(odata),.op(op),.aidx(aidx),.bidx(bidx),.mask(mask),.start(start),
    .out_sim(out_sim),.out_arg(out_arg),.done(done));
  assign led = (^out_sim) ^ (^out_arg) ^ done ^ (^odata);
endmodule
