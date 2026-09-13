// sdram_ctrl.v — компактный SDR SDRAM контроллер (W9825G6KH, 32 МБ, 16 бит)
// под Tang Mega 138K Pro Dock. 100 МГц, CL=2, auto-precharge режим.
//
// Адресное пространство пользователя: 24-бит word-адрес (16M слов = 32 МБ)
//   word_addr = {bank[1:0], row[12:0], col[8:0]}   (4 банка × 8192 строк × 512 слов)
//
// Интерфейс: u_wr/u_rd (однотактный запрос), u_rdy = слово готово/запись принята.
// v1: одиночные слова. v2 (TODO): burst 8 + interleaved banks для стриминга CSR.

module sdram_ctrl (
    input  wire        clk,        // 100 МГц
    input  wire        rst_n,
    // SDRAM side
    output reg         sd_cke = 1'b1,
    output reg         sd_cs_n = 1'b1,
    output reg         sd_ras_n = 1'b1,
    output reg         sd_cas_n = 1'b1,
    output reg         sd_we_n  = 1'b1,
    output reg  [1:0]  sd_ba = 0,
    output reg  [12:0] sd_a = 0,
    output reg  [1:0]  sd_dqm = 2'b00,
    inout  wire [15:0] sd_dq,
    // user side
    input  wire [23:0] u_addr,
    input  wire [15:0] u_wdata,
    input  wire        u_wr,
    input  wire        u_rd,
    output reg  [15:0] u_rdata = 0,
    output reg         u_rdy = 0
);
    // ── тайминги в тактах 100 МГц (W9825G6KH-6, с запасом) ─────────────
    localparam T_PWRUP = 20_000,   // 200 мкс
               T_RCD   = 2,        // ACT→RD/WR 18 нс
               T_RP    = 2,        // PRE→     18 нс
               T_RAS   = 4,        // ACT→PRE  42 нс
               T_RC    = 6,        // REF/ACT cycle 60 нс
               T_WR    = 2,        // write recovery
               T_REF   = 27'd640;  // авто-refresh каждые 6.4 мкс

    // ── команды (CS#=0 в такте команды) ─────────────────────────────────
    localparam CMD_NOP  = 4'b0111,
               CMD_ACT  = 4'b0011,   // RAS#
               CMD_RD   = 4'b0101,   // CAS#
               CMD_WR   = 4'b0100,   // CAS#+WE#
               CMD_PRE  = 4'b0010,   // RAS#+WE# (A10=1: all banks)
               CMD_REF  = 4'b0001,   // RAS#+CAS#
               CMD_MRS  = 4'b0000;   // RAS#+CAS#+WE#

    reg [3:0]  cmd = CMD_NOP;
    always @(*) begin
        {sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n} = cmd | 4'b0000;
        // CS# активен нулём: cmd задаёт [ras,cas,we], cs_n = 0 когда команда не NOP
        sd_cs_n = (cmd == CMD_NOP);
        sd_ras_n = cmd[2];
        sd_cas_n = cmd[1];
        sd_we_n  = cmd[0];
    end

    // ── DQ шина: driver только в циклах записи ──────────────────────────
    reg        dq_out_en = 0;
    reg [15:0] dq_out = 0;
    assign sd_dq = dq_out_en ? dq_out : 16'hZZZZ;

    // ── счётчик авто-refresh ────────────────────────────────────────────
    reg [26:0] ref_cnt = 0;
    wire       ref_due = (ref_cnt >= T_REF);
    always @(posedge clk) begin
        if (!rst_n) ref_cnt <= 0;
        else if (ref_due) ref_cnt <= 0;
        else ref_cnt <= ref_cnt + 1;
    end

    // ── FSM ─────────────────────────────────────────────────────────────
    localparam [4:0] S_PWRUP = 5'd0,  S_IPRE = 5'd1,  S_IREF1 = 5'd2, S_IREF1W = 5'd3,
                     S_IREF2 = 5'd4,  S_IREF2W= 5'd5,  S_IMRS  = 5'd6,  S_IMRSW = 5'd7,
                     S_IDLE  = 5'd8,  S_ACT   = 5'd9,  S_ACTW  = 5'd10, S_RD    = 5'd11,
                     S_RDW   = 5'd12, S_RDWR  = 5'd13, S_RDWRW = 5'd14, S_PRE   = 5'd15,
                     S_PREW  = 5'd16, S_REF   = 5'd17, S_REFW  = 5'd18;
    reg [4:0]  st = S_PWRUP;
