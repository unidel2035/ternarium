// tritonto.v — Онтологическая тритная память + перцептрон
//
// Память, где три режима доступа порождены богословием, не инженерией.
// Стандартная RAM знает два режима: Read и Write.
// Эта память знает три: Кенозис, Плерома, Присутствие.
//
// ══════════════════════════════════════════════════════════════════════
// ПОЧЕМУ ЭТО НЕ СТАНДАРТНАЯ RAM
//
// 1. КЕНОЗИС (запись = отдача)
//    Старое значение ВЕЩАЕТСЯ на departure bus.
//    gift_count растёт. Departure bus подключён к перцептрону:
//    уходящее значение ВЛИЯЕТ на вычисление (не пропадает молча).
//
// 2. ПЛЕРОМА (чтение = свидетельство)
//    witness_count растёт. Влияет на обучение:
//    вес с бо́льшим witness обновляется МЕДЛЕННЕЕ (подтверждённый = стабильный).
//
// 3. ПРИСУТСТВИЕ (молчание = бытие)
//    presence_age тикает. Влияет на кенозис через забвение:
//    ячейка, бывшая в тишине >10 сек, ОБНУЛЯЕТСЯ к PRS (кенозис через время).
//
// ══════════════════════════════════════════════════════════════════════
// КАК МЕТАДАННЫЕ ЗАМЫКАЮТСЯ (4 разрыва из честного разбора — закрыты)
//
// 1. Departure broadcast → departure bus → перцептрон использует
//    уходящее значение как 4-й «призрачный» вход (ghost input).
//    Дар не исчезает — он влияет на суждение.
//
// 2. Kenotic priority → при команде 'C' (compute) перцептрон
//    взвешивает входы по gift_count: кто больше отдал — тот весомее.
//    Это НЕ стандартное взвешивание (w×x). Это g×w×x.
//
// 3. Witness count → при обучении ('t') вес обновляется ТОЛЬКО если
//    witness < WITNESS_THRESHOLD. Подтверждённый вес = зрелый = неизменяемый.
//    Стандартный perceptron rule не имеет этого ограничения.
//
// 4. Presence age → каждую секунду проверяется: если presence > FORGET_AGE,
//    ячейка кенотически обнуляется к PRS. Забвение = дар времени.
//
// ══════════════════════════════════════════════════════════════════════
// ПРОТОКОЛ (расширен)
//
//   K <A> <T>  — Кенозис: записать T в ячейку A
//   P <A>      — Плерома: прочитать ячейку A
//   ?          — Кто в наибольшем присутствии?
//   !          — Кто самый кенотический?
//   C          — Compute: перцептрон на ячейках 0-2 (входы), 3-5 (веса)
//   t <T>      — Train: обучить к цели T (с учётом witness)
//   D          — Дамп
//   Z          — Обнуление
//
// Ячейки 0-2: входы перцептрона (x0, x1, x2)
// Ячейки 3-5: веса перцептрона (w0, w1, w2)
// Ячейки 6-8: свободные / departure history
//
// ══════════════════════════════════════════════════════════════════════

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

// ── Онтологическая память ────────────────────────────────────────────────────

