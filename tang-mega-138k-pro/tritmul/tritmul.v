// tritmul.v — Тритное умножение: исхождение Духа как произведение
//
// Богословие: (-1)×(-1)=+1 — отрицание отрицания есть утверждение.
// Это онтологически: зло не может умножить зло в зло,
// отступление от отступления возвращает к бытию.
// 0×x=0 — ничто умножает любое на ничто. Кенозис абсолютный.
// +1×+1=+1 — дар рождает дар. Плирома воспроизводит себя.
//
// Таблица 3×3 = 9 произведений, 1 сек каждое.
//
// LED (активные LOW):
//   [10,11] = A   [13,14] = B   [15,16] = PRODUCT
//
// UART: "A:-1 x B:+1 = P:-1\r\n" = 20 байт

`default_nettype none

// ── Тритный умножитель: однотактный LUT 3×3 ──────────────
// (-1)*(-1)=+1  (-1)*0=0  (-1)*(+1)=-1
//    0 *(-1)= 0    0 *0=0    0 *(+1)= 0
// (+1)*(-1)=-1 (+1)*0=0  (+1)*(+1)=+1
module trit_mul (
  input  wire [1:0] a,
  input  wire [1:0] b,
  output reg  [1:0] p
);
  always @(*) begin
    if (a == 2'b01 || b == 2'b01)
      p = 2'b01;                      // 0 * x = 0 или x * 0 = 0
    else if (a == b)
      p = 2'b10;                      // одинаковые знаки → +1
    else
      p = 2'b00;                      // разные знаки → -1
  end
endmodule

// ── UART TX: 115200 @ 50 МГц ─────────────────────────────
module uart_tx (
  input  wire       clk,
  input  wire [7:0] data,
  input  wire       start,
  output reg        tx    = 1,
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

// ── Главный модуль ─────────────────────────────────────────
module tritmul (
  input  wire       clk,
  output wire [5:0] leds,
  output wire       uart_tx
);

  // 1 Гц
  reg [24:0] div1 = 0; reg tick = 0;
  always @(posedge clk) begin
    tick <= (div1 == 25'd26_999_999);
    div1 <= (div1 == 25'd26_999_999) ? 25'd0 : div1 + 25'd1;
  end

  // 9 комбинаций (a,b)
  reg [3:0] state = 0;
  always @(posedge clk) begin
    if (tick) state <= (state == 4'd8) ? 4'd0 : state + 4'd1;
  end

  reg [1:0] a_t, b_t;
  always @(*) begin
    case (state)
      4'd0: begin a_t=2'b00; b_t=2'b00; end // -1 × -1
      4'd1: begin a_t=2'b00; b_t=2'b01; end // -1 ×  0
      4'd2: begin a_t=2'b00; b_t=2'b10; end // -1 × +1
      4'd3: begin a_t=2'b01; b_t=2'b00; end //  0 × -1
      4'd4: begin a_t=2'b01; b_t=2'b01; end //  0 ×  0
      4'd5: begin a_t=2'b01; b_t=2'b10; end //  0 × +1
      4'd6: begin a_t=2'b10; b_t=2'b00; end // +1 × -1
      4'd7: begin a_t=2'b10; b_t=2'b01; end // +1 ×  0
      4'd8: begin a_t=2'b10; b_t=2'b10; end // +1 × +1
      default: begin a_t=2'b01; b_t=2'b01; end
    endcase
  end

  wire [1:0] prod;
  trit_mul mul (.a(a_t), .b(b_t), .p(prod));

  assign leds = ~{a_t, b_t, prod};

  // UART: "A:-1 x B:+1 = P:-1\r\n" = 20 байт
  // 0:'A' 1:':' 2:s(a) 3:d(a) 4:' ' 5:'x' 6:' '
  // 7:'B' 8:':' 9:s(b) 10:d(b) 11:' ' 12:'=' 13:' '
  // 14:'P' 15:':' 16:s(p) 17:d(p) 18:'\r' 19:'\n'

  reg [1:0] la, lb, lp;
  always @(posedge clk) begin
    if (tick) begin la <= a_t; lb <= b_t; lp <= prod; end
  end

  function [7:0] ts; input [1:0] t;
    begin case(t) 2'b00:ts=8'h2D; 2'b01:ts=8'h20; 2'b10:ts=8'h2B; default:ts=8'h3F; endcase end
  endfunction
  function [7:0] td; input [1:0] t;
    begin td = (t==2'b01) ? 8'h30 : 8'h31; end
  endfunction

  reg [4:0] bidx=0; reg sending=0,spulse=0; reg [7:0] sbyte=0;
  wire uready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      5'd0:  nbyte=8'h41;    // 'A'
      5'd1:  nbyte=8'h3A;    // ':'
      5'd2:  nbyte=ts(la);
      5'd3:  nbyte=td(la);
      5'd4:  nbyte=8'h20;    // ' '
      5'd5:  nbyte=8'h78;    // 'x'
      5'd6:  nbyte=8'h20;    // ' '
      5'd7:  nbyte=8'h42;    // 'B'
      5'd8:  nbyte=8'h3A;    // ':'
      5'd9:  nbyte=ts(lb);
      5'd10: nbyte=td(lb);
      5'd11: nbyte=8'h20;    // ' '
      5'd12: nbyte=8'h3D;    // '='
      5'd13: nbyte=8'h20;    // ' '
      5'd14: nbyte=8'h50;    // 'P'
      5'd15: nbyte=8'h3A;    // ':'
      5'd16: nbyte=ts(lp);
      5'd17: nbyte=td(lp);
      5'd18: nbyte=8'h0D;    // '\r'
      5'd19: nbyte=8'h0A;    // '\n'
      default: nbyte=8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 1'b0;
    if (tick) begin sending<=1; bidx<=0; end
    else if (sending && uready && !spulse) begin
      sbyte<=nbyte; spulse<=1;
      if (bidx==5'd19) begin sending<=0; bidx<=0; end
      else bidx<=bidx+1;
    end
  end

  uart_tx utx(.clk(clk),.data(sbyte),.start(spulse),.tx(uart_tx),.ready(uready));
endmodule
