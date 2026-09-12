`timescale 1ns/1ps
`default_nettype none
module tb_hdc;
  `include "vectors_hdc.vh"          // D=384, M=8, ITEM0..7, QNOISY, EXP_*
  localparam DD=384, MM=8, LN=16, NCH=(DD+LN-1)/LN, W=2*LN;
  reg clk=0, rst=1;
  reg wr=0;   reg [7:0] waddr=0; reg [W-1:0] wdata=0;
  reg setq=0; reg [4:0] qaddr=0; reg [W-1:0] qdata=0;
  reg [4:0] oaddr=0; wire [W-1:0] odata;
  reg [1:0] op=0; reg [2:0] aidx=0, bidx=0; reg [7:0] mask=0; reg start=0;
  wire signed [31:0] out_sim; wire [2:0] out_arg; wire done;
  hdc #(.D(384),.M(8),.LANES(16)) dut(.clk(clk),.rst(rst),
    .wr(wr),.waddr(waddr),.wdata(wdata),.setq(setq),.qaddr(qaddr),.qdata(qdata),
    .oaddr(oaddr),.odata(odata),.op(op),.aidx(aidx),.bidx(bidx),.mask(mask),.start(start),
    .out_sim(out_sim),.out_arg(out_arg),.done(done));
  always #5 clk=~clk;

  reg [2*DD-1:0] items [0:7];
  reg [W-1:0] sch [0:NCH-1];     // буфер чанков результата
  integer m, c, ok, fail;

  task loaditem(input [2:0] idx, input [2*DD-1:0] v); integer cc; begin
    for (cc=0;cc<NCH;cc=cc+1) begin
      @(posedge clk); wr<=1; waddr<=idx*NCH+cc; wdata<=v[cc*W +: W];
    end @(posedge clk); wr<=0;
  end endtask

  task grab_omem; integer cc; begin   // omem → sch[]
    for (cc=0;cc<NCH;cc=cc+1) begin oaddr<=cc; @(posedge clk); @(posedge clk); sch[cc]=odata; end
  end endtask
  task load_q_from_sch; integer cc; begin
    for (cc=0;cc<NCH;cc=cc+1) begin @(posedge clk); setq<=1; qaddr<=cc; qdata<=sch[cc]; end
    @(posedge clk); setq<=0;
  end endtask
  task load_q_vec(input [2*DD-1:0] v); integer cc; begin
    for (cc=0;cc<NCH;cc=cc+1) begin @(posedge clk); setq<=1; qaddr<=cc; qdata<=v[cc*W +: W]; end
    @(posedge clk); setq<=0;
  end endtask

  task runop(input [1:0] o, input [2:0] a, input [2:0] b, input [7:0] mk); begin
    @(posedge clk); op<=o; aidx<=a; bidx<=b; mask<=mk; start<=1;
    @(posedge clk); start<=0; @(posedge clk); while(!done) @(posedge clk);
  end endtask
  task chk(input signed [31:0] got, input signed [31:0] exp, input [95:0] nm); begin
    if(got===exp) ok=ok+1; else begin fail=fail+1; $display("  MISMATCH %0s: got %0d exp %0d",nm,got,exp); end
  end endtask

  initial begin
    items[0]=ITEM0; items[1]=ITEM1; items[2]=ITEM2; items[3]=ITEM3;
    items[4]=ITEM4; items[5]=ITEM5; items[6]=ITEM6; items[7]=ITEM7;
    ok=0; fail=0;
    repeat(3) @(posedge clk); rst<=0; @(posedge clk);
    for (m=0;m<8;m=m+1) loaditem(m[2:0], items[m]);

    // ① BUNDLE {0,1,2} → omem; копируем в qmem; SIM с каждым item
    runop(2'd1,3'd0,3'd0,8'b00000111); grab_omem; load_q_from_sch;
    for (m=0;m<8;m=m+1) begin
      runop(2'd2,m[2:0],3'd0,8'd0);
      case(m)
        0:chk(out_sim,EXP_SIM_S0,"bSim0"); 1:chk(out_sim,EXP_SIM_S1,"bSim1");
        2:chk(out_sim,EXP_SIM_S2,"bSim2"); 3:chk(out_sim,EXP_SIM_S3,"bSim3");
        4:chk(out_sim,EXP_SIM_S4,"bSim4"); 5:chk(out_sim,EXP_SIM_S5,"bSim5");
        6:chk(out_sim,EXP_SIM_S6,"bSim6"); 7:chk(out_sim,EXP_SIM_S7,"bSim7");
      endcase
    end
    // ② BIND(0,1) → omem → qmem; SIM с частями ≈ 0
    runop(2'd0,3'd0,3'd1,8'd0); grab_omem; load_q_from_sch;
    runop(2'd2,3'd0,3'd0,8'd0); chk(out_sim,EXP_BIND0,"bind0");
    runop(2'd2,3'd1,3'd0,8'd0); chk(out_sim,EXP_BIND1,"bind1");
    // ③ SEARCH cleanup
    load_q_vec(QNOISY);
    runop(2'd3,3'd0,3'd0,8'd0); chk(out_arg,EXP_ARGMAX,"argmax");

    $display("RESULT: %0d ok, %0d fail. argmax=%0d (exp %0d)",ok,fail,out_arg,EXP_ARGMAX);
    if(fail==0) $display("HDC ENGINE OK — троичный язык геометрии на железе (синтезопригодно, D=384)");
    else $display("HDC FAIL");
    $finish;
  end
endmodule
