// trithash.v — Тритный хеш в кремнии
//
// Алгоритм: 3-тритовый LFSR над GF(3)
//
// GF(3) — поле из трёх элементов: {-1, 0, +1}
// Сложение в GF(3): это циклическая группа Z/3Z
//   -1 + -1 = +1   (wraparound!)
//    0 +  0 =  0
//   +1 + +1 = -1   (wraparound!)
//   Т.е. это НЕ обычное сложение — это сложение по модулю 3.
//
// Хеш-состояние: h[2], h[1], h[0] — три трита
// На каждый входной байт b:
//   t = trit(b)          — извлечь трит из байта (b[1:0], 11→-1)
//   new_h[0] = h[1] ⊕3 t  — смешать вход в h[0]
//   new_h[1] = h[2] ⊕3 h[0]  — feedback
//   new_h[2] = h[1]           — сдвиг
//
// Ввод через UART RX:
//   Любые байты — аккумулируются в хеш
//   '.' (0x2E) — вывести хеш и сбросить
//   'r' (0x72) — сбросить без вывода
//
// Вывод через UART TX: "H:+0-\r\n" (8 байт)
// LED: ~{h[2], h[1], h[0]}  (текущее состояние хеша)

`default_nettype none

// ── UART TX ─────────────────────────────────────────────────────────────────

module uart_tx (
  input  wire       clk,
  input  wire [7:0] data,
  input  wire       start,
  output reg        tx = 1,
  output wire       ready
);
  localparam CLKDIV = 434;
  reg [7:0] sr = 8'hFF, div = 0;
  reg [3:0] cnt = 0;
  assign ready = (cnt == 0);

  always @(posedge clk) begin
    if (cnt == 0) begin
      if (start) begin sr <= data; cnt <= 9; tx <= 0; div <= 0; end
    end else begin
      if (div == CLKDIV-1) begin
        div <= 0;
        if (cnt == 1) begin tx <= 1; cnt <= 0; end
        else begin tx <= sr[0]; sr <= {1'b1, sr[7:1]}; cnt <= cnt-1; end
      end else div <= div + 1;
    end
  end
endmodule

// ── UART RX ─────────────────────────────────────────────────────────────────

module uart_rx (
  input  wire       clk,
  input  wire       rx,
  output reg  [7:0] data  = 0,
  output reg        ready = 0
);
  localparam CLKDIV = 434;
  reg [7:0] sr = 0, div = 0;
  reg [3:0] cnt = 0;
  reg       active = 0;

  always @(posedge clk) begin
    ready <= 0;
    if (!active) begin
      if (!rx) begin active <= 1; div <= CLKDIV/2; cnt <= 9; end  // 9: start bit вытесняется из 8-бит sr
    end else begin
      if (div == 0) begin
        div <= CLKDIV - 1;
        if (cnt == 0) begin data <= sr; ready <= 1; active <= 0; end
        else begin sr <= {rx, sr[7:1]}; cnt <= cnt - 1; end
      end else div <= div - 1;
    end
  end
endmodule

// ── GF(3) сложение ─────────────────────────────────────────────────────────
// Кодировка: 2'b00=-1, 2'b01=0, 2'b10=+1
// Таблица: {a,b} → (a_int + b_int) mod 3, mapped back
//   -1+-1=+1  -1+0=-1  -1+1=0
//    0+-1=-1   0+0=0    0+1=+1
//   +1+-1=0  +1+0=+1  +1+1=-1

module gf3_add (input [1:0] a, b, output reg [1:0] y);
  always @(*) begin
    case ({a, b})
      4'b00_00: y = 2'b10;  // -1 + -1 = +1
      4'b00_01: y = 2'b00;  // -1 +  0 = -1
      4'b00_10: y = 2'b01;  // -1 + +1 =  0
      4'b01_00: y = 2'b00;  //  0 + -1 = -1
      4'b01_01: y = 2'b01;  //  0 +  0 =  0
      4'b01_10: y = 2'b10;  //  0 + +1 = +1
      4'b10_00: y = 2'b01;  // +1 + -1 =  0
      4'b10_01: y = 2'b10;  // +1 +  0 = +1
      4'b10_10: y = 2'b00;  // +1 + +1 = -1
      default:  y = 2'b01;
    endcase
  end
endmodule

// ── Тритный хеш ─────────────────────────────────────────────────────────────

module trithash (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // ── Хеш-состояние ────────────────────────────────────────────────
  reg [1:0] h0 = 2'b01, h1 = 2'b01, h2 = 2'b01;  // начало: 0,0,0

  // ── UART ─────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // ── Извлечение трита из байта ────────────────────────────────────
  // b[1:0]: 00→-1, 01→0, 10→+1, 11→-1 (fold, чтобы balance сохранялся)
  // Дополнительно XOR с b[7:6] для лучшего распределения
  function [1:0] byte_trit;
    input [7:0] b;
    reg [1:0] lo, hi, mid;
    begin
      lo  = b[1:0];
      hi  = b[7:6];
      mid = b[4:3];
      // Три пары битов → три трита → сложить в GF(3)
      // Упрощённо: XOR попарно и нормализовать
      case ({lo ^ hi ^ mid})
        2'b00: byte_trit = 2'b00;  // -1
        2'b01: byte_trit = 2'b01;  //  0
        2'b10: byte_trit = 2'b10;  // +1
        2'b11: byte_trit = 2'b00;  // -1 (fold)
      endcase
    end
  endfunction

  // ── GF(3) сумматоры (комбинационно) ─────────────────────────────
  wire [1:0] t_in;
  reg  [1:0] t_in_reg = 2'b01;
  assign t_in = t_in_reg;

  wire [1:0] mix0, feed1;
  gf3_add ga0(.a(h1),  .b(t_in), .y(mix0));   // new h0 = h1 ⊕3 t
  gf3_add ga1(.a(h2),  .b(h0),   .y(feed1));  // new h1 = h2 ⊕3 h0
  // new h2 = h1

  // ── Логика обновления ────────────────────────────────────────────
  reg do_hash   = 0;
  reg do_output = 0;
  reg do_reset  = 0;

  always @(posedge clk) begin
    do_hash   <= 0;
    do_output <= 0;
    do_reset  <= 0;

    if (rx_ready) begin
      case (rx_data)
        8'h2E,            // '.' — вывести хеш и сбросить
        8'h0A: begin      // '\n' — тоже
          do_output <= 1;
        end
        8'h72: begin      // 'r' — сброс
          do_reset <= 1;
        end
        default: begin    // любой байт → аккумулировать
          t_in_reg <= byte_trit(rx_data);
          do_hash  <= 1;
        end
      endcase
    end
  end

  always @(posedge clk) begin
    if (do_reset) begin
      h0 <= 2'b01; h1 <= 2'b01; h2 <= 2'b01;
    end else if (do_hash) begin
      h0 <= mix0;
      h1 <= feed1;
      h2 <= h1;
    end else if (do_output) begin
      h0 <= 2'b01; h1 <= 2'b01; h2 <= 2'b01;
    end
  end

  // ── Лёгкое: фиксируем состояние перед выводом ────────────────────
  reg [1:0] out_h0 = 2'b01, out_h1 = 2'b01, out_h2 = 2'b01;
  reg       tx_trigger = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_output) begin
      out_h0 <= h0;
      out_h1 <= h1;
      out_h2 <= h2;
      tx_trigger <= 1;
    end
  end

  // ── Символ трита для вывода ──────────────────────────────────────
  function [7:0] tc;
    input [1:0] t;
    begin
      case (t)
        2'b00: tc = 8'h2D;  // '-'
        2'b01: tc = 8'h30;  // '0'
        2'b10: tc = 8'h2B;  // '+'
        default: tc = 8'h3F;
      endcase
    end
  endfunction

  // ── UART TX: "H:+0-\r\n" = 8 байт ──────────────────────────────
  reg [3:0] bidx    = 0;
  reg       sending = 0, spulse = 0;
  reg [7:0] sbyte   = 0;
  wire      uready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      4'd0: nbyte = 8'h48;        // 'H'
      4'd1: nbyte = 8'h3A;        // ':'
      4'd2: nbyte = tc(out_h2);   // трит 2 (старший)
      4'd3: nbyte = tc(out_h1);   // трит 1
      4'd4: nbyte = tc(out_h0);   // трит 0 (младший)
      4'd5: nbyte = 8'h0D;        // '\r'
      4'd6: nbyte = 8'h0A;        // '\n'
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == 4'd6) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

  // LED: текущее состояние хеша (меняется при каждом байте)
  assign leds = ~{h2, h1, h0};

endmodule
