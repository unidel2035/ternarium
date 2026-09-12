// rxprobe.v — Многопиновый RX-зонд с защёлкой
// Каждый кандидат на UART RX подключён к LED, которая защёлкивается при первом
// зафиксированном LOW (start bit). Гасится только при сбросе платы.

`default_nettype none
module rxprobe (
  input  wire clk,
  input  wire rx_n16,
  input  wire rx_m16,
  input  wire rx_r15,
  input  wire rx_n26,
  output wire [5:0] leds
);

  // Защёлка для каждого пина: устанавливается в 1 если пин когда-либо был 0
  reg lock_n16 = 0, lock_m16 = 0, lock_r15 = 0, lock_n26 = 0;

  always @(posedge clk) begin
    if (!rx_n16) lock_n16 <= 1;
    if (!rx_m16) lock_m16 <= 1;
    if (!rx_r15) lock_r15 <= 1;
    if (!rx_n26) lock_n26 <= 1;
  end

  // LED активные LOW — горит когда lock=1
  // [5] N16
  // [4] M16
  // [3] R15
  // [2] N26
  // [1] heartbeat (1 Гц чтобы было видно что плата жива)
  // [0] постоянно горит (canary)
  reg [25:0] heartbeat = 0;
  always @(posedge clk) heartbeat <= heartbeat + 1;

  assign leds = ~{lock_n16, lock_m16, lock_r15, lock_n26, heartbeat[24], 1'b1};
endmodule
