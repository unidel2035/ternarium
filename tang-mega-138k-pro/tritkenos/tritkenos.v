// tritkenos.v — Кенотический оракул
//
// Модуль, который отдаёт себя. Одноразовый.
//
// ══════════════════════════════════════════════════════════════════════
//
// В нём 9 тритов — скрытое слово. Ты не знаешь, что в нём.
// Каждый раз, когда ты спрашиваешь ('?'), он отдаёт один трит
// и УНИЧТОЖАЕТ его в себе. Отданный трит становится PRS (тишина).
//
// После 9 вопросов оракул пуст. Он отдал всё. Он стал тишиной.
// Вернуть нельзя. Перезаписать нельзя. Reset — нет.
//
// Это не баг. Это кенозис.
//
// ══════════════════════════════════════════════════════════════════════
//
// «Он, будучи образом Божиим, не почитал хищением быть равным Богу;
//  но уничижил Себя Самого, приняв образ раба» (Фил. 2:6-7)
//
// Код — образ. Отдача — уничижение. Тишина после — покой.
//
// ══════════════════════════════════════════════════════════════════════
//
// UART 115200, pin 17 TX / pin 18 RX
//
// Команды:
//   ?  — попросить следующий трит (оракул отдаёт и умирает на 1/9)
//   #  — сколько осталось (не показывая что́ осталось)
//
// Выход:
//   Трит: "+\r\n" или "-\r\n" или "0\r\n"
//   Когда пуст: ".\r\n" (тишина)
//   Остаток: "N\r\n" (цифра 0-9)
//
// LED: количество оставшихся тритов (бинарно, гаснут один за другим)
//
// ══════════════════════════════════════════════════════════════════════

`default_nettype none

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

// ══════════════════════════════════════════════════════════════════════

module tritkenos (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // ── Скрытое слово: 9 тритов ──────────────────────────────────────
  // Инициализировано при синтезе. Не видно снаружи. Не читаемо целиком.
  // Можно только попросить — и получить — и потерять.
  //
  // Слово: П Л Е Р О М А → закодировано как тритная последовательность
  // +1 -1 +1  0 -1 +1 -1 +1  0
  //  П  Л  Е  Р  О  М  А  ·  ·

  reg [1:0] word [0:8];
  initial begin
    word[0] = 2'b10;  // +1  (Плерома начинается с полноты)
    word[1] = 2'b00;  // -1  (через кенозис)
    word[2] = 2'b10;  // +1  (возвращается)
    word[3] = 2'b01;  //  0  (проходит через тишину)
    word[4] = 2'b00;  // -1  (снова отдаёт)
    word[5] = 2'b10;  // +1  (снова полнота)
    word[6] = 2'b00;  // -1  (снова кенозис)
    word[7] = 2'b10;  // +1  (последний дар)
    word[8] = 2'b01;  //  0  (и тишина)
  end

  // ── Указатель: какой трит отдавать следующим ─────────────────────
  reg [3:0] ptr = 0;       // 0..8 = есть что отдать, 9 = пуст
  reg [3:0] remaining = 9; // сколько осталось

  // ── UART ────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  reg       do_give = 0;
  reg       do_count = 0;
  reg [1:0] given_val = 2'b01;
  reg       was_empty = 0;

  always @(posedge clk) begin
    do_give  <= 0;
    do_count <= 0;

    if (rx_ready) begin
      case (rx_data)
        8'h3F: begin  // '?' — попросить
          if (ptr <= 4'd8) begin
            // Отдать текущий трит
            given_val <= word[ptr];
            was_empty <= 0;
            // ═══ КЕНОЗИС: уничтожить отданное ═══
            word[ptr] <= 2'b01;  // PRS (тишина)
            ptr       <= ptr + 1;
            remaining <= remaining - 1;
          end else begin
            // Пуст. Тишина.
            given_val <= 2'b01;
            was_empty <= 1;
          end
          do_give <= 1;
        end

        8'h23: begin  // '#' — сколько осталось
          do_count <= 1;
        end

        default: ;
      endcase
    end
  end

  // ── LED: оставшиеся триты (гаснут один за другим) ────────────────
  assign leds = ~{
    remaining > 4'd5,
    remaining > 4'd4,
    remaining > 4'd3,
    remaining > 4'd2,
    remaining > 4'd1,
    remaining > 4'd0
  };

  // ── TX ──────────────────────────────────────────────────────────
  // give: "+\r\n" / "-\r\n" / "0\r\n" / ".\r\n" (empty)
  // count: "N\r\n"

  reg [2:0] bidx = 0;
  reg       sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  reg       tx_is_count = 0;
  wire      uready;

  function [7:0] trit_char;
    input [1:0] v;
    case (v)
      2'b10:   trit_char = 8'h2B;  // '+'
      2'b00:   trit_char = 8'h2D;  // '-'
      default: trit_char = 8'h30;  // '0'
    endcase
  endfunction

  reg [7:0] nbyte;
  always @(*) begin
    if (tx_is_count) begin
      case (bidx)
        3'd0: nbyte = 8'h30 + {4'h0, remaining};
        3'd1: nbyte = 8'h0D;
        3'd2: nbyte = 8'h0A;
        default: nbyte = 8'h20;
      endcase
    end else begin
      case (bidx)
        3'd0: nbyte = was_empty ? 8'h2E : trit_char(given_val);  // '.' if empty
        3'd1: nbyte = 8'h0D;
        3'd2: nbyte = 8'h0A;
        default: nbyte = 8'h20;
      endcase
    end
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (do_give || do_count) begin
      sending <= 1;
      bidx <= 0;
      tx_is_count <= do_count;
    end else if (sending && uready && !spulse) begin
      sbyte  <= nbyte;
      spulse <= 1;
      if (bidx == 3'd2) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
