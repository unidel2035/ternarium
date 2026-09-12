// tritsum.v — Троичный сумматор в кремнии
//
// Богословие: Отец (A) + Сын (B) = Логос (SUM) + Дух-Перенос (CARRY)
// Перебирает все 9 комбинаций троичного сложения, 1 секунда каждая.
//
// LED (активные LOW, группами по 2 бита — троичное кодирование):
//   LED1,LED2 (pin 10,11) = A:  00=-1 (Отец), 01=0 (Дух), 10=+1 (Сын)
//   LED3,LED4 (pin 13,14) = B:  то же
//   LED5,LED6 (pin 15,16) = SUM: результат
//
// UART 115200: FT2232H Interface B (pin 17 TX)
//   Каждую секунду: "A:-1 B:+1 S: 0 C: 0\r\n"
//
// Сбалансированная троичная арифметика:
//   2'b00 = -1 | 2'b01 = 0 | 2'b10 = +1

`default_nettype none

// ── Троичный полусумматор ──────────────────────────────────
// a + b → sum + carry*3
// Таблица: -2→(+1,-1) | -1→(-1,0) | 0→(0,0) | +1→(+1,0) | +2→(-1,+1)
module trit_adder (
  input  wire [1:0] a,
  input  wire [1:0] b,
  output reg  [1:0] sum,
  output reg  [1:0] carry
);
  reg signed [2:0] s;
  always @(*) begin
    s = ((a == 2'b00) ? -3'sd1 : (a == 2'b10) ? 3'sd1 : 3'sd0)
      + ((b == 2'b00) ? -3'sd1 : (b == 2'b10) ? 3'sd1 : 3'sd0);
    case (s)
      -3'sd2: begin sum = 2'b10; carry = 2'b00; end // -2 = +1 + (-1)*3
      -3'sd1: begin sum = 2'b00; carry = 2'b01; end // -1 = -1 + 0
       3'sd0: begin sum = 2'b01; carry = 2'b01; end //  0 =  0 + 0
       3'sd1: begin sum = 2'b10; carry = 2'b01; end // +1 = +1 + 0
       3'sd2: begin sum = 2'b00; carry = 2'b10; end // +2 = -1 + (+1)*3
      default: begin sum = 2'b01; carry = 2'b01; end
    endcase
  end
endmodule

// ── UART TX: 115200 бод @ 50 МГц ─────────────────────────
// 1 стартовый бит (0), 8 бит данных (LSB first), 1 стоп (1)
module uart_tx (
  input  wire       clk,
  input  wire [7:0] data,
  input  wire       start,
  output reg        tx    = 1,
  output wire       ready
);
  localparam CLKDIV = 434; // 50_000_000 / 115200 ≈ 234

  reg [7:0] sr  = 8'hFF;
  reg [7:0] div = 0;
  reg [3:0] cnt = 0; // 0=idle, 1..8=биты данных, 9=стоп

  assign ready = (cnt == 0);

  always @(posedge clk) begin
    if (cnt == 0) begin
      if (start) begin
        sr  <= data;
        cnt <= 9;
        tx  <= 0;   // стартовый бит
        div <= 0;
      end
    end else begin
      if (div == CLKDIV - 1) begin
        div <= 0;
        if (cnt == 1) begin
          tx  <= 1; // стоп бит
          cnt <= 0;
        end else begin
          tx  <= sr[0];          // LSB first
          sr  <= {1'b1, sr[7:1]};
          cnt <= cnt - 1;
        end
      end else begin
        div <= div + 1;
      end
    end
  end
endmodule

// ── Главный модуль ─────────────────────────────────────────
module tritsum (
  input  wire       clk,      // 50 МГц
  output wire [5:0] leds,     // активные LOW: [a1,a0, b1,b0, s1,s0]
  output wire       uart_tx
);

  // Делитель 50 МГц → 1 Гц
  reg [24:0] div1 = 0;
  reg        tick = 0;
  always @(posedge clk) begin
    tick <= (div1 == 25'd26_999_999);
    div1 <= (div1 == 25'd26_999_999) ? 25'd0 : div1 + 25'd1;
  end

  // Перебор 9 комбинаций (a,b), 1 секунда на каждую
  reg [3:0] state = 4'd0;
  always @(posedge clk) begin
    if (tick) state <= (state == 4'd8) ? 4'd0 : state + 4'd1;
  end

  // Декодирование состояния → (a_t, b_t)
  reg [1:0] a_t, b_t;
  always @(*) begin
    case (state)
      4'd0: begin a_t = 2'b00; b_t = 2'b00; end // -1 + -1
      4'd1: begin a_t = 2'b00; b_t = 2'b01; end // -1 +  0
      4'd2: begin a_t = 2'b00; b_t = 2'b10; end // -1 + +1
      4'd3: begin a_t = 2'b01; b_t = 2'b00; end //  0 + -1
      4'd4: begin a_t = 2'b01; b_t = 2'b01; end //  0 +  0
      4'd5: begin a_t = 2'b01; b_t = 2'b10; end //  0 + +1
      4'd6: begin a_t = 2'b10; b_t = 2'b00; end // +1 + -1
      4'd7: begin a_t = 2'b10; b_t = 2'b01; end // +1 +  0
      4'd8: begin a_t = 2'b10; b_t = 2'b10; end // +1 + +1
      default: begin a_t = 2'b01; b_t = 2'b01; end
    endcase
  end

  // Сумматор
  wire [1:0] sum_t, carry_t;
  trit_adder adder (.a(a_t), .b(b_t), .sum(sum_t), .carry(carry_t));

  // LED: активные LOW — [a1,a0, b1,b0, sum1,sum0]
  assign leds = ~{a_t, b_t, sum_t};

  // ── UART строка ───────────────────────────────────────
  // Формат: "A:-1 B:+1 S: 0 C: 0\r\n" = 21 байт (индексы 0..20)
  //
  //  0:'A' 1:':' 2:sign(a) 3:dig(a)
  //  4:' ' 5:'B' 6:':' 7:sign(b) 8:dig(b)
  //  9:' ' 10:'S' 11:':' 12:sign(s) 13:dig(s)
  //  14:' ' 15:'C' 16:':' 17:sign(c) 18:dig(c)
  //  19:'\r' 20:'\n'

  // Защёлка значений при каждом тике
  reg [1:0] lat_a = 2'b01, lat_b = 2'b01;
  reg [1:0] lat_s = 2'b01, lat_c = 2'b01;
  reg       sending = 1'b0;
  reg [4:0] byte_idx = 5'd0;
  reg [7:0] send_byte = 8'h00;
  reg       send_pulse = 1'b0;

  wire uart_ready;

  // Вспомогательные функции: символ знака и цифры
  function [7:0] trit_sign;
    input [1:0] t;
    begin
      case (t)
        2'b00: trit_sign = 8'h2D; // '-'
        2'b01: trit_sign = 8'h20; // ' '
        2'b10: trit_sign = 8'h2B; // '+'
        default: trit_sign = 8'h3F; // '?'
      endcase
    end
  endfunction

  function [7:0] trit_digit;
    input [1:0] t;
    begin
      trit_digit = (t == 2'b01) ? 8'h30 : 8'h31; // '0' или '1'
    end
  endfunction

  // Байт по индексу (комбинационно из защёлок)
  reg [7:0] next_byte;
  always @(*) begin
    case (byte_idx)
      5'd0:  next_byte = 8'h41;          // 'A'
      5'd1:  next_byte = 8'h3A;          // ':'
      5'd2:  next_byte = trit_sign(lat_a);
      5'd3:  next_byte = trit_digit(lat_a);
      5'd4:  next_byte = 8'h20;          // ' '
      5'd5:  next_byte = 8'h42;          // 'B'
      5'd6:  next_byte = 8'h3A;          // ':'
      5'd7:  next_byte = trit_sign(lat_b);
      5'd8:  next_byte = trit_digit(lat_b);
      5'd9:  next_byte = 8'h20;          // ' '
      5'd10: next_byte = 8'h53;          // 'S'
      5'd11: next_byte = 8'h3A;          // ':'
      5'd12: next_byte = trit_sign(lat_s);
      5'd13: next_byte = trit_digit(lat_s);
      5'd14: next_byte = 8'h20;          // ' '
      5'd15: next_byte = 8'h43;          // 'C'
      5'd16: next_byte = 8'h3A;          // ':'
      5'd17: next_byte = trit_sign(lat_c);
      5'd18: next_byte = trit_digit(lat_c);
      5'd19: next_byte = 8'h0D;          // '\r'
      5'd20: next_byte = 8'h0A;          // '\n'
      default: next_byte = 8'h20;
    endcase
  end

  // Управление передачей
  always @(posedge clk) begin
    send_pulse <= 1'b0; // по умолчанию сбрасываем

    // При тике — защёлкиваем и запускаем передачу
    if (tick) begin
      lat_a    <= a_t;
      lat_b    <= b_t;
      lat_s    <= sum_t;
      lat_c    <= carry_t;
      sending  <= 1'b1;
      byte_idx <= 5'd0;
    end else if (sending && uart_ready && !send_pulse) begin
      // Отправляем следующий байт
      send_byte  <= next_byte;
      send_pulse <= 1'b1;
      if (byte_idx == 5'd20) begin
        sending  <= 1'b0;
        byte_idx <= 5'd0;
      end else begin
        byte_idx <= byte_idx + 5'd1;
      end
    end
  end

  uart_tx utx (
    .clk   (clk),
    .data  (send_byte),
    .start (send_pulse),
    .tx    (uart_tx),
    .ready (uart_ready)
  );

endmodule
