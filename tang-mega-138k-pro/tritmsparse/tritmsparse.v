// tritmsparse.v — MSP парсер для Betaflight телеметрии
//
// Принимает MSP v1 пакеты с FC (Flight Controller),
// декодирует MSP_STATUS и MSP_ATTITUDE,
// отображает данные через тритную призму на LED и UART.
//
// Богословие: FC не знает что Tang Nano наблюдает.
// Каждый статус — исповедание состояния машины.
// Tang Nano — немой свидетель, превращающий байты в триты.
//
// MSP v1 формат:
//   '$' 'M' '<' size cmd [payload] crc
//   CRC = XOR(size, cmd, payload...)
//
// Поддерживаемые команды:
//   MSP_STATUS   = 101: [cycletime(2) i2cerr(2) sensor(2) mode(4) profile(1)]
//   MSP_ATTITUDE = 108: [roll(2) pitch(2) yaw(2)] — углы × 10 (градусы)
//
// Tang Nano отправляет MSP_STATUS_EX запросы каждые 500мс,
// читает ответ и выводит через UART тритную интерпретацию.
//
// Тритная интерпретация угла (roll/pitch -180..+180):
//   Угол < -60°  → KEN (отклонение в минус)
//   -60..+60°    → PRS (близко к горизонту)
//   Угол > +60°  → PLR (отклонение в плюс)
//
// UART A (115200, pin 17/18) — к ноуту, вывод тритного статуса
// UART B (115200, pin 25/26) — к FC (MSP)
//
// LED: ~{roll_trit, pitch_trit} — тритный горизонт

