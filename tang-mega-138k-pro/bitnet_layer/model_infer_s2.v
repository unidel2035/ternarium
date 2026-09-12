// model_infer_s2.v — ПОЛНОСТЬЮ сериализованный синтезопригодный inference.
// ОДИН общий dot (mvw в MVR) для ВСЕХ матвеков + один sdiv32 + один isqrt32. ABC9-дружественно.
`default_nettype none
module model_infer_s2(input wire clk, input wire rst, input wire start,
  input wire [7:0] tok_addr, output wire [7:0] tok_out, output reg done);
  reg [7:0] gtok[0:15];
  `include "model_vectors.vh"
  assign tok_out = gtok[tok_addr];
  reg signed [31:0] X[0:S*D-1], n1[0:S*D-1], Q[0:S*D-1], K[0:S*D-1], Vv[0:S*D-1];
  reg signed [31:0] ctx[0:S*D-1], Hh[0:S*D-1], nn[0:D-1], gg[0:H-1], xn[0:D-1];
  reg signed [31:0] av[0:D-1], mvout[0:15], vn[0:D-1], vout[0:D-1], vden, sqarg, den;
  integer EXPLUT[0:31]; reg [7:0] seqb[0:S-1];
  reg iq_st; reg [31:0] iq_x; wire [16:0] iq_root; wire iq_busy,iq_done;
  isqrt32 IQ(.clk(clk),.rst(rst),.start(iq_st),.x(iq_x),.root(iq_root),.busy(iq_busy),.done(iq_done));
  reg dv_st; reg signed [31:0] dv_a,dv_b; wire signed [31:0] dv_q; wire dv_busy,dv_done;
  sdiv32 DV(.clk(clk),.rst(rst),.start(dv_st),.a(dv_a),.b(dv_b),.q(dv_q),.busy(dv_busy),.done(dv_done));
  function [2*D-1:0] wrow; input integer l; input integer m; input integer r; begin
    if(m==6) case(r)
      0: wrow=OUTP_0;
      1: wrow=OUTP_1;
      2: wrow=OUTP_2;
      3: wrow=OUTP_3;
      4: wrow=OUTP_4;
      5: wrow=OUTP_5;
      6: wrow=OUTP_6;
      7: wrow=OUTP_7;
      8: wrow=OUTP_8;
      9: wrow=OUTP_9;
      10: wrow=OUTP_10;
      11: wrow=OUTP_11;
      12: wrow=OUTP_12;
      13: wrow=OUTP_13;
      14: wrow=OUTP_14;
      15: wrow=OUTP_15;
      default: wrow=0; endcase
    else case(((l*6)+m)*D+r)
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
  function signed [31:0] mvw; input [2*D-1:0] wr; integer c; reg signed [31:0] s; begin s=0;
    for(c=0;c<D;c=c+1) begin if(wr[2*c+:2]==2'b10) s=s+av[c]; else if(wr[2*c+:2]==2'b00) s=s-av[c]; end mvw=s; end endfunction
  function signed [31:0] mul16; input signed [31:0] x,y; integer i; reg signed [31:0] a; reg signed [31:0] acc; begin
    a=$signed(x[15:0]); acc=0;
    for(i=0;i<15;i=i+1) if(y[i]) acc=acc+(a<<<i);
    if(y[15]) acc=acc-(a<<<15);
    mul16=acc; end endfunction
  function signed [31:0] treq; input signed [31:0] v; input integer sh; begin treq=(v>=0)?(v>>>sh):-((-v)>>>sh); end endfunction
  function signed [31:0] clf; input signed [31:0] v; begin clf=(v>127)?127:(v<-127)?-127:v; end endfunction
  integer ii; initial begin
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
  localparam IDLE=0;
  localparam EMB=1;
  localparam LN1=2;
  localparam LN1D=3;
  localparam LN1S=4;
  localparam LQKV=5;
  localparam LQKVS=6;
  localparam LATT=7;
  localparam LATTS=8;
  localparam LO=9;
  localparam LOS=10;
  localparam LN2=11;
  localparam LN2D=12;
  localparam LN2S=13;
  localparam FFN1=14;
  localparam FFN1S=15;
  localparam FFN2=16;
  localparam FFN2S=17;
  localparam FRMS=18;
  localparam FRMSD=19;
  localparam FRMSS=20;
  localparam LOG=21;
  localparam LOGS=22;
  localparam NXT=23;
  localparam MV=24;
  localparam MVR=25;
  localparam SQRT=26;
  localparam SQRTW=27;
  localparam DIVV=28;
  localparam DIVR=29;
  localparam DIVW=30;
  localparam FIN=31;
  reg [5:0] stt, ret; integer g,l,t,d,c,j,dd,ri,jm,ss,ms,mx,num,sw,best,barg;
  reg [2:0] mb_l, mb_m; reg [4:0] mn;
  always @(posedge clk) begin
    if(rst) begin stt<=IDLE; done<=0; g<=0; l<=0; iq_st<=0; dv_st<=0; end
    else begin iq_st<=0; dv_st<=0; case(stt)
      IDLE: if(start) begin g<=0; l<=0; done<=0;
        seqb[0]<=SEED_0;
        seqb[1]<=SEED_1;
        seqb[2]<=SEED_2;
        seqb[3]<=SEED_3;
        stt<=EMB; end
      EMB: begin for(t=0;t<S;t=t+1) for(d=0;d<D;d=d+1) X[t*D+d]=emb(seqb[t],d); l<=0; t<=0; stt<=LN1; end
      LN1: begin ss=0; for(d=0;d<D;d=d+1) ss=ss+mul16(X[t*D+d],X[t*D+d]); ms=ss>>>3;
        for(d=0;d<D;d=d+1) vn[d]=X[t*D+d]*SC*SC; sqarg<=ms*SC*SC; ret<=LN1D; stt<=SQRT; end
      LN1D: begin vden<=den; ret<=LN1S; stt<=DIVV; end
      LN1S: begin for(d=0;d<D;d=d+1) n1[t*D+d]<=vout[d]; if(t==S-1) begin t<=0; stt<=LQKV; end else begin t<=t+1; stt<=LN1; end end
      LQKV: begin for(d=0;d<D;d=d+1) av[d]=n1[t*D+d]; jm<=0; mb_l<=l; mb_m<=0; mn<=D; ret<=LQKVS; stt<=MV; end
      LQKVS: begin case(jm) 0: for(d=0;d<D;d=d+1) Q[t*D+d]<=mvout[d]; 1: for(d=0;d<D;d=d+1) K[t*D+d]<=mvout[d]; 2: for(d=0;d<D;d=d+1) Vv[t*D+d]<=mvout[d]; endcase
        if(jm==2) begin if(t==S-1) begin t<=0; stt<=LATT; end else begin t<=t+1; stt<=LQKV; end end
        else begin jm<=jm+1; mb_m<=jm+1; ret<=LQKVS; stt<=MV; end end
      LATT: begin mx=-2147483647;
        for(j=0;j<S;j=j+1) if(j<=t) begin sw=0; for(c=0;c<D;c=c+1) sw=sw+mul16(Q[t*D+c],K[j*D+c]); av[j]=sw; if(sw>mx)mx=sw; end
        for(d=0;d<D;d=d+1) begin num=0; sw=0; for(j=0;j<S;j=j+1) if(j<=t) begin c=(mx-av[j])>>>3; if(c>31)c=31; num=num+mul16(EXPLUT[c],Vv[j*D+d]); sw=sw+EXPLUT[c]; end vn[d]=num; end
        vden<=sw; ret<=LATTS; stt<=DIVV; end
      LATTS: begin for(d=0;d<D;d=d+1) ctx[t*D+d]<=vout[d]; if(t==S-1) begin t<=0; stt<=LO; end else begin t<=t+1; stt<=LATT; end end
      LO: begin for(d=0;d<D;d=d+1) av[d]=ctx[t*D+d]; mb_l<=l; mb_m<=3; mn<=D; ret<=LOS; stt<=MV; end
      LOS: begin for(d=0;d<D;d=d+1) Hh[t*D+d]<=clf(X[t*D+d]+treq(mvout[d],SH_A)); if(t==S-1) begin t<=0; stt<=LN2; end else begin t<=t+1; stt<=LO; end end
      LN2: begin ss=0; for(d=0;d<D;d=d+1) ss=ss+mul16(Hh[t*D+d],Hh[t*D+d]); ms=ss>>>3;
        for(d=0;d<D;d=d+1) vn[d]=Hh[t*D+d]*SC*SC; sqarg<=ms*SC*SC; ret<=LN2D; stt<=SQRT; end
      LN2D: begin vden<=den; ret<=LN2S; stt<=DIVV; end
      LN2S: begin for(d=0;d<D;d=d+1) nn[d]<=vout[d]; stt<=FFN1; end
      FFN1: begin for(d=0;d<D;d=d+1) av[d]=nn[d]; mb_l<=l; mb_m<=4; mn<=H; ret<=FFN1S; stt<=MV; end
      FFN1S: begin for(d=0;d<H;d=d+1) gg[d]<=(mvout[d]<0)?0:mvout[d]; stt<=FFN2; end
      FFN2: begin for(d=0;d<H;d=d+1) av[d]=gg[d]; mb_l<=l; mb_m<=5; mn<=D; ret<=FFN2S; stt<=MV; end
      FFN2S: begin for(d=0;d<D;d=d+1) X[t*D+d]<=clf(Hh[t*D+d]+treq(mvout[d],SH_F));
        if(t==S-1) begin if(l==L-1) stt<=FRMS; else begin l<=l+1; t<=0; stt<=LN1; end end else begin t<=t+1; stt<=LN2; end end
      FRMS: begin ss=0; for(d=0;d<D;d=d+1) ss=ss+mul16(X[(S-1)*D+d],X[(S-1)*D+d]); ms=ss>>>3;
        for(d=0;d<D;d=d+1) vn[d]=X[(S-1)*D+d]*SC*SC; sqarg<=ms*SC*SC; ret<=FRMSD; stt<=SQRT; end
      FRMSD: begin vden<=den; ret<=FRMSS; stt<=DIVV; end
      FRMSS: begin for(d=0;d<D;d=d+1) xn[d]<=vout[d]; stt<=LOG; end
      LOG: begin for(d=0;d<D;d=d+1) av[d]=xn[d]; mb_l<=0; mb_m<=6; mn<=V; ret<=LOGS; stt<=MV; end
      LOGS: begin best=-2147483647; barg=0; for(j=0;j<V;j=j+1) if(mvout[j]>best) begin best=mvout[j]; barg=j; end
        gtok[g]=barg[7:0]; stt<=NXT; end
      NXT: begin for(t=0;t<S-1;t=t+1) seqb[t]<=seqb[t+1]; seqb[S-1]<=gtok[g];
        if(g==NGEN-1) stt<=FIN; else begin g<=g+1; l<=0; t<=0; stt<=EMB; end end
      MV: begin ri<=0; stt<=MVR; end
      MVR: begin mvout[ri]<=mvw(wrow(mb_l,mb_m,ri)); if(ri==mn-1) stt<=ret; else ri<=ri+1; end
      SQRT: begin iq_x<=sqarg; iq_st<=1; stt<=SQRTW; end
      SQRTW: begin if(iq_done) begin den<=(iq_root==0)?1:iq_root; stt<=ret; end end
      DIVV: begin dd<=0; stt<=DIVR; end
      DIVR: begin dv_a<=vn[dd]; dv_b<=vden; dv_st<=1; stt<=DIVW; end
      DIVW: begin if(dv_done) begin vout[dd]<=dv_q; if(dd==D-1) stt<=ret; else begin dd<=dd+1; stt<=DIVR; end end end
      FIN: begin done<=1; stt<=IDLE; end
    endcase end end
endmodule