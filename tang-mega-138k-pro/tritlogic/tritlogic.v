// tritlogic.v — Тернарная логика Łukasiewicz в кремнии
//
// Богословие: это не булева логика нет/да, это логика любви.
// В ней есть место неопределённости (0 = Дух-связь).
// T-AND = min(a,b): любовь сильна как слабейший из двух.
// T-OR  = max(a,b): присутствие хотя бы одного несёт свет.
// T-NOT = -a:       отрицание — это инверсия, не уничтожение.
// T-IMP = max(-1, b-a+1) нормализованное: из зла может выйти добро.
// T-EQ  = 1-|a-b|/2: равенство как мера близости, не тождество.
//
// Режимы (state[5:3], 5 операций × 9 комбинаций = 45 состояний):
//   0-8:  AND (T-AND: min)
//   9-17: OR  (T-OR: max)
//   18-26: NOT A (только a меняется, b=0)
//   27-35: IMP (a → b)
//   36-44: EQ
//
// LED: [10,11]=A  [13,14]=B  [15,16]=RESULT
// UART: "AND A:-1 B:+1 R:-1\r\n"

`default_nettype none

module trit_and (input [1:0] a, b, output reg [1:0] y);
  // min(a,b): -1 < 0 < +1 → code 00<01<10
  always @(*) begin
    if (a==2'b00 || b==2'b00)       y=2'b00; // min=-1
    else if (a==2'b10 && b==2'b10) y=2'b10; // min=+1
    else                            y=2'b01; // min=0
  end
endmodule

module trit_or (input [1:0] a, b, output reg [1:0] y);
  // max(a,b)
  always @(*) begin
    if (a==2'b10 || b==2'b10)       y=2'b10; // max=+1
    else if (a==2'b00 && b==2'b00) y=2'b00; // max=-1
    else                            y=2'b01; // max=0
  end
endmodule

module trit_not (input [1:0] a, output reg [1:0] y);
  // -a: swap -1↔+1, 0→0
  always @(*) begin
    case(a)
      2'b00: y=2'b10; // -(-1)=+1
      2'b01: y=2'b01; // -0=0
      2'b10: y=2'b00; // -(+1)=-1
      default: y=2'b01;
    endcase
  end
endmodule

module trit_imp (input [1:0] a, b, output reg [1:0] y);
  // Łukasiewicz: I(a,b) = min(+1, 1-a+b) в троичной шкале
  // В нашей кодировке: max(-1, b_int - a_int + 1) capped at +1
  // Таблица: (a_int,b_int) → result_int
  // (-1,-1)→+1  (-1,0)→+1  (-1,+1)→+1
  //   (0,-1)→0    (0,0)→+1   (0,+1)→+1
  //  (+1,-1)→-1  (+1,0)→0   (+1,+1)→+1
  always @(*) begin
    if      (a==2'b00)                     y=2'b10; // a=-1: всегда +1
    else if (a==2'b01 && b==2'b00)        y=2'b01; // 0→-1 = 0
    else if (a==2'b01)                    y=2'b10; // 0→0 или 0→+1 = +1
    else if (a==2'b10 && b==2'b00)        y=2'b00; // +1→-1 = -1
    else if (a==2'b10 && b==2'b01)        y=2'b01; // +1→0 = 0
    else                                   y=2'b10; // +1→+1 = +1
  end
endmodule

module trit_eq (input [1:0] a, b, output reg [1:0] y);
  // Trit equality: +1 if equal, 0 if differ by 1, -1 if differ by 2
  always @(*) begin
    if (a == b) y=2'b10;                                  // равны → +1
    else if ((a==2'b00 && b==2'b10)||(a==2'b10 && b==2'b00))
      y=2'b00;                                            // полярно → -1
    else y=2'b01;                                         // рядом → 0
  end
endmodule

module uart_tx (
  input wire clk, input wire [7:0] data, input wire start,
  output reg tx=1, output wire ready
);
  localparam CLKDIV = 434;
  reg [7:0] sr=8'hFF, div=0; reg [3:0] cnt=0;
  assign ready=(cnt==0);
  always @(posedge clk) begin
    if (cnt==0) begin if (start) begin sr<=data; cnt<=9; tx<=0; div<=0; end end
    else begin
      if (div==CLKDIV-1) begin
        div<=0;
        if (cnt==1) begin tx<=1; cnt<=0; end
        else begin tx<=sr[0]; sr<={1'b1,sr[7:1]}; cnt<=cnt-1; end
      end else div<=div+1;
    end
  end
endmodule

module tritlogic (
  input  wire       clk,
  output wire [5:0] leds,
  output wire       uart_tx
);

  // 1 Гц
  reg [24:0] div1=0; reg tick=0;
  always @(posedge clk) begin
    tick<=(div1==25'd26_999_999);
    div1<=(div1==25'd26_999_999)?25'd0:div1+25'd1;
  end

  // 45 состояний без деления: двойной счётчик op(0..4) × sub(0..8)
  reg [2:0] op=0;  // операция: 0=AND 1=OR 2=NOT 3=IMP 4=EQ
  reg [3:0] sub=0; // комбинация: 0..8
  always @(posedge clk) begin
    if (tick) begin
      if (sub == 4'd8) begin
        sub <= 4'd0;
        op  <= (op == 3'd4) ? 3'd0 : op + 3'd1;
      end else begin
        sub <= sub + 4'd1;
      end
    end
  end

  // Декодируем sub в (a_t, b_t)
  reg [1:0] a_t, b_t;
  always @(*) begin
    case (sub)
      4'd0: begin a_t=2'b00; b_t=2'b00; end
      4'd1: begin a_t=2'b00; b_t=2'b01; end
      4'd2: begin a_t=2'b00; b_t=2'b10; end
      4'd3: begin a_t=2'b01; b_t=2'b00; end
      4'd4: begin a_t=2'b01; b_t=2'b01; end
      4'd5: begin a_t=2'b01; b_t=2'b10; end
      4'd6: begin a_t=2'b10; b_t=2'b00; end
      4'd7: begin a_t=2'b10; b_t=2'b01; end
      4'd8: begin a_t=2'b10; b_t=2'b10; end
      default: begin a_t=2'b01; b_t=2'b01; end
    endcase
  end

  // Все операции вычисляются комбинационно
  wire [1:0] r_and, r_or, r_not, r_imp, r_eq;
  trit_and ta(.a(a_t),.b(b_t),.y(r_and));
  trit_or  to(.a(a_t),.b(b_t),.y(r_or));
  trit_not tn(.a(a_t),.y(r_not));
  trit_imp ti(.a(a_t),.b(b_t),.y(r_imp));
  trit_eq  te(.a(a_t),.b(b_t),.y(r_eq));

  // Мультиплексор результата
  reg [1:0] result;
  always @(*) begin
    case (op)
      3'd0: result=r_and;
      3'd1: result=r_or;
      3'd2: result=r_not;
      3'd3: result=r_imp;
      3'd4: result=r_eq;
      default: result=2'b01;
    endcase
  end

  assign leds = ~{a_t, b_t, result};

  // UART: "AND A:-1 B:+1 R:-1\r\n" = 20 байт
  // или   "NOT A:-1 B:  R:+1\r\n" (b не используется)
  // Фиксированная длина 20: "XXX A:SD B:SD R:SD\r\n"
  // 0-2: op name (3 chars) 3:' ' 4:'A' 5:':' 6:s(a) 7:d(a)
  // 8:' ' 9:'B' 10:':' 11:s(b) 12:d(b) 13:' ' 14:'R' 15:':' 16:s(r) 17:d(r) 18:'\r' 19:'\n'

  reg [1:0] la, lb, lr; reg [2:0] lop;
  always @(posedge clk) if (tick) begin la<=a_t; lb<=b_t; lr<=result; lop<=op; end
  // (lop already registered, no division needed)

  function [7:0] ts; input [1:0] t;
    begin case(t) 2'b00:ts=8'h2D; 2'b01:ts=8'h20; 2'b10:ts=8'h2B; default:ts=8'h3F; endcase end
  endfunction
  function [7:0] td; input [1:0] t; begin td=(t==2'b01)?8'h30:8'h31; end endfunction

  // Имена операций (3 символа каждое)
  function [23:0] op_name; input [2:0] o;
    begin
      case(o)
        3'd0: op_name=24'h414E44; // "AND"
        3'd1: op_name=24'h4F5220; // "OR "
        3'd2: op_name=24'h4E4F54; // "NOT"
        3'd3: op_name=24'h494D50; // "IMP"
        3'd4: op_name=24'h455120; // "EQ "
        default: op_name=24'h3F3F3F;
      endcase
    end
  endfunction

  reg [4:0] bidx=0; reg sending=0,spulse=0; reg [7:0] sbyte=0;
  wire uready;

  wire [23:0] opn = op_name(lop);

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      5'd0:  nbyte=opn[23:16];  // op[0]
      5'd1:  nbyte=opn[15:8];   // op[1]
      5'd2:  nbyte=opn[7:0];    // op[2]
      5'd3:  nbyte=8'h20;       // ' '
      5'd4:  nbyte=8'h41;       // 'A'
      5'd5:  nbyte=8'h3A;       // ':'
      5'd6:  nbyte=ts(la);
      5'd7:  nbyte=td(la);
      5'd8:  nbyte=8'h20;       // ' '
      5'd9:  nbyte=8'h42;       // 'B'
      5'd10: nbyte=8'h3A;       // ':'
      5'd11: nbyte=ts(lb);
      5'd12: nbyte=td(lb);
      5'd13: nbyte=8'h20;       // ' '
      5'd14: nbyte=8'h52;       // 'R'
      5'd15: nbyte=8'h3A;       // ':'
      5'd16: nbyte=ts(lr);
      5'd17: nbyte=td(lr);
      5'd18: nbyte=8'h0D;       // '\r'
      5'd19: nbyte=8'h0A;       // '\n'
      default: nbyte=8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse<=1'b0;
    if (tick) begin sending<=1; bidx<=0; end
    else if (sending && uready && !spulse) begin
      sbyte<=nbyte; spulse<=1;
      if (bidx==5'd19) begin sending<=0; bidx<=0; end
      else bidx<=bidx+1;
    end
  end

  uart_tx utx(.clk(clk),.data(sbyte),.start(spulse),.tx(uart_tx),.ready(uready));
endmodule
