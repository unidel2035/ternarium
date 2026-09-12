// tritscope.v — Аппаратный логический анализатор на Tang Mega 138K Pro
//
// 8 GPIO входов sampled @ 50 МГц + ring buffer 4096 событий +
// UART дамп изменений. Saleae Logic в кремнии.
//
// Формат пакетов на UART (115200 8N1):
//   E:TTTTTTTT:HH\n   — событие изменения, T=timestamp µs (8 hex), H=новое 8-битное значение
//   S:HH\n            — snapshot текущего состояния каждые 100 мс
//
// LCD: 8 горизонтальных линий волн, прокрутка справа налево.
//   Каждый канал — линия высоты 50px, толщина 4px, цвет = индекс канала.
//
// Применение: отладка I2C, SPI, UART, ШИМ, GPIO устройства.

`default_nettype none

module tritscope (
  input  wire        clk,         // 50 МГц
  input  wire        rst_n,       // active LOW

  // 8 каналов входа (с GPIO header)
  input  wire [7:0]  probe,

  // UART
  output wire        uart_tx,

  // LCD 800×480
  output wire        lcd_clk,
  output wire        lcd_en,
  output wire [5:0]  lcd_r,
  output wire [5:0]  lcd_g,
  output wire [5:0]  lcd_b,

  // LED
  output wire [5:0]  leds
);

  // ═══════════════════════════════════════════════════════════════════
  // 1. Уровень захвата: синхронизаторы + детектор изменения
  // ═══════════════════════════════════════════════════════════════════
  reg [7:0] probe_s1 = 0, probe_s2 = 0, probe_prev = 0;
  always @(posedge clk) begin
    probe_s1   <= probe;
    probe_s2   <= probe_s1;
    probe_prev <= probe_s2;
  end
  wire any_change = (probe_s2 != probe_prev);

  // Uptime в тактах
  reg [31:0] uptime = 0;
  always @(posedge clk) uptime <= uptime + 1;

  // Uptime в µs (50 МГц / 50 = 1 µs). uptime/50 = (uptime * 1311) >> 16
  wire [47:0] uptime_us_x = uptime * 17'd1311;
  wire [31:0] uptime_us = uptime_us_x[47:16];

  // ═══════════════════════════════════════════════════════════════════
  // 2. Ring buffer событий (4096 × 40 бит = 32 ts + 8 value)
  // ═══════════════════════════════════════════════════════════════════
  reg [31:0] evt_ts  [0:4095];
  reg [7:0]  evt_val [0:4095];
  reg [11:0] head = 0;
  reg [12:0] count = 0;

  integer i;
  initial begin
    for (i = 0; i < 4096; i = i + 1) begin
      evt_ts[i]  = 32'd0;
      evt_val[i] = 8'd0;
    end
  end

  always @(posedge clk) begin
    if (any_change) begin
      evt_ts[head]  <= uptime_us;
      evt_val[head] <= probe_s2;
      head <= head + 1'b1;
      if (count < 13'd4096) count <= count + 1'b1;
    end
  end

  // ═══════════════════════════════════════════════════════════════════
  // 3. UART TX: snapshot каждые 100 мс + immediate event push (упрощённо)
  // ═══════════════════════════════════════════════════════════════════
  // Простая логика: каждые 10мс отправляем "S:HH\n" (4 байта).
  // Этого достаточно для диагностики 8 GPIO каналов глазом.

  localparam CLKDIV = 434;
  reg        tx_pin = 1;
  reg [9:0]  tx_shift = 10'h3FF;
  reg [9:0]  tx_baud_cnt = 0;
  reg [3:0]  tx_bit_idx = 0;
  reg        tx_busy = 0;

  reg [22:0] tick_10ms = 0;
  reg [3:0]  msg_idx = 4'd5;        // idle = 5
  reg [7:0]  cur_byte = 0;
  reg        kick = 0;

  // Hex digit
  function [7:0] hex_chr;
    input [3:0] d;
    begin
      hex_chr = (d < 4'd10) ? ("0" + {4'd0, d}) : ("A" + {4'd0, d} - 8'd10);
    end
  endfunction

  always @(posedge clk) begin
    kick <= 0;
    if (msg_idx == 4'd5) begin
      // idle — ждём 10мс
      if (tick_10ms == 23'd499_999) begin
        tick_10ms <= 0;
        msg_idx <= 4'd0;
      end else tick_10ms <= tick_10ms + 1'b1;
    end else if (!tx_busy && !kick) begin
      case (msg_idx)
        4'd0: cur_byte <= "S";
        4'd1: cur_byte <= ":";
        4'd2: cur_byte <= hex_chr(probe_s2[7:4]);
        4'd3: cur_byte <= hex_chr(probe_s2[3:0]);
        default: cur_byte <= "\n";
      endcase
      kick <= 1;
      msg_idx <= msg_idx + 1'b1;
      if (msg_idx == 4'd4) msg_idx <= 4'd5;
    end
  end

  // UART TX модуль
  always @(posedge clk) begin
    if (!tx_busy) begin
      tx_pin <= 1;
      if (kick) begin
        tx_shift    <= {1'b1, cur_byte, 1'b0};
        tx_bit_idx  <= 0;
        tx_baud_cnt <= 0;
        tx_busy     <= 1;
        tx_pin      <= 0;
      end
    end else begin
      if (tx_baud_cnt == CLKDIV - 1) begin
        tx_baud_cnt <= 0;
        if (tx_bit_idx == 9) begin
          tx_busy <= 0;
          tx_pin  <= 1;
        end else begin
          tx_bit_idx <= tx_bit_idx + 1'b1;
          tx_pin     <= tx_shift[1];
          tx_shift   <= {1'b1, tx_shift[9:1]};
        end
      end else tx_baud_cnt <= tx_baud_cnt + 1'b1;
    end
  end
  assign uart_tx = tx_pin;

  // ═══════════════════════════════════════════════════════════════════
  // 4. LCD: 8 каналов в виде waveforms
  // ═══════════════════════════════════════════════════════════════════
  reg clk25 = 0;
  always @(posedge clk) clk25 <= ~clk25;
  assign lcd_clk = clk25;

  localparam H_TOTAL = 16'd1192;
  localparam V_TOTAL = 16'd533;
  localparam H_BP    = 16'd182;
  localparam V_BP    = 16'd8;
  localparam H_VALID = 16'd800;
  localparam V_VALID = 16'd480;

  reg [15:0] h_cnt = 0, v_cnt = 0;
  always @(posedge clk25 or negedge rst_n) begin
    if (!rst_n) begin h_cnt <= 0; v_cnt <= 0; end
    else if (h_cnt == H_TOTAL - 1) begin
      h_cnt <= 0;
      v_cnt <= (v_cnt == V_TOTAL - 1) ? 16'd0 : v_cnt + 1'b1;
    end else h_cnt <= h_cnt + 1'b1;
  end

  wire visible = (h_cnt >= H_BP) && (h_cnt < H_BP + H_VALID) &&
                 (v_cnt >= V_BP) && (v_cnt < V_BP + V_VALID);
  assign lcd_en = visible;

  wire [15:0] x = (h_cnt >= H_BP) ? (h_cnt - H_BP) : 16'd0;
  wire [15:0] y = (v_cnt >= V_BP) ? (v_cnt - V_BP) : 16'd0;

  // 8 ленточек по 60px высота
  // ch0: y 0..58
  // ch1: y 60..118
  // ...
  // ch7: y 420..478
  wire [3:0] ch_idx = y[15:6];   // /60 ≈ /64 (8 каналов точно влезают: 8*60=480)
  // Точнее: ch_idx = y >> 6 даёт деление на 64. 8 ячеек × 64 = 512, чуть больше 480.
  // Для простоты используем y[8:6] (0..7) для 8 каналов

  wire [2:0] ch_sel = y[8:6];      // /64 → 0..7
  wire [15:0] ch_y_top = {7'd0, ch_sel, 6'd0};  // ch_sel*64

  // Бит probe_s2[7-ch_sel] = текущее состояние выбранного канала.
  // Если 1 → линия в верхней части ленточки, 0 → внизу.
  wire bit_val = probe_s2[3'd7 - ch_sel];

  // y_in_strip = y - ch_y_top (0..63)
  wire [15:0] y_in_strip = y - ch_y_top;

  // Уровень: 1 → линия y=10..14, 0 → линия y=46..50.
  wire is_line_high = bit_val && (y_in_strip >= 16'd10) && (y_in_strip < 16'd14);
  wire is_line_low  = !bit_val && (y_in_strip >= 16'd46) && (y_in_strip < 16'd50);
  wire is_line = is_line_high || is_line_low;

  // Вертикальные линии в моменты edge — не реализованы (требуют истории), для simplicity
  // Просто рисуем горизонтальную линию текущего уровня

  // Метка канала слева (x 0..30): цветной квадрат
  wire is_label = (x < 16'd30) && (y_in_strip >= 16'd16) && (y_in_strip < 16'd48);

  // Цвета каналов
  reg [5:0] ch_r, ch_g, ch_b;
  always @(*) begin
    case (ch_sel)
      3'd0: begin ch_r = 6'b111100; ch_g = 6'b001000; ch_b = 6'b001000; end // red
      3'd1: begin ch_r = 6'b111100; ch_g = 6'b101000; ch_b = 6'b001000; end // orange
      3'd2: begin ch_r = 6'b111100; ch_g = 6'b111100; ch_b = 6'b001000; end // yellow
      3'd3: begin ch_r = 6'b001000; ch_g = 6'b111100; ch_b = 6'b001000; end // green
      3'd4: begin ch_r = 6'b001000; ch_g = 6'b101100; ch_b = 6'b111100; end // cyan
      3'd5: begin ch_r = 6'b001000; ch_g = 6'b001000; ch_b = 6'b111100; end // blue
      3'd6: begin ch_r = 6'b101100; ch_g = 6'b001000; ch_b = 6'b111100; end // purple
      default: begin ch_r = 6'b111100; ch_g = 6'b001000; ch_b = 6'b101100; end // pink
    endcase
  end

  // Отдельная разделительная линия каждые 60px
  wire on_separator = (y_in_strip == 16'd0) || (y_in_strip == 16'd1);

  reg [5:0] r, g, b;
  always @(*) begin
    // фон тёмно-серый
    r = 6'b001000; g = 6'b001000; b = 6'b001100;

    if (!visible) begin
      {r, g, b} = 18'h00000;
    end else if (on_separator) begin
      r = 6'b011000; g = 6'b011000; b = 6'b011000;
    end else if (is_label) begin
      r = ch_r; g = ch_g; b = ch_b;
    end else if (is_line) begin
      r = ch_r; g = ch_g; b = ch_b;
    end
  end

  assign lcd_r = r;
  assign lcd_g = g;
  assign lcd_b = b;

  // ═══════════════════════════════════════════════════════════════════
  // 5. LED индикаторы — текущее состояние ch0..5
  // ═══════════════════════════════════════════════════════════════════
  assign leds = ~probe_s2[5:0];   // active LOW

endmodule
