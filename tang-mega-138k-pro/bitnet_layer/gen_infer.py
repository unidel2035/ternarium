#!/usr/bin/env python3
"""gen_infer.py — генерирует синтезопригодный model_infer_dom.v под конфиг из domain_config.json.
Базируется на проверенном model_infer_s2.v (один общий dot + sdiv32 + isqrt32, ABC9-дружественно),
но параметризует то, что в s2 было захардкожено под D=8/L=2/V=16/H=8:
  • таблицы wrow() (веса) и emb() (эмбеддинги) под текущие V,D,L,H;
  • RMS-сдвиг ms=ss>>>DSHIFT (DSHIFT=log2 D) вместо >>>3;
  • stride RW и размер mvout под max(D,H,V);
  • засев seqb[0..S-1] из SEED_*.
H=D обязательно (mvw в RTL суммирует по D). Запуск: python3 gen_infer.py
"""
import json, os, math
HERE=os.path.dirname(os.path.abspath(__file__))
cfg=json.load(open(os.path.join(HERE,"domain_config.json")))
V,D,L,H,S=cfg["V"],cfg["D"],cfg["L"],cfg["H"],cfg["S"]
DSHIFT=cfg["DSHIFT"]; RW=cfg["RW"]
assert H==D, "RTL mvw суммирует по D → требуется H==D"

MNAME=["WQ","WK","WV","WO","W1","W2"]
ROWS =[D,D,D,D,H,D]                       # число строк на каждую матрицу m=0..5

def wrow_arms():
    out=[]
    # веса: key=(l*7+m)*RW+r
    for l in range(L):
        for m in range(6):
            for r in range(ROWS[m]):
                key=(l*7+m)*RW+r
                out.append(f"      {key}: wrow={MNAME[m]}_{l}_{r};")
    # выходная проекция: m=6, l=0
    for r in range(V):
        key=(0*7+6)*RW+r
        out.append(f"      {key}: wrow=OUTP_{r};")
    return "\n".join(out)

def emb_arms():
    out=[]
    for tok in range(V):
        for c in range(D):
            out.append(f"    {tok*D+c}: emb=EMB_{tok}_{c};")
    return "\n".join(out)

def explut_init():
    return "\n".join(f"    EXPLUT[{k}]=EXP_{k};" for k in range(32))

def seqb_seed():
    return "\n".join(f"        seqb[{i}]<=SEED_{i};" for i in range(S))

def seqb_ext():
    # внешний контекст: seqb[i] <- ctx_in[8*i +: 8] (по байту на токен)
    return "\n".join(f"          seqb[{i}]<=ctx_in[{8*i}+:8];" for i in range(S))

