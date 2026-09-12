// hdc.v — синтезируемый троичный HDC/VSA-движок («язык геометрии» на балансной троице).
// Трит {−1,0,+1}, код -1=2'b00,0=2'b01,+1=2'b10 (как tritdot.v / pack2bit в ternary_comms.py).
// Операции: BIND (Адамар), BUNDLE (порог суммы), SIM (троичн.скаляр), SEARCH (argmax-cleanup под РЭБ).
// СИНТЕЗОПРИГОДНЫЙ СТИЛЬ: гипервектор хранится ЧАНКАМИ по LANES тритов (W=2*LANES бит/слово) в памяти,
// адресуемой индексом — никаких широких переменных part-select. Чанк/такт → узкие LANES-редукции.
`default_nettype none
module hdc #(parameter D=384, parameter M=8, parameter LANES=16) (
  input  wire clk, input wire rst,
  input  wire                wr,   input wire [$clog2(M*((D+LANES-1)/LANES))-1:0] waddr, input wire [2*LANES-1:0] wdata,
  input  wire                setq, input wire [$clog2((D+LANES-1)/LANES)-1:0]     qaddr, input wire [2*LANES-1:0] qdata,
  input  wire [$clog2((D+LANES-1)/LANES)-1:0] oaddr, output wire [2*LANES-1:0] odata,
  input  wire [1:0]          op, input wire [$clog2(M)-1:0] aidx, input wire [$clog2(M)-1:0] bidx,
  input  wire [M-1:0]        mask, input wire start,
  output reg  signed [31:0]  out_sim, output reg [$clog2(M)-1:0] out_arg, output reg done
);
  localparam BIND=0, BUNDLE=1, SIM=2, SEARCH=3;
  localparam NCH = (D + LANES - 1) / LANES;
  localparam W   = 2*LANES;
  (* ram_style="distributed" *) reg [W-1:0] mem  [0:M*NCH-1];
  (* ram_style="distributed" *) reg [W-1:0] qmem [0:NCH-1];
  (* ram_style="distributed" *) reg [W-1:0] omem [0:NCH-1];

  reg [$clog2(NCH+1)-1:0] ci;

  always @(posedge clk) begin
    if (wr)   mem[waddr]  <= wdata;
    if (setq) qmem[qaddr] <= qdata;
  end
  assign odata = omem[oaddr];

  function signed [5:0] dec; input [1:0] c; begin
    dec=(c==2'b10)?6'sd1:(c==2'b00)?-6'sd1:6'sd0; end endfunction
  function [1:0] enc; input signed [5:0] s; begin
    enc=(s>0)?2'b10:(s<0)?2'b00:2'b01; end endfunction

  function [W-1:0] bindw; input [W-1:0] x; input [W-1:0] y; integer j; reg [1:0] xc,yc; begin
    for (j=0;j<LANES;j=j+1) begin xc=x[2*j+:2]; yc=y[2*j+:2];
      bindw[2*j+:2] = (xc==2'b01||yc==2'b01)?2'b01:(xc==yc)?2'b10:2'b00; end
  end endfunction

  function signed [15:0] cdot; input integer s; input integer c; integer j; reg [1:0] qc,mc; begin
    cdot=0; for (j=0;j<LANES;j=j+1) begin qc=qmem[c][2*j+:2]; mc=mem[s*NCH+c][2*j+:2];
      if (qc==2'b01||mc==2'b01) cdot=cdot+16'sd0;
      else if (qc==mc)          cdot=cdot+16'sd1;
      else                      cdot=cdot-16'sd1; end
  end endfunction

  reg [W-1:0] bunw;
  integer bj, bm; reg signed [5:0] bs;
  always @(*) begin
    bunw = {W{1'b0}};
    for (bj=0;bj<LANES;bj=bj+1) begin bs=0;
      for (bm=0;bm<M;bm=bm+1) if (mask[bm]) bs = bs + dec(mem[bm*NCH+ci][2*bj+:2]);
      bunw[2*bj+:2] = enc(bs);
    end
  end

  localparam IDLE=0, BIND_R=1, BUN_R=2, SIM_R=3, SCH_R=4, FIN=5;
  reg [2:0] st;
  reg [$clog2(M)-1:0] sel, bestarg;
  reg signed [15:0] dotacc, best, itemdot;

  always @(posedge clk) begin
    if (rst) begin st<=IDLE; done<=0; sel<=0; ci<=0; end
    else case (st)
      IDLE: begin done<=0; if (start) case (op)
          BIND:   begin ci<=0; st<=BIND_R; end
          BUNDLE: begin ci<=0; st<=BUN_R;  end
          SIM:    begin sel<=aidx; ci<=0; dotacc<=0; st<=SIM_R; end
          SEARCH: begin sel<=0; ci<=0; dotacc<=0; best<=-16'sd32767; bestarg<=0; st<=SCH_R; end
        endcase end
      BIND_R: begin
        omem[ci] <= bindw(mem[aidx*NCH+ci], mem[bidx*NCH+ci]);
        if (ci==NCH-1) st<=FIN; else ci<=ci+1'b1;
      end
      BUN_R: begin
        omem[ci] <= bunw;
        if (ci==NCH-1) st<=FIN; else ci<=ci+1'b1;
      end
      SIM_R: begin
        if (ci==NCH-1) begin out_sim <= dotacc + cdot(sel,ci); st<=FIN; end
        else begin dotacc <= dotacc + cdot(sel,ci); ci<=ci+1'b1; end
      end
      SCH_R: begin
        if (ci==NCH-1) begin
          itemdot = dotacc + cdot(sel,ci);
          if (sel==M-1) begin
            out_sim <= (itemdot>best)? itemdot:best;
            out_arg <= (itemdot>best)? sel:bestarg;
            st<=FIN;
          end else begin
            if (itemdot>best) begin best<=itemdot; bestarg<=sel; end
            sel<=sel+1'b1; ci<=0; dotacc<=0;
          end
        end else begin dotacc <= dotacc + cdot(sel,ci); ci<=ci+1'b1; end
      end
      FIN: begin done<=1; st<=IDLE; end
    endcase
  end
endmodule