`ifdef SDRAM_DBG
    reg [4:0] st_q = 0;
`endif
    reg [19:0] wait_cnt = 0;
    reg [15:0] cl_cnt = 0;
    reg        op_wr = 0;
    reg [23:0] op_addr = 0;
    reg [15:0] op_data = 0;

    wire [12:0] row_a = op_addr[21:9];
    wire [8:0]  col_a = op_addr[8:0];
    wire [1:0]  bank_a = op_addr[23:22];

    // MRS: burst=1 seq, CL=2 → A[6:4]=2
    localparam [12:0] MRS_CL2 = 13'b0_00_010_0_000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_PWRUP; wait_cnt <= 0; cmd <= CMD_NOP;
            op_wr <= 0; op_addr <= 0; op_data <= 0;
            u_rdy <= 0; u_rdata <= 0; cl_cnt <= 0;
            sd_cke <= 1; sd_ba <= 0; sd_a <= 0; sd_dqm <= 0;
            dq_out_en <= 0; dq_out <= 0;
        end else begin
            cmd <= CMD_NOP;
`ifdef SDRAM_DBG
            if (st != st_q) begin $display("[%0t] st=%0d", $time, st); st_q <= st; end
`endif
            u_rdy <= 0;
            dq_out_en <= 0;

            case (st)
                S_PWRUP: begin
                    sd_cke <= 1;
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_PWRUP) begin
                        wait_cnt <= 0;
                        sd_a <= 13'h0400;               // A10=1: precharge all
                        cmd  <= CMD_PRE;
                        st   <= S_IPRE;
                    end
                end

                S_IPRE: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RP) begin
                        wait_cnt <= 0;
                        sd_a  <= 13'h0000;              // A10=0: REF
                        cmd   <= CMD_REF;
                        st    <= S_IREF1;
                    end
                end

                S_IREF1: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RC) begin
                        wait_cnt <= 0;
                        cmd <= CMD_REF;
                        st  <= S_IREF2;
                    end
                end

                S_IREF2: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RC) begin
                        wait_cnt <= 0;
                        sd_a <= MRS_CL2;
                        cmd  <= CMD_MRS;
                        st   <= S_IMRS;
                    end
                end

                S_IMRS: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= 2) begin
                        wait_cnt <= 0;
                        st <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    if (ref_due) begin
                        sd_a <= 13'h0000;
                        cmd  <= CMD_REF;
                        st   <= S_REF;
                    end else if (u_wr || u_rd) begin
                        op_addr <= u_addr;
                        op_wr   <= u_wr;
                        op_data <= u_wdata;
                        sd_ba   <= u_addr[23:22];
                        sd_a    <= u_addr[21:9];        // row
                        cmd     <= CMD_ACT;
                        st      <= S_ACT;
                    end
                end

                S_ACT: begin                            // tRCD
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RCD - 1) begin
                        wait_cnt <= 0;
                        sd_ba <= bank_a;
                        sd_a  <= {2'b00, 1'b0, col_a};  // A10=0 (no auto-precharge)
                        if (op_wr) begin
                            cmd       <= CMD_WR;
                            dq_out_en <= 1;
                            dq_out    <= op_data;
                            st        <= S_RDWR;
                        end else begin
                            cmd      <= CMD_RD;
                            cl_cnt   <= 3;              // CL=2 + 1 такт пайплайна модели
                            st       <= S_RDW;
                        end
                    end
                end

                S_RDW: begin                            // CAS latency
                    cl_cnt <= cl_cnt - 1;
                    if (cl_cnt == 1) begin
                        u_rdata <= sd_dq;
                        u_rdy   <= 1;
                        wait_cnt <= 0;
                        st       <= S_PRE;
                    end
                end

                S_RDWR: begin                           // write recovery
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_WR) begin
                        wait_cnt <= 0;
                        u_rdy   <= 1;
                        st      <= S_PRE;
                    end
                end

                S_PRE: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RAS) begin        // tRAS до precharge
                        wait_cnt <= 0;
                        sd_a <= 13'h0400;
                        cmd  <= CMD_PRE;
                        st   <= S_PREW;
                    end
                end

                S_PREW: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RP) begin
                        wait_cnt <= 0;
                        st <= S_IDLE;
                    end
                end

                S_REF: begin
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= T_RC) begin
                        wait_cnt <= 0;
                        st <= S_IDLE;
                    end
                end

                default: st <= S_PWRUP;
            endcase
        end
    end
endmodule
