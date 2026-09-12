// tritalu.v — Тритное АЛУ: 9 операций
//
// Два тритных операнда A, B ∈ {KEN(-1), PRS(0), PLR(+1)} — базовые триты.
// 9 операций: ADD, SUB, MUL, MIN, MAX, NOT_A, NEG_B, EQ, CMP
//
// Операнды — базовые триты (-1, 0, +1), не -13..+13.
// АЛУ — ядро: результат тоже тритный.
//
// Богословие:
//   ADD: встреча — дар суммируется
//   SUB: разрыв — кенозис одного через другого
//   MUL: произведение — свидетельство
//   MIN: Łukasiewicz T-AND — наименьшее из двух
//   MAX: Łukasiewicz T-OR — наибольшее из двух
//   NOT_A: Łukasiewicz отрицание A (-A)
//   NEG_B: отрицание B (-B)
//   EQ:  равенство → PLR(+1) если A==B, иначе KEN(-1)
//   CMP: сравнение → знак(A-B)
//
// UART RX (115200, pin 18):
//   'a' T  — установить A (T = '+'/'-'/'0')
//   'b' T  — установить B
//   'o' N  — выбрать операцию N (0-8, ASCII цифра)
//   '='    — вычислить и вывести
//   '!'    — прогнать все 9 операций для текущих A,B
//
// UART TX: "A:- OP:ADD B:+ = +\r\n" (22 байт)
//   или для '!': все 9 строк подряд
//
// LED: ~{h2,h1,h0} результата (h2=res, h1=A-offset, h0=B-offset)

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

// ── Тритное АЛУ ──────────────────────────────────────────────────────────────

