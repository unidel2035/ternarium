// tritmux.v — Тритный мультиплексор 3→1
//
// Три тритных входа A, B, C (-13..+13).
// Тритный селектор S ∈ {KEN(-1), PRS(0), PLR(+1)} выбирает один.
//
// Богословие: S — воля. A/B/C — три возможности бытия.
//   KEN → A (кенозис: ничто, основание)
//   PRS → B (присутствие: середина, баланс)
//   PLR → C (плерома: полнота, вершина)
//
// UART RX (115200, pin 18) — команды:
//   'a' <v>  — установить вход A, v = '+'/'-'/'0'/'r'/'p'
//   'b' <v>  — установить вход B
//   'c' <v>  — установить вход C
//   's' <v>  — установить селектор S, v = '+'/'-'/'0'
//   '?'      — запросить вывод
//
// UART TX: "MUX S=+: C=+05\r\n" (16 байт)
//   S — символ селектора, выбранный вход (A/B/C), значение ±NN
//
// LED: ~{sel_h2,sel_h1,sel_h0} = ternary(out_idx)

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

// ── Тритный MUX ──────────────────────────────────────────────────────────────

module tritmux (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // Входы A, B, C и селектор S (все как смещённые индексы 0..26)
  reg [4:0] inp_a = 5'd13; // PRS
  reg [4:0] inp_b = 5'd13;
  reg [4:0] inp_c = 5'd13;
  reg [1:0] sel   = 2'b01; // PRS → B

  // Выход MUX
  wire [4:0] mux_out = (sel == 2'b00) ? inp_a :  // KEN → A
                       (sel == 2'b10) ? inp_c :  // PLR → C
                                        inp_b;  // PRS → B

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // Парсер: ждём букву (a/b/c/s) потом значение
  localparam ST_IDLE = 2'd0, ST_VAL_INP = 2'd1, ST_VAL_SEL = 2'd2;
  reg [1:0] parse_st = ST_IDLE;
  reg [1:0] inp_sel  = 2'd0;  // 0=A, 1=B, 2=C

  // Вспомогательная: применить символ тритного значения к регистру 0..26
  // '+' = PLR=+1, '0' = PRS=0, '-' = KEN=-1
  // Также поддержим расширенный ввод через '+'/'-' шаги
  function [4:0] trit_sym_to_idx;
    input [7:0] sym;
    case (sym)
      8'h2B: trit_sym_to_idx = 5'd26;  // '+' → PLR
      8'h30: trit_sym_to_idx = 5'd13;  // '0' → PRS
      8'h2D: trit_sym_to_idx = 5'd0;   // '-' → KEN
      default: trit_sym_to_idx = 5'd13;
    endcase
  endfunction

  reg do_report = 0;

  always @(posedge clk) begin
    do_report <= 0;
    if (rx_ready) begin
      case (parse_st)
        ST_IDLE: begin
          case (rx_data)
            8'h61: begin inp_sel <= 2'd0; parse_st <= ST_VAL_INP; end  // 'a'
            8'h62: begin inp_sel <= 2'd1; parse_st <= ST_VAL_INP; end  // 'b'
            8'h63: begin inp_sel <= 2'd2; parse_st <= ST_VAL_INP; end  // 'c'
            8'h73: parse_st <= ST_VAL_SEL;  // 's'
            8'h3F: begin do_report <= 1; end  // '?'
            default: ;
          endcase
        end
        ST_VAL_INP: begin
          parse_st <= ST_IDLE;
          case (inp_sel)
            2'd0: inp_a <= trit_sym_to_idx(rx_data);
            2'd1: inp_b <= trit_sym_to_idx(rx_data);
            2'd2: inp_c <= trit_sym_to_idx(rx_data);
            default: ;
          endcase
          do_report <= 1;
        end
        ST_VAL_SEL: begin
          parse_st <= ST_IDLE;
          case (rx_data)
            8'h2D: sel <= 2'b00;  // '-' → KEN
            8'h30: sel <= 2'b01;  // '0' → PRS
            8'h2B: sel <= 2'b10;  // '+' → PLR
            default: ;
          endcase
          do_report <= 1;
        end
        default: parse_st <= ST_IDLE;
      endcase
    end
  end

  // ── LED: ternary(mux_out) ────────────────────────────────────────────────
  wire [1:0] h2 = (mux_out >= 5'd18) ? 2'b10 : (mux_out >= 5'd9) ? 2'b01 : 2'b00;
  wire [4:0] r1 = (mux_out >= 5'd18) ? mux_out - 5'd18 :
                  (mux_out >= 5'd9)  ? mux_out - 5'd9  : mux_out;
  wire [1:0] h1 = (r1 >= 5'd6) ? 2'b10 : (r1 >= 5'd3) ? 2'b01 : 2'b00;
  wire [4:0] r0 = (r1 >= 5'd6) ? r1 - 5'd6 : (r1 >= 5'd3) ? r1 - 5'd3 : r1;
  wire [1:0] h0 = (r0 >= 5'd2) ? 2'b10 : (r0 == 5'd1) ? 2'b01 : 2'b00;
  assign leds = ~{h2, h1, h0};

  // ── TX: "MUX S=±: X=±NN\r\n" ─────────────────────────────────────────────
  // Длина: 14 байт (bidx 0..13)
  //   M U X   S = ± :   X = ± N N \r \n
  //   0 1 2 3 4 5 6 7 8 9 ...

  // Вычисление знака и абсолютного значения выхода
  wire        out_neg  = (mux_out < 5'd13);
  wire [4:0]  out_abs  = out_neg ? (5'd13 - mux_out) : (mux_out - 5'd13);
  wire [3:0]  out_tens = (out_abs >= 5'd10) ? 4'd1 : 4'd0;
  wire [3:0]  out_ones = (out_abs >= 5'd10) ? out_abs[3:0] - 4'd10 : out_abs[3:0];

  // Выбранный канал
  wire [7:0] chan_char = (sel == 2'b00) ? 8'h41 : (sel == 2'b10) ? 8'h43 : 8'h42;  // A/B/C
  wire [7:0] sel_char  = (sel == 2'b00) ? 8'h2D : (sel == 2'b10) ? 8'h2B : 8'h30;  // -/+/0

  // Защёлка TX
  reg [7:0] tx_chan = 8'h42, tx_sel = 8'h30;
  reg       tx_neg  = 0;
  reg [3:0] tx_tens = 0, tx_ones = 0;
  reg       tx_trigger = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_report) begin
      tx_chan    <= chan_char;
      tx_sel     <= sel_char;
      tx_neg     <= out_neg;
      tx_tens    <= out_tens;
      tx_ones    <= out_ones;
      tx_trigger <= 1;
    end
  end

  reg [3:0] bidx = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready;

  // "MUX S=x: X=±NN\r\n"
  //  0123456789...
  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      4'd0:  nbyte = 8'h4D;  // 'M'
      4'd1:  nbyte = 8'h55;  // 'U'
      4'd2:  nbyte = 8'h58;  // 'X'
      4'd3:  nbyte = 8'h20;  // ' '
      4'd4:  nbyte = 8'h53;  // 'S'
      4'd5:  nbyte = 8'h3D;  // '='
      4'd6:  nbyte = tx_sel; // -/0/+
      4'd7:  nbyte = 8'h3A;  // ':'
      4'd8:  nbyte = 8'h20;  // ' '
      4'd9:  nbyte = tx_chan; // A/B/C
      4'd10: nbyte = 8'h3D;  // '='
      4'd11: nbyte = tx_neg ? 8'h2D : 8'h2B;
      4'd12: nbyte = 8'h30 + {4'h0, tx_tens};
      4'd13: nbyte = 8'h30 + {4'h0, tx_ones};
      4'd14: nbyte = 8'h0D;
      4'd15: nbyte = 8'h0A;  // (не достигается при bidx==4'd13 последнее)
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == 4'd14) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
