// model_infer.v — ПОЛНЫЙ inference мелкой троичной модели: embed→[L слоёв]→финальный RMSNorm
//   →логиты→argmax→авторегрессия. Та же fixed-point математика, что в эталоне. FSM-топ.
`default_nettype none
module model_infer(input wire clk, input wire rst, input wire start,
  input wire [7:0] tok_addr, output wire [7:0] tok_out, output reg done);
  reg [7:0] gtok[0:15];                 // сгенерённые токены (NGEN<=16)
  `include "model_vectors.vh"           // V,D,L,H,S,NGEN,..., веса, EXP_*, GTOK_*, SEED_*
  assign tok_out = gtok[tok_addr];
  reg signed [31:0] X[0:S*D-1], n1[0:S*D-1], Q[0:S*D-1], K[0:S*D-1], Vv[0:S*D-1];
  reg signed [31:0] ctx[0:S*D-1], Hh[0:S*D-1], av[0:D-1], av2[0:D-1], xn[0:D-1];
  integer EXPLUT[0:31];
  reg [7:0] seqb[0:S-1];
  function [2*D-1:0] wrow; input integer l; input integer m; input integer r; begin case(((l*6)+m)*D+r)
    0: wrow=WQ_0_0;
    1: wrow=WQ_0_1;
    2: wrow=WQ_0_2;
    3: wrow=WQ_0_3;
    4: wrow=WQ_0_4;
    5: wrow=WQ_0_5;
    6: wrow=WQ_0_6;
    7: wrow=WQ_0_7;
    8: wrow=WK_0_0;
    9: wrow=WK_0_1;
    10: wrow=WK_0_2;
    11: wrow=WK_0_3;
    12: wrow=WK_0_4;
    13: wrow=WK_0_5;
    14: wrow=WK_0_6;
    15: wrow=WK_0_7;
    16: wrow=WV_0_0;
    17: wrow=WV_0_1;
    18: wrow=WV_0_2;
    19: wrow=WV_0_3;
    20: wrow=WV_0_4;
    21: wrow=WV_0_5;
    22: wrow=WV_0_6;
    23: wrow=WV_0_7;
    24: wrow=WO_0_0;
    25: wrow=WO_0_1;
    26: wrow=WO_0_2;
    27: wrow=WO_0_3;
    28: wrow=WO_0_4;
    29: wrow=WO_0_5;
    30: wrow=WO_0_6;
    31: wrow=WO_0_7;
    32: wrow=W1_0_0;
    33: wrow=W1_0_1;
    34: wrow=W1_0_2;
    35: wrow=W1_0_3;
    36: wrow=W1_0_4;
    37: wrow=W1_0_5;
    38: wrow=W1_0_6;
    39: wrow=W1_0_7;
    40: wrow=W2_0_0;
    41: wrow=W2_0_1;
    42: wrow=W2_0_2;
    43: wrow=W2_0_3;
    44: wrow=W2_0_4;
    45: wrow=W2_0_5;
    46: wrow=W2_0_6;
    47: wrow=W2_0_7;
    48: wrow=WQ_1_0;
    49: wrow=WQ_1_1;
    50: wrow=WQ_1_2;
    51: wrow=WQ_1_3;
    52: wrow=WQ_1_4;
    53: wrow=WQ_1_5;
    54: wrow=WQ_1_6;
    55: wrow=WQ_1_7;
    56: wrow=WK_1_0;
    57: wrow=WK_1_1;
    58: wrow=WK_1_2;
    59: wrow=WK_1_3;
    60: wrow=WK_1_4;
    61: wrow=WK_1_5;
    62: wrow=WK_1_6;
    63: wrow=WK_1_7;
    64: wrow=WV_1_0;
    65: wrow=WV_1_1;
    66: wrow=WV_1_2;
    67: wrow=WV_1_3;
    68: wrow=WV_1_4;
    69: wrow=WV_1_5;
    70: wrow=WV_1_6;
    71: wrow=WV_1_7;
    72: wrow=WO_1_0;
    73: wrow=WO_1_1;
    74: wrow=WO_1_2;
    75: wrow=WO_1_3;
    76: wrow=WO_1_4;
    77: wrow=WO_1_5;
    78: wrow=WO_1_6;
    79: wrow=WO_1_7;
    80: wrow=W1_1_0;
    81: wrow=W1_1_1;
    82: wrow=W1_1_2;
    83: wrow=W1_1_3;
    84: wrow=W1_1_4;
    85: wrow=W1_1_5;
    86: wrow=W1_1_6;
    87: wrow=W1_1_7;
    88: wrow=W2_1_0;
    89: wrow=W2_1_1;
    90: wrow=W2_1_2;
    91: wrow=W2_1_3;
    92: wrow=W2_1_4;
    93: wrow=W2_1_5;
    94: wrow=W2_1_6;
    95: wrow=W2_1_7;
    default: wrow=0; endcase end endfunction
  function signed [7:0] emb; input integer tok; input integer c; begin case(tok*D+c)
    0: emb=EMB_0_0;
    1: emb=EMB_0_1;
    2: emb=EMB_0_2;
    3: emb=EMB_0_3;
    4: emb=EMB_0_4;
    5: emb=EMB_0_5;
    6: emb=EMB_0_6;
    7: emb=EMB_0_7;
    8: emb=EMB_1_0;
    9: emb=EMB_1_1;
    10: emb=EMB_1_2;
    11: emb=EMB_1_3;
    12: emb=EMB_1_4;
    13: emb=EMB_1_5;
    14: emb=EMB_1_6;
    15: emb=EMB_1_7;
    16: emb=EMB_2_0;
    17: emb=EMB_2_1;
    18: emb=EMB_2_2;
    19: emb=EMB_2_3;
    20: emb=EMB_2_4;
    21: emb=EMB_2_5;
    22: emb=EMB_2_6;
    23: emb=EMB_2_7;
    24: emb=EMB_3_0;
    25: emb=EMB_3_1;
    26: emb=EMB_3_2;
    27: emb=EMB_3_3;
    28: emb=EMB_3_4;
    29: emb=EMB_3_5;
    30: emb=EMB_3_6;
    31: emb=EMB_3_7;
    32: emb=EMB_4_0;
    33: emb=EMB_4_1;
    34: emb=EMB_4_2;
    35: emb=EMB_4_3;
    36: emb=EMB_4_4;
    37: emb=EMB_4_5;
    38: emb=EMB_4_6;
    39: emb=EMB_4_7;
    40: emb=EMB_5_0;
    41: emb=EMB_5_1;
    42: emb=EMB_5_2;
    43: emb=EMB_5_3;
    44: emb=EMB_5_4;
    45: emb=EMB_5_5;
    46: emb=EMB_5_6;
    47: emb=EMB_5_7;
    48: emb=EMB_6_0;
    49: emb=EMB_6_1;
    50: emb=EMB_6_2;
    51: emb=EMB_6_3;
    52: emb=EMB_6_4;
    53: emb=EMB_6_5;
    54: emb=EMB_6_6;
    55: emb=EMB_6_7;
    56: emb=EMB_7_0;
    57: emb=EMB_7_1;
    58: emb=EMB_7_2;
    59: emb=EMB_7_3;
    60: emb=EMB_7_4;
    61: emb=EMB_7_5;
    62: emb=EMB_7_6;
    63: emb=EMB_7_7;
    64: emb=EMB_8_0;
    65: emb=EMB_8_1;
    66: emb=EMB_8_2;
    67: emb=EMB_8_3;
    68: emb=EMB_8_4;
    69: emb=EMB_8_5;
    70: emb=EMB_8_6;
    71: emb=EMB_8_7;
    72: emb=EMB_9_0;
    73: emb=EMB_9_1;
    74: emb=EMB_9_2;
    75: emb=EMB_9_3;
    76: emb=EMB_9_4;
    77: emb=EMB_9_5;
    78: emb=EMB_9_6;
    79: emb=EMB_9_7;
    80: emb=EMB_10_0;
    81: emb=EMB_10_1;
    82: emb=EMB_10_2;
    83: emb=EMB_10_3;
    84: emb=EMB_10_4;
    85: emb=EMB_10_5;
    86: emb=EMB_10_6;
    87: emb=EMB_10_7;
    88: emb=EMB_11_0;
    89: emb=EMB_11_1;
    90: emb=EMB_11_2;
    91: emb=EMB_11_3;
    92: emb=EMB_11_4;
    93: emb=EMB_11_5;
    94: emb=EMB_11_6;
    95: emb=EMB_11_7;
    96: emb=EMB_12_0;
    97: emb=EMB_12_1;
    98: emb=EMB_12_2;
    99: emb=EMB_12_3;
    100: emb=EMB_12_4;
    101: emb=EMB_12_5;
    102: emb=EMB_12_6;
    103: emb=EMB_12_7;
    104: emb=EMB_13_0;
    105: emb=EMB_13_1;
    106: emb=EMB_13_2;
    107: emb=EMB_13_3;
    108: emb=EMB_13_4;
    109: emb=EMB_13_5;
    110: emb=EMB_13_6;
    111: emb=EMB_13_7;
    112: emb=EMB_14_0;
    113: emb=EMB_14_1;
    114: emb=EMB_14_2;
    115: emb=EMB_14_3;
    116: emb=EMB_14_4;
    117: emb=EMB_14_5;
    118: emb=EMB_14_6;
    119: emb=EMB_14_7;
    120: emb=EMB_15_0;
    121: emb=EMB_15_1;
    122: emb=EMB_15_2;
    123: emb=EMB_15_3;
    124: emb=EMB_15_4;
    125: emb=EMB_15_5;
    126: emb=EMB_15_6;
    127: emb=EMB_15_7;
    default: emb=0; endcase end endfunction
  function [2*D-1:0] outp; input integer v; begin case(v)
    0: outp=OUTP_0;
    1: outp=OUTP_1;
    2: outp=OUTP_2;
    3: outp=OUTP_3;
    4: outp=OUTP_4;
    5: outp=OUTP_5;
    6: outp=OUTP_6;
    7: outp=OUTP_7;
    8: outp=OUTP_8;
    9: outp=OUTP_9;
    10: outp=OUTP_10;
    11: outp=OUTP_11;
    12: outp=OUTP_12;
    13: outp=OUTP_13;
    14: outp=OUTP_14;
    15: outp=OUTP_15;
    default: outp=0; endcase end endfunction
  function signed [31:0] mvw; input [2*D-1:0] wr; integer c; reg signed [31:0] s; begin s=0;
    for(c=0;c<D;c=c+1) begin if(wr[2*c+:2]==2'b10) s=s+av[c]; else if(wr[2*c+:2]==2'b00) s=s-av[c]; end mvw=s; end endfunction
  function integer isq; input integer n; integer i; reg [31:0] op,res,one; begin
    op=n; res=0; one=(1<<30);
    for(i=0;i<16;i=i+1) begin
      if(op>=res+one) begin op=op-(res+one); res=(res>>1)+one; end else res=res>>1;
      one=one>>2; end
    isq=res; end endfunction
  function signed [31:0] tdiv; input signed [31:0] a; input signed [31:0] b; begin tdiv=(b==0)?a:(a>=0)?a/b:-((-a)/b); end endfunction
  function signed [31:0] clf; input signed [31:0] v; begin clf=(v>127)?127:(v<-127)?-127:v; end endfunction
  integer ii;
  initial begin
    EXPLUT[0]=EXP_0;
    EXPLUT[1]=EXP_1;
    EXPLUT[2]=EXP_2;
    EXPLUT[3]=EXP_3;
    EXPLUT[4]=EXP_4;
    EXPLUT[5]=EXP_5;
    EXPLUT[6]=EXP_6;
    EXPLUT[7]=EXP_7;
    EXPLUT[8]=EXP_8;
    EXPLUT[9]=EXP_9;
    EXPLUT[10]=EXP_10;
    EXPLUT[11]=EXP_11;
    EXPLUT[12]=EXP_12;
    EXPLUT[13]=EXP_13;
    EXPLUT[14]=EXP_14;
    EXPLUT[15]=EXP_15;
    EXPLUT[16]=EXP_16;
    EXPLUT[17]=EXP_17;
    EXPLUT[18]=EXP_18;
    EXPLUT[19]=EXP_19;
    EXPLUT[20]=EXP_20;
    EXPLUT[21]=EXP_21;
    EXPLUT[22]=EXP_22;
    EXPLUT[23]=EXP_23;
    EXPLUT[24]=EXP_24;
    EXPLUT[25]=EXP_25;
    EXPLUT[26]=EXP_26;
    EXPLUT[27]=EXP_27;
    EXPLUT[28]=EXP_28;
    EXPLUT[29]=EXP_29;
    EXPLUT[30]=EXP_30;
    EXPLUT[31]=EXP_31;
  end
  localparam IDLE=0,EMBED=1,LN1=2,LQKV=3,LATTN=4,LO=5,LFFN=6,LOGITS=7,NEXTT=8,FIN=9;
  reg [3:0] st; integer g,l,t,d,c,j,ms,den,sc,mx,num,dd,wg,ao,go,best,barg,lg;
  always @(posedge clk) begin
    if(rst) begin st<=IDLE; done<=0; g<=0; l<=0; end
    else case(st)
      IDLE: if(start) begin g<=0; l<=0; done<=0;
        seqb[0]<=SEED_0;
        seqb[1]<=SEED_1;
        seqb[2]<=SEED_2;
        seqb[3]<=SEED_3;
        st<=EMBED; end
      EMBED: begin for(t=0;t<S;t=t+1) for(d=0;d<D;d=d+1) X[t*D+d]=emb(seqb[t],d); l<=0; st<=LN1; end
      LN1: begin for(t=0;t<S;t=t+1) begin ms=0; for(d=0;d<D;d=d+1) ms=ms+X[t*D+d]*X[t*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
        for(d=0;d<D;d=d+1) n1[t*D+d]=tdiv(X[t*D+d]*SC*SC,den); end st<=LQKV; end
      LQKV: begin for(t=0;t<S;t=t+1) begin for(d=0;d<D;d=d+1) av[d]=n1[t*D+d];
        for(d=0;d<D;d=d+1) begin Q[t*D+d]=mvw(wrow(l,0,d)); K[t*D+d]=mvw(wrow(l,1,d)); Vv[t*D+d]=mvw(wrow(l,2,d)); end end st<=LATTN; end
      LATTN: begin for(t=0;t<S;t=t+1) begin mx=-2147483647;
        for(j=0;j<=t;j=j+1) begin sc=0; for(c=0;c<D;c=c+1) sc=sc+Q[t*D+c]*K[j*D+c]; av[j]=sc; if(sc>mx)mx=sc; end
        for(d=0;d<D;d=d+1) begin num=0; dd=0;
          for(j=0;j<=t;j=j+1) begin c=(mx-av[j])/SMSCALE; if(c>31)c=31; wg=EXPLUT[c]; num=num+wg*Vv[j*D+d]; dd=dd+wg; end
          ctx[t*D+d]=tdiv(num,dd); end end st<=LO; end
      LO: begin for(t=0;t<S;t=t+1) begin for(d=0;d<D;d=d+1) av[d]=ctx[t*D+d];
        for(d=0;d<D;d=d+1) begin ao=clf(tdiv(mvw(wrow(l,3,d)),1<<SH_A)); Hh[t*D+d]=clf(X[t*D+d]+ao); end end st<=LFFN; end
      LFFN: begin for(t=0;t<S;t=t+1) begin ms=0; for(d=0;d<D;d=d+1) ms=ms+Hh[t*D+d]*Hh[t*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
        for(d=0;d<D;d=d+1) av[d]=tdiv(Hh[t*D+d]*SC*SC,den);
        for(d=0;d<D;d=d+1) begin go=mvw(wrow(l,4,d)); if(go<0)go=0; av2[d]=go; end
        for(d=0;d<D;d=d+1) av[d]=av2[d];
        for(d=0;d<D;d=d+1) begin go=clf(tdiv(mvw(wrow(l,5,d)),1<<SH_F)); X[t*D+d]=clf(Hh[t*D+d]+go); end end
        if(l==L-1) st<=LOGITS; else begin l<=l+1; st<=LN1; end end
      LOGITS: begin ms=0; for(d=0;d<D;d=d+1) ms=ms+X[(S-1)*D+d]*X[(S-1)*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
        for(d=0;d<D;d=d+1) av[d]=tdiv(X[(S-1)*D+d]*SC*SC,den);
        best=-2147483647; barg=0;
        for(j=0;j<V;j=j+1) begin lg=mvw(outp(j)); if(lg>best) begin best=lg; barg=j; end end
        gtok[g]=barg[7:0]; st<=NEXTT; end
      NEXTT: begin for(t=0;t<S-1;t=t+1) seqb[t]<=seqb[t+1]; seqb[S-1]<=gtok[g];
        if(g==NGEN-1) st<=FIN; else begin g<=g+1; st<=EMBED; end end
      FIN: begin done<=1; st<=IDLE; end
    endcase end
endmodule