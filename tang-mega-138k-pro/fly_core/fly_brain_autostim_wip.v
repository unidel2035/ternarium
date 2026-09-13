// fly_brain.v — «живой» срез мозга мухи: матvec + порог + UART-интерактив.
//
// Шаг динамики: y = S·x;  x' = +1 (y>θ) / −1 (y<−θ) / 0.
// Автодемо: после 2 с без UART-команд сам стартует (серии по 16 шагов,
// авто-стимул «сенсоров»), активность видна на LED.
//
// UART 115200 8N1 (внешний USB-TTL; onboard FT2232 = JTAG only):
//   'S' id3hex ('+'|'-') → x[id]=±1, ответ 'k'
//   'T' steps2hex        → шаги, отчёт "S=ss P=ppp N=nnn\r\n" после каждого
//   'D'                  → дамп x: ROWS байт '0'/'1'/'2'
//   'H' th2hex           → порог θ (по умолчанию 1)
//
// Золотая модель: tools/fly/brain_sim.py. Срез: fly_slice_*.hex (export_slice.py).

module fly_brain (
    input  wire       clk,        // 50 МГц
    input  wire       rst_n,      // active LOW
    input  wire       rx,
    output wire       uart_tx,
    output wire [2:0] state_led   // active LOW
);
`include "fly_params.vh"

    // ── память связей (тот же срез, что в fly_matvec) ───────────────────
    reg  [31:0] entries [0:ENTRY_WORDS-1];
    initial     $readmemh("fly_slice_csr.hex", entries);
    reg  [31:0] rowptr [0:ROWS];
    initial     $readmemh("fly_slice_rowptr.hex", rowptr);
    reg  [31:0] entries_q;

    // ── активность x (две копии ради двух портов чтения) ────────────────
    reg [1:0] xa [0:ROWS-1];
    reg [1:0] xb [0:ROWS-1];
    reg [1:0] xva, xvb;                    // коды пары колонок текущего шага

    integer ini;
    initial begin                          // активность стартует с нуля
        for (ini = 0; ini < ROWS; ini = ini + 1) begin
            xa[ini] = 2'b00;
            xb[ini] = 2'b00;
        end
    end

    // ── аккумуляторы y текущего прохода ─────────────────────────────────
    reg signed [15:0] ymem [0:ROWS-1];
    reg signed [15:0] y_q;

    reg [7:0]  theta = 8'd1;
    reg [15:0] pcount = 0, ncount = 0;

    function signed [15:0] term;
        input [1:0] wc;
        input [1:0] xv;
        begin
            if (wc == 2'b00 || xv == 2'b00) term = 16'd0;
            else if (wc[1] ^ xv[1])         term = -16'd1;
            else                            term = 16'd1;
        end
    endfunction

    function [7:0] hexn;
        input [3:0] n;
        hexn = (n < 4'd10) ? (8'h30 + {4'd0, n}) : (8'h37 + {4'd0, n});
    endfunction

    function [3:0] hexn_in;
        input [7:0] c;
        hexn_in = (c >= "0" && c <= "9") ? c[3:0] : (c[3:0] + 4'd9);
    endfunction

    function [11:0] stim_id;
        input [1:0] k;
        case (k)
            2'd0: stim_id = 12'h160;
            2'd1: stim_id = 12'h15E;
            2'd2: stim_id = 12'h096;
            default: stim_id = 12'h032;
        endcase
    endfunction

    reg [11:0] sid;
    always @(*) begin
        case (stim_idx[1:0])
            2'd0: sid = 12'h160;
            2'd1: sid = 12'h15E;
            2'd2: sid = 12'h096;
            default: sid = 12'h032;
        endcase
    end

    // ── UART TX движок ──────────────────────────────────────────────────
    reg [7:0] tx_byte;
    reg       tx_start = 0;
    wire      tx_busy;
    wire      tx_line;

    uart_tx_engine txe(.clk(clk), .rst_n(rst_n), .start(tx_start), .din(tx_byte),
                       .tx(tx_line), .busy(tx_busy));
    assign uart_tx = tx_line;

    // секвенсор: 0=простой, 1=буфер отчёта, 2='k', 3=дамп
    reg [7:0]  rbuf [0:17];
    reg [5:0]  ridx = 0;
    reg [1:0]  txsrc = 0;
    reg [15:0] dump_idx = 0;
    reg        buf_ready = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txsrc <= 0; ridx <= 0; dump_idx <= 0; tx_byte <= 0; tx_start <= 0;
        end else begin
            tx_start <= 0;
            case (txsrc)
                2'd1: if (!tx_busy && !tx_start && ridx < 6'd18) begin
                    tx_byte  <= rbuf[ridx];
                    tx_start <= 1'b1;
                    ridx     <= ridx + 6'd1;
                    if (ridx == 6'd17) txsrc <= 0;
                end
                2'd2: if (!tx_busy && !tx_start) begin
                    tx_byte  <= 8'h6B;                       // 'k'
                    tx_start <= 1'b1;
                    txsrc    <= 0;
                end
                2'd3: if (!tx_busy && !tx_start) begin
                    if (dump_idx < ROWS) begin
                        tx_byte  <= {6'b000000, xa[dump_idx[11:0]]} + 8'h30;
                        tx_start <= 1'b1;
                        dump_idx <= dump_idx + 1;
                    end else
                        txsrc <= 0;
                end
                default: ;
            endcase
        end
    end

    // ── UART RX + парсер ────────────────────────────────────────────────
    wire [7:0] rx_data;
    wire       rx_rdy;

    uart_rx_engine rxe(.clk(clk), .rst_n(rst_n), .rx(rx), .data(rx_data), .ready(rx_rdy));

    localparam [3:0] C_CMD = 4'd0, C_ID1 = 4'd1, C_ID2 = 4'd2, C_ID3 = 4'd3,
                     C_SGN = 4'd4, C_T1  = 4'd5, C_T2  = 4'd6, C_H1  = 4'd7,
                     C_H2  = 4'd8;
    reg [3:0]  cst = C_CMD;
    reg [11:0] id_sh;
    reg [7:0]  arg_sh;
    reg [15:0] steps_sh;

    wire [1:0] wr_val = (rx_data == 8'h2B) ? 2'b01 : 2'b10;   // '+' / '-'

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cst <= C_CMD; id_sh <= 0; arg_sh <= 0; steps_sh <= 0;
        end else if (rx_rdy && mst == M_IDLE && txsrc == 0 && !inj_pend) begin
            case (cst)
                C_CMD: case (rx_data)
                    8'h53: cst <= C_ID1;                            // 'S'
                    8'h54: cst <= C_T1;                             // 'T'
                    8'h44: begin dump_idx <= 0; txsrc <= 2'd3; end  // 'D'
                    8'h48: cst <= C_H1;                             // 'H'
                    default: ;
                endcase
                C_ID1: begin id_sh[11:8] <= hexn_in(rx_data); cst <= C_ID2; end
                C_ID2: begin id_sh[7:4]  <= hexn_in(rx_data); cst <= C_ID3; end
                C_ID3: begin id_sh[3:0]  <= hexn_in(rx_data); cst <= C_SGN; end
                C_SGN: begin
                    if (rx_data == 8'h2B || rx_data == 8'h2D) begin
                        inj_id  <= id_sh;
                        inj_val <= wr_val;
                        inj_pend <= 1'b1;
                        txsrc     <= 2'd2;                          // 'k'
                    end
                    cst <= C_CMD;
                end
                C_T1: begin steps_sh[7:4] <= hexn_in(rx_data); cst <= C_T2; end
                C_T2: begin
                    steps_sh[3:0] <= hexn_in(rx_data);
                    steps   <= {steps_sh[7:4], hexn_in(rx_data)};
                    step    <= 16'd1;
                    run_req <= 1'b1;
                    cst     <= C_CMD;
                end
                C_H1: begin arg_sh[7:4] <= hexn_in(rx_data); cst <= C_H2; end
                C_H2: begin theta <= {arg_sh[3:0], hexn_in(rx_data)}; cst <= C_CMD; end
                default: cst <= C_CMD;
            endcase
        end
    end

    // ── главный автомат ─────────────────────────────────────────────────
    localparam [3:0] M_IDLE = 4'd0, M_RP  = 4'd1, M_WK  = 4'd2, M_XLK = 4'd3,
                     M_XA   = 4'd4, M_ACC = 4'd5, M_YWR = 4'd6, M_TH0 = 4'd7,
                     M_TH1  = 4'd8, M_REP = 4'd9;
    reg [3:0]  mst = M_IDLE;
    reg [31:0] r = 0, rp_a = 0, rp_b = 0;
    reg signed [15:0] acc = 0;
    reg [COL_AW-1:0] col_a, col_b;
    reg [1:0]  wc_a, wc_b;
    reg        vb_ok;
    reg [15:0] steps = 0, step = 0;
    reg        run_req = 0;
    reg [11:0] inj_id = 0;
    reg [1:0]  inj_val = 0;
    reg        inj_pend = 0;

    wire [15:0] v_a = rp_a[0] ? entries_q[31:16] : entries_q[15:0];
    wire [15:0] v_b = entries_q[31:16];
    wire signed [15:0] th_s = {8'h00, theta};
    wire signed [15:0] nth  = -th_s;

    // ── LED ─────────────────────────────────────────────────────────────
    reg [25:0] hb = 0;
    reg [26:0] idle_cnt = 0;
    reg [15:0] stim_idx = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb <= 0;
        else if (hb == 26'd24_999_999) hb <= 0;
        else hb <= hb + 26'd1;
    end

    assign state_led[0] = ~((mst != M_IDLE) | hb[25]);  // пульс жизни
    assign state_led[1] = ~(mst == M_ACC);              // ход matvec
    assign state_led[2] = ~(pcount > 16'd64);           // высокая активность

    // ── главный тактовый блок (единственный писатель состояния) ─────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mst <= M_IDLE; cst <= C_CMD; r <= 0; rp_a <= 0; rp_b <= 0; acc <= 0;
            col_a <= 0; col_b <= 0; wc_a <= 0; wc_b <= 0; vb_ok <= 0;
            entries_q <= 0; xva <= 0; xvb <= 0; y_q <= 0;
            pcount <= 0; ncount <= 0; steps <= 0; step <= 0; run_req <= 0;
            id_sh <= 0; arg_sh <= 0; steps_sh <= 0;
            inj_id <= 0; inj_val <= 0; inj_pend <= 0;
            txsrc <= 0; ridx <= 0; dump_idx <= 0; tx_byte <= 0; tx_start <= 0;
            buf_ready <= 0; idle_cnt <= 0; stim_idx <= 0; hb <= 0;
        end else begin
            tx_start <= 0;

            // ── LED-пульс жизни ──
            if (hb == 26'd24_999_999) hb <= 0;
            else hb <= hb + 26'd1;

            // ── UART TX секвенсор ──
            case (txsrc)
                2'd1: if (!tx_busy && !tx_start && ridx < 6'd18) begin
                    tx_byte  <= rbuf[ridx];
                    tx_start <= 1'b1;
                    ridx     <= ridx + 6'd1;
                    if (ridx == 6'd17) txsrc <= 0;
                end
                2'd2: if (!tx_busy && !tx_start) begin
                    tx_byte  <= 8'h6B;
                    tx_start <= 1'b1;
                    txsrc    <= 0;
                end
                2'd3: if (!tx_busy && !tx_start) begin
                    if (dump_idx < ROWS) begin
                        tx_byte  <= {6'b000000, xa[dump_idx[11:0]]} + 8'h30;
                        tx_start <= 1'b1;
                        dump_idx <= dump_idx + 1;
                    end else
                        txsrc <= 0;
                end
                default: ;
            endcase

            // ── парсер UART (только в простое, без отложенной инъекции) ──
            if (rx_rdy && mst == M_IDLE && txsrc == 0 && !inj_pend) begin
                case (cst)
                    C_CMD: case (rx_data)
                        8'h53: cst <= C_ID1;                            // 'S'
                        8'h54: cst <= C_T1;                             // 'T'
                        8'h44: begin dump_idx <= 0; txsrc <= 2'd3; end  // 'D'
                        8'h48: cst <= C_H1;                             // 'H'
                        default: ;
                    endcase
                    C_ID1: begin id_sh[11:8] <= hexn_in(rx_data); cst <= C_ID2; end
                    C_ID2: begin id_sh[7:4]  <= hexn_in(rx_data); cst <= C_ID3; end
                    C_ID3: begin id_sh[3:0]  <= hexn_in(rx_data); cst <= C_SGN; end
                    C_SGN: begin
                        if (rx_data == 8'h2B || rx_data == 8'h2D) begin
                            inj_id   <= id_sh;
                            inj_val  <= wr_val;
                            inj_pend <= 1'b1;
                            txsrc    <= 2'd2;                           // 'k'
                        end
                        cst <= C_CMD;
                    end
                    C_T1: begin steps_sh[7:4] <= hexn_in(rx_data); cst <= C_T2; end
                    C_T2: begin
                        steps_sh[3:0] <= hexn_in(rx_data);
                        steps   <= {steps_sh[7:4], hexn_in(rx_data)};
                        step    <= 16'd1;
                        run_req <= 1'b1;
                        cst     <= C_CMD;
                    end
                    C_H1: begin arg_sh[7:4] <= hexn_in(rx_data); cst <= C_H2; end
                    C_H2: begin theta <= {arg_sh[3:0], hexn_in(rx_data)}; cst <= C_CMD; end
                    default: cst <= C_CMD;
                endcase
            end

            // ── главный автомат прохода ──
            case (mst)
                M_IDLE: begin
                    if (inj_pend) begin                                 // сервис инъекции
                        xa[inj_id] <= inj_val;
                        xb[inj_id] <= inj_val;
                        inj_pend   <= 0;
                        mst        <= M_IDLE;
                    end else if (run_req) begin
                        r   <= 0;
                        mst <= M_RP;
                    end
                end

                M_RP: begin
                    rp_a <= rowptr[r];
                    rp_b <= rowptr[r + 1];
                    acc  <= 16'd0;
                    mst  <= M_WK;
                end

                M_WK: begin
                    if (rp_a >= rp_b) begin
                        ymem[r] <= acc;
                        r       <= r + 1;
                        mst     <= M_YWR;
                    end else begin
                        entries_q <= entries[rp_a[31:1]];
                        mst       <= M_XLK;
                    end
                end

                M_XLK: begin
                    col_a <= v_a[COL_AW+1:2];
                    wc_a  <= v_a[1:0];
                    col_b <= v_b[COL_AW+1:2];
                    wc_b  <= v_b[1:0];
                    vb_ok <= !rp_a[0] && (rp_a + 2 <= rp_b);
                    mst   <= M_XA;
                end

                M_XA: begin
                    xva <= xa[col_a];
                    xvb <= xb[col_b];
                    mst <= M_ACC;
                end

                M_ACC: begin
                    acc  <= acc + term(wc_a, xva)
                                  + (vb_ok ? term(wc_b, xvb) : 16'd0);
                    rp_a <= rp_a + (rp_a[0] ? 32'd1 : 32'd2);
                    mst  <= M_WK;
                end

                // y строки записан; r уже инкрементирован
                M_YWR: begin
                    if (r == ROWS) begin
                        r      <= 0;
                        pcount <= 0;
                        ncount <= 0;
                        mst    <= M_TH0;
                    end else begin
                        // авто-стимул: раз в 16 шагов свежий «сенсор»
                        if (step[3:0] == 4'h0) begin
                            xa[sid] <= 2'b01;
                            xb[sid] <= 2'b01;
                            stim_idx <= stim_idx + 1;
                        end
                        mst <= M_RP;
                    end
                end

                M_TH0: begin
                    y_q <= ymem[r];
                    mst <= M_TH1;
                end

                M_TH1: begin
                    if (y_q > th_s) begin
                        xa[r] <= 2'b01;  xb[r] <= 2'b01;
                        pcount <= pcount + 1;
                    end else if (y_q < nth) begin
                        xa[r] <= 2'b10;  xb[r] <= 2'b10;
                        ncount <= ncount + 1;
                    end else begin
                        xa[r] <= 2'b00;  xb[r] <= 2'b00;
                    end
                    if (r == ROWS) begin
                        r   <= 0;
                        mst <= M_REP;
                    end else begin
                        r   <= r + 1;
                        mst <= M_TH0;
                    end
                end

                M_REP: begin
                    if (!buf_ready) begin
                        rbuf[0]  <= 8'h53;                          // 'S'
                        rbuf[1]  <= 8'h3D;                          // '='
                        rbuf[2]  <= hexn(step[7:4]);
                        rbuf[3]  <= hexn(step[3:0]);
                        rbuf[4]  <= 8'h20;
                        rbuf[5]  <= 8'h50;                          // 'P'
                        rbuf[6]  <= 8'h3D;
                        rbuf[7]  <= hexn(pcount[11:8]);
                        rbuf[8]  <= hexn(pcount[7:4]);
                        rbuf[9]  <= hexn(pcount[3:0]);
                        rbuf[10] <= 8'h20;
                        rbuf[11] <= 8'h4E;                          // 'N'
                        rbuf[12] <= 8'h3D;
                        rbuf[13] <= hexn(ncount[11:8]);
                        rbuf[14] <= hexn(ncount[7:4]);
                        rbuf[15] <= hexn(ncount[3:0]);
                        rbuf[16] <= 8'h0D;
                        rbuf[17] <= 8'h0A;
                        ridx      <= 0;
                        buf_ready <= 1;
                        txsrc     <= 2'd1;
                    end else if (txsrc == 0 && ridx >= 6'd18) begin
                        buf_ready <= 0;
                        if (step == steps) begin
                            run_req <= 0;
                            mst     <= M_IDLE;
                        end else begin
                            step <= step + 1;
                            r    <= 0;
                            mst  <= M_RP;
                        end
                    end
                end

                default: mst <= M_IDLE;
            endcase
        end
    end

    // ── LED ─────────────────────────────────────────────────────────────
    assign state_led[0] = ~((mst != M_IDLE) | hb[25]);  // пульс жизни
    assign state_led[1] = ~(mst == M_ACC);              // акт матvec
    assign state_led[2] = ~(pcount > 16'd64);           // высокая активность

endmodule

// ── UART TX: байтовый движок, 115200 @ 50 МГц ───────────────────────────
module uart_tx_engine (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] din,
    output reg        tx = 1,
    output reg        busy = 0
);
    localparam DIV = 434;
    reg [8:0]  cnt = 0;
    reg [3:0]  bits = 0;
    reg [9:0]  sh = 10'h3FF;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1; busy <= 0; cnt <= 0; bits <= 0; sh <= 10'h3FF;
        end else if (!busy) begin
            tx <= 1;
            if (start) begin
                sh   <= {1'b1, din, 1'b0};
                cnt  <= 0;
                bits <= 0;
                busy <= 1;
            end
        end else if (cnt == DIV - 1) begin
            cnt <= 0;
            tx  <= sh[0];
            sh  <= sh >> 1;
            bits <= bits + 1;
            if (bits == 4'd9) begin
                busy <= 0;
                tx   <= 1;
            end
        end else
            cnt <= cnt + 1;
    end
endmodule

// ── UART RX: байтовый приёмник ──────────────────────────────────────────
module uart_rx_engine (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data = 0,
    output reg        ready = 0
);
    localparam DIV = 434;
    reg [8:0]  cnt = 0;
    reg [3:0]  bits = 0;
    reg [1:0]  sync = 2'b11;
    reg        run = 0;
    reg [7:0]  sh = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync <= 2'b11; run <= 0; cnt <= 0; bits <= 0; ready <= 0; data <= 0; sh <= 0;
        end else begin
            ready <= 0;
            sync  <= {sync[0], rx};
            if (!run) begin
                if (sync[1] == 1'b0) begin          // старт-бит
                    run <= 1;
                    cnt <= DIV / 2;                 // середина старт-бита
                    bits <= 0;
                end
            end else if (cnt == DIV - 1) begin
                cnt <= 0;
                if (bits == 0) begin
                    if (sync[1] == 1'b0) bits <= 1; // старт подтверждён
                    else run <= 0;                  // глитч
                end else if (bits <= 8) begin
                    sh  <= {sync[1], sh[7:1]};      // данные LSB-first
                    bits <= bits + 1;
                end else begin                      // стоп-позиция
                    if (sync[1]) begin
                        data  <= sh;
                        ready <= 1;
                    end
                    run <= 0;
                end
            end else
                cnt <= cnt + 1;
        end
    end
endmodule