TEMPLATE=f"""// model_infer_dom.v — СГЕНЕРИРОВАН gen_infer.py под доменный конфиг
//   V={V} D={D} L={L} H={H} S={S}  (домен из lexicon.json)
// Полностью сериализованный синтезопригодный inference: один общий dot (MVR) для ВСЕХ матвеков
// + один sdiv32 + один isqrt32 (fxops.v). ABC9-дружественно, без MULT18X18 в матвеках (троичные).
`default_nettype none
module model_infer_dom(input wire clk, input wire rst, input wire start,
  input wire [7:0] tok_addr, output wire [7:0] tok_out, output reg done,
  // ── ВНЕШНИЙ КОНТЕКСТ (Трек C): ext=1 → seqb грузится из ctx_in (по байту/токен),
  //    ОДИН forward, команда в gtok[0], done. ext=0 → прежнее (seed SEED_*, NGEN авторегр.) ──
  input wire ext, input wire [{8*S-1}:0] ctx_in);
  reg [7:0] gtok[0:15];
  `include "model_vectors.vh"
  assign tok_out = gtok[tok_addr];
  // большие буферы S*D — 16 бит (значения ±~4000; Q/K/Vv всё равно усекаются mul16 до 16б) → FF вдвое
  reg signed [15:0] X[0:S*D-1], n1[0:S*D-1], Q[0:S*D-1], K[0:S*D-1], Vv[0:S*D-1];
  reg signed [15:0] ctx[0:S*D-1], Hh[0:S*D-1];
  reg signed [31:0] nn[0:D-1], gg[0:H-1], xn[0:D-1];
  reg signed [31:0] av[0:{RW-1}], mvout[0:{RW-1}], vn[0:D-1], vout[0:D-1], vden, sqarg, den;
  integer EXPLUT[0:31]; reg [7:0] seqb[0:S-1];
  reg iq_st; reg [31:0] iq_x; wire [16:0] iq_root; wire iq_busy,iq_done;
  isqrt32 IQ(.clk(clk),.rst(rst),.start(iq_st),.x(iq_x),.root(iq_root),.busy(iq_busy),.done(iq_done));
  reg dv_st; reg signed [31:0] dv_a,dv_b; wire signed [31:0] dv_q; wire dv_busy,dv_done;
  sdiv32 DV(.clk(clk),.rst(rst),.start(dv_st),.a(dv_a),.b(dv_b),.q(dv_q),.busy(dv_busy),.done(dv_done));
  function [2*D-1:0] wrow; input integer l; input integer m; input integer r; integer key; begin
    key=(l*7+m)*{RW}+r;
    case(key)
{wrow_arms()}
      default: wrow=0; endcase end endfunction
  function signed [7:0] emb; input integer tok; input integer c; begin case(tok*D+c)
{emb_arms()}
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
  function signed [31:0] rsrc; input ish; input integer idx; begin rsrc=ish?Hh[idx]:X[idx]; end endfunction
  integer ii; initial begin
{explut_init()}
  end
  localparam IDLE=0,EMB=1,LN1=2,LN1D=3,LN1S=4,LQKV=5,LQKVS=6,LATT=7,LATTS=8,LO=9,LOS=10,
    LN2=11,LN2D=12,LN2S=13,FFN1=14,FFN1S=15,FFN2=16,FFN2S=17,FRMS=18,FRMSD=19,FRMSS=20,
    LOG=21,LOGS=22,NXT=23,MV=24,MVR=25,SQRT=26,SQRTW=27,DIVV=28,DIVR=29,DIVW=30,FIN=31,
    SSQ=32,SSQD=33,ATSC=34,ATSCJ=35,ATEXP=36,ATWS=37,ATWSACC=38,ATWSD=39;
  reg [5:0] stt, ret;
  integer g,l,t,d,c,j,dd,ri,jm,ss,ms,mx,num,sw,best,barg;
  reg [3:0] mb_l, mb_m; reg [9:0] mn;
  // serial-MAC: один общий mul16 переиспользуется по тактам (вместо ~512 параллельных)
  reg signed [31:0] macc; reg signed [31:0] ew[0:S-1]; reg rms_isH;
  reg ext_mode;  // защёлкнут в IDLE: 1 = внешний контекст (один forward)
  integer rms_base, si, ci, jj, aj, di;
  always @(posedge clk) begin
    if(rst) begin stt<=IDLE; done<=0; g<=0; l<=0; iq_st<=0; dv_st<=0; ext_mode<=1'b0; end
    else begin iq_st<=0; dv_st<=0; case(stt)
      IDLE: if(start) begin g<=0; l<=0; done<=0; ext_mode<=ext;
        if(ext) begin
{seqb_ext()}
        end else begin
{seqb_seed()}
        end
        stt<=EMB; end
      EMB: begin for(t=0;t<S;t=t+1) for(d=0;d<D;d=d+1) X[t*D+d]=emb(seqb[t],d); l<=0; t<=0; stt<=LN1; end
      LN1: begin macc<=0; si<=0; rms_isH<=1'b0; rms_base<=t*D; ret<=LN1D; stt<=SSQ; end
      LN1D: begin vden<=den; ret<=LN1S; stt<=DIVV; end
      LN1S: begin for(d=0;d<D;d=d+1) n1[t*D+d]<=vout[d]; if(t==S-1) begin t<=0; stt<=LQKV; end else begin t<=t+1; stt<=LN1; end end
      LQKV: begin for(d=0;d<D;d=d+1) av[d]=n1[t*D+d]; jm<=0; mb_l<=l; mb_m<=0; mn<=D; ret<=LQKVS; stt<=MV; end
      LQKVS: begin case(jm) 0: for(d=0;d<D;d=d+1) Q[t*D+d]<=mvout[d]; 1: for(d=0;d<D;d=d+1) K[t*D+d]<=mvout[d]; 2: for(d=0;d<D;d=d+1) Vv[t*D+d]<=mvout[d]; endcase
        if(jm==2) begin if(t==S-1) begin t<=0; stt<=LATT; end else begin t<=t+1; stt<=LQKV; end end
        else begin jm<=jm+1; mb_m<=jm+1; ret<=LQKVS; stt<=MV; end end
      LATT: begin mx=-2147483647; jj<=0; ci<=0; macc<=0; stt<=ATSC; end
      LATTS: begin for(d=0;d<D;d=d+1) ctx[t*D+d]<=vout[d]; if(t==S-1) begin t<=0; stt<=LO; end else begin t<=t+1; stt<=LATT; end end
      LO: begin for(d=0;d<D;d=d+1) av[d]=ctx[t*D+d]; mb_l<=l; mb_m<=3; mn<=D; ret<=LOS; stt<=MV; end
      LOS: begin for(d=0;d<D;d=d+1) Hh[t*D+d]<=clf(X[t*D+d]+treq(mvout[d],SH_A)); if(t==S-1) begin t<=0; stt<=LN2; end else begin t<=t+1; stt<=LO; end end
      LN2: begin macc<=0; si<=0; rms_isH<=1'b1; rms_base<=t*D; ret<=LN2D; stt<=SSQ; end
      LN2D: begin vden<=den; ret<=LN2S; stt<=DIVV; end
      LN2S: begin for(d=0;d<D;d=d+1) nn[d]<=vout[d]; stt<=FFN1; end
      FFN1: begin for(d=0;d<D;d=d+1) av[d]=nn[d]; mb_l<=l; mb_m<=4; mn<=H; ret<=FFN1S; stt<=MV; end
      FFN1S: begin for(d=0;d<H;d=d+1) gg[d]<=(mvout[d]<0)?0:mvout[d]; stt<=FFN2; end
      FFN2: begin for(d=0;d<H;d=d+1) av[d]=gg[d]; mb_l<=l; mb_m<=5; mn<=D; ret<=FFN2S; stt<=MV; end
      FFN2S: begin for(d=0;d<D;d=d+1) X[t*D+d]<=clf(Hh[t*D+d]+treq(mvout[d],SH_F));
        if(t==S-1) begin if(l==L-1) stt<=FRMS; else begin l<=l+1; t<=0; stt<=LN1; end end else begin t<=t+1; stt<=LN2; end end
      FRMS: begin macc<=0; si<=0; rms_isH<=1'b0; rms_base<=(S-1)*D; ret<=FRMSD; stt<=SSQ; end
      FRMSD: begin vden<=den; ret<=FRMSS; stt<=DIVV; end
      FRMSS: begin for(d=0;d<D;d=d+1) xn[d]<=vout[d]; stt<=LOG; end
      LOG: begin for(d=0;d<D;d=d+1) av[d]=xn[d]; mb_l<=0; mb_m<=6; mn<=V; ret<=LOGS; stt<=MV; end
      LOGS: begin best=-2147483647; barg=0; for(j=0;j<V;j=j+1) if(mvout[j]>best) begin best=mvout[j]; barg=j; end
        gtok[g]=barg[7:0]; stt<=NXT; end
      NXT: begin for(t=0;t<S-1;t=t+1) seqb[t]<=seqb[t+1]; seqb[S-1]<=gtok[g];
        // ext: ровно ОДИН forward → команда уже в gtok[0], завершаемся
        if(ext_mode || g==NGEN-1) stt<=FIN; else begin g<=g+1; l<=0; t<=0; stt<=EMB; end end
      // ── serial RMS sum-of-squares (один mul16/такт) ──
      SSQ: begin macc <= macc + mul16(rsrc(rms_isH,rms_base+si),rsrc(rms_isH,rms_base+si));
        if(si==D-1) stt<=SSQD; else si<=si+1; end
      SSQD: begin ms=macc>>>{DSHIFT};
        for(d=0;d<D;d=d+1) vn[d]=rsrc(rms_isH,rms_base+d)*SC*SC; sqarg<=ms*SC*SC; stt<=SQRT; end
      // ── serial attention: скоры (один mul16/такт) ──
      ATSC: begin macc <= macc + mul16(Q[t*D+ci],K[jj*D+ci]);
        if(ci==D-1) stt<=ATSCJ; else ci<=ci+1; end
      ATSCJ: begin av[jj]=macc; if(macc>mx) mx=macc;
        if(jj==t) stt<=ATEXP; else begin jj<=jj+1; ci<=0; macc<=0; stt<=ATSC; end end
      // ── softmax-веса (LUT, без mul16) ──
      ATEXP: begin sw=0;
        for(jj=0;jj<S;jj=jj+1) if(jj<=t) begin c=(mx-av[jj])>>>3; if(c>31)c=31; ew[jj]=EXPLUT[c]; sw=sw+EXPLUT[c]; end
        vden<=sw; di<=0; stt<=ATWS; end
      // ── взвешенная сумма (один mul16/такт) ──
      ATWS: begin macc<=0; aj<=0; stt<=ATWSACC; end
      ATWSACC: begin macc <= macc + mul16(ew[aj],Vv[aj*D+di]);
        if(aj==t) stt<=ATWSD; else aj<=aj+1; end
      ATWSD: begin vn[di]<=macc;
        if(di==D-1) begin ret<=LATTS; stt<=DIVV; end else begin di<=di+1; stt<=ATWS; end end
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
"""
open(os.path.join(HERE,"model_infer_dom.v"),"w").write(TEMPLATE)
print(f"model_infer_dom.v сгенерирован (V={V} D={D} L={L} H={H} S={S}, DSHIFT={DSHIFT}, RW={RW})")
print(f"  wrow арм: {L*6*D+V}, emb арм: {V*D}")
