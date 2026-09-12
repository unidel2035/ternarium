// tritseq.v — Тритный секвенсор 27 шагов
//
// 27 ячеек памяти (каждая хранит тритное значение -13..+13).
// Секвенсор обходит шаги 0..26 с настраиваемым темпом.
// На каждом шаге выводит значение через UART и на LED.
//
// Богословие: 27 = 3³ — полный тернарный цикл.
// Секвенсор — это литургия: каждый шаг проходит KEN→PRS→PLR и возвращается.
//
// UART RX (115200, pin 18) — команды:
//   'W' AA T  — записать тритный символ T в шаг AA (00..26)
//   'P'       — play (запустить/возобновить)
//   'S'       — stop (пауза)
//   'R'       — rewind (вернуться к шагу 0)
//   '+'       — ускорить темп × 2
//   '-'       — замедлить темп × 2
//   '0'       — нормальный темп (500 мс/шаг)
//   'D'       — дамп всей последовательности
//
// UART TX:
//   На каждом шаге: "S[AA]:T V:±NN\r\n" (14 байт)
//   После D:        "D:TTT...T\r\n" (31 байт)
//
// LED: ~{h2,h1,h0} текущего значения

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

// ── Тритный секвенсор ─────────────────────────────────────────────────────────

module tritseq (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // ── Память 27 шагов ───────────────────────────────────────────────────────
  reg [4:0] seq [0:26];  // смещённые значения 0..26 (PRS=13)
  integer k;
  initial begin
    // По умолчанию: тритная шкала --- ... 000 ... +++
    for (k = 0; k < 27; k = k+1) seq[k] = k[4:0];
  end

  // ── Темп ──────────────────────────────────────────────────────────────────
  // Нормальный темп: 500 мс = 13_500_000 тактов
  // speed: 0=медленно(1с), 1=норма(500мс), 2=быстро(250мс), 3=очень быстро(125мс)
  reg [1:0] speed  = 2'd1;
  reg       playing = 0;
  reg [4:0] step   = 5'd0;

  wire [23:0] period = (speed == 2'd0) ? 24'd26999999 :
                       (speed == 2'd2) ? 24'd6749999  :
                       (speed == 2'd3) ? 24'd3374999  :
                                         24'd13499999;

  reg [23:0] div_cnt = 0;
  reg        tick    = 0;
  always @(posedge clk) begin
    tick <= 0;
    if (playing) begin
      if (div_cnt >= period) begin
        div_cnt <= 0;
        tick    <= 1;
      end else div_cnt <= div_cnt + 1;
    end else div_cnt <= 0;
  end

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // Парсер команд
  localparam ST_IDLE = 2'd0, ST_W_A1 = 2'd1, ST_W_A2 = 2'd2, ST_W_T = 2'd3;
  reg [1:0] parse_st = ST_IDLE;
  reg [3:0] dig1     = 0;
  reg [4:0] addr_acc = 0;

  reg do_step   = 0;  // новый шаг секвенсора
  reg do_dump   = 0;

  always @(posedge clk) begin
    do_step <= 0;
    do_dump <= 0;

    // Тик секвенсора
    if (tick) begin
      step    <= (step == 5'd26) ? 5'd0 : step + 5'd1;
      do_step <= 1;
    end

    if (rx_ready) begin
      case (parse_st)
        ST_IDLE: case (rx_data)
          8'h57: parse_st <= ST_W_A1;  // 'W'
          8'h50: begin playing <= 1; end  // 'P'
          8'h53: begin playing <= 0; end  // 'S'
          8'h52: begin step <= 5'd0; do_step <= 1; end  // 'R'
          8'h2B: speed <= (speed < 2'd3) ? speed + 2'd1 : 2'd3;  // '+'
          8'h2D: speed <= (speed > 2'd0) ? speed - 2'd1 : 2'd0;  // '-'
          8'h30: speed <= 2'd1;   // '0'
          8'h44: do_dump <= 1;    // 'D'
          default: ;
        endcase
        ST_W_A1: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h39) begin
            dig1 <= rx_data[3:0]; parse_st <= ST_W_A2;
          end else parse_st <= ST_IDLE;
        end
        ST_W_A2: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h39) begin
            addr_acc <= dig1 * 4'd10 + rx_data[3:0];
            parse_st <= ST_W_T;
          end else parse_st <= ST_IDLE;
        end
        ST_W_T: begin
          parse_st <= ST_IDLE;
          if (addr_acc <= 5'd26) begin
            case (rx_data)
              8'h2B: seq[addr_acc] <= 5'd26;  // '+' → PLR
              8'h30: seq[addr_acc] <= 5'd13;  // '0' → PRS
              8'h2D: seq[addr_acc] <= 5'd0;   // '-' → KEN
              default: ;
            endcase
          end
        end
        default: parse_st <= ST_IDLE;
      endcase
    end
  end

  // Текущее значение в шаге
  wire [4:0] cur_val = seq[step];

  // ── LED ───────────────────────────────────────────────────────────────────
  wire [1:0] h2 = (cur_val >= 5'd18) ? 2'b10 : (cur_val >= 5'd9) ? 2'b01 : 2'b00;
  wire [4:0] r1 = (cur_val >= 5'd18) ? cur_val - 5'd18 :
                  (cur_val >= 5'd9)  ? cur_val - 5'd9  : cur_val;
  wire [1:0] h1 = (r1 >= 5'd6) ? 2'b10 : (r1 >= 5'd3) ? 2'b01 : 2'b00;
  wire [4:0] r0 = (r1 >= 5'd6) ? r1 - 5'd6 : (r1 >= 5'd3) ? r1 - 5'd3 : r1;
  wire [1:0] h0 = (r0 >= 5'd2) ? 2'b10 : (r0 == 5'd1) ? 2'b01 : 2'b00;
  assign leds = ~{h2, h1, h0};

  // ── TX машина ─────────────────────────────────────────────────────────────
  // Режимы: 0=шаг "S[AA]:T V:±NN\r\n" (14 байт), 1=дамп "D:...\r\n" (31 байт)
  reg tx_mode = 0;

  // Вычисление знака и абсолютного значения
  wire        val_neg  = (cur_val < 5'd13);
  wire [4:0]  val_abs  = val_neg ? (5'd13 - cur_val) : (cur_val - 5'd13);
  wire [3:0]  val_tens = (val_abs >= 5'd10) ? 4'd1 : 4'd0;
  wire [3:0]  val_ones = (val_abs >= 5'd10) ? val_abs[3:0] - 4'd10 : val_abs[3:0];

  function [7:0] trit_char;
    input [4:0] v;
    trit_char = (v == 5'd26) ? 8'h2B : (v == 5'd0) ? 8'h2D : 8'h30;
  endfunction

  // Защёлка
  reg [4:0] tx_step = 0;
  reg [4:0] tx_val  = 5'd13;
  reg       tx_neg  = 0;
  reg [3:0] tx_tens = 0, tx_ones = 0;
  reg       tx_trigger = 0;
  reg       tx_dump    = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    tx_dump    <= 0;
    if (do_step) begin
      tx_mode  <= 0;
      tx_step  <= step;
      tx_val   <= cur_val;
      tx_neg   <= val_neg;
      tx_tens  <= val_tens;
      tx_ones  <= val_ones;
      tx_trigger <= 1;
    end else if (do_dump) begin
      tx_mode <= 1;
      tx_dump <= 1;
    end
  end

  reg [5:0] bidx   = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready;

  wire [4:0] dump_cell = bidx[4:0] - 5'd2;

  reg [7:0] nbyte;
  always @(*) begin
    if (!tx_mode) begin
      // "S[AA]:T V:±NN\r\n"
      case (bidx)
        6'd0:  nbyte = 8'h53;  // 'S'
        6'd1:  nbyte = 8'h5B;  // '['
        6'd2:  nbyte = 8'h30 + tx_step / 5'd10;
        6'd3:  nbyte = 8'h30 + tx_step % 5'd10;
        6'd4:  nbyte = 8'h5D;  // ']'
        6'd5:  nbyte = 8'h3A;  // ':'
        6'd6:  nbyte = trit_char(tx_val);
        6'd7:  nbyte = 8'h20;  // ' '
        6'd8:  nbyte = 8'h56;  // 'V'
        6'd9:  nbyte = 8'h3A;  // ':'
        6'd10: nbyte = tx_neg ? 8'h2D : 8'h2B;
        6'd11: nbyte = 8'h30 + {4'h0, tx_tens};
        6'd12: nbyte = 8'h30 + {4'h0, tx_ones};
        6'd13: nbyte = 8'h0D;
        6'd14: nbyte = 8'h0A;
        default: nbyte = 8'h20;
      endcase
    end else begin
      // "D:TTT...T\r\n" (31 байт)
      case (bidx)
        6'd0:  nbyte = 8'h44;  // 'D'
        6'd1:  nbyte = 8'h3A;  // ':'
        6'd29: nbyte = 8'h0D;
        6'd30: nbyte = 8'h0A;
        default: nbyte = (bidx >= 6'd2 && bidx <= 6'd28) ?
                         trit_char(seq[dump_cell]) : 8'h20;
      endcase
    end
  end

  wire [5:0] last_bidx = tx_mode ? 6'd30 : 6'd14;

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger || tx_dump) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == last_bidx) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
