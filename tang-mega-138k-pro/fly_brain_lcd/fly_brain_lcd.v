// fly_brain_lcd.v — живой мозг мухи НА ЭКРАНЕ: срез K=256 + LCD 800×480.
//
// Экран (5" RGB, DE-режим):
//   - заголовок FLY BRAIN LIVE
//   - лента активности: 256 колонок-нейронов (зелёный=+1, красный=−1, синий=0)
//   - бары P/N (возбуждение/торможение) и номер шага
// Мозг: шаг динамики y=S·x + порог, серия 16 шагов, пауза, авто-стимул сенсоров.
// Всё в одном клоке 25 МГц (pclk), UART 115200 (DIV=217 @25МГц).
//
// Золотая модель: tools/fly/brain_sim.py. Срез: fly_slice_*.hex (export_slice.py).

module fly_brain_lcd (
    input  wire       clk,        // 50 МГц
    input  wire       rst_n,      // active LOW
    input  wire       rx,
    output wire       uart_tx,
    output wire       lcd_clk,
    output wire       lcd_en,
    output wire [5:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [5:0] lcd_b,
    output wire [2:0] state_led   // active LOW
);
`include "fly_params.vh"

    // ── 25 МГц: единый домен ────────────────────────────────────────────
    reg clk25 = 1'b0;
    always @(posedge clk) clk25 <= ~clk25;
    assign lcd_clk = clk25;

    // ── память связей ───────────────────────────────────────────────────
    reg  [31:0] entries [0:ENTRY_WORDS-1];
    initial     $readmemh("fly_slice_csr.hex", entries);
    reg  [31:0] rowptr [0:ROWS];
    initial     $readmemh("fly_slice_rowptr.hex", rowptr);
    reg  [31:0] entries_q;

    // ── шрифт (Terminus 8×16, CP1251, 256 глифов × 16 байт) ────────────
    reg [7:0] fontrom [0:4095];
    initial   $readmemh("font8x16.hex", fontrom);

    // ── активность x (две копии ради двух портов чтения) ────────────────
    reg [1:0] xa [0:ROWS-1];
    reg [1:0] xb [0:ROWS-1];
    reg [1:0] xva, xvb;

    integer ini;
    initial begin
        for (ini = 0; ini < ROWS; ini = ini + 1) begin
            xa[ini] = 2'b00;
            xb[ini] = 2'b00;
        end
    end

    // ── y-аккумуляторы прохода ──────────────────────────────────────────
    reg signed [15:0] ymem [0:ROWS-1];
    reg signed [15:0] y_q;

    // ── состояние ───────────────────────────────────────────────────────
    reg [7:0]  theta = 8'd1;
    reg [15:0] pcount = 0, ncount = 0;
    reg [3:0]  mst = 4'd0;                 // 0 IDLE,1 RP,2 WK,3 XLK,4 XA,5 ACC,6 YWR,7 TH0,8 TH1,9 REP,10 PAUSE
    reg [3:0]  cst = 4'd0;
    reg [31:0] r = 0, rp_a = 0, rp_b = 0;
    reg signed [15:0] acc = 0;
    reg [COL_AW-1:0] col_a, col_b;
    reg [1:0]  wc_a, wc_b;
    reg        vb_ok;
    reg [15:0] steps = 0, step = 0;
    reg        run_req = 0;
    reg [11:0] id_sh = 0;
    reg [7:0]  arg_sh = 0;
    reg [15:0] steps_sh = 0;
    reg [7:0]  tx_byte = 0;
    reg        tx_start = 0;
    reg [7:0]  rbuf [0:17];
    reg [5:0]  ridx = 0;
    reg [1:0]  txsrc = 0;
    reg [15:0] dump_idx = 0;
    reg        buf_ready = 0;
    reg [25:0] hb = 0;
    reg [26:0] idle_cnt = 0;
    reg [15:0] stim_idx = 0;

    // ── readout: тернарный классификатор 4×256 (обучен на ПК) ──────────
    reg [31:0] ro_rom [0:63];              // 4 класса × 16 слов × 16 весов
    initial    $readmemh("class_ro.hex", ro_rom);
    reg [31:0] ro_w0 = 0, ro_w1 = 0, ro_w2 = 0, ro_w3 = 0;
    reg [15:0] acc_ro0 = 0, acc_ro1 = 0, acc_ro2 = 0, acc_ro3 = 0;
    reg [1:0]  cls_reg = 0;
    reg [15:0] ro_r = 0;
    reg [25:0] pace_cnt = 0;               // темп шагов демо
    reg        pace_fire = 0;

    wire demo_idle = (mst == 4'd0) && !run_req;

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
            2'd0: stim_id = 12'h092;
            2'd1: stim_id = 12'h096;
            2'd2: stim_id = 12'h05E;
            default: stim_id = 12'h032;
        endcase
    endfunction

    // ── UART движки (25 МГц: DIV=217) ───────────────────────────────────
    wire      tx_busy;
    uart_tx_engine txe(.clk(clk25), .rst_n(rst_n), .start(tx_start), .din(tx_byte),
                       .tx(uart_tx), .busy(tx_busy));

    wire [7:0] rx_data;
    wire       rx_rdy;
    uart_rx_engine rxe(.clk(clk25), .rst_n(rst_n), .rx(rx), .data(rx_data), .ready(rx_rdy));

    // ── декод ───────────────────────────────────────────────────────────
    wire [15:0] v_a = rp_a[0] ? entries_q[31:16] : entries_q[15:0];
    wire [15:0] v_b = entries_q[31:16];
    wire signed [15:0] th_s = {8'h00, theta};
    wire signed [15:0] nth  = -th_s;

    // ═════════════ ЕДИНСТВЕННЫЙ ТАКТОВЫЙ БЛОК (clk25) ══════════════════
    always @(posedge clk25 or negedge rst_n) begin
        if (!rst_n) begin
            mst <= 0; cst <= 0; r <= 0; rp_a <= 0; rp_b <= 0; acc <= 0;
            col_a <= 0; col_b <= 0; wc_a <= 0; wc_b <= 0; vb_ok <= 0;
            entries_q <= 0; xva <= 0; xvb <= 0; y_q <= 0;
            theta <= 8'd1; pcount <= 0; ncount <= 0;
            steps <= 0; step <= 0; run_req <= 0;
            id_sh <= 0; arg_sh <= 0; steps_sh <= 0;
            tx_byte <= 0; tx_start <= 0; txsrc <= 0; ridx <= 0;
            dump_idx <= 0; buf_ready <= 0;
            hb <= 0; idle_cnt <= 0; stim_idx <= 0; pace_cnt <= 0; pace_fire <= 0;
        end else begin
            tx_start <= 0;
            pace_fire <= 0;

            // ── LED ──
            if (hb == 26'd12_499_999) hb <= 0;
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

            // ── парсер UART ──
            if (rx_rdy && mst == 4'd0 && txsrc == 0) begin
                case (cst)
                    4'd0: case (rx_data)
                        8'h53: cst <= 4'd1;                             // 'S'
                        8'h54: cst <= 4'd5;                             // 'T'
                        8'h44: begin dump_idx <= 0; txsrc <= 2'd3; end  // 'D'
                        8'h48: cst <= 4'd7;                             // 'H'
                        default: ;
                    endcase
                    4'd1: begin id_sh[11:8] <= hexn_in(rx_data); cst <= 4'd2; end
                    4'd2: begin id_sh[7:4]  <= hexn_in(rx_data); cst <= 4'd3; end
                    4'd3: begin id_sh[3:0]  <= hexn_in(rx_data); cst <= 4'd4; end
                    4'd4: begin
                        if (rx_data == 8'h2B || rx_data == 8'h2D) begin
                            xa[id_sh] <= (rx_data == 8'h2B) ? 2'b01 : 2'b10;
                            xb[id_sh] <= (rx_data == 8'h2B) ? 2'b01 : 2'b10;
                            tx_byte   <= 8'h6B;                         // 'k'
                            tx_start  <= 1'b1;
                        end
                        cst <= 4'd0;
                    end
                    4'd5: begin steps_sh[7:4] <= hexn_in(rx_data); cst <= 4'd6; end
                    4'd6: begin
                        steps_sh[3:0] <= hexn_in(rx_data);
                        steps   <= {steps_sh[7:4], hexn_in(rx_data)};
                        step    <= 16'd1;
                        run_req <= 1'b1;
                        mst     <= 4'd1;
                        cst     <= 4'd0;
                    end
                    4'd7: begin arg_sh[7:4] <= hexn_in(rx_data); cst <= 4'd8; end
                    4'd8: begin theta <= {arg_sh[3:0], hexn_in(rx_data)}; cst <= 4'd0; end
                    default: cst <= 4'd0;
                endcase
            end

            // ── автомат демо-темпа: серия 16 шагов каждые 2 с ──
            if (mst == 4'd0 && !run_req) begin
                idle_cnt <= idle_cnt + 1;
                if (idle_cnt == 27'd50_000_000) begin               // 2 с простоя
                    steps    <= 16'd16;
                    step     <= 16'd1;
                    stim_idx <= 0;
                    run_req  <= 1'b1;
                    idle_cnt <= 0;
                    pace_cnt <= 0;
                    pace_fire <= 1'b1;
                    mst      <= 4'd1;
                end
            end else if (mst == 4'd10) begin                        // PAUSE между шагами
                pace_cnt <= pace_cnt + 1;
                if (pace_cnt == 25'd12_499_999) begin               // 0.5 с
                    pace_cnt <= 0;
                    pace_fire <= 1'b1;
                end
            end

            // ── главный автомат прохода ──
            case (mst)
                4'd0: ;                                             // IDLE: ожидание 2 с
                4'd1: if (pace_fire) begin                          // M_RP
                    rp_a <= rowptr[r];
                    rp_b <= rowptr[r + 1];
                    acc  <= 16'd0;
                    pace_fire <= 1'b0;
                    mst  <= 4'd2;
                end

                4'd2: begin                                         // M_WK
                    if (rp_a >= rp_b) begin
                        ymem[r] <= acc;
                        r       <= r + 1;
                        mst     <= 4'd6;
                    end else begin
                        entries_q <= entries[rp_a[31:1]];
                        mst       <= 4'd3;
                    end
                end

                4'd3: begin                                         // M_XLK
                    col_a <= v_a[COL_AW+1:2];
                    wc_a  <= v_a[1:0];
                    col_b <= v_b[COL_AW+1:2];
                    wc_b  <= v_b[1:0];
                    vb_ok <= !rp_a[0] && (rp_a + 2 <= rp_b);
                    mst   <= 4'd4;
                end

                4'd4: begin                                         // M_XA
                    xva <= xa[col_a];
                    xvb <= xb[col_b];
                    mst <= 4'd5;
                end

                4'd5: begin                                         // M_ACC
                    acc  <= acc + term(wc_a, xva)
                                  + (vb_ok ? term(wc_b, xvb) : 16'd0);
                    rp_a <= rp_a + (rp_a[0] ? 32'd1 : 32'd2);
                    mst  <= 4'd2;
                end

                4'd6: begin                                         // M_YWR: строка y записана
                    if (r == ROWS) begin
                        r      <= 0;
                        pcount <= 0;
                        ncount <= 0;
                        mst    <= 4'd7;                             // → пороговая развёртка
                    end else begin
                        mst <= 4'd1;                                // → следующая строка
                    end
                end

                4'd7: begin                                         // M_TH0: чтение y[r]
                    y_q <= ymem[r];
                    mst <= 4'd8;
                end

                4'd8: begin                                         // M_TH1: порог + продвижение
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
                        acc_ro0 <= 0; acc_ro1 <= 0; acc_ro2 <= 0; acc_ro3 <= 0;
                        mst <= 4'd11;                           // → readout pass
                    end else begin
                        r   <= r + 1;
                        mst <= 4'd7;
                    end
                end

                4'd11: begin                                        // M_RO0: чтение весов и x
                    ro_w0 <= ro_rom[{2'b00, r[7:0]}];
                    ro_w1 <= ro_rom[{2'b01, r[7:0]}];
                    ro_w2 <= ro_rom[{2'b10, r[7:0]}];
                    ro_w3 <= ro_rom[{2'b11, r[7:0]}];
                    xva   <= xa[r];
                    mst   <= 4'd12;
                end

                4'd12: begin                                        // M_RO1: аккумуляция
                    acc_ro0 <= acc_ro0 + term(2'b01, (ro_w0 >> {r[3:0], 1'b0}) & 2'b11);
                    acc_ro1 <= acc_ro1 + term(2'b01, (ro_w1 >> {r[3:0], 1'b0}) & 2'b11);
                    acc_ro2 <= acc_ro2 + term(2'b01, (ro_w2 >> {r[3:0], 1'b0}) & 2'b11);
                    acc_ro3 <= acc_ro3 + term(2'b01, (ro_w3 >> {r[3:0], 1'b0}) & 2'b11);
                    r   <= r + 1;
                    mst <= (r + 1 == ROWS) ? 4'd13 : 4'd11;
                end

                4'd13: begin                                        // argmax → cls_reg
                    cls_reg <= (acc_ro0 >= acc_ro1 && acc_ro0 >= acc_ro2 && acc_ro0 >= acc_ro3) ? 2'd0 :
                               (acc_ro1 >= acc_ro2 && acc_ro1 >= acc_ro3) ? 2'd1 :
                               (acc_ro2 >= acc_ro3) ? 2'd2 : 2'd3;
                    mst <= 4'd9;
                end

                4'd9: begin                                         // M_REP + продвижение
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
                            mst     <= 4'd0;                        // дальше — авто-перезапуск
                        end else begin
                            step <= step + 1;
                            r    <= 0;
                            mst  <= 4'd10;                          // пауза 0.5 с
                        end
                    end
                end

                4'd10: begin                                        // PAUSE → следующий шаг
                    if (pace_fire) begin
                        pace_fire <= 1'b0;
                        r         <= 0;
                        mst       <= 4'd1;
                    end
                end

                default: mst <= 4'd0;
            endcase
        end
    end

    // ── пороговая развёртка корректно: M_TH0/TH1 ──
    // (в автомате выше: 4'd6 YWR → 4'd7 TH0 → порог; реализовано ниже
    //  отдельными состояниями 4'd7/4'd8 при обходе — см. вер. в репо)

    // ── LED ─────────────────────────────────────────────────────────────
    assign state_led[0] = ~((mst != 4'd0) | hb[24]);
    assign state_led[1] = ~(mst == 4'd5);
    assign state_led[2] = ~(pcount > 16'd64);

    // ── LCD развёртка 800×480 (DE-режим, всё в clk25) ───────────────────
    reg [15:0] h_cnt = 0, v_cnt = 0;
    always @(posedge clk25 or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 0; v_cnt <= 0;
        end else if (h_cnt == 16'd1191) begin
            h_cnt <= 0;
            v_cnt <= (v_cnt == 16'd532) ? 16'd0 : v_cnt + 16'd1;
        end else
            h_cnt <= h_cnt + 16'd1;
    end

    wire        visible = (h_cnt >= 16'd182) && (h_cnt < 16'd982) &&
                          (v_cnt >= 16'd8)   && (v_cnt < 16'd488);
    wire [15:0] px = h_cnt - 16'd182;      // 0..799
    wire [15:0] py = v_cnt - 16'd8;        // 0..479
    assign lcd_en = visible;

    // ── лента: цвет состояния нейрона (3 px колонки) ──
    wire [11:0] tape_idx  = px[11:2] - 8;              // (px-32)/4
    wire        in_tape   = (px >= 32) && (px < 32 + 1024) && (py >= 130) && (py < 250);
    wire [11:0] tape_neur = tape_idx[11:2] * 4 + px[1:0];

    // ── класс-квадранты: активный класс подсвечен ──
    wire in_c0 = (py >= 380) && (py < 444) && (px >=  40) && (px < 100);
    wire in_c1 = (py >= 380) && (py < 444) && (px >= 100) && (px < 160);
    wire in_c2 = (py >= 380) && (py < 444) && (px >= 160) && (px < 220);
    wire in_c3 = (py >= 380) && (py < 444) && (px >= 220) && (px < 280);
    wire in_cl = in_c0 | in_c1 | in_c2 | in_c3;
    wire [1:0] cls_q = in_c0 ? 2'd0 : in_c1 ? 2'd1 : in_c2 ? 2'd2 : 2'd3;
    wire       cls_hit = (cls_q == cls_reg);

    // ── бары P/N ──
    wire in_pbar = (py >= 270) && (py < 300) && (px >= 32) && (px < 32 + pcount[11:0] * 3);
    wire in_nbar = (py >= 310) && (py < 340) && (px >= 32) && (px < 32 + ncount[11:0] * 3);


    reg [5:0] r6, g6, b6;
    always @(*) begin
        if (!visible)                 {r6, g6, b6} = 18'h00300C;
        else if (in_cl) begin
            case (cls_q)
                2'd0: {r6, g6, b6} = cls_hit ? 18'h003F18 : 18'h001018;
                2'd1: {r6, g6, b6} = cls_hit ? 18'h3F0808 : 18'h100808;
                2'd2: {r6, g6, b6} = cls_hit ? 18'h08383F : 18'h081018;
                default: {r6, g6, b6} = cls_hit ? 18'h3F3A08 : 18'h101008;
            endcase
        end
        else if (in_tape) begin
            case (xa[tape_neur])
                2'b01: {r6, g6, b6} = 18'h003F18;  // +1 зелёный
                2'b10: {r6, g6, b6} = 18'h3F0808;  // −1 красный
                default: {r6, g6, b6} = 18'h000830; // покой — тёмно-синий
            endcase
        end
        else if (in_pbar)             {r6, g6, b6} = 18'h002A20;
        else if (in_nbar)             {r6, g6, b6} = 18'h2A0808;
        else                          {r6, g6, b6} = 18'h000814;
    end

    assign lcd_r = b6;   // BGR-панель: каналы переставлены
    assign lcd_g = g6;
    assign lcd_b = r6;

endmodule

// ── UART TX: байтовый движок ────────────────────────────────────────────
module uart_tx_engine (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] din,
    output reg        tx = 1,
    output reg        busy = 0
);
    localparam DIV = 217;                       // 115200 @ 25 МГц
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
    localparam DIV = 217;
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
                if (sync[1] == 1'b0) begin
                    run <= 1;
                    cnt <= DIV / 2;
                    bits <= 0;
                end
            end else if (cnt == DIV - 1) begin
                cnt <= 0;
                if (bits == 0) begin
                    if (sync[1] == 1'b0) bits <= 1;
                    else run <= 0;
                end else if (bits <= 8) begin
                    sh  <= {sync[1], sh[7:1]};
                    bits <= bits + 1;
                end else begin
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
