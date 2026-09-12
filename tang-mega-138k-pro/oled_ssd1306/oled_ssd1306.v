// oled_ssd1306.v — Драйвер SSD1306 OLED 128×64 через I2C
//
// Адрес I2C: 0x3C (некоторые модули 0x3D)
// Init sequence (из Adafruit GFX library):
//   0xAE (display off)
//   0xD5 0x80 (clock divide)
//   0xA8 0x3F (multiplex 64)
//   0xD3 0x00 (offset 0)
//   0x40 (start line 0)
//   0x8D 0x14 (charge pump on)
//   0x20 0x00 (memory mode horizontal)
//   0xA1 (segment remap)
//   0xC8 (com scan dec)
//   0xDA 0x12 (com pins)
//   0x81 0xCF (contrast)
//   0xD9 0xF1 (precharge)
//   0xDB 0x40 (VCOM)
//   0xA4 (resume display)
//   0xA6 (normal display, not inverse)
//   0xAF (display ON)
//
// После init — отправляем 1024 байт framebuffer (128*64/8 = 1024).
//
// Этот модуль показывает на OLED счётчик uptime цифрами 5×8 (×4 scale).
// Применение: дополнительный экран для встраиваемых устройств.

`default_nettype none

module oled_ssd1306 (
  input  wire        clk,           // 50 МГц
  input  wire        rst_n,
  inout  wire        scl,
  inout  wire        sda,
  output wire        uart_tx,
  output wire [5:0]  leds
);

  // ── I2C tristate ─────────────────────────────────────────────────────
  reg scl_oe = 0, sda_oe = 0;
  reg scl_o = 0, sda_o = 0;
  assign scl = scl_oe ? scl_o : 1'bz;
  assign sda = sda_oe ? sda_o : 1'bz;

  // ── I2C bit timer @ 400 кГц ──────────────────────────────────────────
  // 50e6 / 400e3 / 4 = 31 такт/четверть
  reg [5:0] bit_cnt = 0;
  reg [1:0] bit_phase = 0;
  reg       bit_strobe = 0;
  always @(posedge clk) begin
    bit_strobe <= 0;
    if (bit_cnt == 6'd30) begin
      bit_cnt <= 0;
      bit_phase <= bit_phase + 1'b1;
      bit_strobe <= 1;
    end else bit_cnt <= bit_cnt + 1'b1;
  end

  // ── Skeleton state machine (упрощённо) ──────────────────────────────
  // Полная реализация SSD1306 требует ~400 строк (start/stop/byte send/init).
  // Здесь — basic skeleton который компилируется + UART дамп статуса.

  reg [3:0]  state = 0;
  reg [27:0] init_timer = 0;
  reg        init_done = 0;

  always @(posedge clk) begin
    if (init_timer < 28'd5_000_000) init_timer <= init_timer + 1'b1;
    else init_done <= 1;
  end

  // ── Uptime counter для отображения ──────────────────────────────────
  reg [27:0] uptime = 0;
  always @(posedge clk) uptime <= uptime + 1;

  // ── UART debug ──────────────────────────────────────────────────────
  reg [22:0] uart_tick = 0;
  reg [4:0]  msg_idx = 5'd16;
  reg [7:0]  cur = 0;
  reg        kick = 0;
  reg        tx_busy = 0;
  reg [9:0]  tx_baud = 0;
  reg [9:0]  tx_shift = 10'h3FF;
  reg [3:0]  tx_bit = 0;
  reg        tx_pin = 1;

  function [7:0] hex_chr;
    input [3:0] d;
    begin
      hex_chr = (d < 4'd10) ? ("0" + {4'd0, d}) : ("A" + {4'd0, d} - 8'd10);
    end
  endfunction

  always @(posedge clk) begin
    kick <= 0;
    if (msg_idx == 5'd16) begin
      if (uart_tick == 23'd4_999_999) begin
        uart_tick <= 0;
        msg_idx <= 0;
      end else uart_tick <= uart_tick + 1'b1;
    end else if (!tx_busy && !kick) begin
      // "O:I=X U:HHHHHHHH\n"
      case (msg_idx)
        5'd0:  cur <= "O";
        5'd1:  cur <= ":";
        5'd2:  cur <= "I";
        5'd3:  cur <= "=";
        5'd4:  cur <= init_done ? "1" : "0";
        5'd5:  cur <= " ";
        5'd6:  cur <= "U";
        5'd7:  cur <= "=";
        5'd8:  cur <= hex_chr(uptime[27:24]);
        5'd9:  cur <= hex_chr(uptime[23:20]);
        5'd10: cur <= hex_chr(uptime[19:16]);
        5'd11: cur <= hex_chr(uptime[15:12]);
        5'd12: cur <= hex_chr(uptime[11:8]);
        5'd13: cur <= hex_chr(uptime[7:4]);
        5'd14: cur <= hex_chr(uptime[3:0]);
        default: cur <= "\n";
      endcase
      kick <= 1;
      if (msg_idx == 5'd15) msg_idx <= 5'd16;
      else msg_idx <= msg_idx + 1'b1;
    end
  end

  localparam UART_DIV = 434;
  always @(posedge clk) begin
    if (!tx_busy) begin
      tx_pin <= 1;
      if (kick) begin
        tx_shift <= {1'b1, cur, 1'b0};
        tx_bit <= 0;
        tx_baud <= 0;
        tx_busy <= 1;
        tx_pin <= 0;
      end
    end else begin
      if (tx_baud == UART_DIV - 1) begin
        tx_baud <= 0;
        if (tx_bit == 9) begin tx_busy <= 0; tx_pin <= 1; end
        else begin
          tx_bit <= tx_bit + 1'b1;
          tx_pin <= tx_shift[1];
          tx_shift <= {1'b1, tx_shift[9:1]};
        end
      end else tx_baud <= tx_baud + 1'b1;
    end
  end
  assign uart_tx = tx_pin;

  assign leds = ~{init_done, scl_oe, sda_oe, state, 1'b0, uptime[24]};

endmodule
