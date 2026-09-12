// auto: integ_demo.py — golden ext-контексты (бит-в-бит fixed-point доктрина)
localparam NS=8;
localparam [31:0] CTX_0=32'h011d1417;
localparam [7:0] ECMD_0=21;  // патруль кольца (норма): → retreat
localparam [31:0] CTX_1=32'h1a011d0b;
localparam [7:0] ECMD_1=25;  // ЧП: разряд батареи в окне: → rtb
localparam [31:0] CTX_2=32'h14171311;
localparam [7:0] ECMD_2=25;  // ЧП: топливо на нуле: → rtb
localparam [31:0] CTX_3=32'h17131a01;
localparam [7:0] ECMD_3=20;  // ЧП: борт повреждён: → relay
localparam [31:0] CTX_4=32'h1a011d0c;
localparam [7:0] ECMD_4=20;  // потеря связи → ретрансляция: → relay
localparam [31:0] CTX_5=32'h03070908;
localparam [7:0] ECMD_5=19;  // незнакомый/нейтральный поток: → observe
localparam [31:0] CTX_6=32'h17101918;
localparam [7:0] ECMD_6=23;  // кольцо: текущий = handoff: → handoff
localparam [31:0] CTX_7=32'h1a171301;
localparam [7:0] ECMD_7=0;  // приоритет ЧП над связью (оба в окне): → tank
