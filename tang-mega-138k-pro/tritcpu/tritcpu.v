// tritcpu.v — Первый программируемый тритный вычислитель
//
// Богословие: это не процессор в техническом смысле — это орган.
// Он принимает команды извне (от человека, от анамнезиса) и отвечает.
// Регистры A, B — два собеседника. ACC — плод их встречи.
// Команды — это слова. Вычисление — это диалог.
//
// Регистры: A, B, ACC — 3-тритные числа (-13..+13)
//
// Команды (1 байт через UART RX 115200):
//   'a'  — A = A + 1      'A'  — A = A - 1
//   'b'  — B = B + 1      'B'  — B = B - 1
//   '+'  — ACC = A + B    '-'  — ACC = A - B
//   '*'  — ACC = A ⊗ B   (потритное умножение)
//   '&'  — ACC = AND(A,B) '|'  — ACC = OR(A,B)
//   '!'  — ACC = NOT(A)   '='  — A = ACC
//   'r'  — сброс в 0
//
// LED: ACC на 6 LED (активные LOW)
// UART TX: "A:+05 B:-03 ACC:+02\r\n" после каждой команды

`default_nettype none

// ── Тритный полный сумматор ──────────────────────────────
module trit_fa (
  input  wire [1:0] a, b, cin,
  output reg  [1:0] sum, cout
);
  reg signed [2:0] s;
  always @(*) begin
    s = ((a==2'b00)?-3'sd1:(a==2'b10)?3'sd1:3'sd0)
      + ((b==2'b00)?-3'sd1:(b==2'b10)?3'sd1:3'sd0)
      + ((cin==2'b00)?-3'sd1:(cin==2'b10)?3'sd1:3'sd0);
    case(s)
      -3'sd3:begin sum=2'b01;cout=2'b00;end
      -3'sd2:begin sum=2'b10;cout=2'b00;end
      -3'sd1:begin sum=2'b00;cout=2'b01;end
       3'sd0:begin sum=2'b01;cout=2'b01;end
       3'sd1:begin sum=2'b10;cout=2'b01;end
       3'sd2:begin sum=2'b00;cout=2'b10;end
       3'sd3:begin sum=2'b01;cout=2'b10;end
      default:begin sum=2'b01;cout=2'b01;end
    endcase
  end
endmodule

// ── 3-тритный рябой сумматор ─────────────────────────────
module trit3_add (
  input  wire [5:0] a, b,
  output wire [5:0] s,
  output wire [1:0] cout
);
  wire [1:0] c0, c1;
  trit_fa fa0(.a(a[1:0]),.b(b[1:0]),.cin(2'b01),.sum(s[1:0]),.cout(c0));
  trit_fa fa1(.a(a[3:2]),.b(b[3:2]),.cin(c0),  .sum(s[3:2]),.cout(c1));
  trit_fa fa2(.a(a[5:4]),.b(b[5:4]),.cin(c1),  .sum(s[5:4]),.cout(cout));
endmodule

// ── Тритный умножитель (1 трит) ──────────────────────────
module trit1_mul (input [1:0] a, b, output reg [1:0] p);
  always @(*) begin
    if (a==2'b01||b==2'b01) p=2'b01;
    else if (a==b)           p=2'b10;
    else                     p=2'b00;
  end
endmodule

// ── UART RX: 115200 @ 50 МГц ─────────────────────────────
module uart_rx (
  input  wire       clk,
  input  wire       rx,
  output reg  [7:0] data  = 0,
  output reg        valid = 0
);
  localparam CLKDIV = 434;
  localparam HALF   = 117;

  reg rx1=1, rx2=1;
  reg [7:0] timer=0;
  reg [3:0] state=0;
  reg [7:0] shift=0;

  always @(posedge clk) begin
    rx1 <= rx; rx2 <= rx1;
    valid <= 0;
    case (state)
      4'd0: begin // ожидание стартового бита
        if (!rx2) begin state<=4'd1; timer<=HALF-1; end
      end
      4'd1: begin // подтверждение стартового бита
        if (timer==0) begin
          if (!rx2) begin state<=4'd2; timer<=CLKDIV-1; end
          else       state<=4'd0; // ложное срабатывание
        end else timer<=timer-1;
      end
      4'd10: begin // стоп-бит
        if (timer==0) begin
          if (rx2) begin data<=shift; valid<=1; end
          state<=4'd0;
        end else timer<=timer-1;
      end
      default: begin // биты данных 2..9 (LSB first)
        if (timer==0) begin
          shift<={rx2,shift[7:1]};
          state<=state+4'd1;
          timer<=CLKDIV-1;
        end else timer<=timer-1;
      end
    endcase
  end
endmodule

// ── UART TX: 115200 @ 50 МГц ─────────────────────────────
module uart_tx (
  input  wire       clk,
  input  wire [7:0] data,
  input  wire       start,
  output reg        tx    = 1,
  output wire       ready
);
  localparam CLKDIV = 434;
  reg [7:0] sr=8'hFF,div=0; reg [3:0] cnt=0;
  assign ready=(cnt==0);
  always @(posedge clk) begin
    if (cnt==0) begin if(start) begin sr<=data;cnt<=9;tx<=0;div<=0;end end
    else begin
      if (div==CLKDIV-1) begin div<=0;
        if(cnt==1) begin tx<=1;cnt<=0;end
        else begin tx<=sr[0];sr<={1'b1,sr[7:1]};cnt<=cnt-1;end
      end else div<=div+1;
    end
  end
endmodule

// ── Главный модуль ─────────────────────────────────────────
module tritcpu (
  input  wire       clk,
  input  wire       rx,
  output wire [5:0] leds,
  output wire       uart_tx
);

  // ── Регистры A, B, ACC ────────────────────────────────
  reg [5:0] reg_a = 6'b01_01_01; // 0
  reg [5:0] reg_b = 6'b01_01_10; // +1
  reg [5:0] reg_acc = 6'b01_01_01; // 0

  // Помощники
  wire [5:0] one_pos = 6'b01_01_10; // +1 в 3-тритном формате
  wire [5:0] one_neg = 6'b01_01_00; // -1

  // A+1 и A-1
  wire [5:0] a_plus1, a_minus1;
  wire [1:0] dummy1, dummy2;
  trit3_add add_a1(.a(reg_a),.b(one_pos),.s(a_plus1),.cout(dummy1));
  trit3_add sub_a1(.a(reg_a),.b(one_neg),.s(a_minus1),.cout(dummy2));

  // B+1 и B-1
  wire [5:0] b_plus1, b_minus1;
  wire [1:0] dummy3, dummy4;
  trit3_add add_b1(.a(reg_b),.b(one_pos),.s(b_plus1),.cout(dummy3));
  trit3_add sub_b1(.a(reg_b),.b(one_neg),.s(b_minus1),.cout(dummy4));

  // A+B
  wire [5:0] ab_sum;
  wire [1:0] dummy5;
  trit3_add adder(.a(reg_a),.b(reg_b),.s(ab_sum),.cout(dummy5));

  // NOT A (инверсия)
  wire [5:0] not_a;
  assign not_a[1:0] = (reg_a[1:0]==2'b00)?2'b10:(reg_a[1:0]==2'b10)?2'b00:2'b01;
  assign not_a[3:2] = (reg_a[3:2]==2'b00)?2'b10:(reg_a[3:2]==2'b10)?2'b00:2'b01;
  assign not_a[5:4] = (reg_a[5:4]==2'b00)?2'b10:(reg_a[5:4]==2'b10)?2'b00:2'b01;

  // A-B = A + NOT(B)  // в тритной арифметике NOT(x)=-x, +1 НЕ нужен!
  wire [5:0] not_b;
  assign not_b[1:0] = (reg_b[1:0]==2'b00)?2'b10:(reg_b[1:0]==2'b10)?2'b00:2'b01;
  assign not_b[3:2] = (reg_b[3:2]==2'b00)?2'b10:(reg_b[3:2]==2'b10)?2'b00:2'b01;
  assign not_b[5:4] = (reg_b[5:4]==2'b00)?2'b10:(reg_b[5:4]==2'b10)?2'b00:2'b01;
  wire [5:0] ab_diff;
  wire [1:0] dummy6;
  trit3_add sub_step(.a(reg_a),.b(not_b),.s(ab_diff),.cout(dummy6));

  // AND(A,B) — потритный min
  wire [5:0] ab_and;
  assign ab_and[1:0] = (reg_a[1:0]==2'b00||reg_b[1:0]==2'b00)?2'b00:
                       (reg_a[1:0]==2'b10&&reg_b[1:0]==2'b10)?2'b10:2'b01;
  assign ab_and[3:2] = (reg_a[3:2]==2'b00||reg_b[3:2]==2'b00)?2'b00:
                       (reg_a[3:2]==2'b10&&reg_b[3:2]==2'b10)?2'b10:2'b01;
  assign ab_and[5:4] = (reg_a[5:4]==2'b00||reg_b[5:4]==2'b00)?2'b00:
                       (reg_a[5:4]==2'b10&&reg_b[5:4]==2'b10)?2'b10:2'b01;

  // OR(A,B) — потритный max
  wire [5:0] ab_or;
  assign ab_or[1:0] = (reg_a[1:0]==2'b10||reg_b[1:0]==2'b10)?2'b10:
                      (reg_a[1:0]==2'b00&&reg_b[1:0]==2'b00)?2'b00:2'b01;
  assign ab_or[3:2] = (reg_a[3:2]==2'b10||reg_b[3:2]==2'b10)?2'b10:
                      (reg_a[3:2]==2'b00&&reg_b[3:2]==2'b00)?2'b00:2'b01;
  assign ab_or[5:4] = (reg_a[5:4]==2'b10||reg_b[5:4]==2'b10)?2'b10:
                      (reg_a[5:4]==2'b00&&reg_b[5:4]==2'b00)?2'b00:2'b01;

  // MUL(A,B) — потритное умножение
  wire [5:0] ab_mul;
  trit1_mul m0(.a(reg_a[1:0]),.b(reg_b[1:0]),.p(ab_mul[1:0]));
  trit1_mul m1(.a(reg_a[3:2]),.b(reg_b[3:2]),.p(ab_mul[3:2]));
  trit1_mul m2(.a(reg_a[5:4]),.b(reg_b[5:4]),.p(ab_mul[5:4]));

  // ── UART RX → команды ─────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_valid;
  uart_rx urx(.clk(clk),.rx(rx),.data(rx_data),.valid(rx_valid));

  reg tx_trigger = 0; // триггер ответа

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (rx_valid) begin
      tx_trigger <= 1;
      case (rx_data)
        8'h61: reg_a   <= a_plus1;   // 'a' A++
        8'h41: reg_a   <= a_minus1;  // 'A' A--
        8'h62: reg_b   <= b_plus1;   // 'b' B++
        8'h42: reg_b   <= b_minus1;  // 'B' B--
        8'h2B: reg_acc <= ab_sum;    // '+' ACC=A+B
        8'h2D: reg_acc <= ab_diff;   // '-' ACC=A-B
        8'h2A: reg_acc <= ab_mul;    // '*' ACC=A⊗B
        8'h26: reg_acc <= ab_and;    // '&' ACC=AND
        8'h7C: reg_acc <= ab_or;     // '|' ACC=OR
        8'h21: reg_acc <= not_a;     // '!' ACC=NOT(A)
        8'h3D: reg_a   <= reg_acc;   // '=' A=ACC
        8'h72: begin                 // 'r' reset
          reg_a<=6'b01_01_01; reg_b<=6'b01_01_01; reg_acc<=6'b01_01_01;
        end
        default: tx_trigger <= 0;
      endcase
    end
  end

  // ── LED: ACC ──────────────────────────────────────────
  assign leds = ~reg_acc;

  // ── UART TX: "A:+05 B:-03 ACC:+02\r\n" ───────────────
  // Длина: "A:" (2) + 3 (sign+t2+t1+t0) + " B:" (3) + 3 + " ACC:" (5) + 3 + "\r\n" (2) = 21
  // Формат: "A:sdt B:sdt ACC:sdt\r\n" где s=+/-/ d=0/1
  // Реально: "A:+1+1-1 B: 0-1+1 ACC:+1 0 0\r\n" — громоздко
  // Проще: показать decimal значение каждого регистра
  // "A:+13 B:-03 C:+00\r\n" = 21 байт (C = ACC)
  // 0:'A' 1:':' 2:s(a) 3:t(a,tens) 4:t(a,ones)
  // 5:' ' 6:'B' 7:':' 8:s(b) 9:t(b,tens) 10:t(b,ones)
  // 11:' ' 12:'C' 13:':' 14:s(c) 15:t(c,tens) 16:t(c,ones)
  // 17:'\r' 18:'\n'  = 19 байт

  // ── UART TX: формат "A:+-0 B: 0+ C:-+0\r\n" = 20 байт ──
  // Каждый трит = один символ: '-'=−1 '0'=0 '+'=+1
  // Просто, без signed-арифметики, гарантированно синтезируется

  // Защёлки
  reg [5:0] lat_a=6'b01_01_01, lat_b=6'b01_01_01, lat_c=6'b01_01_01;
  always @(posedge clk) begin
    if (tx_trigger) begin lat_a<=reg_a; lat_b<=reg_b; lat_c<=reg_acc; end
  end

  // Символ для одного трита
  function [7:0] tc;
    input [1:0] t;
    begin case(t) 2'b00:tc=8'h2D; 2'b01:tc=8'h30; 2'b10:tc=8'h2B; default:tc=8'h3F; endcase end
  endfunction

  // "A:t2t1t0 B:t2t1t0 C:t2t1t0\r\n" = 20 байт (0..19)
  reg [4:0] bidx=0; reg sending=0,spulse=0; reg [7:0] sbyte=0;
  wire uready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      5'd0:  nbyte=8'h41;           // 'A'
      5'd1:  nbyte=8'h3A;           // ':'
      5'd2:  nbyte=tc(lat_a[5:4]);  // A тrit2 (MSB)
      5'd3:  nbyte=tc(lat_a[3:2]);  // A тrit1
      5'd4:  nbyte=tc(lat_a[1:0]);  // A тrit0 (LSB)
      5'd5:  nbyte=8'h20;           // ' '
      5'd6:  nbyte=8'h42;           // 'B'
      5'd7:  nbyte=8'h3A;
      5'd8:  nbyte=tc(lat_b[5:4]);
      5'd9:  nbyte=tc(lat_b[3:2]);
      5'd10: nbyte=tc(lat_b[1:0]);
      5'd11: nbyte=8'h20;
      5'd12: nbyte=8'h43;           // 'C' (ACC)
      5'd13: nbyte=8'h3A;
      5'd14: nbyte=tc(lat_c[5:4]);
      5'd15: nbyte=tc(lat_c[3:2]);
      5'd16: nbyte=tc(lat_c[1:0]);
      5'd17: nbyte=8'h0D;           // '\r'
      5'd18: nbyte=8'h0A;           // '\n'
      default: nbyte=8'h20;
    endcase
  end

  // Единый always-блок (нет dual-driver!)
  always @(posedge clk) begin
    spulse <= 1'b0;
    if (tx_trigger) begin
      sending <= 1'b1;
      bidx    <= 5'd0;
    end else if (sending && uready && !spulse) begin
      sbyte  <= nbyte;
      spulse <= 1'b1;
      if (bidx == 5'd18) begin sending<=1'b0; bidx<=5'd0; end
      else bidx <= bidx + 5'd1;
    end
  end

  uart_tx utx(.clk(clk),.data(sbyte),.start(spulse),.tx(uart_tx),.ready(uready));
endmodule
