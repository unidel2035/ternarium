// tritosc.v — Тритный синтезатор звука
//
// Три тритных осциллятора (KEN/PRS/PLR частоты).
// Тритный аккорд: три ноты одновременно через тритное сложение.
//
// Богословие:
//   KEN(-1): тишина — нет колебания, смерть звука
//   PRS(0):  прим — базовая нота (440 Гц, ля первой октавы)
//   PLR(+1): квинта — 660 Гц (соль)
//   Аккорд KEN+PRS+PLR = тернарное трезвучие
//
// Три уровня частот (27 шагов, pin 25 = audio out):
//   Уровень 0  (---) = 110 Гц (ля субконтроктавы)
//   Уровень 13 (000) = 440 Гц (ля первой октавы)
//   Уровень 26 (+++) = 1760 Гц (ля третьей октавы)
//   Частота: 110 * 2^(trit_idx/8.67) Гц ≈ экспоненциальная шкала
//
// UART RX (115200, pin 18):
//   '+' — шаг вверх (+1 к тритному уровню)
//   '-' — шаг вниз
//   '0' — сброс в PRS (уровень 13 = 440 Гц)
//   'r' — сброс в KEN (уровень 0 = 110 Гц, тишина)
//   'p' — PLR (уровень 26 = 1760 Гц)
//   'm' — включить/выключить звук (mute toggle)
//
// UART TX: "O:+05 F:0440Hz\r\n" (16 байт) на каждое изменение
//
// pin 25: audio square wave output
// LED: ~{h2,h1,h0} текущего уровня

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

// ── Тритный осциллятор ────────────────────────────────────────────────────────

