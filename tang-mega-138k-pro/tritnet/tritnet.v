// tritnet.v — Тритный аппаратный перцептрон
//
// Однослойный перцептрон: 3 тритных входа, 3 веса, тритный выход.
//
// Богословие: нейрон — суждение. Три входа — три свидетеля (Ин 5:8).
// Вес — доверие свидетелю. Выход: KEN (нет), PRS (неизвестно), PLR (да).
//
// Математика:
//   x0,x1,x2 ∈ {-1,0,+1},  w0,w1,w2 ∈ {-1,0,+1}
//   sum = w0·x0 + w1·x1 + w2·x2 ∈ {-3..+3}
//   out = sign(sum)
//
// UART RX (115200, pin 18):
//   'x' N T  — вход N (0/1/2), T = '+'/'-'/'0'
//   'w' N T  — вес N
//   '?'      — вычислить и вывести
//   't' T    — шаг обучения (Perceptron Rule, цель T)
//
// UART TX: "N:[x0x1x2] W:[w0w1w2] S:±N O:±\r\n" (26 байт)
//
// LED: ~{net_out, wgt[0], wgt[1]}

`default_nettype none

// ── UART TX ──────────────────────────────────────────────────────────────────

module uart_tx (
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

// ── UART RX ──────────────────────────────────────────────────────────────────

module uart_rx (
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

// ── Тритный перцептрон ────────────────────────────────────────────────────────

module tritnet (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // Входы и веса: 2'b00=KEN(-1), 2'b01=PRS(0), 2'b10=PLR(+1)
  reg [1:0] inp [0:2];
  reg [1:0] wgt [0:2];
  initial begin
    inp[0] = 2'b01; inp[1] = 2'b01; inp[2] = 2'b01;
    wgt[0] = 2'b10; wgt[1] = 2'b10; wgt[2] = 2'b10;
  end

  // ── Взвешенная сумма ──────────────────────────────────────────────────────
  wire signed [1:0] xs0 = $signed({1'b0, inp[0]}) - 2'sd1;
  wire signed [1:0] xs1 = $signed({1'b0, inp[1]}) - 2'sd1;
  wire signed [1:0] xs2 = $signed({1'b0, inp[2]}) - 2'sd1;
  wire signed [1:0] ws0 = $signed({1'b0, wgt[0]}) - 2'sd1;
  wire signed [1:0] ws1 = $signed({1'b0, wgt[1]}) - 2'sd1;
  wire signed [1:0] ws2 = $signed({1'b0, wgt[2]}) - 2'sd1;

  wire signed [2:0] p0 = xs0 * ws0;
  wire signed [2:0] p1 = xs1 * ws1;
  wire signed [2:0] p2 = xs2 * ws2;
  wire signed [3:0] total = $signed({p0[2], p0}) +
                             $signed({p1[2], p1}) +
                             $signed({p2[2], p2});
  wire [1:0] net_out = (total > 0) ? 2'b10 : (total < 0) ? 2'b00 : 2'b01;

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  localparam ST_IDLE  = 3'd0,
             ST_X_N   = 3'd1,
             ST_X_T   = 3'd2,
             ST_W_N   = 3'd3,
             ST_W_T   = 3'd4,
             ST_TRAIN = 3'd5;

  reg [2:0] parse_st = ST_IDLE;
  reg [1:0] cur_n    = 0;
  reg       do_calc  = 0;

  function [1:0] sym_to_trit;
    input [7:0] s;
    case (s)
      8'h2B: sym_to_trit = 2'b10;
      8'h2D: sym_to_trit = 2'b00;
      default: sym_to_trit = 2'b01;
    endcase
  endfunction

  always @(posedge clk) begin
    do_calc <= 0;
    if (rx_ready) begin
      case (parse_st)
        ST_IDLE: case (rx_data)
          8'h78: parse_st <= ST_X_N;
          8'h77: parse_st <= ST_W_N;
          8'h3F: begin do_calc <= 1; end
          8'h74: parse_st <= ST_TRAIN;
          default: ;
        endcase
        ST_X_N: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h32)
            begin cur_n <= rx_data[1:0]; parse_st <= ST_X_T; end
          else parse_st <= ST_IDLE;
        end
        ST_X_T: begin
          parse_st <= ST_IDLE;
          case (cur_n)
            2'd0: inp[0] <= sym_to_trit(rx_data);
            2'd1: inp[1] <= sym_to_trit(rx_data);
            2'd2: inp[2] <= sym_to_trit(rx_data);
            default: ;
          endcase
          do_calc <= 1;
        end
        ST_W_N: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h32)
            begin cur_n <= rx_data[1:0]; parse_st <= ST_W_T; end
          else parse_st <= ST_IDLE;
        end
        ST_W_T: begin
          parse_st <= ST_IDLE;
          case (cur_n)
            2'd0: wgt[0] <= sym_to_trit(rx_data);
            2'd1: wgt[1] <= sym_to_trit(rx_data);
            2'd2: wgt[2] <= sym_to_trit(rx_data);
            default: ;
          endcase
          do_calc <= 1;
        end
        ST_TRAIN: begin
          parse_st <= ST_IDLE;
          // Perceptron rule: если target=PLR и out≠PLR → усилить вдоль x
          if ((rx_data == 8'h2B) && (net_out != 2'b10)) begin
            if (xs0 > 0 && wgt[0] < 2'b10) wgt[0] <= wgt[0] + 2'd1;
            if (xs0 < 0 && wgt[0] > 2'b00) wgt[0] <= wgt[0] - 2'd1;
            if (xs1 > 0 && wgt[1] < 2'b10) wgt[1] <= wgt[1] + 2'd1;
            if (xs1 < 0 && wgt[1] > 2'b00) wgt[1] <= wgt[1] - 2'd1;
            if (xs2 > 0 && wgt[2] < 2'b10) wgt[2] <= wgt[2] + 2'd1;
            if (xs2 < 0 && wgt[2] > 2'b00) wgt[2] <= wgt[2] - 2'd1;
          end else if ((rx_data == 8'h2D) && (net_out != 2'b00)) begin
            if (xs0 > 0 && wgt[0] > 2'b00) wgt[0] <= wgt[0] - 2'd1;
            if (xs0 < 0 && wgt[0] < 2'b10) wgt[0] <= wgt[0] + 2'd1;
            if (xs1 > 0 && wgt[1] > 2'b00) wgt[1] <= wgt[1] - 2'd1;
            if (xs1 < 0 && wgt[1] < 2'b10) wgt[1] <= wgt[1] + 2'd1;
            if (xs2 > 0 && wgt[2] > 2'b00) wgt[2] <= wgt[2] - 2'd1;
            if (xs2 < 0 && wgt[2] < 2'b10) wgt[2] <= wgt[2] + 2'd1;
          end
          do_calc <= 1;
        end
        default: parse_st <= ST_IDLE;
      endcase
    end
  end

  // ── LED ───────────────────────────────────────────────────────────────────
  assign leds = ~{net_out, wgt[0], wgt[1]};

  // ── TX: "N:[x0x1x2] W:[w0w1w2] S:±N O:±\r\n" (26 байт, bidx 0..25) ─────
  function [7:0] trit_ch;
    input [1:0] v;
    case (v)
      2'b10: trit_ch = 8'h2B;
      2'b00: trit_ch = 8'h2D;
      default: trit_ch = 8'h30;
    endcase
  endfunction

  reg [1:0] tx_x0=0, tx_x1=0, tx_x2=0;
  reg [1:0] tx_w0=0, tx_w1=0, tx_w2=0;
  reg [1:0] tx_out = 2'b01;
  reg signed [3:0] tx_sum = 0;
  reg       tx_trigger = 0;

  wire        sum_neg = (tx_sum < 0);
  wire [3:0]  sum_abs = sum_neg ? (-tx_sum[3:0]) : tx_sum[3:0];

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_calc) begin
      tx_x0 <= inp[0]; tx_x1 <= inp[1]; tx_x2 <= inp[2];
      tx_w0 <= wgt[0]; tx_w1 <= wgt[1]; tx_w2 <= wgt[2];
      tx_out <= net_out;
      tx_sum <= total;
      tx_trigger <= 1;
    end
  end

  reg [5:0] bidx = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      6'd0:  nbyte = 8'h4E;  // 'N'
      6'd1:  nbyte = 8'h3A;
      6'd2:  nbyte = 8'h5B;  // '['
      6'd3:  nbyte = trit_ch(tx_x0);
      6'd4:  nbyte = trit_ch(tx_x1);
      6'd5:  nbyte = trit_ch(tx_x2);
      6'd6:  nbyte = 8'h5D;  // ']'
      6'd7:  nbyte = 8'h20;
      6'd8:  nbyte = 8'h57;  // 'W'
      6'd9:  nbyte = 8'h3A;
      6'd10: nbyte = 8'h5B;
      6'd11: nbyte = trit_ch(tx_w0);
      6'd12: nbyte = trit_ch(tx_w1);
      6'd13: nbyte = trit_ch(tx_w2);
      6'd14: nbyte = 8'h5D;
      6'd15: nbyte = 8'h20;
      6'd16: nbyte = 8'h53;  // 'S'
      6'd17: nbyte = 8'h3A;
      6'd18: nbyte = sum_neg ? 8'h2D : 8'h2B;
      6'd19: nbyte = 8'h30 + {4'h0, sum_abs[3:0]};
      6'd20: nbyte = 8'h20;
      6'd21: nbyte = 8'h4F;  // 'O'
      6'd22: nbyte = 8'h3A;
      6'd23: nbyte = trit_ch(tx_out);
      6'd24: nbyte = 8'h0D;
      6'd25: nbyte = 8'h0A;
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == 6'd25) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
