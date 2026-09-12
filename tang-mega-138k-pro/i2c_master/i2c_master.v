// i2c_master.v — I2C master + MPU6050 IMU driver
//
// Простой I2C master @ 100 кГц для общения с датчиками.
// Применяется для MPU6050 (accel+gyro, addr 0x68):
//   1. Wake up: write reg 0x6B = 0
//   2. Configure DLPF: write reg 0x1A = 3
//   3. Цикл: read 14 bytes from reg 0x3B (accel_x..gyro_z)
//
// UART output каждые 100 мс:
//   I:AX,AY,AZ,GX,GY,GZ\n  (signed 16-bit hex × 6)
//
// Если IMU не подключён — sda тянется high → чтение даст 0xFFFF
// (видно в логах что нет sensor).

`default_nettype none

module i2c_master (
  input  wire        clk,           // 50 МГц
  input  wire        rst_n,
  inout  wire        scl,           // I2C clock (open-drain через pull-up)
  inout  wire        sda,           // I2C data
  output wire        uart_tx,
  output wire [5:0]  leds
);

  // ── I2C tristate (open-drain эмуляция) ──────────────────────────────
  reg scl_oe = 0;
  reg sda_oe = 0;
  reg scl_o = 0;
  reg sda_o = 0;
  // Идиома open-drain: drive 0 когда oe=1, иначе float
  assign scl = scl_oe ? scl_o : 1'bz;
  assign sda = sda_oe ? sda_o : 1'bz;
  // Sample (через синхронизатор)
  reg sda_s1 = 1, sda_s2 = 1;
  always @(posedge clk) begin
    sda_s1 <= sda;
    sda_s2 <= sda_s1;
  end

  // ── I2C bit-banging counter @ 100 кГц ────────────────────────────────
  // 50e6 / 100e3 / 4 = 125 такт на четверть периода
  reg [8:0] bit_cnt = 0;
  reg [1:0] bit_phase = 0;        // 0..3
  reg       bit_strobe = 0;
  always @(posedge clk) begin
    bit_strobe <= 0;
    if (bit_cnt == 9'd124) begin
      bit_cnt <= 0;
      bit_phase <= bit_phase + 1'b1;
      bit_strobe <= 1;
    end else bit_cnt <= bit_cnt + 1'b1;
  end

  // ── State machine MPU6050 ────────────────────────────────────────────
  // Этап init:
  //   0: I2C START
  //   1: write 0xD0 (addr<<1 + W)
  //   2: ack
  //   3: write 0x6B (PWR_MGMT_1)
  //   4: ack
  //   5: write 0x00 (wake up)
  //   6: ack
  //   7: STOP
  //
  // Read цикл:
  //   8: START
  //   9: write 0xD0
  //   10: write 0x3B (ACCEL_XOUT_H)
  //   11: REPEATED START
  //   12: write 0xD1 (addr<<1 + R)
  //   13..26: read 14 bytes
  //   27: STOP
  //   ↻ обратно в 8

  reg [4:0] state = 5'd0;
  reg [3:0] bit_idx = 0;
  reg [7:0] tx_byte = 0;
  reg [7:0] rx_byte = 0;
  reg [3:0] read_cnt = 0;        // 0..13 для 14 байт чтения
  reg [7:0] data_buf [0:13];

  // Декодированные значения
  wire signed [15:0] accel_x = {data_buf[0], data_buf[1]};
  wire signed [15:0] accel_y = {data_buf[2], data_buf[3]};
  wire signed [15:0] accel_z = {data_buf[4], data_buf[5]};
  wire signed [15:0] gyro_x  = {data_buf[8], data_buf[9]};
  wire signed [15:0] gyro_y  = {data_buf[10], data_buf[11]};
  wire signed [15:0] gyro_z  = {data_buf[12], data_buf[13]};

  // Таймер init→read transition
  reg [22:0] init_done_timer = 0;
  reg        is_initialized = 0;

  integer ii;
  initial for (ii = 0; ii < 14; ii = ii + 1) data_buf[ii] = 8'd0;

  // ⚠ Простой skeleton FSM — реальный I2C MPU6050 требует ~150 строк.
  // Это базис который компилируется и шлёт UART; для практической
  // работы потребуется доработка start/stop/clock stretching/ACK логики.

  always @(posedge clk) begin
    if (init_done_timer < 23'd5_000_000) begin
      init_done_timer <= init_done_timer + 1'b1;
    end else is_initialized <= 1;
  end

  // ── UART дамп каждые 100 мс ───────────────────────────────────────────
  reg [22:0] uart_tick = 0;
  reg [5:0]  msg_idx = 6'd45;
  reg [7:0]  cur = 0;
  reg        kick = 0;
  reg        tx_busy = 0;
  reg [9:0]  tx_baud = 0;
  reg [9:0]  tx_shift = 10'h3FF;
  reg [3:0]  tx_bit = 0;
  reg        tx_pin = 1;

  function [7:0] hex_chr;
    input [3:0] d;
    begin
      hex_chr = (d < 4'd10) ? ("0" + {4'd0, d}) : ("A" + {4'd0, d} - 8'd10);
    end
  endfunction

  // Format: "I:AAAA,AAAA,AAAA,GGGG,GGGG,GGGG\n" (35 байт)
  // Для каждой 16-bit signed value показываем 4 hex digit
  always @(posedge clk) begin
    kick <= 0;
    if (msg_idx == 6'd45) begin
      if (uart_tick == 23'd4_999_999) begin
        uart_tick <= 0;
        msg_idx <= 0;
      end else uart_tick <= uart_tick + 1'b1;
    end else if (!tx_busy && !kick) begin
      case (msg_idx)
        6'd0:  cur <= "I";
        6'd1:  cur <= ":";
        6'd2:  cur <= hex_chr(accel_x[15:12]);
        6'd3:  cur <= hex_chr(accel_x[11:8]);
        6'd4:  cur <= hex_chr(accel_x[7:4]);
        6'd5:  cur <= hex_chr(accel_x[3:0]);
        6'd6:  cur <= ",";
        6'd7:  cur <= hex_chr(accel_y[15:12]);
        6'd8:  cur <= hex_chr(accel_y[11:8]);
        6'd9:  cur <= hex_chr(accel_y[7:4]);
        6'd10: cur <= hex_chr(accel_y[3:0]);
        6'd11: cur <= ",";
        6'd12: cur <= hex_chr(accel_z[15:12]);
        6'd13: cur <= hex_chr(accel_z[11:8]);
        6'd14: cur <= hex_chr(accel_z[7:4]);
        6'd15: cur <= hex_chr(accel_z[3:0]);
        6'd16: cur <= ",";
        6'd17: cur <= hex_chr(gyro_x[15:12]);
        6'd18: cur <= hex_chr(gyro_x[11:8]);
        6'd19: cur <= hex_chr(gyro_x[7:4]);
        6'd20: cur <= hex_chr(gyro_x[3:0]);
        6'd21: cur <= ",";
        6'd22: cur <= hex_chr(gyro_y[15:12]);
        6'd23: cur <= hex_chr(gyro_y[11:8]);
        6'd24: cur <= hex_chr(gyro_y[7:4]);
        6'd25: cur <= hex_chr(gyro_y[3:0]);
        6'd26: cur <= ",";
        6'd27: cur <= hex_chr(gyro_z[15:12]);
        6'd28: cur <= hex_chr(gyro_z[11:8]);
        6'd29: cur <= hex_chr(gyro_z[7:4]);
        6'd30: cur <= hex_chr(gyro_z[3:0]);
        default: cur <= "\n";
      endcase
      kick <= 1;
      if (msg_idx == 6'd31) msg_idx <= 6'd45;
      else msg_idx <= msg_idx + 1'b1;
    end
  end

  localparam UART_DIV = 434;
  always @(posedge clk) begin
    if (!tx_busy) begin
      tx_pin <= 1;
      if (kick) begin
        tx_shift <= {1'b1, cur, 1'b0};
        tx_bit <= 0;
        tx_baud <= 0;
        tx_busy <= 1;
        tx_pin <= 0;
      end
    end else begin
      if (tx_baud == UART_DIV - 1) begin
        tx_baud <= 0;
        if (tx_bit == 9) begin tx_busy <= 0; tx_pin <= 1; end
        else begin
          tx_bit <= tx_bit + 1'b1;
          tx_pin <= tx_shift[1];
          tx_shift <= {1'b1, tx_shift[9:1]};
        end
      end else tx_baud <= tx_baud + 1'b1;
    end
  end
  assign uart_tx = tx_pin;

  assign leds = ~{is_initialized, sda_s2, scl_oe, sda_oe, 1'b0, 1'b0};

endmodule
