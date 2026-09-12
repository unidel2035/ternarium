`timescale 1ns/1ps
`default_nettype none
module tb_rx;
  `include "vectors_hdc.vh"          // D, M, ITEM0..7
  `include "vectors_rx.vh"           // NBYTES, PKT0.., RX_EXP_ARG
  localparam DD=384, MM=8, LN=8, NCH=(DD+LN-1)/LN, W=2*LN;
  reg clk=0, rst=1;
  reg wr=0; reg [8:0] waddr=0; reg [W-1:0] wdata=0;
  reg byte_valid=0; reg [7:0] byte_in=0;
  wire rx_ready, rx_done; wire [2:0] recog;
  rx_hdc #(.D(384),.M(8),.LANES(8)) dut(.clk(clk),.rst(rst),
    .wr(wr),.waddr(waddr),.wdata(wdata),.byte_valid(byte_valid),.byte_in(byte_in),
    .rx_ready(rx_ready),.rx_done(rx_done),.recog(recog));
  always #5 clk=~clk;

  reg [2*DD-1:0] items [0:7];
  reg [7:0] pkt [0:127];
  integer m, c, i;
  task loaditem(input [2:0] idx, input [2*DD-1:0] v); integer cc; begin
    for (cc=0;cc<NCH;cc=cc+1) begin @(posedge clk); wr<=1; waddr<=idx*NCH+cc; wdata<=v[cc*W +: W]; end
    @(posedge clk); wr<=0;
  end endtask

  initial begin
    items[0]=ITEM0; items[1]=ITEM1; items[2]=ITEM2; items[3]=ITEM3;
    items[4]=ITEM4; items[5]=ITEM5; items[6]=ITEM6; items[7]=ITEM7;
    `include "rx_pkt_load.vh"        // pkt[i]=PKTi;
    repeat(3) @(posedge clk); rst<=0; @(posedge clk);
    for (m=0;m<8;m=m+1) loaditem(m[2:0], items[m]);   // словарь смыслов

    // стрим радио-пакета побайтно (handshake по rx_ready)
    for (i=0;i<NBYTES;i=i+1) begin
      @(posedge clk); while(!rx_ready) @(posedge clk);
      byte_valid<=1; byte_in<=pkt[i]; @(posedge clk); byte_valid<=0;
    end
    while(!rx_done) @(posedge clk);
    @(posedge clk);
    if (recog===RX_EXP_ARG)
      $display("RX OK: радио-пакет → распознан смысл #%0d (ожидаем %0d). Приём+cleanup на железе.",recog,RX_EXP_ARG);
    else
      $display("RX FAIL: got %0d exp %0d",recog,RX_EXP_ARG);
    $finish;
  end
endmodule