`default_nettype none

// ── UART TX ──────────────────────────────────────────────────────────────────

module uart_tx_m (
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

module uart_rx_m (
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

// ── MSP парсер ───────────────────────────────────────────────────────────────

module tritmsparse (
  input  wire       clk,
  input  wire       rx_a,   // pin 18 — от ноута (управление)
  input  wire       rx_b,   // pin 26 — от FC (MSP ответы)
  output wire       tx_a,   // pin 17 — к ноуту (отчёт)
  output wire       tx_b,   // pin 25 — к FC (MSP запросы)
  output wire [5:0] leds
);

  // ── UART каналы ──────────────────────────────────────────────────────────
  wire [7:0] rx_a_data; wire rx_a_ready;
  uart_rx_m urx_a(.clk(clk), .rx(rx_a), .data(rx_a_data), .ready(rx_a_ready));

  wire [7:0] rx_b_data; wire rx_b_ready;
  uart_rx_m urx_b(.clk(clk), .rx(rx_b), .data(rx_b_data), .ready(rx_b_ready));

  wire tx_a_ready; reg [7:0] a_sbyte=0; reg a_start=0;
  uart_tx_m utx_a(.clk(clk), .data(a_sbyte), .start(a_start), .tx(tx_a), .ready(tx_a_ready));

  wire tx_b_ready; reg [7:0] b_sbyte=0; reg b_start=0;
  uart_tx_m utx_b(.clk(clk), .data(b_sbyte), .start(b_start), .tx(tx_b), .ready(tx_b_ready));

  // ── Таймер запросов (каждые 500 мс) ──────────────────────────────────────
  reg [23:0] req_cnt  = 0;
  reg        req_tick = 0;
  always @(posedge clk) begin
    req_tick <= 0;
    if (req_cnt >= 24'd13499999) begin req_cnt <= 0; req_tick <= 1; end
    else req_cnt <= req_cnt + 1;
  end

  // ── MSP запрос: $ M < 0 108 108 (MSP_ATTITUDE) ───────────────────────────
  // Пакет: 0x24 0x4D 0x3C 0x00 0x6C 0x6C  (6 байт)
  localparam MSP_ATT_LEN = 4'd5;  // 5 байт (без '$')
  reg [7:0] msp_req [0:4];
  initial begin
    msp_req[0] = 8'h4D;  // 'M'
    msp_req[1] = 8'h3C;  // '<'
    msp_req[2] = 8'h00;  // size=0
    msp_req[3] = 8'h6C;  // cmd=108
    msp_req[4] = 8'h6C;  // crc=108 XOR 0 = 108
  end

  reg [2:0] req_bidx = 0;
  reg       req_send = 0, req_pulse = 0;

  always @(posedge clk) begin
    b_start <= 0;
    if (req_tick && !req_send) begin
      b_sbyte <= 8'h24;  // '$'
      b_start <= 1;
      req_send <= 1;
      req_bidx <= 0;
    end else if (req_send && tx_b_ready && !b_start) begin
      if (req_bidx <= MSP_ATT_LEN - 1) begin
        b_sbyte <= msp_req[req_bidx];
        b_start <= 1;
        req_bidx <= req_bidx + 1;
      end else req_send <= 0;
    end
  end

  // ── MSP парсер ответа ─────────────────────────────────────────────────────
  // Состояния: WAIT_$ → WAIT_M → WAIT_DIR → WAIT_SIZE → WAIT_CMD →
  //            PAYLOAD → WAIT_CRC
  localparam
    MSP_WAIT_D = 3'd0,  // '$'
    MSP_WAIT_M = 3'd1,  // 'M'
    MSP_WAIT_R = 3'd2,  // '>'
    MSP_WAIT_S = 3'd3,  // size
    MSP_WAIT_C = 3'd4,  // cmd
    MSP_PAYLOAD = 3'd5,
    MSP_CRC    = 3'd6;

  reg [2:0]  msp_st   = MSP_WAIT_D;
  reg [7:0]  msp_size = 0;
  reg [7:0]  msp_cmd  = 0;
  reg [7:0]  msp_pi   = 0;  // payload index
  reg [7:0]  msp_crc  = 0;
  reg [7:0]  pl [0:11]; // до 12 байт payload
  integer k;
  initial for (k = 0; k < 12; k = k+1) pl[k] = 0;

  reg att_valid = 0;

  always @(posedge clk) begin
    att_valid <= 0;
    if (rx_b_ready) begin
      case (msp_st)
        MSP_WAIT_D: if (rx_b_data == 8'h24) msp_st <= MSP_WAIT_M;
        MSP_WAIT_M: msp_st <= (rx_b_data == 8'h4D) ? MSP_WAIT_R : MSP_WAIT_D;
        MSP_WAIT_R: msp_st <= (rx_b_data == 8'h3E) ? MSP_WAIT_S : MSP_WAIT_D;
        MSP_WAIT_S: begin
          msp_size <= rx_b_data;
          msp_crc  <= rx_b_data;
          msp_st   <= MSP_WAIT_C;
        end
        MSP_WAIT_C: begin
          msp_cmd <= rx_b_data;
          msp_crc <= msp_crc ^ rx_b_data;
          msp_pi  <= 0;
          msp_st  <= (msp_size > 0) ? MSP_PAYLOAD : MSP_CRC;
        end
        MSP_PAYLOAD: begin
          if (msp_pi < 12) pl[msp_pi] <= rx_b_data;
          msp_crc <= msp_crc ^ rx_b_data;
          msp_pi  <= msp_pi + 1;
          if (msp_pi + 1 >= msp_size) msp_st <= MSP_CRC;
        end
        MSP_CRC: begin
          msp_st <= MSP_WAIT_D;
          if (rx_b_data == msp_crc && msp_cmd == 8'h6C)
            att_valid <= 1;  // MSP_ATTITUDE ответ
        end
        default: msp_st <= MSP_WAIT_D;
      endcase
    end
  end

  // ── Декодирование attitude (roll/pitch/yaw) ───────────────────────────────
  // roll  = pl[0] + pl[1]*256  (signed, единицы 0.1°)
  // pitch = pl[2] + pl[3]*256
  // yaw   = pl[4] + pl[5]*256 (0..3600, единицы 0.1°)

  reg signed [15:0] att_roll  = 0;
  reg signed [15:0] att_pitch = 0;
  reg        [15:0] att_yaw   = 0;

  // Тритная интерпретация: ±60° порог (600 в единицах 0.1°)
  // roll_trit: 2'b00=KEN(<-600), 2'b01=PRS(-600..+600), 2'b10=PLR(>+600)
  wire [1:0] roll_trit  = (att_roll  < -600) ? 2'b00 :
                          (att_roll  >  600)  ? 2'b10 : 2'b01;
  wire [1:0] pitch_trit = (att_pitch < -600) ? 2'b00 :
                          (att_pitch >  600)  ? 2'b10 : 2'b01;
  wire [1:0] yaw_trit   = (att_yaw  < 16'd1200) ? 2'b00 :
                          (att_yaw  > 16'd2400)  ? 2'b10 : 2'b01;

  reg do_report = 0;

  always @(posedge clk) begin
    do_report <= 0;
    if (att_valid) begin
      att_roll  <= $signed({pl[1], pl[0]});
      att_pitch <= $signed({pl[3], pl[2]});
      att_yaw   <= {pl[5], pl[4]};
      do_report <= 1;
    end
  end

  // ── LED ───────────────────────────────────────────────────────────────────
  assign leds = ~{roll_trit, pitch_trit, yaw_trit};

  // ── TX к ноуту: "R:± P:± Y:±\r\n" (13 байт) ─────────────────────────────
  function [7:0] tc;
    input [1:0] v;
    case (v)
      2'b10: tc = 8'h2B;
      2'b00: tc = 8'h2D;
      default: tc = 8'h30;
    endcase
  endfunction

  reg [1:0] tx_roll=2'b01, tx_pitch=2'b01, tx_yaw=2'b01;
  reg       tx_trigger = 0;

  always @(posedge clk) begin
    tx_trigger <= 0;
    if (do_report) begin
      tx_roll  <= roll_trit;
      tx_pitch <= pitch_trit;
      tx_yaw   <= yaw_trit;
      tx_trigger <= 1;
    end
  end

  reg [3:0] bidx = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready_a;
  assign uready_a = tx_a_ready;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      4'd0:  nbyte = 8'h52;  // 'R'
      4'd1:  nbyte = 8'h3A;  // ':'
      4'd2:  nbyte = tc(tx_roll);
      4'd3:  nbyte = 8'h20;
      4'd4:  nbyte = 8'h50;  // 'P'
      4'd5:  nbyte = 8'h3A;
      4'd6:  nbyte = tc(tx_pitch);
      4'd7:  nbyte = 8'h20;
      4'd8:  nbyte = 8'h59;  // 'Y'
      4'd9:  nbyte = 8'h3A;
      4'd10: nbyte = tc(tx_yaw);
      4'd11: nbyte = 8'h0D;
      4'd12: nbyte = 8'h0A;
      default: nbyte = 8'h20;
    endcase
  end

  always @(posedge clk) begin
    a_start <= 0;
    if (tx_trigger) begin sending <= 1; bidx <= 0; end
    else if (sending && uready_a && !a_start) begin
      a_sbyte <= nbyte; a_start <= 1;
      if (bidx == 4'd12) begin sending <= 0; bidx <= 0; end
      else bidx <= bidx + 1;
    end
  end

endmodule