module tritalu (
  input  wire       clk,
  input  wire       rx,
  output wire       uart_tx,
  output wire [5:0] leds
);

  // Операнды: 2'b00=KEN(-1), 2'b01=PRS(0), 2'b10=PLR(+1)
  reg [1:0] op_a = 2'b01;  // PRS
  reg [1:0] op_b = 2'b01;
  reg [3:0] op_sel = 4'd0;  // 0..8

  // ── Тритная арифметика (все в {00=KEN, 01=PRS, 10=PLR}) ──────────────────
  // Конвертация: 00→-1, 01→0, 10→+1
  // signed: a_s = a-1, b_s = b-1 (где a,b = 0,1,2)

  function [1:0] clamp3;
    input signed [2:0] v;
    // clamp to -1..+1, encode as 00/01/10
    if (v <= -1) clamp3 = 2'b00;
    else if (v >= 1) clamp3 = 2'b10;
    else clamp3 = 2'b01;
  endfunction

  function [1:0] trit_add;
    input [1:0] a, b;
    // a_s = a-1, b_s = b-1, sum = a_s+b_s, clamp
    reg signed [2:0] s;
    begin s = $signed({1'b0,a}) + $signed({1'b0,b}) - 3'sd2; trit_add = clamp3(s); end
  endfunction

  function [1:0] trit_sub;
    input [1:0] a, b;
    reg signed [2:0] s;
    begin s = $signed({1'b0,a}) - $signed({1'b0,b}); trit_sub = clamp3(s); end
  endfunction

  function [1:0] trit_mul;
    input [1:0] a, b;
    // (-1)*(-1)=+1, (-1)*0=0, (-1)*(+1)=-1, 0*x=0, (+1)*(+1)=+1
    reg signed [2:0] p;
    begin
      p = ($signed({1'b0,a}) - 3'sd1) * ($signed({1'b0,b}) - 3'sd1);
      trit_mul = clamp3(p + 3'sd1);
    end
  endfunction

  function [1:0] trit_min;
    input [1:0] a, b;
    trit_min = (a < b) ? a : b;  // Łukasiewicz AND
  endfunction

  function [1:0] trit_max;
    input [1:0] a, b;
    trit_max = (a > b) ? a : b;  // Łukasiewicz OR
  endfunction

  function [1:0] trit_not;
    input [1:0] a;
    // NOT: PLR→KEN, PRS→PRS, KEN→PLR
    case (a)
      2'b10: trit_not = 2'b00;
      2'b00: trit_not = 2'b10;
      default: trit_not = 2'b01;
    endcase
  endfunction

  function [1:0] trit_eq;
    input [1:0] a, b;
    trit_eq = (a == b) ? 2'b10 : 2'b00;  // PLR если равны, KEN иначе
  endfunction

  function [1:0] trit_cmp;
    input [1:0] a, b;
    trit_cmp = (a == b) ? 2'b01 : (a > b) ? 2'b10 : 2'b00;
  endfunction

  // АЛУ: вычислить результат по op_sel
  reg [1:0] alu_result;
  always @(*) begin
    case (op_sel)
      4'd0: alu_result = trit_add(op_a, op_b);   // ADD
      4'd1: alu_result = trit_sub(op_a, op_b);   // SUB
      4'd2: alu_result = trit_mul(op_a, op_b);   // MUL
      4'd3: alu_result = trit_min(op_a, op_b);   // MIN
      4'd4: alu_result = trit_max(op_a, op_b);   // MAX
      4'd5: alu_result = trit_not(op_a);          // NOT_A
      4'd6: alu_result = trit_not(op_b);          // NEG_B
      4'd7: alu_result = trit_eq(op_a, op_b);    // EQ
      4'd8: alu_result = trit_cmp(op_a, op_b);   // CMP
      default: alu_result = 2'b01;
    endcase
  end

  // ── UART RX ───────────────────────────────────────────────────────────────
  wire [7:0] rx_data;
  wire       rx_ready;
  uart_rx urx(.clk(clk), .rx(rx), .data(rx_data), .ready(rx_ready));

  localparam ST_IDLE = 2'd0, ST_SET_A = 2'd1, ST_SET_B = 2'd2;
  reg [1:0] parse_st = ST_IDLE;

  reg do_calc  = 0;  // одна операция
  reg do_all   = 0;  // все 9 операций

  function [1:0] sym_to_trit;
    input [7:0] s;
    case (s)
      8'h2B: sym_to_trit = 2'b10;  // '+'
      8'h2D: sym_to_trit = 2'b00;  // '-'
      default: sym_to_trit = 2'b01;  // '0' или что угодно
    endcase
  endfunction

  always @(posedge clk) begin
    do_calc <= 0;
    do_all  <= 0;
    if (rx_ready) begin
      case (parse_st)
        ST_IDLE: case (rx_data)
          8'h61: parse_st <= ST_SET_A;  // 'a'
          8'h62: parse_st <= ST_SET_B;  // 'b'
          8'h6F: ;  // 'o' — следующий байт в idle тоже
          8'h3D: do_calc <= 1;  // '='
          8'h21: do_all  <= 1;  // '!'
          8'h30, 8'h31, 8'h32, 8'h33, 8'h34,
          8'h35, 8'h36, 8'h37, 8'h38: begin
            // ASCII '0'..'8' — выбор операции
            op_sel <= rx_data[3:0];
          end
          default: ;
        endcase
        ST_SET_A: begin
          op_a <= sym_to_trit(rx_data);
          parse_st <= ST_IDLE;
        end
        ST_SET_B: begin
          op_b <= sym_to_trit(rx_data);
          parse_st <= ST_IDLE;
        end
        default: parse_st <= ST_IDLE;
      endcase
    end
  end

  // ── LED: результат ────────────────────────────────────────────────────────
  // leds[5:4] = alu_result, leds[3:2] = op_a, leds[1:0] = op_b
  assign leds = ~{alu_result, op_a, op_b};

  // ── TX машина ─────────────────────────────────────────────────────────────
  // "A:x OP:NNN B:y = z\r\n" ≈ 22 байт
  // Имена операций (3 буквы):
  //   ADD SUB MUL MIN MAX NOT NEG  EQ CMP

  // Защёлка
  reg [1:0]  tx_a = 2'b01, tx_b = 2'b01, tx_res = 2'b01;
  reg [3:0]  tx_op = 0;
  reg        tx_trigger = 0;
  reg        tx_do_all  = 0;
  reg [3:0]  all_op_cnt = 0;  // для режима '!' (0..8)

  always @(posedge clk) begin
    tx_trigger <= 0;
    tx_do_all  <= 0;
    if (do_calc) begin
      tx_a <= op_a; tx_b <= op_b; tx_res <= alu_result; tx_op <= op_sel;
      tx_trigger <= 1;
    end else if (do_all) begin
      tx_a <= op_a; tx_b <= op_b;
      all_op_cnt <= 0;
      tx_do_all  <= 1;
    end
  end

  function [7:0] trit_byte;
    input [1:0] v;
    case (v)
      2'b10: trit_byte = 8'h2B;
      2'b00: trit_byte = 8'h2D;
      default: trit_byte = 8'h30;
    endcase
  endfunction

  // Имена операций: 3 байта каждая
  // 0:ADD 1:SUB 2:MUL 3:MIN 4:MAX 5:NOT 6:NEG 7:EQ_ 8:CMP
  function [23:0] op_name;
    input [3:0] op;
    case (op)
      4'd0: op_name = 24'h414444;  // ADD
      4'd1: op_name = 24'h535542;  // SUB
      4'd2: op_name = 24'h4D554C;  // MUL
      4'd3: op_name = 24'h4D494E;  // MIN
      4'd4: op_name = 24'h4D4158;  // MAX
      4'd5: op_name = 24'h4E4F54;  // NOT
      4'd6: op_name = 24'h4E4547;  // NEG
      4'd7: op_name = 24'h455120;  // EQ_
      4'd8: op_name = 24'h434D50;  // CMP
      default: op_name = 24'h3F3F3F;
    endcase
  endfunction

  // Compute result for given op (for '!' mode)
  function [1:0] alu_for_op;
    input [3:0] o;
    input [1:0] a, b;
    case (o)
      4'd0: alu_for_op = trit_add(a, b);
      4'd1: alu_for_op = trit_sub(a, b);
      4'd2: alu_for_op = trit_mul(a, b);
      4'd3: alu_for_op = trit_min(a, b);
      4'd4: alu_for_op = trit_max(a, b);
      4'd5: alu_for_op = trit_not(a);
      4'd6: alu_for_op = trit_not(b);
      4'd7: alu_for_op = trit_eq(a, b);
      4'd8: alu_for_op = trit_cmp(a, b);
      default: alu_for_op = 2'b01;
    endcase
  endfunction

  // TX: "A:x OP:NNN B:y = z\r\n" = 20 байт (bidx 0..19)
  //  0:'A' 1:':' 2:tx_a 3:' ' 4:'O' 5:'P' 6:':' 7..9:op_name 10:' '
  // 11:'B' 12:':' 13:tx_b 14:' ' 15:'=' 16:' ' 17:tx_res 18:'\r' 19:'\n'

  reg [4:0] bidx    = 0;
  reg sending = 0, spulse = 0;
  reg [7:0] sbyte = 0;
  wire uready;

  // Защёлка для текущей операции при выводе '!'
  reg [1:0]  cur_res   = 2'b01;
  reg [23:0] cur_opname = 0;

  reg [7:0] nbyte;
  always @(*) begin
    case (bidx)
      5'd0:  nbyte = 8'h41;  // 'A'
      5'd1:  nbyte = 8'h3A;  // ':'
      5'd2:  nbyte = trit_byte(tx_a);
      5'd3:  nbyte = 8'h20;
      5'd4:  nbyte = 8'h4F;  // 'O'
      5'd5:  nbyte = 8'h50;  // 'P'
      5'd6:  nbyte = 8'h3A;
      5'd7:  nbyte = cur_opname[23:16];
      5'd8:  nbyte = cur_opname[15:8];
      5'd9:  nbyte = cur_opname[7:0];
      5'd10: nbyte = 8'h20;
      5'd11: nbyte = 8'h42;  // 'B'
      5'd12: nbyte = 8'h3A;
      5'd13: nbyte = trit_byte(tx_b);
      5'd14: nbyte = 8'h20;
      5'd15: nbyte = 8'h3D;  // '='
      5'd16: nbyte = 8'h20;
      5'd17: nbyte = trit_byte(cur_res);
      5'd18: nbyte = 8'h0D;
      5'd19: nbyte = 8'h0A;
      default: nbyte = 8'h20;
    endcase
  end

  // Режим '!': отправляем 9 строк подряд
  reg do_all_mode = 0;

  always @(posedge clk) begin
    spulse <= 0;
    if (tx_trigger) begin
      sending     <= 1;
      bidx        <= 0;
      do_all_mode <= 0;
      cur_res     <= tx_res;
      cur_opname  <= op_name(tx_op);
    end else if (tx_do_all) begin
      sending     <= 1;
      bidx        <= 0;
      do_all_mode <= 1;
      all_op_cnt  <= 0;
      cur_res     <= alu_for_op(4'd0, tx_a, tx_b);
      cur_opname  <= op_name(4'd0);
    end else if (sending && uready && !spulse) begin
      sbyte <= nbyte;
      spulse <= 1;
      if (bidx == 5'd19) begin
        if (do_all_mode && all_op_cnt < 4'd8) begin
          // следующая операция
          all_op_cnt <= all_op_cnt + 4'd1;
          cur_res    <= alu_for_op(all_op_cnt + 4'd1, tx_a, tx_b);
          cur_opname <= op_name(all_op_cnt + 4'd1);
          bidx <= 0;
        end else begin
          sending <= 0;
          bidx    <= 0;
        end
      end else bidx <= bidx + 1;
    end
  end

  uart_tx utx(.clk(clk), .data(sbyte), .start(spulse), .tx(uart_tx), .ready(uready));

endmodule
