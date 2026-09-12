// trit3count.v — Трёхтритный счётчик: кенозис (-13) → плирома (+13) → кенозис
//
// Богословие: три трита — три ипостаси:
//   trit2 (×9) = Отец — источник и основание
//   trit1 (×3) = Дух  — связь и движение
//   trit0 (×1) = Сын  — явление и воплощение
//
// 27 состояний (-13..+13), 1 сек каждое = 27-секундный цикл вечности.
//
// LED (активные LOW, 2 бита на трит):
//   [pin10,pin11] = trit2  00=-1 01=0 10=+1
//   [pin13,pin14] = trit1
//   [pin15,pin16] = trit0
//
// UART 115200 (pin17, FT2232H Interface B):
//   "V:+13 [+1,+1,+1]\r\n" = 18 байт каждую секунду
//
// Кодирование: 2'b00=-1 | 2'b01=0 | 2'b10=+1

`default_nettype none

// ── Тритный полный сумматор ────────────────────────────────
// a + b + cin → sum + cout
// s = a_int + b_int + cin_int ∈ {-3..+3}
// s=-3: sum=0  carry=-1 | s=-2: sum=+1 carry=-1 | s=-1: sum=-1 carry=0
// s= 0: sum=0  carry= 0 | s=+1: sum=+1 carry= 0
// s=+2: sum=-1 carry=+1 | s=+3: sum= 0 carry=+1
module trit_fa (
  input  wire [1:0] a,
  input  wire [1:0] b,
  input  wire [1:0] cin,
  output reg  [1:0] sum,
  output reg  [1:0] cout
);
  reg signed [2:0] s;
  always @(*) begin
    s = ((a   == 2'b00) ? -3'sd1 : (a   == 2'b10) ? 3'sd1 : 3'sd0)
      + ((b   == 2'b00) ? -3'sd1 : (b   == 2'b10) ? 3'sd1 : 3'sd0)
      + ((cin == 2'b00) ? -3'sd1 : (cin == 2'b10) ? 3'sd1 : 3'sd0);
    case (s)
      -3'sd3: begin sum = 2'b01; cout = 2'b00; end //  0 - 3
      -3'sd2: begin sum = 2'b10; cout = 2'b00; end // +1 - 3
      -3'sd1: begin sum = 2'b00; cout = 2'b01; end // -1
       3'sd0: begin sum = 2'b01; cout = 2'b01; end //  0
       3'sd1: begin sum = 2'b10; cout = 2'b01; end // +1
       3'sd2: begin sum = 2'b00; cout = 2'b10; end // -1 + 3
       3'sd3: begin sum = 2'b01; cout = 2'b10; end //  0 + 3
      default: begin sum = 2'b01; cout = 2'b01; end
    endcase
  end
endmodule

// ── Трёхтритный рябой сумматор ─────────────────────────────
// a[5:4]=t2 a[3:2]=t1 a[1:0]=t0 (t0 — младший трит)
// s = a + b (с нулевым переносом на входе)
// overflow: если cout != 0 (|a+b| > 13)
module trit3_add (
  input  wire [5:0] a,
  input  wire [5:0] b,
  output wire [5:0] s,
  output wire [1:0] cout    // перенос из старшего трита
);
  wire [1:0] c0, c1;

  // LSB сначала
  trit_fa fa0 (.a(a[1:0]), .b(b[1:0]), .cin(2'b01), .sum(s[1:0]), .cout(c0));
  trit_fa fa1 (.a(a[3:2]), .b(b[3:2]), .cin(c0),    .sum(s[3:2]), .cout(c1));
  trit_fa fa2 (.a(a[5:4]), .b(b[5:4]), .cin(c1),    .sum(s[5:4]), .cout(cout));
endmodule

// ── UART TX: 115200 бод @ 50 МГц ──────────────────────────
module uart_tx (
  input  wire       clk,
  input  wire [7:0] data,
  input  wire       start,
  output reg        tx    = 1,
  output wire       ready
);
  localparam CLKDIV = 434;

  reg [7:0] sr  = 8'hFF;
  reg [7:0] div = 0;
  reg [3:0] cnt = 0;

  assign ready = (cnt == 0);

  always @(posedge clk) begin
    if (cnt == 0) begin
      if (start) begin
        sr <= data; cnt <= 9; tx <= 0; div <= 0;
      end
    end else begin
      if (div == CLKDIV - 1) begin
        div <= 0;
        if (cnt == 1) begin tx <= 1; cnt <= 0; end
        else begin tx <= sr[0]; sr <= {1'b1, sr[7:1]}; cnt <= cnt - 1; end
      end else div <= div + 1;
    end
  end
endmodule

// ── Главный модуль ─────────────────────────────────────────
module trit3count (
  input  wire       clk,
  output wire [5:0] leds,
  output wire       uart_tx
);

  // Делитель 50 МГц → 1 Гц
  reg [24:0] div1 = 0;
  reg        tick = 0;
  always @(posedge clk) begin
    tick <= (div1 == 25'd26_999_999);
    div1 <= (div1 == 25'd26_999_999) ? 25'd0 : div1 + 25'd1;
  end

  // Трёхтритный счётчик: начало с -13 = {00,00,00}
  reg  [5:0] cnt = 6'b00_00_00;
  wire [5:0] next_cnt;
  wire [1:0] overflow; // естественный переход +13 → -13

  trit3_add adder (
    .a   (cnt),
    .b   (6'b01_01_10),  // +1 = {trit2=0, trit1=0, trit0=+1}
    .s   (next_cnt),
    .cout(overflow)
  );

  always @(posedge clk) begin
    if (tick) cnt <= next_cnt;
  end

  // LED: активные LOW — [t2₁,t2₀, t1₁,t1₀, t0₁,t0₀]
  assign leds = ~cnt;

  // ── UART: "V:+13 [+1,+1,+1]\r\n" = 18 байт ───────────
  // Защёлкиваем при каждом тике
  reg [5:0] lat = 6'b00_00_00; // {t2,t1,t0}
  always @(posedge clk) begin
    if (tick) lat <= next_cnt;
  end

  // Вычисляем десятичное значение из трёх тритов
  wire [1:0] lt2 = lat[5:4], lt1 = lat[3:2], lt0 = lat[1:0];

  wire signed [4:0] val =
      ((lt2 == 2'b10) ? 5'sd9 : (lt2 == 2'b00) ? -5'sd9 : 5'sd0)
    + ((lt1 == 2'b10) ? 5'sd3 : (lt1 == 2'b00) ? -5'sd3 : 5'sd0)
    + ((lt0 == 2'b10) ? 5'sd1 : (lt0 == 2'b00) ? -5'sd1 : 5'sd0);

  wire        sign_neg = val[4];          // 1 если отрицательное
  wire [4:0]  abs_v    = sign_neg ? (~val + 5'd1) : val; // |val|
  wire        tens_bit = (abs_v >= 5'd10);
  wire [3:0]  ones_v   = tens_bit ? abs_v[3:0] - 4'd10 : abs_v[3:0];

  // Вспомогательные функции знака/цифры трита
  function [7:0] t_sign;
    input [1:0] t;
    begin
      case (t)
        2'b00: t_sign = 8'h2D; // '-'
        2'b01: t_sign = 8'h20; // ' '
        2'b10: t_sign = 8'h2B; // '+'
        default: t_sign = 8'h3F;
      endcase
    end
  endfunction

  function [7:0] t_dig;
    input [1:0] t;
    begin t_dig = (t == 2'b01) ? 8'h30 : 8'h31; end
  endfunction

  // Байт по индексу (0..17):
  // "V:+13 [+1,+1,+1]\r\n"
  reg [4:0] byte_idx  = 0;
  reg       sending   = 0;
  reg       send_pulse = 0;
  reg [7:0] send_byte = 0;
  wire      uart_ready;

  reg [7:0] next_byte;
  always @(*) begin
    case (byte_idx)
      5'd0:  next_byte = 8'h56;                  // 'V'
      5'd1:  next_byte = 8'h3A;                  // ':'
      5'd2:  next_byte = sign_neg ? 8'h2D : 8'h2B; // '+'/'-'
      5'd3:  next_byte = tens_bit ? 8'h31 : 8'h30; // '1'/'0'
      5'd4:  next_byte = 8'h30 + {4'b0, ones_v}; // '0'-'9'
      5'd5:  next_byte = 8'h20;                  // ' '
      5'd6:  next_byte = 8'h5B;                  // '['
      5'd7:  next_byte = t_sign(lt2);
      5'd8:  next_byte = t_dig(lt2);
      5'd9:  next_byte = 8'h2C;                  // ','
      5'd10: next_byte = t_sign(lt1);
      5'd11: next_byte = t_dig(lt1);
      5'd12: next_byte = 8'h2C;                  // ','
      5'd13: next_byte = t_sign(lt0);
      5'd14: next_byte = t_dig(lt0);
      5'd15: next_byte = 8'h5D;                  // ']'
      5'd16: next_byte = 8'h0D;                  // '\r'
      5'd17: next_byte = 8'h0A;                  // '\n'
      default: next_byte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    send_pulse <= 1'b0;
    if (tick) begin
      sending  <= 1'b1;
      byte_idx <= 5'd0;
    end else if (sending && uart_ready && !send_pulse) begin
      send_byte  <= next_byte;
      send_pulse <= 1'b1;
      if (byte_idx == 5'd17) begin
        sending  <= 1'b0;
        byte_idx <= 5'd0;
      end else begin
        byte_idx <= byte_idx + 5'd1;
      end
    end
  end

  uart_tx utx (
    .clk   (clk),
    .data  (send_byte),
    .start (send_pulse),
    .tx    (uart_tx),
    .ready (uart_ready)
  );

endmodule