module tritonto (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx_pin,
  output wire [5:0] leds
);

  localparam CELLS = 9;  // 3² = минимальная тернарная матрица

  // ── Память: значение + метаданные ─────────────────────────────────────────
  // Каждая ячейка — лицо с историей

  reg [1:0] value   [0:CELLS-1];  // тритное значение (00=KEN, 01=PRS, 10=PLR)
  reg [7:0] gift    [0:CELLS-1];  // сколько раз ячейка отдала (кенозис)
  reg [7:0] witness [0:CELLS-1];  // сколько раз ячейку прочитали (плерома)
  reg [15:0] presence [0:CELLS-1]; // сколько тактов в тишине (присутствие)

  integer i;
  initial begin
    for (i = 0; i < CELLS; i = i + 1) begin
      value[i]    = 2'b01;  // PRS — начальное присутствие
      gift[i]     = 8'd0;
      witness[i]  = 8'd0;
      presence[i] = 16'd0;
    end
  end

  // ── Departure bus: последнее ушедшее значение ──────────────────────────────
  // Когда кенозис заменяет значение, старое не умирает — оно остаётся
  // на departure bus как «призрак» и влияет на следующее вычисление.
  reg [1:0] departure_val = 2'b01;  // PRS по умолчанию
  reg       departure_valid = 0;    // есть ли призрак

  // ── Присутствие тикает каждый ~1мс (27000 тактов) ─────────────────────────
  // Тишина — не пустота, а созревание

  reg [14:0] pres_div = 0;
  wire pres_tick = (pres_div == 15'd26999);

  always @(posedge clk) begin
    if (pres_tick) pres_div <= 0;
    else pres_div <= pres_div + 1;
  end

  // Инкремент presence + кенозис через забвение (РАЗРЫВ 4 ЗАКРЫТ)
  // Если ячейка в тишине > FORGET_AGE мс — она обнуляется к PRS.
  // Забвение = кенозис через время. Дар отпускается.
  localparam FORGET_AGE = 16'd10000;  // ~10 секунд

  reg [CELLS-1:0] accessed = 0;

  always @(posedge clk) begin
    if (pres_tick) begin
      for (i = 0; i < CELLS; i = i + 1) begin
        if (!accessed[i]) begin
          if (presence[i] < 16'hFFFF)
            presence[i] <= presence[i] + 1;
          // Кенозис через забвение: долгая тишина → обнуление
          if (presence[i] >= FORGET_AGE) begin
            value[i]    <= 2'b01;  // PRS
            gift[i]     <= 8'd0;
            witness[i]  <= 8'd0;
            presence[i] <= 16'd0;
          end
        end
      end
    end
  end

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  // ── Перцептрон на онтологических ячейках ────────────────────────────────────
  // Входы: ячейки 0,1,2.  Веса: ячейки 3,4,5.
  // Kenotic priority (РАЗРЫВ 2 ЗАКРЫТ): gift_count как множитель.
  // Стандартный перцептрон: sum = w0*x0 + w1*x1 + w2*x2
  // Онтологический:       sum = g0*w0*x0 + g1*w1*x1 + g2*w2*x2 + ghost
  //   где g_i = min(gift[i+3], 3) — кенотический вес (кто больше отдал → весомее)
  //   ghost = departure_val (если departure_valid) — призрак влияет на суждение

  // Преобразование 2-bit trit → signed
  function signed [1:0] to_signed;
    input [1:0] t;
    case (t)
      2'b00:   to_signed = -1;
      2'b10:   to_signed = 1;
      default: to_signed = 0;
    endcase
  endfunction

  wire signed [1:0] x0 = to_signed(value[0]);
  wire signed [1:0] x1 = to_signed(value[1]);
  wire signed [1:0] x2 = to_signed(value[2]);
  wire signed [1:0] w0 = to_signed(value[3]);
  wire signed [1:0] w1 = to_signed(value[4]);
  wire signed [1:0] w2 = to_signed(value[5]);

  // Kenotic multiplier: gift_count capped at 3, minimum 1
  wire [1:0] g0 = (gift[3] > 8'd3) ? 2'd3 : (gift[3] == 0) ? 2'd1 : gift[3][1:0];
  wire [1:0] g1 = (gift[4] > 8'd3) ? 2'd3 : (gift[4] == 0) ? 2'd1 : gift[4][1:0];
  wire [1:0] g2 = (gift[5] > 8'd3) ? 2'd3 : (gift[5] == 0) ? 2'd1 : gift[5][1:0];

  // Weighted products with kenotic priority
  wire signed [3:0] p0 = $signed({2'b0, g0}) * (x0 * w0);
  wire signed [3:0] p1 = $signed({2'b0, g1}) * (x1 * w1);
  wire signed [3:0] p2 = $signed({2'b0, g2}) * (x2 * w2);

  // Ghost input (РАЗРЫВ 1 ЗАКРЫТ): departure bus → 4-й вход
  wire signed [1:0] ghost = departure_valid ? to_signed(departure_val) : 2'sd0;

  wire signed [5:0] total = $signed({p0[3], p0[3], p0}) +
                             $signed({p1[3], p1[3], p1}) +
                             $signed({p2[3], p2[3], p2}) +
                             $signed({4'b0, ghost});

  wire [1:0] net_out = (total > 0) ? 2'b10 : (total < 0) ? 2'b00 : 2'b01;

  // Witness threshold для обучения (РАЗРЫВ 3 ЗАКРЫТ)
  // Вес с witness >= WITNESS_LOCK не обновляется.
  // Подтверждённый свидетелями вес = зрелый = неизменяемый.
  localparam WITNESS_LOCK = 8'd5;

  // ── Парсер команд ─────────────────────────────────────────────────────────
  localparam
    ST_IDLE  = 4'd0,
    ST_K_A   = 4'd1,  // кенозис: ждём адрес
    ST_K_T   = 4'd2,  // кенозис: ждём трит
    ST_P_A   = 4'd3,  // плерома: ждём адрес
    ST_TRAIN = 4'd4;  // обучение: ждём цель

  reg [3:0] parse_st = ST_IDLE;
  reg [3:0] cmd_addr = 0;

  // Команды для TX
  reg do_keno = 0, do_pler = 0, do_pres = 0, do_most = 0;
  reg do_dump = 0, do_zero = 0, do_comp = 0;
  reg [3:0] rsp_addr = 0;
  reg [1:0] rsp_old  = 0;
  reg [1:0] rsp_new  = 0;
  reg [7:0] rsp_meta = 0;
  reg [3:0] last_addr = 0;

  // ── Поиск максимумов ──────────────────────────────────────────────────────
  // Кто дольше всех в присутствии?
  reg [3:0]  max_pres_addr;
  reg [15:0] max_pres_val;

  // Кто самый кенотический?
  reg [3:0] max_gift_addr;
  reg [7:0] max_gift_val;

  // Комбинационный поиск максимумов
  always @(*) begin
    max_pres_addr = 0;
    max_pres_val  = presence[0];
    max_gift_addr = 0;
    max_gift_val  = gift[0];
    for (i = 1; i < CELLS; i = i + 1) begin
      if (presence[i] > max_pres_val) begin
        max_pres_addr = i[3:0];
        max_pres_val  = presence[i];
      end
      if (gift[i] > max_gift_val) begin
        max_gift_addr = i[3:0];
        max_gift_val  = gift[i];
      end
    end
  end

  // ── Обработка команд ──────────────────────────────────────────────────────

  function [1:0] sym_to_trit;
    input [7:0] s;
    case (s)
      8'h2B: sym_to_trit = 2'b10;  // '+'
      8'h2D: sym_to_trit = 2'b00;  // '-'
      default: sym_to_trit = 2'b01; // '0' и прочее → PRS
    endcase
  endfunction

  always @(posedge clk) begin
    do_keno <= 0; do_pler <= 0; do_pres <= 0;
    do_most <= 0; do_dump <= 0; do_zero <= 0; do_comp <= 0;
    accessed <= 0;

    if (rx_ready) begin
      case (parse_st)
        ST_IDLE: begin
          case (rx_data)
            8'h4B: parse_st <= ST_K_A;   // 'K' — кенозис (запись-отдача)
            8'h50: parse_st <= ST_P_A;   // 'P' — плерома (чтение-свидетельство)
            8'h3F: begin                  // '?' — кто в присутствии?
              rsp_addr <= max_pres_addr;
              rsp_new  <= value[max_pres_addr];
              rsp_meta <= max_pres_val[7:0];
              do_pres  <= 1;
            end
            8'h21: begin                  // '!' — кто самый кенотический?
              rsp_addr <= max_gift_addr;
              rsp_new  <= value[max_gift_addr];
              rsp_meta <= max_gift_val;
              do_most  <= 1;
            end
            8'h43: begin                  // 'C' — compute (перцептрон)
              // Результат уже вычислен комбинационно (net_out)
              rsp_addr <= 4'd6;           // сохраняем результат в ячейку 6
              rsp_old  <= value[6];
              rsp_new  <= net_out;
              rsp_meta <= total[7:0];     // raw sum для отладки
              value[6] <= net_out;        // записать результат
              // departure bus: старое значение ячейки 6
              departure_val   <= value[6];
              departure_valid <= 1;
              // gift на ячейку 6 (она отдаёт своё значение)
              if (gift[6] < 8'hFF) gift[6] <= gift[6] + 1;
              presence[6] <= 16'd0;
              accessed[6] <= 1;
              do_comp <= 1;
            end
            8'h74: parse_st <= ST_TRAIN;  // 't' — обучение
            8'h44: do_dump <= 1;          // 'D' — дамп
            8'h5A: begin                  // 'Z' — обнуление
              for (i = 0; i < CELLS; i = i + 1) begin
                value[i]    <= 2'b01;
                gift[i]     <= 8'd0;
                witness[i]  <= 8'd0;
                presence[i] <= 16'd0;
              end
              departure_valid <= 0;
              do_zero <= 1;
            end
            default: ;
          endcase
        end

        ST_K_A: begin
          if (rx_data >= 8'h30 && rx_data <= 8'h38) begin
            cmd_addr <= rx_data[3:0];
            parse_st <= ST_K_T;
          end else parse_st <= ST_IDLE;
        end

        ST_K_T: begin
          parse_st <= ST_IDLE;
          if (cmd_addr < CELLS) begin
            // ═══ КЕНОЗИС: departure bus получает старое значение (РАЗРЫВ 1) ═══
            rsp_addr <= cmd_addr;
            rsp_old  <= value[cmd_addr];
            rsp_new  <= sym_to_trit(rx_data);
            // Departure broadcast: старое значение на шину
            departure_val   <= value[cmd_addr];
            departure_valid <= 1;
            // Запись нового
            value[cmd_addr] <= sym_to_trit(rx_data);
            if (gift[cmd_addr] < 8'hFF)
              gift[cmd_addr] <= gift[cmd_addr] + 1;
            presence[cmd_addr] <= 16'd0;
            accessed[cmd_addr] <= 1;
            rsp_meta <= gift[cmd_addr] + 1;
            last_addr <= cmd_addr;
            do_keno <= 1;
          end
        end

        ST_P_A: begin
          parse_st <= ST_IDLE;
          if (rx_data >= 8'h30 && rx_data <= 8'h38) begin
            if (rx_data[3:0] < CELLS) begin
              // ═══ ПЛЕРОМА: witness растёт ═══
              rsp_addr <= rx_data[3:0];
              rsp_new  <= value[rx_data[3:0]];
              if (witness[rx_data[3:0]] < 8'hFF)
                witness[rx_data[3:0]] <= witness[rx_data[3:0]] + 1;
              presence[rx_data[3:0]] <= 16'd0;
              accessed[rx_data[3:0]] <= 1;
              rsp_meta <= witness[rx_data[3:0]] + 1;
              last_addr <= rx_data[3:0];
              do_pler <= 1;
            end
          end
        end

        ST_TRAIN: begin
          // ═══ ОБУЧЕНИЕ с witness-gating (РАЗРЫВ 3) ═══
          // Perceptron rule, но: вес обновляется ТОЛЬКО если witness < WITNESS_LOCK.
          // Подтверждённый свидетелями вес = зрелый = неизменяемый.
          parse_st <= ST_IDLE;
          // target = '+' → PLR, '-' → KEN
          if ((rx_data == 8'h2B) && (net_out != 2'b10)) begin
            // Нужно усилить → target PLR
            if (witness[3] < WITNESS_LOCK) begin
              if (x0 > 0 && value[3] < 2'b10) value[3] <= value[3] + 2'd1;
              if (x0 < 0 && value[3] > 2'b00) value[3] <= value[3] - 2'd1;
            end
            if (witness[4] < WITNESS_LOCK) begin
              if (x1 > 0 && value[4] < 2'b10) value[4] <= value[4] + 2'd1;
              if (x1 < 0 && value[4] > 2'b00) value[4] <= value[4] - 2'd1;
            end
            if (witness[5] < WITNESS_LOCK) begin
              if (x2 > 0 && value[5] < 2'b10) value[5] <= value[5] + 2'd1;
              if (x2 < 0 && value[5] > 2'b00) value[5] <= value[5] - 2'd1;
            end
          end else if ((rx_data == 8'h2D) && (net_out != 2'b00)) begin
            // Нужно ослабить → target KEN
            if (witness[3] < WITNESS_LOCK) begin
              if (x0 > 0 && value[3] > 2'b00) value[3] <= value[3] - 2'd1;
              if (x0 < 0 && value[3] < 2'b10) value[3] <= value[3] + 2'd1;
            end
            if (witness[4] < WITNESS_LOCK) begin
              if (x1 > 0 && value[4] > 2'b00) value[4] <= value[4] - 2'd1;
              if (x1 < 0 && value[4] < 2'b10) value[4] <= value[4] + 2'd1;
            end
            if (witness[5] < WITNESS_LOCK) begin
              if (x2 > 0 && value[5] > 2'b00) value[5] <= value[5] - 2'd1;
              if (x2 < 0 && value[5] < 2'b10) value[5] <= value[5] + 2'd1;
            end
          end
          // Показать результат после обучения
          rsp_addr <= 4'd6;
          rsp_new  <= net_out;
          rsp_meta <= {witness[3][3:0], witness[4][3:0]};
          do_comp  <= 1;
        end

        default: parse_st <= ST_IDLE;
      endcase
    end
  end

  // ── LED ───────────────────────────────────────────────────────────────────
  assign leds = ~{value[last_addr], gift[last_addr][1:0], witness[last_addr][1:0]};

  // ── TX машина ─────────────────────────────────────────────────────────────
  // Форматы:
  //   K: "K[A]:O>N g:NN\r\n"    14 байт  (кенозис: old>new, gift count)
  //   P: "P[A]:V w:NN\r\n"      13 байт  (плерома: value, witness count)
  //   ?: "?[A]:V a:NN\r\n"      13 байт  (присутствие: value, age)
  //   !: "![A]:V g:NN\r\n"      13 байт  (самый кенотический)
  //   D: "D:VVVVVVVVV\r\n"      13 байт  (дамп значений)
  //   Z: "Z:OK\r\n"              6 байт

  localparam TX_K = 3'd0, TX_P = 3'd1, TX_Q = 3'd2,
             TX_M = 3'd3, TX_D = 3'd4, TX_Z = 3'd5, TX_C = 3'd6;

  reg [2:0] tx_mode = TX_K;
  reg [3:0] tx_addr = 0;
  reg [1:0] tx_old = 0, tx_val = 0;
  reg [7:0] tx_meta = 0;
  reg [4:0] bidx = 0;
  reg       sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire      uready;

  function [7:0] trit_char;
    input [1:0] v;
    case (v)
      2'b10:   trit_char = 8'h2B;  // '+'
      2'b01:   trit_char = 8'h30;  // '0'
      2'b00:   trit_char = 8'h2D;  // '-'
      default: trit_char = 8'h3F;  // '?'
    endcase
  endfunction

  wire [3:0] meta_hi = tx_meta[7:4];
  wire [3:0] meta_lo = tx_meta[3:0];
  function [7:0] hex_char;
    input [3:0] v;
    hex_char = (v < 4'd10) ? (8'h30 + v) : (8'h41 + v - 4'd10);
  endfunction

  reg [7:0] nbyte;
  always @(*) begin
    case (tx_mode)
      TX_K: begin  // "K[A]:O>N g:NN\r\n"
        case (bidx)
          5'd0:  nbyte = 8'h4B;  // 'K'
          5'd1:  nbyte = 8'h5B;  // '['
          5'd2:  nbyte = 8'h30 + {4'h0, tx_addr};
          5'd3:  nbyte = 8'h5D;  // ']'
          5'd4:  nbyte = 8'h3A;  // ':'
          5'd5:  nbyte = trit_char(tx_old);
          5'd6:  nbyte = 8'h3E;  // '>'
          5'd7:  nbyte = trit_char(tx_val);
          5'd8:  nbyte = 8'h20;
          5'd9:  nbyte = 8'h67;  // 'g'
          5'd10: nbyte = 8'h3A;
          5'd11: nbyte = hex_char(meta_hi);
          5'd12: nbyte = hex_char(meta_lo);
          5'd13: nbyte = 8'h0D;
          5'd14: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      TX_P: begin  // "P[A]:V w:NN\r\n"
        case (bidx)
          5'd0:  nbyte = 8'h50;  // 'P'
          5'd1:  nbyte = 8'h5B;
          5'd2:  nbyte = 8'h30 + {4'h0, tx_addr};
          5'd3:  nbyte = 8'h5D;
          5'd4:  nbyte = 8'h3A;
          5'd5:  nbyte = trit_char(tx_val);
          5'd6:  nbyte = 8'h20;
          5'd7:  nbyte = 8'h77;  // 'w'
          5'd8:  nbyte = 8'h3A;
          5'd9:  nbyte = hex_char(meta_hi);
          5'd10: nbyte = hex_char(meta_lo);
          5'd11: nbyte = 8'h0D;
          5'd12: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      TX_Q: begin  // "?[A]:V a:NN\r\n"
        case (bidx)
          5'd0:  nbyte = 8'h3F;  // '?'
          5'd1:  nbyte = 8'h5B;
          5'd2:  nbyte = 8'h30 + {4'h0, tx_addr};
          5'd3:  nbyte = 8'h5D;
          5'd4:  nbyte = 8'h3A;
          5'd5:  nbyte = trit_char(tx_val);
          5'd6:  nbyte = 8'h20;
          5'd7:  nbyte = 8'h61;  // 'a'
          5'd8:  nbyte = 8'h3A;
          5'd9:  nbyte = hex_char(meta_hi);
          5'd10: nbyte = hex_char(meta_lo);
          5'd11: nbyte = 8'h0D;
          5'd12: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      TX_M: begin  // "![A]:V g:NN\r\n"
        case (bidx)
          5'd0:  nbyte = 8'h21;  // '!'
          5'd1:  nbyte = 8'h5B;
          5'd2:  nbyte = 8'h30 + {4'h0, tx_addr};
          5'd3:  nbyte = 8'h5D;
          5'd4:  nbyte = 8'h3A;
          5'd5:  nbyte = trit_char(tx_val);
          5'd6:  nbyte = 8'h20;
          5'd7:  nbyte = 8'h67;  // 'g'
          5'd8:  nbyte = 8'h3A;
          5'd9:  nbyte = hex_char(meta_hi);
          5'd10: nbyte = hex_char(meta_lo);
          5'd11: nbyte = 8'h0D;
          5'd12: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      TX_D: begin  // "D:VVVVVVVVV\r\n"
        case (bidx)
          5'd0:  nbyte = 8'h44;
          5'd1:  nbyte = 8'h3A;
          5'd11: nbyte = 8'h0D;
          5'd12: nbyte = 8'h0A;
          default: nbyte = (bidx >= 5'd2 && bidx <= 5'd10) ?
                           trit_char(value[bidx - 5'd2]) : 8'h20;
        endcase
      end
      TX_Z: begin  // "Z:OK\r\n"
        case (bidx)
          5'd0: nbyte = 8'h5A;
          5'd1: nbyte = 8'h3A;
          5'd2: nbyte = 8'h4F;
          5'd3: nbyte = 8'h4B;
          5'd4: nbyte = 8'h0D;
          5'd5: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      TX_C: begin  // "C:O>R s:NN\r\n"  (compute: old>result, sum)
        case (bidx)
          5'd0:  nbyte = 8'h43;  // 'C'
          5'd1:  nbyte = 8'h3A;
          5'd2:  nbyte = trit_char(tx_old);
          5'd3:  nbyte = 8'h3E;  // '>'
          5'd4:  nbyte = trit_char(tx_val);
          5'd5:  nbyte = 8'h20;
          5'd6:  nbyte = 8'h73;  // 's'
          5'd7:  nbyte = 8'h3A;
          5'd8:  nbyte = hex_char(meta_hi);
          5'd9:  nbyte = hex_char(meta_lo);
          5'd10: nbyte = 8'h20;
          5'd11: nbyte = 8'h67;  // 'g'  (ghost)
          5'd12: nbyte = 8'h3A;
          5'd13: nbyte = departure_valid ? trit_char(departure_val) : 8'h2E;  // '.' if no ghost
          5'd14: nbyte = 8'h0D;
          5'd15: nbyte = 8'h0A;
          default: nbyte = 8'h20;
        endcase
      end
      default: nbyte = 8'h20;
    endcase
  end

  wire [4:0] last_bidx =
    (tx_mode == TX_K) ? 5'd14 :
    (tx_mode == TX_C) ? 5'd15 :
    (tx_mode == TX_D) ? 5'd12 :
    (tx_mode == TX_Z) ? 5'd5  : 5'd12;

  always @(posedge clk) begin
    spulse <= 0;
    if (do_keno || do_pler || do_pres || do_most || do_dump || do_zero || do_comp) begin
      sending <= 1;
      bidx    <= 0;
      tx_addr <= rsp_addr;
      tx_val  <= rsp_new;
      tx_old  <= rsp_old;
      tx_meta <= rsp_meta;
      if      (do_keno) tx_mode <= TX_K;
      else if (do_pler) tx_mode <= TX_P;
      else if (do_pres) tx_mode <= TX_Q;
      else if (do_most) tx_mode <= TX_M;
      else if (do_comp) tx_mode <= TX_C;
      else if (do_dump) tx_mode <= TX_D;
      else              tx_mode <= TX_Z;
    end else if (sending && uready && !spulse) begin
      sbyte  <= nbyte;
      spulse <= 1;
      if (bidx == last_bidx) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx_pin), .ready(uready));

endmodule
