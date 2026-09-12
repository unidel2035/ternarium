// mlgru_board.v — борт MatMul-free MLGRU + UART СЛОВАМИ. Clock-enable (вся логика на чистом 50МГц,
// модель шагает по ce ÷4 → 12.5МГц; нет hold делёного такта). Словарь токен→строка через $readmemh +
// СИНХРОННОЕ чтение (→BSRAM, не LUT-логика, которая раздувала дизайн). UART DIV=434 → 115200.
// После done КА: NGEN токенов → слова из словаря + пробел → CRLF → пауза → повтор.
`default_nettype none
module mlgru_board (input wire clk, output reg [5:0] leds, output wire uart_tx_pin);
  `include "mlgru_vectors.vh"
  reg [1:0] cdiv=0; always @(posedge clk) cdiv<=cdiv+1'b1;
  wire ce = (cdiv==2'b00);                          // ÷4 → модель на 12.5 МГц

  reg [27:0] pc=0; always @(posedge clk) pc<=pc+1'b1;
  wire rst   = (pc < 28'd64);
  wire start = (pc >= 28'd100) && (pc < 28'd116);
  reg [7:0] taddr; wire [7:0] tout; wire done;
  model_mlgru u(.clk(clk),.ce(ce),.rst(rst),.start(start),.tok_addr(taddr),.tok_out(tout),.done(done));

  reg done_latch;
  always @(posedge clk) if(rst) done_latch<=1'b0; else if(done) done_latch<=1'b1;

  // словарь токен→строка: 32×12 байт, $readmemh + СИНХРОННОЕ чтение → BSRAM (не комбинаторная логика)
  reg [7:0] words [0:32*12-1];
  initial $readmemh("words.hex", words);
  reg [7:0] tok; reg [4:0] ci;
  wire [8:0] waddr = tok[4:0]*12 + ci;
  reg [7:0] wbyte;
  always @(posedge clk) wbyte <= words[waddr];      // регистрированное чтение

  reg [7:0] ud; reg usend; wire ubusy; wire utx;
  uart_tx #(.DIV(434)) UT(.clk(clk),.rst(rst),.data(ud),.send(usend),.tx(utx),.busy(ubusy));
  assign uart_tx_pin = utx;

  localparam S_IDLE=0,S_TOK=1,S_RD=2,S_W1=3,S_W2=4,S_CHAR=5,S_NEXT=6,S_SPACE=7,S_AFT=8,
             S_CR=9,S_LF=10,S_PAUSE=11,S_SEND0=12,S_SEND1=13,S_SEND2=14;
  reg [3:0] st, ret, gi; reg [23:0] paus;
  always @(posedge clk) begin
    if(rst) begin st<=S_IDLE; gi<=0; ci<=0; usend<=1'b0; taddr<=8'd0; paus<=0; tok<=0; ret<=S_IDLE; end
    else begin
      usend<=1'b0;
      case(st)
        S_IDLE: if(done_latch) begin gi<=0; st<=S_TOK; end
        S_TOK:  begin taddr<=gi; st<=S_RD; end
        S_RD:   begin tok<=tout; ci<=0; st<=S_W1; end       // токен зафиксирован
        S_W1:   st<=S_W2;                                   // settle waddr → wbyte (синхр. чтение)
        S_W2:   st<=S_CHAR;
        S_CHAR: if(ci==5'd12 || wbyte==8'd0) st<=S_SPACE;   // конец слова (паддинг 0)
                else begin ud<=wbyte; ret<=S_NEXT; st<=S_SEND0; end
        S_NEXT: begin ci<=ci+1'b1; st<=S_W1; end            // следующий символ
        S_SPACE:begin ud<=8'h20; ret<=S_AFT; st<=S_SEND0; end
        S_AFT:  if(gi==NGEN-1) st<=S_CR; else begin gi<=gi+1'b1; st<=S_TOK; end
        S_CR:   begin ud<=8'h0D; ret<=S_LF;    st<=S_SEND0; end
        S_LF:   begin ud<=8'h0A; ret<=S_PAUSE; st<=S_SEND0; end
        S_PAUSE:begin paus<=paus+1'b1; if(paus[23]) begin paus<=0; gi<=0; st<=S_TOK; end end
        S_SEND0:if(!ubusy) begin usend<=1'b1; st<=S_SEND1; end
        S_SEND1:st<=S_SEND2;
        S_SEND2:if(!ubusy) st<=ret;
        default:st<=S_IDLE;
      endcase
    end
  end

  always @(posedge clk)
    leds <= done_latch ? {1'b1, ~tout[4:0]} : {6{pc[24]}};
endmodule
