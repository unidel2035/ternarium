// tritclock.v — Тритные часы реального времени
//
// Три тритных счётчика: h2, h1, h0 ∈ {-1(KEN), 0(PRS), +1(PLR)}
// Отсчитывают ternary time от 000 до +++, цикл 27 секунд.
//
// Богословие:
//   [---] = KEN = тьма, начало
//   [000] = PRS = момент присутствия, середина цикла
//   [+++] = PLR = плерома, полнота — и снова кенозис
//
// Тритные часы — не просто счётчик. Каждый такт вселенной
// проходит через KEN → PRS → PLR и возвращается.
//
// UART TX (115200, pin 17): каждую секунду отправляет
//   "T:---\r\n"  (7 байт) — текущее тритное время
//   "+01"  — тритное значение (от -13 до +13) через 2 цифры
//   Формат полный: "T:--- V:-13\r\n" (13 байт)
//
// UART RX (pin 18):
//   'r' — сброс в KEN (---)
//   's' — выдать текущее время немедленно
//   '+' — ускорить × 2 (каждые 500 мс)
//   '-' — замедлить × 2 (каждые 2 сек)
//   '0' — нормальная скорость (1 сек)
//
// LED [5:0]: ~{h2, h1, h0} — текущее тритное время

`default_nettype none

// ── UART TX ──────────────────────────────────────────────────────────────────

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
      end else div <= div+1;
    end
  end
endmodule

// ── UART RX ──────────────────────────────────────────────────────────────────

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
      if (!rx) begin active <= 1; div <= CLKDIV/2; cnt <= 8; end
    end else begin
      if (div == 0) begin
        div <= CLKDIV - 1;
        if (cnt == 0) begin data <= sr; ready <= 1; active <= 0; end
        else begin sr <= {rx, sr[7:1]}; cnt <= cnt - 1; end
      end else div <= div - 1;
    end
  end
endmodule

// ── Тритные часы ─────────────────────────────────────────────────────────────

module tritclock (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // ── Тритный счётчик времени (0..26 = тритный индекс) ─────────────────────
  // h2 h1 h0: каждый ∈ {00=KEN, 01=PRS, 10=PLR}
  // Представление: idx = h2*9 + h1*3 + h0  (h2,h1,h0 ∈ {0,1,2})
  reg [4:0] trit_idx = 5'd0;  // начало: --- (KEN)

  // ── Делитель до 1 Гц ─────────────────────────────────────────────────────
  // 50 МГц → 1 сек = 50_000_000 тактов
  // Скорость регулируется: normal=27M, fast=13.5M, slow=54M
  // Храним делитель как 27M / speed_shift
  reg [1:0] speed = 2'd1;  // 0=медленно(2с), 1=норма(1с), 2=быстро(0.5с)

  reg [24:0] div_cnt = 0;
  reg        tick    = 0;

  wire [24:0] period = (speed == 2'd0) ? 25'd53999999 :
                       (speed == 2'd2) ? 25'd13499999 :
                                         25'd26999999;

  always @(posedge clk) begin
    tick <= 0;
    if (div_cnt >= period) begin
      div_cnt <= 0;
      tick    <= 1;
    end else div_cnt <= div_cnt + 1;
  end

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // ── Инкремент и команды в одном блоке ────────────────────────────────────
  reg do_report = 0;
  always @(posedge clk) begin
    do_report <= 0;
    if (tick) begin
      trit_idx  <= (trit_idx == 5'd26) ? 5'd0 : trit_idx + 5'd1;
      do_report <= 1;
    end
    if (rx_ready) begin
      case (rx_data)
        8'h72: begin trit_idx <= 5'd0; do_report <= 1; end  // 'r' — сброс
        8'h73: do_report <= 1;  // 's' — выдать сейчас
        8'h2B: speed <= (speed < 2'd2) ? speed + 2'd1 : 2'd2;  // '+'
        8'h2D: speed <= (speed > 2'd0) ? speed - 2'd1 : 2'd0;  // '-'
        8'h30: speed <= 2'd1;   // '0' — норма
        default: ;
      endcase
    end
  end

  // ── Декодирование тритного индекса ────────────────────────────────────────
  wire [1:0] h2 = (trit_idx >= 5'd18) ? 2'b10 : (trit_idx >= 5'd9) ? 2'b01 : 2'b00;
  wire [4:0] r1 = (trit_idx >= 5'd18) ? trit_idx - 5'd18 :
                  (trit_idx >= 5'd9)  ? trit_idx - 5'd9  : trit_idx;
  wire [1:0] h1 = (r1 >= 5'd6) ? 2'b10 : (r1 >= 5'd3) ? 2'b01 : 2'b00;
  wire [4:0] r0 = (r1 >= 5'd6) ? r1 - 5'd6 : (r1 >= 5'd3) ? r1 - 5'd3 : r1;
  wire [1:0] h0 = (r0 >= 5'd2) ? 2'b10 : (r0 == 5'd1) ? 2'b01 : 2'b00;

  assign leds = ~{h2, h1, h0};

  // ── Тритное значение -13..+13 ─────────────────────────────────────────────
  wire signed [4:0] trit_val = $signed({1'b0, trit_idx}) - $signed(5'd13);
  wire        sign_neg = trit_val < 0;
  wire [3:0]  absval   = sign_neg ? ~trit_val[3:0] + 4'd1 : trit_val[3:0];
  wire [3:0]  av_tens  = (absval >= 4'd10) ? 4'd1 : 4'd0;
  wire [3:0]  av_ones  = (absval >= 4'd10) ? absval - 4'd10 : absval;

  // ── Символы для TX ────────────────────────────────────────────────────────
  function [7:0] trit_char;
    input [1:0] v;
    case (v)
      2'b10: trit_char = 8'h2B;  // '+'
      2'b01: trit_char = 8'h30;  // '0'
      2'b00: trit_char = 8'h2D;  // '-'
      default: trit_char = 8'h3F;
    endcase
  endfunction

  // ── Защёлка TX ───────────────────────────────────────────────────────────
  // Формат: "T:h2h1h0 V:±NN\r\n" = 13 байт (bidx 0..12)
  reg [1:0]  tx_h2 = 0, tx_h1 = 0, tx_h0 = 0;
  reg        tx_neg = 0;
  reg [3:0]  tx_at = 0, tx_ao = 0;
  reg        tx_trigger = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_report) begin
      tx_h2 <= h2; tx_h1 <= h1; tx_h0 <= h0;
      tx_neg <= sign_neg;
      tx_at  <= av_tens;
      tx_ao  <= av_ones;
      tx_trigger <= 1;
    end
  end

  reg [3:0] bidx = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      4'd0:  nbyte = 8'h54;  // 'T'
      4'd1:  nbyte = 8'h3A;  // ':'
      4'd2:  nbyte = trit_char(tx_h2);
      4'd3:  nbyte = trit_char(tx_h1);
      4'd4:  nbyte = trit_char(tx_h0);
      4'd5:  nbyte = 8'h20;  // ' '
      4'd6:  nbyte = 8'h56;  // 'V'
      4'd7:  nbyte = 8'h3A;  // ':'
      4'd8:  nbyte = tx_neg ? 8'h2D : 8'h2B;  // знак
      4'd9:  nbyte = 8'h30 + {4'h0, tx_at};   // десятки |val|
      4'd10: nbyte = 8'h30 + {4'h0, tx_ao};   // единицы |val|
      4'd11: nbyte = 8'h0D;
      4'd12: nbyte = 8'h0A;
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == 4'd12) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
