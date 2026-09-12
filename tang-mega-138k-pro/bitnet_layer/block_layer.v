// block_layer.v — СЕКВЕНСЕР одного троичного трансформер-слоя (FSM, веса в памяти).
// h=x+Oproj(Attn(RMSNorm(x))); y=h+FFN(RMSNorm(h)). Та же fixed-point математика, что в спеке.
// Нелинейности (isqrt/div) — функции (sim-точно); для полного синтеза заменяются итеративными.
`default_nettype none
module block_layer(input wire clk, input wire rst, input wire start,
  input wire [15:0] y_addr, output wire signed [31:0] y_out, output reg done);
  reg signed [31:0] X[0:31];  integer EXPLUT[0:31];   // S*D=32; заполняются initial из .vh (объявить ДО include)
  `include "vectors_block.vh"   // D,S,SC,..., WQ_*..WD_*, initial fills X/EXPLUT, gy()
  reg signed [31:0] n1[0:S*D-1], Q[0:S*D-1], K[0:S*D-1], V[0:S*D-1];
  reg signed [31:0] ctx[0:S*D-1], H[0:S*D-1], Y[0:S*D-1], av[0:D-1], av2[0:D-1];
  assign y_out = Y[y_addr];
  function [2*D-1:0] wrow; input integer m; input integer r; begin case(m*D+r)
    0: wrow=WQ_0;
    1: wrow=WQ_1;
    2: wrow=WQ_2;
    3: wrow=WQ_3;
    4: wrow=WQ_4;
    5: wrow=WQ_5;
    6: wrow=WQ_6;
    7: wrow=WQ_7;
    8: wrow=WK_0;
    9: wrow=WK_1;
    10: wrow=WK_2;
    11: wrow=WK_3;
    12: wrow=WK_4;
    13: wrow=WK_5;
    14: wrow=WK_6;
    15: wrow=WK_7;
    16: wrow=WV_0;
    17: wrow=WV_1;
    18: wrow=WV_2;
    19: wrow=WV_3;
    20: wrow=WV_4;
    21: wrow=WV_5;
    22: wrow=WV_6;
    23: wrow=WV_7;
    24: wrow=WO_0;
    25: wrow=WO_1;
    26: wrow=WO_2;
    27: wrow=WO_3;
    28: wrow=WO_4;
    29: wrow=WO_5;
    30: wrow=WO_6;
    31: wrow=WO_7;
    32: wrow=WG_0;
    33: wrow=WG_1;
    34: wrow=WG_2;
    35: wrow=WG_3;
    36: wrow=WG_4;
    37: wrow=WG_5;
    38: wrow=WG_6;
    39: wrow=WG_7;
    40: wrow=WD_0;
    41: wrow=WD_1;
    42: wrow=WD_2;
    43: wrow=WD_3;
    44: wrow=WD_4;
    45: wrow=WD_5;
    46: wrow=WD_6;
    47: wrow=WD_7;
    default: wrow={2*D{1'b0}}; endcase end endfunction
  function signed [31:0] mv; input integer m; input integer r; integer c; reg [2*D-1:0] w; reg signed [31:0] s; begin
    w=wrow(m,r); s=0;
    for(c=0;c<D;c=c+1) begin if(w[2*c+:2]==2'b10) s=s+av[c]; else if(w[2*c+:2]==2'b00) s=s-av[c]; end
    mv=s; end endfunction
  function integer isq; input integer n; integer i; reg [31:0] op,res,one; begin
    op=n; res=0; one=(1<<30);
    for(i=0;i<16;i=i+1) begin if(op>=res+one) begin op=op-(res+one); res=(res>>1)+one; end else res=res>>1; one=one>>2; end
    isq=res; end endfunction
  function signed [31:0] tdiv; input signed [31:0] a; input signed [31:0] b; begin tdiv=(a>=0)?a/b:-((-a)/b); end endfunction
  function signed [31:0] clampf; input signed [31:0] v; begin clampf=(v>127)?127:(v<-127)?-127:v; end endfunction
  localparam IDLE=0,P_N1=1,P_QKV=2,P_ATTN=3,P_O=4,P_FFN=5,FIN=6;
  reg [2:0] st; integer t;
  integer d,c,j,ms,den,sc,mx,num,dd,wgt,ao,go;
  always @(posedge clk) begin
    if(rst) begin st<=IDLE; done<=0; t<=0; end
    else case(st)
      IDLE: if(start) begin t<=0; done<=0; st<=P_N1; end
      P_N1: begin
        ms=0; for(d=0;d<D;d=d+1) ms=ms+X[t*D+d]*X[t*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
        for(d=0;d<D;d=d+1) n1[t*D+d]=tdiv(X[t*D+d]*SC*SC, den);
        if(t==S-1) begin t<=0; st<=P_QKV; end else t<=t+1; end
      P_QKV: begin
        for(d=0;d<D;d=d+1) av[d]=n1[t*D+d];
        for(d=0;d<D;d=d+1) begin Q[t*D+d]=mv(0,d); K[t*D+d]=mv(1,d); V[t*D+d]=mv(2,d); end
        if(t==S-1) begin t<=0; st<=P_ATTN; end else t<=t+1; end
      P_ATTN: begin
        mx=-2147483647;
        for(j=0;j<S;j=j+1) begin sc=0; for(c=0;c<D;c=c+1) sc=sc+Q[t*D+c]*K[j*D+c]; av[j]=sc; if(sc>mx)mx=sc; end
        for(d=0;d<D;d=d+1) begin num=0; dd=0;
          for(j=0;j<S;j=j+1) begin c=(mx-av[j])/SMSCALE; if(c>31)c=31; wgt=EXPLUT[c]; num=num+wgt*V[j*D+d]; dd=dd+wgt; end
          ctx[t*D+d]=tdiv(num, dd); end
        if(t==S-1) begin t<=0; st<=P_O; end else t<=t+1; end
      P_O: begin
        for(d=0;d<D;d=d+1) av[d]=ctx[t*D+d];
        for(d=0;d<D;d=d+1) begin ao=clampf(tdiv(mv(3,d), 1<<SH_A)); H[t*D+d]=clampf(X[t*D+d]+ao); end
        if(t==S-1) begin t<=0; st<=P_FFN; end else t<=t+1; end
      P_FFN: begin
        ms=0; for(d=0;d<D;d=d+1) ms=ms+H[t*D+d]*H[t*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
        for(d=0;d<D;d=d+1) av[d]=tdiv(H[t*D+d]*SC*SC, den);
        for(d=0;d<D;d=d+1) begin go=mv(4,d); if(go<0)go=0; av2[d]=go; end
        for(d=0;d<D;d=d+1) av[d]=av2[d];
        for(d=0;d<D;d=d+1) begin go=clampf(tdiv(mv(5,d),1<<SH_F)); Y[t*D+d]=clampf(H[t*D+d]+go); end
        if(t==S-1) st<=FIN; else t<=t+1; end
      FIN: begin done<=1; st<=IDLE; end
    endcase end
endmodule