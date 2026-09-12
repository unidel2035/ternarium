`timescale 1ns/1ps
`default_nettype none
module tb_layer;
  localparam NIN=8, NOUT=4, CH=NIN/2;
  reg clk=0, rst=1, start=0;
  reg wr_a=0; reg [8:0] a_addr=0; reg signed [7:0] a_data=0;
  reg wr_w=0; reg [15:0] w_addr=0; reg [3:0] w_data=0;
  reg [8:0] o_addr=0; wire signed [31:0] o_data; wire done;
  tlmm_layer #(.NIN(NIN),.NOUT(NOUT)) dut(.clk(clk),.rst(rst),.start(start),
    .wr_a(wr_a),.a_addr(a_addr),.a_data(a_data),
    .wr_w(wr_w),.w_addr(w_addr),.w_data(w_data),
    .o_addr(o_addr),.o_data(o_data),.done(done));
  always #5 clk=~clk;

  // эталон: активации, троичные веса (распакованные из пар-индексов)
  integer i,j,n,p,c0,c1;
  reg signed [7:0] act [0:NIN-1];
  reg [3:0]        wpi [0:NOUT*CH-1];   // pair index 0..8 = (c0*3+c1)
  integer expected [0:NOUT-1];
  reg signed [1:0] tern; // -1,0,+1

  // распаковать индекс пары в два тритта: idx = (c0)*3 + (c1), c в {0=-1,1=0,2=+1}
  function integer trit; input [1:0] c; begin trit=(c==0)?-1:(c==2)?1:0; end endfunction

  reg signed [31:0] cyc;
  initial begin
    // случайные-детерминированные данные
    for (i=0;i<NIN;i=i+1) act[i]=(i*37+5)%17-8;       // -8..8
    for (i=0;i<NOUT*CH;i=i+1) wpi[i]=(i*5+1)%9;        // 0..8
    // эталонный MAC
    for (n=0;n<NOUT;n=n+1) begin
      expected[n]=0;
      for (p=0;p<CH;p=p+1) begin
        c0=wpi[n*CH+p]/3; c1=wpi[n*CH+p]%3;
        expected[n]=expected[n]+trit(c0)*act[2*p]+trit(c1)*act[2*p+1];
      end
    end
    // reset
    repeat(4) @(posedge clk); rst<=0; @(posedge clk);
    // загрузка активаций
    for (i=0;i<NIN;i=i+1) begin wr_a<=1; a_addr<=i; a_data<=act[i]; @(posedge clk); end
    wr_a<=0;
    // загрузка весов
    for (i=0;i<NOUT*CH;i=i+1) begin wr_w<=1; w_addr<=i; w_data<=wpi[i]; @(posedge clk); end
    wr_w<=0; @(posedge clk);
    // старт + счёт тактов
    cyc=0; start<=1; @(posedge clk); start<=0;
    while(!done) begin @(posedge clk); cyc=cyc+1; end
    @(posedge clk);
    // проверка выходов
    begin : chk
      integer ok; ok=0;
      for (n=0;n<NOUT;n=n+1) begin
        o_addr<=n; @(posedge clk); @(posedge clk); // 2 такта на синхр. чтение
        if (o_data===expected[n]) ok=ok+1;
        else $display("  neuron %0d: got %0d exp %0d  MISMATCH",n,o_data,expected[n]);
      end
      $display("RESULT: %0d/%0d neurons correct; compute cycles=%0d (NIN=%0d NOUT=%0d)",ok,NOUT,cyc,NIN,NOUT);
      if (ok==NOUT) $display("LAYER OK"); else $display("LAYER FAIL");
    end
    $finish;
  end
endmodule
