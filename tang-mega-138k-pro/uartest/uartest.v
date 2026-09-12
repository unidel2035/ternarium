// uartest.v — Минимальный UART тест
// При получении любого байта на RX — переключает LED
// Эхо: отправляет полученный байт обратно на TX
// Тест для определения правильных UART пинов

`default_nettype none

module uartest (
  input  wire clk,     // 50 MHz (pin 52)
  input  wire rx,      // UART RX
  output reg  tx = 1,  // UART TX
  output reg  [5:0] leds = 6'b111111  // все LED выключены (active low)
);

  // ── UART RX ───────────────────────────────────────────────────────────
  localparam CLKDIV = 434;  // 50 MHz / 115200
  reg [7:0] rx_sr = 0;
  reg [7:0] rx_div = 0;
  reg [3:0] rx_cnt = 0;
  reg       rx_active = 0;
  reg       rx_ready = 0;
  reg [7:0] rx_data = 0;

  always @(posedge clk) begin
    rx_ready <= 0;
    if (!rx_active) begin
      if (!rx) begin rx_active <= 1; rx_div <= CLKDIV/2; rx_cnt <= 8; end
    end else begin
      if (rx_div == 0) begin
        rx_div <= CLKDIV - 1;
        if (rx_cnt == 0) begin rx_data <= rx_sr; rx_ready <= 1; rx_active <= 0; end
        else begin rx_sr <= {rx, rx_sr[7:1]}; rx_cnt <= rx_cnt - 1; end
      end else rx_div <= rx_div - 1;
    end
  end

  // ── При приёме — переключить LED и отправить эхо ──────────────────────
  reg [5:0] led_state = 6'b111111;
  reg [2:0] rx_count = 0;

  // TX state
  reg [7:0] tx_sr = 8'hFF;
  reg [7:0] tx_div = 0;
  reg [3:0] tx_cnt = 0;

  always @(posedge clk) begin
    if (rx_ready) begin
      // Toggle LEDs based on received count
      rx_count <= rx_count + 1;
      led_state <= ~(6'b1 << rx_count[2:0]);

      // Start echo TX
      if (tx_cnt == 0) begin
        tx_sr <= rx_data;
        tx_cnt <= 9;
        tx <= 0;  // start bit
        tx_div <= 0;
      end
    end

    // TX shift
    if (tx_cnt != 0) begin
      if (tx_div == CLKDIV-1) begin
        tx_div <= 0;
        if (tx_cnt == 1) begin tx <= 1; tx_cnt <= 0; end
        else begin tx <= tx_sr[0]; tx_sr <= {1'b1, tx_sr[7:1]}; tx_cnt <= tx_cnt-1; end
      end else tx_div <= tx_div + 1;
    end
  end

  always @(*) leds = led_state;

endmodule
