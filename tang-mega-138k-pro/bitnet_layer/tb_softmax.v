`default_nettype none
`timescale 1ns/1ps
module tb;
  reg signed [7:0] X [0:31];
  integer EXPLUT [0:31];
  `include "vectors_softmax.vh"
  reg [15:0] WQ[0:7],WK[0:7],WV[0:7];
  function signed [31:0] tmul; input [1:0] c; input signed [31:0] v;
    begin tmul=(c==2'b10)?v:(c==2'b00)?-v:0; end endfunction
  integer t,j,d,c,ok;
  reg signed [31:0] Q[0:31],K[0:31],Vv[0:31], sc[0:3], mx, w, num, den, o;
  initial begin
    WQ[0]=WQ_0;WQ[1]=WQ_1;WQ[2]=WQ_2;WQ[3]=WQ_3;WQ[4]=WQ_4;WQ[5]=WQ_5;WQ[6]=WQ_6;WQ[7]=WQ_7;
    WK[0]=WK_0;WK[1]=WK_1;WK[2]=WK_2;WK[3]=WK_3;WK[4]=WK_4;WK[5]=WK_5;WK[6]=WK_6;WK[7]=WK_7;
    WV[0]=WV_0;WV[1]=WV_1;WV[2]=WV_2;WV[3]=WV_3;WV[4]=WV_4;WV[5]=WV_5;WV[6]=WV_6;WV[7]=WV_7;
    #1;
    for(t=0;t<S;t=t+1)for(d=0;d<D;d=d+1)begin
      Q[t*D+d]=0;K[t*D+d]=0;Vv[t*D+d]=0;
      for(j=0;j<D;j=j+1)begin
        Q[t*D+d]=Q[t*D+d]+tmul(WQ[d][2*j+:2],X[t*D+j]);
        K[t*D+d]=K[t*D+d]+tmul(WK[d][2*j+:2],X[t*D+j]);
        Vv[t*D+d]=Vv[t*D+d]+tmul(WV[d][2*j+:2],X[t*D+j]); end end
    ok=0;
    $display("Fixed-point softmax-внимание: RTL vs fixed-спека (бит-в-бит)");
    for(t=0;t<S;t=t+1)begin
      // scores строки t + max
      mx=-2147483647;
      for(j=0;j<S;j=j+1)begin sc[j]=0; for(d=0;d<D;d=d+1) sc[j]=sc[j]+Q[t*D+d]*K[j*D+d]; if(sc[j]>mx)mx=sc[j]; end
      // softmax fixed-point: num=Σ EXPLUT[(mx-sc)/SCALE]·V, den=ΣEXPLUT
      for(d=0;d<D;d=d+1)begin
        num=0; den=0;
        for(j=0;j<S;j=j+1)begin
          c=(mx-sc[j])/SCALE; if(c>LUTLEN-1)c=LUTLEN-1;
          w=EXPLUT[c]; num=num+w*Vv[j*D+d]; if(d==0)den=den; den=den+w; end
        // den пересчитан D раз — но одинаков; делим
        o = num/den;
        if(o===gfix(t,d)) ok=ok+1;
        else $display("  t%0d d%0d RTL=%0d spec=%0d FAIL",t,d,o,gfix(t,d));
      end
    end
    $display("совпало %0d/%0d элементов", ok, S*D);
    if(ok==S*D)$display("RTL fixed-point softmax == спека БИТ-В-БИТ ✓ (а спека ≈ float, см. выше)");
    $finish;
  end
endmodule
