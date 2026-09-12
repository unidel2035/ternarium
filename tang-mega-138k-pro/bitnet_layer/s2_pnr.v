`default_nettype none
module s2_pnr(input wire clk, output wire led);
  reg [15:0] pc=0; always @(posedge clk) pc<=pc+1'b1;
  wire rst=(pc<16'd8); wire start=(pc==16'd16);
  reg [7:0] taddr; always @(posedge clk) taddr<=taddr+1'b1;
  wire [7:0] tout; wire done;
  model_infer_s2 u(.clk(clk),.rst(rst),.start(start),.tok_addr(taddr),.tok_out(tout),.done(done));
  assign led = (^tout) ^ done;
endmodule
