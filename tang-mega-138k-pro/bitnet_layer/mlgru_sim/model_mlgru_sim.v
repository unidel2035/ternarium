// model_mlgru.v — MatMul-free MLGRU (троичный рекуррент) inference, ПОТОКОВО (RNN-style).
// Архитектура Zhu 2024 (arXiv:2406.02528): MLGRU вместо attention. КЛЮЧЕВОЕ: токены текут по одному,
// неся per-layer стейт hs[l]; буфер всей последовательности X[S*D] НЕ НУЖЕН (это и есть постоянная
// память рекуррента — и это убирает синтез-киллер: нет регистрового файла с переменным индексом).
// Веса/LUT/эмбеддинги в BRAM ($readmemh). Один общий isqrt32+sdiv32 (fxops.v). Без KV-кэша.
`default_nettype none
module model_mlgru(input wire clk, input wire ce, input wire rst, input wire start,
  input wire [1:0] sit, input wire use_ext, input wire [63:0] seed_flat,
  input wire [7:0] tok_addr, output wire [7:0] tok_out, output reg done);
  `include "mlgru_vectors.vh"
  localparam DSHIFT = (D==8)?3:(D==16)?4:(D==32)?5:(D==4)?2:3;
  reg [7:0] gtok[0:15]; assign tok_out = gtok[tok_addr];
  reg [2*RW-1:0]    wrom [0:WROWS-1];
  reg [2*RW-1:0]    wrd;                          // регистр чтения wrom → синхронное чтение → инференс BSRAM
  reg signed [15:0] embrom[0:V*D-1];
  reg signed [15:0] lutrom[0:12*LN-1];
  initial begin $readmemh("mlgru_wt.hex",wrom); $readmemh("mlgru_emb.hex",embrom); $readmemh("mlgru_lut.hex",lutrom); end
  // активации: ТОЛЬКО текущий токен x[D] + per-layer стейты hs[L*D] (рекуррент)
  reg signed [15:0] x[0:D-1], hs[0:L*D-1];
  reg signed [15:0] xn[0:D-1], av[0:RW-1];
  reg signed [15:0] fg[0:D-1], cg[0:D-1], gg2[0:H-1], ug[0:H-1], hgh[0:H-1];
  reg signed [31:0] ss, ms, den32;
  reg [7:0] seqb[0:S-1];
  reg [7:0] seedrom[0:4*S-1];                       // 4 демо-ситуации × S токенов
  initial $readmemh("seedrom.hex", seedrom);
  reg iq_st; reg [31:0] iq_x; wire [16:0] iq_root; wire iq_busy,iq_done;
  isqrt32 IQ(.clk(clk),.ce(ce),.rst(rst),.start(iq_st),.x(iq_x),.root(iq_root),.busy(iq_busy),.done(iq_done));
  reg dv_st; reg signed [31:0] dv_a,dv_b; wire signed [31:0] dv_q; wire dv_busy,dv_done;
  sdiv32 DV(.clk(clk),.ce(ce),.rst(rst),.start(dv_st),.a(dv_a),.b(dv_b),.q(dv_q),.busy(dv_busy),.done(dv_done));
  // знаковое умножение 16×16 → `*` (маппится на аппаратный DSP вместо сотен LUT). Семантически
  // идентично прежнему сдвиг-сложению (bit15 = знак), что подтверждает sim 6/6.
  function signed [31:0] mul16; input signed [31:0] a,b; integer i; reg signed [31:0] t,acc; begin
    t=$signed(a[15:0]); acc=0;
    for(i=0;i<15;i=i+1) if(b[i]) acc=acc+(t<<<i);
    if(b[15]) acc=acc-(t<<<15); mul16=acc; end endfunction
  function signed [31:0] mvw; input [2*RW-1:0] wr; input integer n; integer c; reg signed [31:0] s; begin s=0;
    for(c=0;c<RW;c=c+1) if(c<n) begin
      if(wr[2*c+:2]==2'b10) s=s+av[c]; else if(wr[2*c+:2]==2'b00) s=s-av[c]; end mvw=s; end endfunction
  function signed [15:0] clf;  input signed [31:0] v; begin clf =(v>127)?16'sd127:(v<-127)?-16'sd127:v[15:0]; end endfunction
  function signed [15:0] clf2; input signed [31:0] v; begin clf2=(v>8192)?16'sd8192:(v<-8192)?-16'sd8192:v[15:0]; end endfunction
  function signed [31:0] lut; input integer lb; input signed [31:0] pre; reg signed [31:0] idx; begin
    idx=(pre>>>SHIN)+HALF; if(idx<0) idx=0; else if(idx>LN-1) idx=LN-1; lut=lutrom[lb+idx]; end endfunction
  function integer bWf;  input integer l; bWf =(l==0)?B_Wf0:(l==1)?B_Wf1:B_Wf2;  endfunction
  function integer bWc;  input integer l; bWc =(l==0)?B_Wc0:(l==1)?B_Wc1:B_Wc2;  endfunction
  function integer bWg;  input integer l; bWg =(l==0)?B_Wg0:(l==1)?B_Wg1:B_Wg2;  endfunction
  function integer bWo;  input integer l; bWo =(l==0)?B_Wo0:(l==1)?B_Wo1:B_Wo2;  endfunction
  function integer bW2g; input integer l; bW2g=(l==0)?B_W2g0:(l==1)?B_W2g1:B_W2g2; endfunction
  function integer bW2u; input integer l; bW2u=(l==0)?B_W2u0:(l==1)?B_W2u1:B_W2u2; endfunction
  function integer bW2d; input integer l; bW2d=(l==0)?B_W2d0:(l==1)?B_W2d1:B_W2d2; endfunction
  function integer blf;  input integer l; blf =(l==0)?BL_Lf0:(l==1)?BL_Lf1:BL_Lf2;  endfunction
  function integer blc;  input integer l; blc =(l==0)?BL_Lc0:(l==1)?BL_Lc1:BL_Lc2;  endfunction
  function integer blg;  input integer l; blg =(l==0)?BL_Lg0:(l==1)?BL_Lg1:BL_Lg2;  endfunction
  function integer bl2g; input integer l; bl2g=(l==0)?BL_L2g0:(l==1)?BL_L2g1:BL_L2g2; endfunction
  function integer mwo;  input integer l; mwo=(l==0)?MWo_0:(l==1)?MWo_1:MWo_2; endfunction
  function integer mwu;  input integer l; mwu=(l==0)?MWu_0:(l==1)?MWu_1:MWu_2; endfunction
  function integer mwd;  input integer l; mwd=(l==0)?MWd_0:(l==1)?MWd_1:MWd_2; endfunction
  // FSM
  localparam IDLE=0,LD=1,RMS=2,SQW=3,DVV=4,DVR=5,DVW=6,
    MV=7,MVR=8,                                  // СЕРИЙНЫЙ матвек: регистрируем чтение (MVR→MVR2) → BSRAM
    GSET=9,GCP=10,REC=11,GHSET=12,
    FRMS=13,FSET=14,FUSET=15,FCP=16,FGU=17,NEXTL=18,LARG=19,NXT=20,FIN=21,LOG=22,MVR2=23;
  // serial-MV: mvb=база строк, mvi=indim, mvo=outdim, mvmode(0=LUT→mvb_o,1=PROJ→x,2=RAW→mvb_o,3=SCALED→mvb_o)
  reg [11:0] mvb; integer mvi, mvo; reg [1:0] mvmode; reg [11:0] mvlb; reg signed [31:0] mvmw; reg [4:0] mvret;
  reg signed [15:0] mvres[0:V-1]; reg [1:0] gph;
  reg signed [31:0] pre;
  reg [4:0] stt, ret; integer g,t,l,d,c,j,dd,best,barg;
  always @(posedge clk) begin
    if(rst) begin stt<=IDLE; done<=0; g<=0; t<=0; l<=0; iq_st<=0; dv_st<=0; end
    else if(ce) begin iq_st<=0; dv_st<=0; case(stt)
      IDLE: if(start) begin g<=0; t<=0; l<=0; done<=0;
        for(j=0;j<S;j=j+1) seqb[j]<= use_ext ? seed_flat[j*8 +: 8] : seedrom[sit*S+j];  // внешняя обстановка или ситуация-ROM
        for(d=0;d<L*D;d=d+1) hs[d]<=0; stt<=LD; end
      LD: begin for(d=0;d<D;d=d+1) x[d]=embrom[seqb[t]*D+d]; l<=0; stt<=RMS; end
      // ── общий RMS: ss/sqrt → SQW → serial divide → ret ──
      RMS:  begin ss=0; for(d=0;d<D;d=d+1) ss=ss+mul16(x[d],x[d]); ms=ss/D;
        iq_x<=ms*AS*AS; iq_st<=1; ret<=GSET; gph<=0; stt<=SQW; end
      FRMS: begin ss=0; for(d=0;d<D;d=d+1) ss=ss+mul16(x[d],x[d]); ms=ss/D;
        iq_x<=ms*AS*AS; iq_st<=1; ret<=FSET; stt<=SQW; end
      LOG:  begin ss=0; for(d=0;d<D;d=d+1) ss=ss+mul16(x[d],x[d]); ms=ss/D;
        iq_x<=ms*AS*AS; iq_st<=1; ret<=LARG; stt<=SQW; end
      SQW: begin if(iq_done) begin den32<=(iq_root==0)?1:iq_root; stt<=DVV; end end
      DVV: begin dd<=0; stt<=DVR; end
      DVR: begin dv_a<=$signed(x[dd])*AS*AS; dv_b<=den32; dv_st<=1; stt<=DVW; end
      DVW: begin if(dv_done) begin xn[dd]<=clf(dv_q); if(dd==D-1) stt<=ret; else begin dd<=dd+1; stt<=DVR; end end end
      // ── СЕРИЙНЫЙ матвек (одно чтение wrom за такт) ──
      MV: begin dd<=0; stt<=MVR; end
      MVR: begin wrd<=wrom[mvb+dd]; stt<=MVR2; end                         // такт 1: регистрируем строку весов (→BSRAM)
      MVR2: begin pre=mvw(wrd,mvi);                                        // такт 2: считаем по защёлкнутой строке
        case(mvmode)
          2'd0: mvres[dd]<=lut(mvlb,pre);                                  // LUT
          2'd1: x[dd]<=clf2($signed(x[dd])+((mul16(pre,mvmw))>>>MWF));      // PROJ → x
          2'd2: mvres[dd]<=pre[15:0];                                       // RAW (для argmax используем pre)
          2'd3: mvres[dd]<=clf((mul16(pre,mvmw))>>>MWF);                    // SCALED → int8
        endcase
        if(mvmode==2'd2) begin if(pre>best) begin best=pre; barg=dd; end end
        if(dd==mvo-1) stt<=mvret; else begin dd<=dd+1; stt<=MVR; end end
      // ── MLGRU гейты: f,c,g последовательно через MV(LUT) ──
      GSET: begin for(d=0;d<D;d=d+1) av[d]=xn[d];
        mvb<=(gph==0)?bWf(l):(gph==1)?bWc(l):bWg(l); mvlb<=(gph==0)?blf(l):(gph==1)?blc(l):blg(l);
        mvi<=D; mvo<=D; mvmode<=0; mvret<=GCP; stt<=MV; end
      GCP: begin case(gph) 2'd0: for(d=0;d<D;d=d+1) fg[d]<=mvres[d];
                           2'd1: for(d=0;d<D;d=d+1) cg[d]<=mvres[d];
                           default: for(d=0;d<D;d=d+1) gg2[d]<=mvres[d]; endcase
        if(gph==2) stt<=REC; else begin gph<=gph+1; stt<=GSET; end end
      REC: begin for(d=0;d<D;d=d+1) hs[l*D+d]<=(mul16(fg[d],hs[l*D+d])+mul16(FXONE-fg[d],cg[d]))>>>8; stt<=GHSET; end
      GHSET: begin for(d=0;d<D;d=d+1) av[d]=clf((mul16(gg2[d],hs[l*D+d]))>>>8);   // av=gh
        mvb<=bWo(l); mvi<=D; mvo<=D; mvmode<=1; mvmw<=mwo(l); mvret<=FRMS; stt<=MV; end
      // ── GLU FFN: g2=LUT(W2g), u=SCALED(W2u), gu=(g2*u)>>5, x+=PROJ(W2d) ──
      FSET: begin for(d=0;d<D;d=d+1) av[d]=xn[d];
        mvb<=bW2g(l); mvlb<=bl2g(l); mvi<=D; mvo<=H; mvmode<=0; mvret<=FUSET; stt<=MV; end
      FUSET: begin for(d=0;d<H;d=d+1) gg2[d]<=mvres[d];                            // g2
        mvb<=bW2u(l); mvi<=D; mvo<=H; mvmode<=3; mvmw<=mwu(l); mvret<=FCP; stt<=MV; end
      FCP: begin for(d=0;d<H;d=d+1) ug[d]<=mvres[d]; stt<=FGU; end                 // u
      FGU: begin for(d=0;d<H;d=d+1) av[d]=clf((mul16(gg2[d],ug[d]))>>>5);          // av=gu
        mvb<=bW2d(l); mvi<=H; mvo<=D; mvmode<=1; mvmw<=mwd(l); mvret<=NEXTL; stt<=MV; end
      NEXTL: begin if(l==L-1) begin if(t==S-1) stt<=LOG; else begin t<=t+1; l<=0; stt<=LD; end end
                   else begin l<=l+1; stt<=RMS; end end
      LARG: begin for(d=0;d<D;d=d+1) av[d]=xn[d]; best=-2147483647; barg=0;
        mvb<=B_OUT; mvi<=D; mvo<=V; mvmode<=2; mvret<=NXT; stt<=MV; end
      NXT: begin gtok[g]=barg[7:0];
        for(t=0;t<S-1;t=t+1) seqb[t]<=seqb[t+1]; seqb[S-1]<=barg[7:0];
        if(g==NGEN-1) stt<=FIN; else begin g<=g+1; t<=0; l<=0; for(d=0;d<L*D;d=d+1) hs[d]<=0; stt<=LD; end end
      FIN: begin done<=1; stt<=IDLE; end
    endcase end end
endmodule
