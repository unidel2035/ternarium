// fxops.v — синтезируемые итеративные isqrt (digit-by-digit) и знаковый делитель (restoring, trunc к нулю).
// Замена несинтезируемым функциям isq/tdiv для полного синтеза model_infer.
`default_nettype none
module isqrt32(input wire clk, input wire ce, input wire rst, input wire start,
  input wire [31:0] x, output reg [16:0] root, output reg busy, output reg done);
  reg [31:0] op, res, one; reg [4:0] cnt; reg [31:0] nres;
  always @(posedge clk) begin
    if (rst) begin busy<=0; done<=0; end
    else if (ce) begin
      if (start && !busy) begin busy<=1; done<=0; res<=0; one<=(1<<30); op<=x; cnt<=15; end
      else if (busy) begin
        if (op >= res+one) begin op<=op-(res+one); nres=(res>>1)+one; end
        else nres=(res>>1);
        res<=nres; one<=one>>2;
        if (cnt==0) begin busy<=0; done<=1; root<=nres[16:0]; end else cnt<=cnt-1;
      end else done<=0;
    end
  end
endmodule

module sdiv32(input wire clk, input wire ce, input wire rst, input wire start,
  input wire signed [31:0] a, input wire signed [31:0] b,
  output reg signed [31:0] q, output reg busy, output reg done);
  reg [31:0] na, nb, quo, rem; reg [5:0] cnt; reg sgn; reg [31:0] nrem, nquo;
  always @(posedge clk) begin
    if (rst) begin busy<=0; done<=0; end
    else if (ce) begin
      if (start && !busy) begin
        busy<=1; done<=0; quo<=0; rem<=0; cnt<=31; sgn<=(a[31]^b[31]);
        na <= a[31]? (~a+1):a; nb <= b[31]? (~b+1):b;
      end else if (busy) begin
        nrem = (rem<<1) | na[31];
        if (nrem >= nb) begin nrem = nrem - nb; nquo = (quo<<1)|1; end
        else nquo = (quo<<1);
        rem<=nrem; quo<=nquo; na<=na<<1;
        if (cnt==0) begin busy<=0; done<=1; q <= sgn ? (~nquo+1) : nquo; end else cnt<=cnt-1;
      end else done<=0;
    end
  end
endmodule
