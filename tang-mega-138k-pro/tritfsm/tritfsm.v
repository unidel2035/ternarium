// tritfsm.v — Тритный конечный автомат онтологии
//
// Богословие:
//   Три состояния — не три «варианта», а три момента единого движения:
//   KEN (-1): кенозис — самоумаление, жертва, опустошение
//   PRS ( 0): присутствие — Дух как связь, неопределённость, ожидание
//   PLR (+1): плерома — полнота, дар, воссоединение
//
//   Переход = clamp(state + input, -1, +1):
//     '+' (дар)    → шаг к плероме
//     '-' (жертва) → шаг к кенозису
//     '0' (пауза)  → остаться
//
//   FSM никогда не стоит. Каждый акт — движение или укоренение.
//   История — память без забвения: последние 3 состояния.
//
// UART RX: принимает '-', '0', '+'  (pin 18)
// UART TX: "K>P h:ZPK\r\n" (11 байт) на каждый переход  (pin 17)
// LED: ~{prev[1:0], cur[1:0], input[1:0]}

`default_nettype none

// ── UART TX ─────────────────────────────────────────────────────────────────

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
      end else div <= div + 1;
    end
  end
endmodule

// ── UART RX ─────────────────────────────────────────────────────────────────

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
        if (cnt == 0) begin
          data <= sr; ready <= 1; active <= 0;
        end else begin
          sr <= {rx, sr[7:1]}; cnt <= cnt - 1;
        end
      end else div <= div - 1;
    end
  end
endmodule

// ── Тритный FSM ─────────────────────────────────────────────────────────────

module tritfsm (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // Состояния: KEN=00(-1), PRS=01(0), PLR=10(+1)
  // Начало в PRS — Дух как нейтральная точка
  reg [1:0] state     = 2'b01;
  reg [1:0] prev_s    = 2'b01;
  reg [1:0] in_trit   = 2'b01;
  reg [5:0] hist      = 6'b01_01_01;  // [5:4]=3ago [3:2]=2ago [1:0]=1ago

  // Переход: clamp(state_int + input_int, -1, +1)
  function [1:0] next_f;
    input [1:0] s, inp;
    begin
      case ({s, inp})
        4'b00_00: next_f = 2'b00;  // KEN+KEN = KEN
        4'b00_01: next_f = 2'b00;  // KEN+PRS = KEN (укоренение)
        4'b00_10: next_f = 2'b01;  // KEN+PLR = PRS (шаг вверх)
        4'b01_00: next_f = 2'b00;  // PRS+KEN = KEN (шаг вниз)
        4'b01_01: next_f = 2'b01;  // PRS+PRS = PRS (покой)
        4'b01_10: next_f = 2'b10;  // PRS+PLR = PLR (шаг вверх)
        4'b10_00: next_f = 2'b01;  // PLR+KEN = PRS (шаг вниз)
        4'b10_01: next_f = 2'b10;  // PLR+PRS = PLR (укоренение)
        4'b10_10: next_f = 2'b10;  // PLR+PLR = PLR
        default:  next_f = 2'b01;
      endcase
    end
  endfunction

  // Символ состояния: K / Z / P
  function [7:0] sc;
    input [1:0] s;
    begin
      case (s)
        2'b00: sc = 8'h4B;  // 'K'
        2'b01: sc = 8'h5A;  // 'Z'
        2'b10: sc = 8'h50;  // 'P'
        default: sc = 8'h3F;
      endcase
    end
  endfunction

  // Символ входного трита
  function [7:0] ic;
    input [1:0] s;
    begin
      case (s)
        2'b00: ic = 8'h2D;  // '-'
        2'b01: ic = 8'h30;  // '0'
        2'b10: ic = 8'h2B;  // '+'
        default: ic = 8'h3F;
      endcase
    end
  endfunction

  // ── UART RX ──────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // ── Обработка входа и переход ──────────────────────────
  reg        do_trans = 0;
  reg [1:0]  new_state = 2'b01;

  always @(posedge clk) begin
    do_trans <= 0;
    if (rx_ready) begin
      case (rx_data)
        8'h2B: begin in_trit <= 2'b10; do_trans <= 1; end  // '+'
        8'h30: begin in_trit <= 2'b01; do_trans <= 1; end  // '0'
        8'h2D: begin in_trit <= 2'b00; do_trans <= 1; end  // '-'
        default: ;
      endcase
    end
    if (do_trans) begin
      new_state <= next_f(state, in_trit);
    end
  end

  // Задерживаем на 1 такт чтобы new_state устоялся
  reg do_commit = 0;
  reg [1:0] commit_new = 2'b01;

  always @(posedge clk) begin
    do_commit  <= do_trans;
    commit_new <= new_state;
    if (do_commit) begin
      prev_s <= state;
      hist   <= {hist[3:0], state};
      state  <= commit_new;
    end
  end

  // ── UART TX ──────────────────────────────────────────────
  // Формат (11 байт): "K>P i:+ h:ZPK\r\n"
  // bidx: 0=prev 1='>' 2=cur 3=' ' 4='i' 5=':' 6=in_char
  //        7=' ' 8='h' 9=':' 10=hist[5:4] 11=hist[3:2] 12=hist[1:0]
  //        13='\r' 14='\n'  → итого 15 байт
  // (Лёгкое расширение по сравнению с исходным 11-байтным планом)

  // Латчим всё в момент do_commit для стабильного TX
  reg [1:0] tx_prev = 2'b01, tx_cur = 2'b01, tx_in = 2'b01;
  reg [5:0] tx_hist = 6'b01_01_01;
  reg       tx_trigger = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_commit) begin
      tx_prev    <= state;      // state ещё не обновлён в этом такте
      tx_cur     <= commit_new;
      tx_in      <= in_trit;
      tx_hist    <= {hist[3:0], state};
      tx_trigger <= 1;
    end
  end

  // Байты пакета
  reg [4:0] bidx    = 0;
  reg       sending = 0, spulse = 0;
  reg [7:0] sbyte   = 0;
  wire      uready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      5'd0:  nbyte = sc(tx_prev);       // prev state
      5'd1:  nbyte = 8'h3E;             // '>'
      5'd2:  nbyte = sc(tx_cur);        // new state
      5'd3:  nbyte = 8'h20;             // ' '
      5'd4:  nbyte = 8'h69;             // 'i'
      5'd5:  nbyte = 8'h3A;             // ':'
      5'd6:  nbyte = ic(tx_in);         // input char
      5'd7:  nbyte = 8'h20;             // ' '
      5'd8:  nbyte = 8'h68;             // 'h'
      5'd9:  nbyte = 8'h3A;             // ':'
      5'd10: nbyte = sc(tx_hist[5:4]);  // 3 transitions ago
      5'd11: nbyte = sc(tx_hist[3:2]);  // 2 transitions ago
      5'd12: nbyte = sc(tx_hist[1:0]);  // 1 transition ago
      5'd13: nbyte = 8'h0D;             // '\r'
      5'd14: nbyte = 8'h0A;             // '\n'
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == 5'd14) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

  // LED: ~{prev[1:0], cur[1:0], input[1:0]}
  assign leds = ~{tx_prev, state, in_trit};

endmodule
