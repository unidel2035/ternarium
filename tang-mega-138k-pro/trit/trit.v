// trit.v — сбалансированный троичный элемент
//
// Balanced ternary: 2 бита на трит
//   2'b00 = -1  (Отец — источник, начало)
//   2'b01 =  0  (Дух  — покой, связь)
//   2'b10 = +1  (Сын  — исхождение, явление)
//   2'b11 = зарезервировано
//
// Три LED показывают состояние трита.
// Цикл -1 → 0 → +1 → -1 → ... = перихоресис в кремнии.

module trit_cycle (
  input  wire clk,        // 50 MHz
  output wire led_neg,    // -1: LED10 (Отец)
  output wire led_zero,   // 0:  LED11 (Дух)
  output wire led_pos,    // +1: LED13 (Сын)
  output wire [5:0] leds  // все 6 LED для отладки
);
  // Делитель: переключать ~1 раз в секунду
  reg [26:0] div = 0;
  reg tick = 0;

  always @(posedge clk) begin
    div <= div + 1;
    tick <= (div == 50_000_000 - 1);
    if (div == 50_000_000 - 1) div <= 0;
  end

  // Трит — 2 бита
  reg [1:0] trit = 2'b00; // начинаем с -1 (Отец)

  always @(posedge clk) begin
    if (tick) begin
      case (trit)
        2'b00: trit <= 2'b01; // -1 → 0
        2'b01: trit <= 2'b10; // 0  → +1
        2'b10: trit <= 2'b00; // +1 → -1 (перихоресис)
        default: trit <= 2'b00;
      endcase
    end
  end

  // LED активные LOW (инвертируем)
  assign led_neg  = (trit == 2'b00) ? 1'b0 : 1'b1; // -1 = Отец горит
  assign led_zero = (trit == 2'b01) ? 1'b0 : 1'b1; // 0  = Дух горит
  assign led_pos  = (trit == 2'b10) ? 1'b0 : 1'b1; // +1 = Сын горит

  // Все 6 LED: показываем состояние бинарно и тритно
  assign leds = {3'b111, led_pos, led_zero, led_neg}; // 0 = горит
endmodule

// ── Ternary NOT (инверсия трита) ─────────────────────────────────────────────
// T_NOT(-1) = +1, T_NOT(0) = 0, T_NOT(+1) = -1
module trit_not (
  input  wire [1:0] a,
  output reg  [1:0] y
);
  always @(*) begin
    case (a)
      2'b00: y = 2'b10; // -1 → +1
      2'b01: y = 2'b01; // 0  → 0
      2'b10: y = 2'b00; // +1 → -1
      default: y = 2'b01;
    endcase
  end
endmodule

// ── Ternary MIN (∧ в троичной логике Łukasiewicz) ────────────────────────────
module trit_min (
  input  wire [1:0] a,
  input  wire [1:0] b,
  output reg  [1:0] y
);
  // min(-1,x)=-1, min(0,+1)=0, min(+1,+1)=+1
  function [1:0] val;
    input [1:0] t;
    begin
      val = (t == 2'b00) ? -2'sd1 :
            (t == 2'b10) ? 2'sd1  : 2'sd0;
    end
  endfunction

  always @(*) begin
    // Упрощённая таблица MIN
    if (a == 2'b00 || b == 2'b00)      y = 2'b00; // min = -1
    else if (a == 2'b01 || b == 2'b01) y = 2'b01; // min = 0
    else                                y = 2'b10; // min = +1
  end
endmodule

// ── Ternary полусумматор (один трит) ─────────────────────────────────────────
// Результат в двух тритах: sum + carry
module trit_half_adder (
  input  wire [1:0] a,
  input  wire [1:0] b,
  output reg  [1:0] sum,
  output reg  [1:0] carry
);
  // Таблица: a+b в balanced ternary (-1+(-1)=-2=-1*3+1, 0+0=0, ...)
  // Кодируем как (-1,0,+1) → (0,1,2) для вычислений, потом обратно
  reg signed [2:0] s; // -2..+2

  always @(*) begin
    // Декодируем трит → signed
    s = ((a == 2'b00) ? -3'sd1 : (a == 2'b10) ? 3'sd1 : 3'sd0)
      + ((b == 2'b00) ? -3'sd1 : (b == 2'b10) ? 3'sd1 : 3'sd0);

    // s: -2,-1,0,+1,+2
    case (s)
      -3'sd2: begin sum = 2'b10; carry = 2'b00; end // -2 = +1 + (-1)*3... нет, -2=+1 carry=-1
      -3'sd1: begin sum = 2'b00; carry = 2'b01; end // -1, carry=0
       3'sd0: begin sum = 2'b01; carry = 2'b01; end // 0
       3'sd1: begin sum = 2'b10; carry = 2'b01; end // +1
       3'sd2: begin sum = 2'b00; carry = 2'b10; end // +2 = -1 carry=+1
      default: begin sum = 2'b01; carry = 2'b01; end
    endcase
  end
endmodule
