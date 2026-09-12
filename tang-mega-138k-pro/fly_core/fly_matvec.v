// fly_matvec.v — троичный CSR-матvec: срез коннектома мухи (FAFB v783) в BRAM
//
// y = S·x, где S — разреженная троичная матрица {−1,0,+1} в CSR-упаковке:
//   entry (16 бит) = {col[COL_AW-1:0], wcode[1:0]}, wcode 01=+1, 10=−1
//   два entry в 32-битном слове BRAM: чётный entry в [15:0], нечётный в [31:16]
// x тоже троичный (тот же код), продублирован в двух BRAM — оба entry пары
// читаются за один такт. Итог: 3 такта на слово = 1.5 такта/трит.
// @50 MHz: проход K=4096, nnz=211606 ≈ 6.3 мс.
//
// Файлы инициализации генерирует tools/fly/export_slice.py.
// Симуляция:  make sim   (в каталоге sim/, нужен iverilog)

module fly_matvec (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg  [31:0] dbg_row,   // последняя завершённая строка (для отладки)
    output wire        busy
);
`include "fly_params.vh"

    // ── память весов (CSR entries, 2 шт/слово) ──────────────────────────
    reg [31:0] entries [0:ENTRY_WORDS-1];
    initial   $readmemh("fly_slice_csr.hex", entries);
    reg [31:0] entries_q;

    // ── указатели строк (ROWS+1 шт) ─────────────────────────────────────
    reg [31:0] rowptr [0:ROWS];
    initial   $readmemh("fly_slice_rowptr.hex", rowptr);
    reg [31:0] rp_a, rp_b;                 // начало/конец текущей строки

    // ── вектор x (дублирован ради двух портов чтения) ───────────────────
    reg [31:0] xw_a [0:XWORDS-1];
    reg [31:0] xw_b [0:XWORDS-1];
    initial   $readmemh("fly_x_test.hex", xw_a);
    initial   $readmemh("fly_x_test.hex", xw_b);
    reg [31:0] xa_q, xb_q;

    // ── результат ───────────────────────────────────────────────────────
    reg signed [31:0] ymem [0:ROWS-1];

    // ── FSM ─────────────────────────────────────────────────────────────
    localparam S_IDLE  = 3'd0,   // ждём start
               S_RP    = 3'd1,   // rowptr[r], rowptr[r+1]
               S_WK    = 3'd2,   // конец строки? нет -> выборка слова
               S_XLK   = 3'd3,   // разбор пары, адреса x
               S_ACC   = 3'd4;   // аккумуляция пары
    localparam S_FIN   = 3'd5;   // done, ждём снятия start
    reg [2:0]  st;
    reg [31:0] r;
    reg signed [31:0] acc;

    reg  [COL_AW-1:0] col_a, col_b;
    reg  [1:0]        wc_a,  wc_b;
    reg               vb_ok;             // второй entry пары ещё в нашей строке?

    // троичное произведение: коды 00=0, 01=+1, 10=−1
    function signed [31:0] term;
        input [1:0] wc;
        input [1:0] xv;
        begin
            if (wc == 2'b00 || xv == 2'b00) term = 32'd0;
            else if (wc[1] ^ xv[1])         term = -32'd1;
            else                            term = 32'd1;
        end
    endfunction

    // пара: чётный rp_a -> lo+hi, нечётный rp_a -> только hi (lo чужой)
    wire [15:0] v_a = rp_a[0] ? entries_q[31:16] : entries_q[15:0];
    wire [15:0] v_b = entries_q[31:16];

    assign busy = (st != S_IDLE) && (st != S_FIN);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; r <= 32'd0; acc <= 32'd0; done <= 1'b0;
            dbg_row <= 32'd0; rp_a <= 32'd0; rp_b <= 32'd0;
        end else begin
            case (st)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        r  <= 32'd0;
                        st <= S_RP;
                    end
                end

                S_RP: begin
                    rp_a <= rowptr[r];
                    rp_b <= rowptr[r + 1];
                    acc  <= 32'd0;
                    st   <= S_WK;
                end

                S_WK: begin
                    if (rp_a >= rp_b) begin         // строка исчерпана
                        ymem[r]  <= acc;
                        dbg_row  <= r;
                        r        <= r + 1;
                        if (r + 1 == ROWS) st <= S_FIN;
                        else               st <= S_RP;
                    end else begin
                        entries_q <= entries[rp_a[31:1]];
                        st        <= S_XLK;
                    end
                end

                S_XLK: begin
                    col_a <= v_a[COL_AW+1:2];
                    wc_a  <= v_a[1:0];
                    col_b <= v_b[COL_AW+1:2];
                    wc_b  <= v_b[1:0];
                    vb_ok <= !rp_a[0] && (rp_a + 2 <= rp_b);
                    xa_q  <= xw_a[v_a[COL_AW+1:6]];  // col_a >> 4
                    xb_q  <= xw_b[v_b[COL_AW+1:6]];  // col_b >> 4
                    st    <= S_ACC;
                end

                S_ACC: begin
                    acc  <= acc + term(wc_a, xa_q >> {col_a[3:0], 1'b0})
                                  + (vb_ok ? term(wc_b, xb_q >> {col_b[3:0], 1'b0})
                                           : 32'd0);
                    rp_a <= rp_a + (rp_a[0] ? 32'd1 : 32'd2);
                    st   <= S_WK;
                end

                S_FIN: begin
                    done <= 1'b1;
                    if (!start) st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end

`ifdef FLY_SIM
    integer cyc = 0;
    always @(posedge clk) if (st != S_IDLE) cyc <= cyc + 1;
`endif

endmodule
