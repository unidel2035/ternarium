// trituart2.v — Двухканальный UART мост с тритной фильтрацией
//
// Tang Nano как посредник между двумя UART-устройствами:
//   UART A (115200, pin 17/18) ↔ Tang Nano ↔ UART B (115200, pin 25/26)
//
// Богословие: мост — не просто ретрансляция. Каждый байт
// проходит через тритный фильтр: отображается на тритный символ
// и записывается в историю последних 9 байт.
// Мост — анамнезис потока.
//
// Функционал:
//   - Всё что приходит с A → идёт на B (прозрачный мост)
//   - Всё что приходит с B → идёт на A
//   - LED: последний байт с A как тритный паттерн (b7b6b5→h2h1h0)
//   - Байты подсчитываются (A→B и B→A счётчики 8-бит)
//
// Pin назначение:
//   pin 17 = TX_A (к хосту/ноуту)
//   pin 18 = RX_A
//   pin 25 = TX_B (к устройству)
//   pin 26 = RX_B  (Tang Nano 9K: пин 26 = IO[26])
//
// LED [5:4]: h2 последнего байта A
// LED [3:2]: h1
// LED [1:0]: h0

`default_nettype none

// ── UART TX (generic) ────────────────────────────────────────────────────────

module uart_tx_ch (
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

// ── UART RX (generic) ────────────────────────────────────────────────────────

module uart_rx_ch (
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

// ── Тритный мост ─────────────────────────────────────────────────────────────

module trituart2 (
  input  wire clk,
  input  wire rx_a,   // pin 18 — от хоста
  input  wire rx_b,   // pin 26 — от FC
  output wire tx_a,   // pin 17 — к хосту
  output wire tx_b,   // pin 25 — к FC
  output wire [5:0] leds
);

  // ── Канал A: хост ─────────────────────────────────────────────────────────
  wire [7:0] a_data;
  wire       a_ready;
  uart_rx_ch urx_a(.clk(clk), .rx(rx_a), .data(a_data), .ready(a_ready));

  wire tx_b_ready;
  reg [7:0] b_sbyte = 0;
  reg       b_start = 0;
  uart_tx_ch utx_b(.clk(clk), .data(b_sbyte), .start(b_start), .tx(tx_b), .ready(tx_b_ready));

  // ── Канал B: FC ───────────────────────────────────────────────────────────
  wire [7:0] b_data;
  wire       b_ready;
  uart_rx_ch urx_b(.clk(clk), .rx(rx_b), .data(b_data), .ready(b_ready));

  wire tx_a_ready;
  reg [7:0] a_sbyte = 0;
  reg       a_start = 0;
  uart_tx_ch utx_a(.clk(clk), .data(a_sbyte), .start(a_start), .tx(tx_a), .ready(tx_a_ready));

  // ── Мост A→B ──────────────────────────────────────────────────────────────
  reg [7:0] cnt_ab = 0;
  reg [7:0] last_a = 0;

  always @(posedge clk) begin
    b_start <= 0;
    if (a_ready && tx_b_ready) begin
      b_sbyte <= a_data;
      b_start <= 1;
      last_a  <= a_data;
      cnt_ab  <= cnt_ab + 8'd1;
    end
  end

  // ── Мост B→A ──────────────────────────────────────────────────────────────
  reg [7:0] cnt_ba = 0;

  always @(posedge clk) begin
    a_start <= 0;
    if (b_ready && tx_a_ready) begin
      a_sbyte <= b_data;
      a_start <= 1;
      cnt_ba  <= cnt_ba + 8'd1;
    end
  end

  // ── LED: тритный паттерн последнего байта A ───────────────────────────────
  // b[7:6] → h2, b[5:4] → h1, b[3:2] → h0
  // Кодировка: 2'b11→2'b10(PLR), 2'b10→2'b10, 2'b01→2'b01(PRS), 2'b00→2'b00(KEN)
  wire [1:0] la_h2 = (last_a[7:6] == 2'b00) ? 2'b00 :
                     (last_a[7:6] == 2'b01) ? 2'b01 : 2'b10;
  wire [1:0] la_h1 = (last_a[5:4] == 2'b00) ? 2'b00 :
                     (last_a[5:4] == 2'b01) ? 2'b01 : 2'b10;
  wire [1:0] la_h0 = (last_a[3:2] == 2'b00) ? 2'b00 :
                     (last_a[3:2] == 2'b01) ? 2'b01 : 2'b10;
  assign leds = ~{la_h2, la_h1, la_h0};

endmodule
