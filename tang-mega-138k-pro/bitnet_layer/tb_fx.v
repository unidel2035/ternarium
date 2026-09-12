`timescale 1ns/1ps
`default_nettype none
module tb_fx;
  reg clk=0,rst=1; always #5 clk=~clk;
  reg sts=0; reg [31:0] xv; wire [16:0] rt; wire sb,sd;
  isqrt32 u(.clk(clk),.rst(rst),.start(sts),.x(xv),.root(rt),.busy(sb),.done(sd));
  reg std=0; reg signed [31:0] da,db; wire signed [31:0] qq; wire db_,dd;
  sdiv32 v(.clk(clk),.rst(rst),.start(std),.a(da),.b(db),.q(qq),.busy(db_),.done(dd));
  integer i,oks,okq,exp;
  initial begin
    repeat(3)@(posedge clk); rst<=0; @(posedge clk);
    oks=0;
    for(i=0;i<24;i=i+1) begin
      xv=i*i*97+i*1311+7; @(posedge clk); sts<=1;@(posedge clk);sts<=0;
      while(!sd)@(posedge clk); @(posedge clk);
      exp=$rtoi($sqrt(xv));
      if(rt==exp) oks=oks+1; else $display("  isqrt(%0d)=%0d exp %0d",xv,rt,exp);
    end
    $display("isqrt: %0d/24 точно",oks);
    okq=0;
    for(i=0;i<20;i=i+1) begin
      da=(i*977-4000); db=(i-10); if(db==0)db=7;
      @(posedge clk); std<=1;@(posedge clk);std<=0; while(!dd)@(posedge clk);@(posedge clk);
      exp=(da>=0)?da/db:-((-da)/db);
      if(qq==exp) okq=okq+1; else $display("  sdiv %0d/%0d=%0d exp %0d",da,db,qq,exp);
    end
    $display("sdiv: %0d/20 точно",okq);
    if(oks==24&&okq==20)$display("FXOPS OK — синтезируемые isqrt+делитель верны");
    $finish;
  end
endmodule
