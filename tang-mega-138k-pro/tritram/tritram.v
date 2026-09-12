// tritram.v — Тритная память 27 ячеек
//
// 27 ячеек × 2 бита = 54 бита регистровой памяти.
// Каждая ячейка хранит тритное значение: 2'b00=KEN(-1), 2'b01=PRS(0), 2'b10=PLR(+1).
// Адреса 0..26 (тритные числа -13..+13 в смещённом коде).
//
// Богословие: 27 = 3³ — полная тернарная матрица бытия.
// Каждая ячейка — лицо. Доступ — анамнезис.
//
// UART RX (115200, pin 18), ASCII-протокол:
//   W <AA> <T> — запись: AA = 00..26 (2 цифры), T = '+'/'-'/'0'
//   R <AA>     — чтение: AA = 00..26
//   D          — дамп всех 27 ячеек
//   Z          — обнуление (PRS) всей памяти
//
// UART TX:
//   После W: "W[AA]:T\r\n"          (9 байт)
//   После R: "R[AA]:T\r\n"          (9 байт)
//   После D: "D:TTTTTTTTTTTTTTTTTTTTTTTTTTT\r\n"  (31 байт)
//   После Z: "Z:OK\r\n"             (6 байт)
//
// LED [5:0]: ~{h2,h1,h0} последнего адреса (ternary)

