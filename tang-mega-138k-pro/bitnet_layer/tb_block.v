`default_nettype none
`timescale 1ns/1ps
// ПОЛНЫЙ троичный трансформер-блок: h=x+Oproj(Attn(RMSNorm(x))); y=h+FFN(RMSNorm(h))
// Все веса тернарные (реальные BitNet), реквант int8 между под-слоями. RTL мирроринг fixed-спеки.
module tb;
  reg signed [31:0] X [0:31];
  integer EXPLUT [0:31];
  `include "vectors_block.vh"
  reg [15:0] WQ[0:7],WK[0:7],WV[0:7],WO[0:7],WG[0:7],WD[0:7];
  function signed [31:0] tmul; input [1:0] c; input signed [31:0] v;
    begin tmul=(c==2'b10)?v:(c==2'b00)?-v:0; end endfunction
  function signed [31:0] tdiv; input signed [31:0] a; input signed [31:0] b;
    begin tdiv = (a>=0)? a/b : -((-a)/b); end endfunction
  function signed [31:0] clampf; input signed [31:0] v;
    begin clampf=(v<-127)?-127:((v>127)?127:v); end endfunction
  function integer isq; input integer n; integer r; begin r=0; while((r+1)*(r+1)<=n) r=r+1; isq=r; end endfunction
  // matvec: ряд троичных весов wrow · вектор vec[base..base+D-1]
  function signed [31:0] mv; input [15:0] wrow; input integer base; input integer useX;
    integer c; reg signed [31:0] s; begin s=0;
      for(c=0;c<D;c=c+1) s=s+tmul(wrow[2*c+:2], useX? X[base+c] : VEC[base+c]); mv=s; end endfunction
  reg signed [31:0] VEC [0:255];   // общий буфер промежуточных векторов
  reg signed [31:0] n1[0:31],Q[0:31],K[0:31],V[0:31],ctx[0:31],H[0:31],n2v[0:31],Y[0:31];
  integer t,j,d,c,ms,den,mx,sc,w,num,dd,ok; reg signed [31:0] g,fo,ao;
  reg [15:0] WROWS[0:7];
  // helper: RMSNorm вектора VEC[base..] → res[base..]
  task rmsnorm; input integer base; integer i,m,de; reg signed [31:0] xx; begin
    m=0; for(i=0;i<D;i=i+1) m=m+VEC[base+i]*VEC[base+i]; m=m/D; de=isq(m*SC*SC); if(de==0)de=1;
    for(i=0;i<D;i=i+1) VEC[256-D+i]=tdiv(VEC[base+i]*SC*SC, de);   // во временный хвост
  end endtask
  initial begin
    WQ[0]=WQ_0;WQ[1]=WQ_1;WQ[2]=WQ_2;WQ[3]=WQ_3;WQ[4]=WQ_4;WQ[5]=WQ_5;WQ[6]=WQ_6;WQ[7]=WQ_7;
    WK[0]=WK_0;WK[1]=WK_1;WK[2]=WK_2;WK[3]=WK_3;WK[4]=WK_4;WK[5]=WK_5;WK[6]=WK_6;WK[7]=WK_7;
    WV[0]=WV_0;WV[1]=WV_1;WV[2]=WV_2;WV[3]=WV_3;WV[4]=WV_4;WV[5]=WV_5;WV[6]=WV_6;WV[7]=WV_7;
    WO[0]=WO_0;WO[1]=WO_1;WO[2]=WO_2;WO[3]=WO_3;WO[4]=WO_4;WO[5]=WO_5;WO[6]=WO_6;WO[7]=WO_7;
    WG[0]=WG_0;WG[1]=WG_1;WG[2]=WG_2;WG[3]=WG_3;WG[4]=WG_4;WG[5]=WG_5;WG[6]=WG_6;WG[7]=WG_7;
    WD[0]=WD_0;WD[1]=WD_1;WD[2]=WD_2;WD[3]=WD_3;WD[4]=WD_4;WD[5]=WD_5;WD[6]=WD_6;WD[7]=WD_7;
    #1;
    // RMSNorm(X) → n1 (по токенам)
    for(t=0;t<S;t=t+1) begin
      ms=0; for(d=0;d<D;d=d+1) ms=ms+X[t*D+d]*X[t*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
      for(d=0;d<D;d=d+1) n1[t*D+d]=tdiv(X[t*D+d]*SC*SC, den);
    end
    // Q/K/V = троичная проекция n1
    for(t=0;t<S;t=t+1) for(d=0;d<D;d=d+1) begin
      Q[t*D+d]=0;K[t*D+d]=0;V[t*D+d]=0;
      for(c=0;c<D;c=c+1) begin
        Q[t*D+d]=Q[t*D+d]+tmul(WQ[d][2*c+:2], n1[t*D+c]);
        K[t*D+d]=K[t*D+d]+tmul(WK[d][2*c+:2], n1[t*D+c]);
        V[t*D+d]=V[t*D+d]+tmul(WV[d][2*c+:2], n1[t*D+c]); end end
    // attention softmax → ctx
    for(t=0;t<S;t=t+1) begin
      mx=-2147483647;
      for(j=0;j<S;j=j+1) begin sc=0; for(d=0;d<D;d=d+1) sc=sc+Q[t*D+d]*K[j*D+d]; VEC[240+j]=sc; if(sc>mx)mx=sc; end
      for(d=0;d<D;d=d+1) begin
        num=0; dd=0;
        for(j=0;j<S;j=j+1) begin c=(mx-VEC[240+j])/SMSCALE; if(c>31)c=31; w=EXPLUT[c]; num=num+w*V[j*D+d]; dd=dd+w; end
        ctx[t*D+d]=tdiv(num,dd);
      end
    end
    // Oproj + residual → H
    for(t=0;t<S;t=t+1) for(d=0;d<D;d=d+1) begin
      ao=0; for(c=0;c<D;c=c+1) ao=ao+tmul(WO[d][2*c+:2], ctx[t*D+c]);
      ao=clampf(tdiv(ao, 1<<SH_A)); H[t*D+d]=clampf(X[t*D+d]+ao);
    end
    // RMSNorm(H) → n2 ; FFN ReLU ; residual → Y
    ok=0;
    for(t=0;t<S;t=t+1) begin
      ms=0; for(d=0;d<D;d=d+1) ms=ms+H[t*D+d]*H[t*D+d]; ms=ms/D; den=isq(ms*SC*SC); if(den==0)den=1;
      for(d=0;d<D;d=d+1) n2v[t*D+d]=tdiv(H[t*D+d]*SC*SC, den);
      for(d=0;d<D;d=d+1) begin
        g=0; for(c=0;c<D;c=c+1) g=g+tmul(WG[d][2*c+:2], n2v[t*D+c]); if(g<0)g=0;  // ReLU(gate)
        VEC[d]=g; end
      for(d=0;d<D;d=d+1) begin
        fo=0; for(c=0;c<D;c=c+1) fo=fo+tmul(WD[d][2*c+:2], VEC[c]);
        fo=clampf(tdiv(fo,1<<SH_F)); Y[t*D+d]=clampf(H[t*D+d]+fo);
        if(Y[t*D+d]===gy(t,d)) ok=ok+1; else $display("  t%0d d%0d RTL=%0d spec=%0d FAIL",t,d,Y[t*D+d],gy(t,d));
      end
    end
    $display("ПОЛНЫЙ троичный трансформер-блок: совпало %0d/%0d", ok, S*D);
    if(ok==S*D)$display("ВЕСЬ БЛОК RTL == fixed-спека БИТ-В-БИТ ✓  (RMSNorm+attn(softmax)+residual+RMSNorm+FFN+residual на троице)");
    $finish;
  end
endmodule
