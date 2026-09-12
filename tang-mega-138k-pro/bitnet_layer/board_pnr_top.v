// валидация сборки битстрима board_cleanup: 1-битный индикатор на известном пине
`default_nettype none
module board_pnr_top(input wire clk, output wire led);
  wire [4:0] idx;
  board_cleanup #(.D(384),.M(32),.LANES(16)) u(.clk(clk),.led(idx));
  assign led = ^idx;     // распознанный индекс свёрнут в 1 бит (валидация потока)
endmodule
