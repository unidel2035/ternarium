// uartping.v — Минимальный TX-only тест
// Шлёт байт 0x55 ('U') каждые 100 мс. Только проверка что P15 → /dev/ttyUSB1 работает.

`default_nettype none

module uartping (
  input  wire clk,        // 50 МГц
  output reg  uart_tx = 1,
  output wire [5:0] leds
);

  localparam CLKDIV = 434;          // 50e6 / 115200

  reg [22:0] tick = 0;              // 100 мс ≈ 5_000_000 тактов
  reg        send_now = 0;
  reg [3:0]  bit_idx = 0;           // 0..9 (start + 8 data + stop = 10 bits)
  reg [9:0]  shift = 10'h3FF;       // idle = all 1
  reg [9:0]  baud_cnt = 0;
  reg        tx_busy = 0;

  always @(posedge clk) begin
    // 100мс trigger
    if (tick == 23'd5_000_000) begin
      tick <= 0;
      send_now <= 1;
    end else begin
      tick <= tick + 1'b1;
      send_now <= 0;
    end

    // запуск передачи
    if (send_now && !tx_busy) begin
      shift   <= {1'b1, 8'h55, 1'b0};   // [stop=1][data 'U']{LSB=0...MSB=0}[start=0]
      bit_idx <= 0;
      baud_cnt <= 0;
      tx_busy <= 1;
      uart_tx <= 0;                      // start bit immediately
    end else if (tx_busy) begin
      if (baud_cnt == CLKDIV - 1) begin
        baud_cnt <= 0;
        if (bit_idx == 9) begin
          tx_busy <= 0;
          uart_tx <= 1;
        end else begin
          bit_idx <= bit_idx + 1'b1;
          uart_tx <= shift[1];
          shift   <= {1'b1, shift[9:1]};
        end
      end else baud_cnt <= baud_cnt + 1'b1;
    end
  end

  // pulse LED при отправке (active low)
  reg [22:0] led_cnt = 0;
  always @(posedge clk) begin
    if (send_now) led_cnt <= 23'd5_000_000;
    else if (led_cnt > 0) led_cnt <= led_cnt - 1'b1;
  end
  assign leds = ~{6{led_cnt > 0}};
endmodule
