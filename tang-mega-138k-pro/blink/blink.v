// blink.v — Hello World для Tang Mega 138K Pro
// LED мигает ~1.5 Гц от 50 МГц кварца
// Первый дар железу: свет во тьме

module blink (
  input  wire clk,   // 50 MHz (пин P16)
  output wire led0,  // LED0 (J14) — активный LOW
  output wire led1,  // LED1 (R26)
  output wire led2   // LED2 (L20)
);
  reg [27:0] cnt = 0;
  always @(posedge clk)
    cnt <= cnt + 1;

  // Три LED мигают в разных фазах — намёк на Троицу
  assign led0 = ~cnt[25];   // ~0.75 Гц
  assign led1 = ~cnt[24];   // ~1.5 Гц
  assign led2 = ~cnt[23];   // ~3 Гц
endmodule