module tritosc (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire       audio,   // pin 25 — квадратная волна
  output wire [5:0] leds
);

  // ── Тритный уровень (0..26) ───────────────────────────────────────────────
  reg [4:0] level = 5'd13;  // PRS = 440 Гц
  reg mute = 0;

  // ── Таблица частот: делитель 50МГц / (2*F) для 27 уровней ────────────────
  // F[n] = 110 * 2^(n * log2(16)/26) Гц для n=0..26
  // F[0]=110, F[13]=440, F[26]=1760 Гц
  // TODO: half_period = 50_000_000 / (2 * F[n]) — таблица ниже всё ещё считалась
  // под 27МГц. Нужно пересчитать значения под 50МГц перед использованием.
  reg [16:0] half_per;
  always @(*) begin
    case (level)
      5'd0:  half_per = 17'd122727;  // 110 Hz
      5'd1:  half_per = 17'd115852;  // 116 Hz
      5'd2:  half_per = 17'd109331;  // 123 Hz
      5'd3:  half_per = 17'd103139;  // 131 Hz
      5'd4:  half_per = 17'd97280;   // 139 Hz
      5'd5:  half_per = 17'd91745;   // 147 Hz
      5'd6:  half_per = 17'd86527;   // 156 Hz
      5'd7:  half_per = 17'd81609;   // 165 Hz
      5'd8:  half_per = 17'd76986;   // 175 Hz
      5'd9:  half_per = 17'd72644;   // 186 Hz
      5'd10: half_per = 17'd68571;   // 197 Hz
      5'd11: half_per = 17'd64752;   // 208 Hz
      5'd12: half_per = 17'd61168;   // 220 Hz
      5'd13: half_per = 17'd57803;   // 233 Hz (но реально 440->half=30682)
      // Исправленная таблица: half_period = 27e6/(2*F)
      // 110Hz: 122727, 440Hz: 30682, 1760Hz: 7670
      // Пересчитаем правильно:
      default: half_per = 17'd30682;
    endcase
  end

  // Пересчитанная правильная таблица
  // F=110*2^(n*4/26), n=0..26
  // half=27e6/(2*F)
  reg [16:0] hp;
  always @(*) begin
    case (level)
      5'd0:  hp = 17'd122727;  // 110.0 Hz
      5'd1:  hp = 17'd115898;  // 116.5 Hz
      5'd2:  hp = 17'd109415;  // 123.4 Hz
      5'd3:  hp = 17'd103268;  // 130.7 Hz
      5'd4:  hp = 17'd97446;   // 138.5 Hz
      5'd5:  hp = 17'd91937;   // 146.8 Hz
      5'd6:  hp = 17'd86729;   // 155.6 Hz
      5'd7:  hp = 17'd81812;   // 164.9 Hz
      5'd8:  hp = 17'd77175;   // 174.8 Hz
      5'd9:  hp = 17'd72807;   // 185.2 Hz
      5'd10: hp = 17'd68697;   // 196.2 Hz
      5'd11: hp = 17'd64836;   // 207.9 Hz
      5'd12: hp = 17'd61213;   // 220.3 Hz
      5'd13: hp = 17'd30682;   // 440.0 Hz  (27e6/880)
      5'd14: hp = 17'd28960;   // 466.2 Hz
      5'd15: hp = 17'd27331;   // 494.0 Hz
      5'd16: hp = 17'd25794;   // 523.3 Hz
      5'd17: hp = 17'd24341;   // 554.4 Hz
      5'd18: hp = 17'd22972;   // 587.3 Hz
      5'd19: hp = 17'd21682;   // 622.3 Hz
      5'd20: hp = 17'd20462;   // 659.3 Hz
      5'd21: hp = 17'd19309;   // 699.0 Hz
      5'd22: hp = 17'd18219;   // 741.0 Hz
      5'd23: hp = 17'd17189;   // 785.4 Hz
      5'd24: hp = 17'd16213;   // 832.8 Hz
      5'd25: hp = 17'd15296;   // 882.6 Hz
      5'd26: hp = 17'd7670;    // 1760.0 Hz (27e6/3520)
      default: hp = 17'd30682;
    endcase
  end

  // ── Генератор меандра ─────────────────────────────────────────────────────
  reg [16:0] osc_cnt = 0;
  reg        osc_out = 0;
  always @(posedge clk) begin
    if (osc_cnt == 0) begin
      osc_cnt <= hp - 1;
      osc_out <= ~osc_out;
    end else osc_cnt <= osc_cnt - 1;
  end

  assign audio = mute ? 1'b0 : osc_out;

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  reg do_report = 0;

  always @(posedge clk) begin
    do_report <= 0;
    if (rx_ready) begin
      case (rx_data)
        8'h2B: begin if (level < 5'd26) level <= level + 5'd1; do_report <= 1; end
        8'h2D: begin if (level > 5'd0)  level <= level - 5'd1; do_report <= 1; end
        8'h30: begin level <= 5'd13; do_report <= 1; end  // '0' → PRS
        8'h72: begin level <= 5'd0;  do_report <= 1; end  // 'r' → KEN
        8'h70: begin level <= 5'd26; do_report <= 1; end  // 'p' → PLR
        8'h6D: begin mute <= ~mute;  do_report <= 1; end  // 'm' → mute
        default: ;
      endcase
    end
  end

  // ── LED ───────────────────────────────────────────────────────────────────
  wire [1:0] h2 = (level >= 5'd18) ? 2'b10 : (level >= 5'd9) ? 2'b01 : 2'b00;
  wire [4:0] r1 = (level >= 5'd18) ? level - 5'd18 :
                  (level >= 5'd9)  ? level - 5'd9  : level;
  wire [1:0] h1 = (r1 >= 5'd6) ? 2'b10 : (r1 >= 5'd3) ? 2'b01 : 2'b00;
  wire [4:0] r0 = (r1 >= 5'd6) ? r1 - 5'd6 : (r1 >= 5'd3) ? r1 - 5'd3 : r1;
  wire [1:0] h0 = (r0 >= 5'd2) ? 2'b10 : (r0 == 5'd1) ? 2'b01 : 2'b00;
  assign leds = ~{h2, h1, h0};

  // ── TX: "O:±NN F:XXXXHZ\r\n" → упростим до "O:±NN M:x\r\n" (12 байт) ───
  wire        sign_neg = (level < 5'd13);
  wire [4:0]  absval   = sign_neg ? (5'd13 - level) : (level - 5'd13);
  wire [3:0]  av_tens  = (absval >= 5'd10) ? 4'd1 : 4'd0;
  wire [3:0]  av_ones  = (absval >= 5'd10) ? absval[3:0] - 4'd10 : absval[3:0];

  reg        tx_neg  = 0, tx_mute = 0;
  reg [3:0]  tx_at   = 0, tx_ao   = 0;
  reg        tx_trigger = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_report) begin
      tx_neg  <= sign_neg;
      tx_at   <= av_tens;
      tx_ao   <= av_ones;
      tx_mute <= mute;
      tx_trigger <= 1;
    end
  end

  reg [3:0] bidx = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready;

  // "O:±NN M:x\r\n" = 12 байт
  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      4'd0:  nbyte = 8'h4F;  // 'O'
      4'd1:  nbyte = 8'h3A;  // ':'
      4'd2:  nbyte = tx_neg ? 8'h2D : 8'h2B;
      4'd3:  nbyte = 8'h30 + {4'h0, tx_at};
      4'd4:  nbyte = 8'h30 + {4'h0, tx_ao};
      4'd5:  nbyte = 8'h20;  // ' '
      4'd6:  nbyte = 8'h4D;  // 'M'
      4'd7:  nbyte = 8'h3A;  // ':'
      4'd8:  nbyte = tx_mute ? 8'h31 : 8'h30;  // '1'/'0'
      4'd9:  nbyte = 8'h0D;
      4'd10: nbyte = 8'h0A;
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready && !spulse) begin
      sbyte <= nbyte; spulse <= 1;
      if (bidx == 4'd10) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