`default_nettype none

// ── UART TX ──────────────────────────────────────────────────────────────────

module uart_tx (
  input  wire       clk,
  input  wire [7:0] data,
  input  wire       start,
  output reg        tx = 1,
  output wire       ready
);
  localparam CLKDIV = 434;  // 50 MHz / 115200
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

// ── Тритная память ────────────────────────────────────────────────────────────

module tritram (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // ── 27 ячеек × 2 бита (00=KEN, 01=PRS, 10=PLR) ───────────────────────────
  reg [1:0] mem [0:26];
  integer i;
  initial for (i = 0; i < 27; i = i+1) mem[i] = 2'b01; // PRS по умолчанию

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // ── Парсер команд ─────────────────────────────────────────────────────────
  // Состояния парсера
  localparam
    ST_IDLE    = 3'd0,
    ST_W_A1    = 3'd1,  // ждём первую цифру адреса (W)
    ST_W_A2    = 3'd2,  // ждём вторую цифру адреса (W)
    ST_W_TRIT  = 3'd3,  // ждём тритный символ (W)
    ST_R_A1    = 3'd4,  // ждём первую цифру адреса (R)
    ST_R_A2    = 3'd5;  // ждём вторую цифру адреса (R)

  reg [2:0] parse_st  = ST_IDLE;
  reg [4:0] addr_acc  = 0;  // накопленный адрес 0..26
  reg [3:0] dig1      = 0;  // первая цифра адреса

  // Команды для TX-машины
  reg do_write  = 0, do_read = 0, do_dump = 0, do_zero = 0;
  reg [4:0] cmd_addr = 0;
  reg [1:0] cmd_val  = 0;
  reg [4:0] last_addr = 0;  // для LED

  always @(posedge clk) begin
    do_write <= 0; do_read <= 0; do_dump <= 0; do_zero <= 0;
    if (rx_ready) begin
      case (parse_st)
        ST_IDLE: begin
          case (rx_data)
            8'h57: parse_st <= ST_W_A1;  // 'W'
            8'h52: parse_st <= ST_R_A1;  // 'R'
            8'h44: begin do_dump <= 1; end  // 'D'
            8'h5A: begin  // 'Z' — zero all
              for (i = 0; i < 27; i = i+1) mem[i] <= 2'b01;
              do_zero <= 1;
            end
            default: ;
          endcase
        end
        ST_W_A1: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h39) begin
            dig1 <= rx_data[3:0];
            parse_st <= ST_W_A2;
          end else parse_st <= ST_IDLE;
        end
        ST_W_A2: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h39) begin
            addr_acc <= dig1 * 4'd10 + rx_data[3:0];
            parse_st <= ST_W_TRIT;
          end else parse_st <= ST_IDLE;
        end
        ST_W_TRIT: begin
          parse_st <= ST_IDLE;
          if (addr_acc <= 5'd26) begin
            cmd_addr <= addr_acc;
            case (rx_data)
              8'h2B: begin mem[addr_acc] <= 2'b10; cmd_val <= 2'b10; end  // '+'
              8'h30: begin mem[addr_acc] <= 2'b01; cmd_val <= 2'b01; end  // '0'
              8'h2D: begin mem[addr_acc] <= 2'b00; cmd_val <= 2'b00; end  // '-'
              default: ;
            endcase
            last_addr <= addr_acc;
            do_write <= 1;
          end
        end
        ST_R_A1: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h39) begin
            dig1 <= rx_data[3:0];
            parse_st <= ST_R_A2;
          end else parse_st <= ST_IDLE;
        end
        ST_R_A2: begin
          parse_st <= ST_IDLE;
          if (rx_data >= 8'h30 && rx_data <= 8'h39) begin
            addr_acc <= dig1 * 4'd10 + rx_data[3:0];
            if (dig1 * 4'd10 + rx_data[3:0] <= 5'd26) begin
              cmd_addr <= dig1 * 4'd10 + rx_data[3:0];
              cmd_val  <= mem[dig1 * 4'd10 + rx_data[3:0]];
              last_addr <= dig1 * 4'd10 + rx_data[3:0];
              do_read <= 1;
            end
          end else parse_st <= ST_IDLE;
        end
        default: parse_st <= ST_IDLE;
      endcase
    end
  end

  // ── LED: тритное представление last_addr ─────────────────────────────────
  wire [1:0] la_h2 = (last_addr >= 5'd18) ? 2'b10 : (last_addr >= 5'd9) ? 2'b01 : 2'b00;
  wire [4:0] la_r1 = (last_addr >= 5'd18) ? last_addr - 5'd18 :
                     (last_addr >= 5'd9)  ? last_addr - 5'd9  : last_addr;
  wire [1:0] la_h1 = (la_r1 >= 5'd6) ? 2'b10 : (la_r1 >= 5'd3) ? 2'b01 : 2'b00;
  wire [4:0] la_r0 = (la_r1 >= 5'd6) ? la_r1 - 5'd6 : (la_r1 >= 5'd3) ? la_r1 - 5'd3 : la_r1;
  wire [1:0] la_h0 = (la_r0 >= 5'd2) ? 2'b10 : (la_r0 == 5'd1) ? 2'b01 : 2'b00;
  assign leds = ~{la_h2, la_h1, la_h0};

  // ── TX машина ─────────────────────────────────────────────────────────────
  // Форматы:
  //   W: "W[AA]:T\r\n"   9 байт  (bidx 0..8)
  //   R: "R[AA]:T\r\n"   9 байт  (bidx 0..8)
  //   D: "D:TTT...T\r\n" 31 байт (bidx 0..30)
  //   Z: "Z:OK\r\n"      6 байт  (bidx 0..5)

  localparam TX_W = 2'd0, TX_R = 2'd1, TX_D = 2'd2, TX_Z = 2'd3;

  reg [1:0]  tx_mode = TX_W;
  reg [4:0]  tx_addr = 0;
  reg [1:0]  tx_val  = 0;
  reg [5:0]  bidx    = 0;
  reg        sending = 0, spulse = 0;
  reg [7:0]  sbyte   = 0;
  wire       uready;

  // Вспомогательные функции
  function [7:0] trit_char;
    input [1:0] v;
    case (v)
      2'b10: trit_char = 8'h2B;  // '+'
      2'b01: trit_char = 8'h30;  // '0'
      2'b00: trit_char = 8'h2D;  // '-'
      default: trit_char = 8'h3F;  // '?'
    endcase
  endfunction

  // Индекс ячейки при дампе (bidx 2..28 → ячейки 0..26)
  wire [4:0] dump_cell = bidx[4:0] - 5'd2;

  reg [7:0] nbyte;
  always @(*) begin
    case (tx_mode)
      TX_W, TX_R: begin
        case (bidx)
          6'd0: nbyte = (tx_mode == TX_W) ? 8'h57 : 8'h52;  // 'W'/'R'
          6'd1: nbyte = 8'h5B;  // '['
          6'd2: nbyte = 8'h30 + tx_addr / 5'd10;  // десятки адреса
          6'd3: nbyte = 8'h30 + tx_addr % 5'd10;  // единицы адреса
          6'd4: nbyte = 8'h5D;  // ']'
          6'd5: nbyte = 8'h3A;  // ':'
          6'd6: nbyte = trit_char(tx_val);
          6'd7: nbyte = 8'h0D;  // '\r'
          6'd8: nbyte = 8'h0A;  // '\n'
          default: nbyte = 8'h20;
        endcase
      end
      TX_D: begin
        case (bidx)
          6'd0:  nbyte = 8'h44;  // 'D'
          6'd1:  nbyte = 8'h3A;  // ':'
          // bidx 2..28 → ячейки 0..26
          6'd29: nbyte = 8'h0D;
          6'd30: nbyte = 8'h0A;
          default: nbyte = (bidx >= 6'd2 && bidx <= 6'd28) ?
                           trit_char(mem[dump_cell]) : 8'h20;
        endcase
      end
      TX_Z: begin
        case (bidx)
          6'd0: nbyte = 8'h5A;  // 'Z'
          6'd1: nbyte = 8'h3A;  // ':'
          6'd2: nbyte = 8'h4F;  // 'O'
          6'd3: nbyte = 8'h4B;  // 'K'
          6'd4: nbyte = 8'h0D;
          6'd5: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      default: nbyte = 8'h20;
    endcase
  end

  // Последний индекс для каждого режима
  wire [5:0] last_bidx = (tx_mode == TX_D) ? 6'd30 :
                         (tx_mode == TX_Z) ? 6'd5  : 6'd8;

  // Защёлкиваем параметры TX при команде
  always @(posedge clk) begin
    spulse <= 0;
    if (do_write || do_read || do_dump || do_zero) begin
      sending <= 1;
      bidx    <= 0;
      if (do_write) begin tx_mode <= TX_W; tx_addr <= cmd_addr; tx_val <= cmd_val; end
      else if (do_read) begin tx_mode <= TX_R; tx_addr <= cmd_addr; tx_val <= cmd_val; end
      else if (do_dump) tx_mode <= TX_D;
      else              tx_mode <= TX_Z;
    end else if (sending && uready && !spulse) begin
      sbyte <= nbyte;
      spulse <= 1;
      if (bidx == last_bidx) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
