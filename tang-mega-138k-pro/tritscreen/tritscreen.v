// tritscreen.v — Интерактивная Троица на 5" 800×480 RGB LCD
// Tang Mega 138K Pro + 5" RGB-параллельная LCD-панель
//
// Перихоресис на экране:
//   3 горизонтальные полосы, активная горит ярче.
//   Без UART: автоцикл K → P → L каждую секунду.
//   С UART (115200, /dev/ttyUSB1):
//     '-' или 'k' → фиксирует Кенозис (верх)
//     '0' или 'p' → фиксирует Присутствие (центр)
//     '+' или 'l' → фиксирует Плерома (низ)
//     'a' (auto)  → возобновить автоцикл
//
// LED показывают активную полосу (один горит, остальные потушены).

`default_nettype none

// ── UART RX 115200 @ 50 МГц ──────────────────────────────────────────────────
module uart_rx_lcd (
  input  wire       clk,
  input  wire       rx,
  output reg  [7:0] data  = 0,
  output reg        ready = 0
);
  localparam CLKDIV = 434;
  reg [8:0] sr  = 0;
  reg [9:0] div = 0;
  reg [3:0] cnt = 0;
  reg       active = 0;
  always @(posedge clk) begin
    ready <= 0;
    if (!active) begin
      if (!rx) begin active <= 1; div <= CLKDIV/2; cnt <= 8; end
    end else begin
      if (div == 0) begin
        div <= CLKDIV - 1;
        if (cnt == 0) begin data <= sr[7:0]; ready <= 1; active <= 0; end
        else begin sr <= {rx, sr[8:1]}; cnt <= cnt - 1; end
      end else div <= div - 1;
    end
  end
endmodule

// ── Top ──────────────────────────────────────────────────────────────────────
module tritscreen (
  input  wire        clk,        // 50 МГц
  input  wire        rst_n,      // active LOW
  input  wire        rx,         // UART RX (P14 pin header / R15 — TODO verify)

  // RGB LCD интерфейс (18-bit)
  output wire        lcd_clk,
  output wire        lcd_en,
  output wire [5:0]  lcd_r,
  output wire [5:0]  lcd_g,
  output wire [5:0]  lcd_b,

  // Бортовые LED
  output wire [2:0]  state_led
);

  // ── Делитель тактовой 50 → 25 МГц ────────────────────────────────────────
  reg clk25 = 1'b0;
  always @(posedge clk) clk25 <= ~clk25;
  assign lcd_clk = clk25;

  // ── UART приёмник ────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx_lcd urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // ── Управление активной полосой (всё в 50 МГц домене) ───────────────────
  // 0 = K (Кенозис), 1 = P (Присутствие), 2 = L (Плерома)
  reg [1:0]  active_band = 2'd0;
  reg        auto_mode   = 1'b1;
  reg [26:0] sec_cnt     = 0;     // 1 сек @ 50 МГц = 50_000_000

  always @(posedge clk) begin
    if (rx_ready) begin
      case (rx_data)
        8'h2D, 8'h6B: begin active_band <= 2'd0; auto_mode <= 1'b0; end // '-' or 'k'
        8'h30, 8'h70: begin active_band <= 2'd1; auto_mode <= 1'b0; end // '0' or 'p'
        8'h2B, 8'h6C: begin active_band <= 2'd2; auto_mode <= 1'b0; end // '+' or 'l'
        8'h61:        begin auto_mode   <= 1'b1; end                    // 'a' → auto
        default: ;
      endcase
    end else if (auto_mode) begin
      if (sec_cnt == 27'd49_999_999) begin
        sec_cnt <= 0;
        active_band <= (active_band == 2'd2) ? 2'd0 : active_band + 1'b1;
      end else sec_cnt <= sec_cnt + 1'b1;
    end else begin
      sec_cnt <= 0;
    end
  end

  // ── Тайминги 800×480 (5" Sipeed-совместимая панель) ──────────────────────
  localparam H_VALID = 16'd800;
  localparam H_FP    = 16'd210;
  localparam H_BP    = 16'd182;
  localparam H_TOTAL = H_VALID + H_FP + H_BP;   // 1192

  localparam V_VALID = 16'd480;
  localparam V_FP    = 16'd45;
  localparam V_BP    = 16'd8;
  localparam V_TOTAL = V_VALID + V_FP + V_BP;   // 533

  reg [15:0] h_cnt = 0;
  reg [15:0] v_cnt = 0;

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

  wire [15:0] y = (v_cnt >= V_BP) ? (v_cnt - V_BP) : 16'd0;

  // ── Какая полоса соответствует текущему y ────────────────────────────────
  wire [1:0] band_here =
      (y < 16'd160) ? 2'd0 :
      (y < 16'd320) ? 2'd1 : 2'd2;

  wire is_active = (band_here == active_band);

  // ── Цвета ────────────────────────────────────────────────────────────────
  reg [5:0] r, g, b;
  always @(*) begin
    if (!visible) begin
      {r, g, b} = 18'h00000;
    end else case (band_here)
      2'd0: begin   // КЕНОЗИС — красный
        r = is_active ? 6'b111100 : 6'b011000;
        g = 6'b000000;
        b = 6'b000000;
      end
      2'd1: begin   // ПРИСУТСТВИЕ — белое золото
        r = is_active ? 6'b111111 : 6'b011000;
        g = is_active ? 6'b111111 : 6'b011000;
        b = is_active ? 6'b011000 : 6'b001000;
      end
      default: begin   // ПЛЕРОМА — глубокий синий
        r = is_active ? 6'b001000 : 6'b000100;
        g = is_active ? 6'b011000 : 6'b001000;
        b = is_active ? 6'b111111 : 6'b011000;
      end
    endcase
  end

  assign lcd_r = r;
  assign lcd_g = g;
  assign lcd_b = b;

  // ── LED дублируют активную полосу (active LOW) ───────────────────────────
  assign state_led[0] = (active_band != 2'd0);
  assign state_led[1] = (active_band != 2'd1);
  assign state_led[2] = (active_band != 2'd2);

endmodule
