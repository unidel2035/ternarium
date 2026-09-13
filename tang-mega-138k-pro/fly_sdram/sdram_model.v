// sdram_model.v — упрощённая поведенческая модель SDR SDRAM (функциональная).
// Откликается на команды контроллера: ACT/RD/WR/PRE. CL=2, данные через 2 такта.

module sdram_model (
    input  wire        clk,
    input  wire        cke,
    input  wire        cs_n,
    input  wire        ras_n,
    input  wire        cas_n,
    input  wire        we_n,
    input  wire [1:0]  ba,
    input  wire [12:0] a,
    input  wire [1:0]  dqm,
    inout  wire [15:0] dq
);
    reg [15:0] mem [0:1048575];

    reg        row_open = 0;
    reg [1:0]  open_ba = 0;
    reg [12:0] open_row = 0;
    reg [15:0] dq_reg = 16'hZZZZ;

    assign dq = dq_reg;

    wire cmd_en = (cs_n == 1'b0);
    wire is_act = cmd_en && !ras_n &&  cas_n &&  we_n;
    wire is_rd  = cmd_en &&  ras_n && !cas_n &&  we_n;
    wire is_wr  = cmd_en &&  ras_n && !cas_n && !we_n;
    wire is_pre = cmd_en && !ras_n &&  cas_n && !we_n;

    wire [19:0] flat = {open_ba, open_row[8:0], a[8:0]};   // упрощённая адресация

    reg [1:0]  rd_wait = 0;
    reg        rd_pend = 0;
    reg [19:0] rd_addr_q = 0;

    integer k;
    initial begin
        for (k = 0; k < 1048576; k = k + 1) mem[k] = 16'hxDEAD;
    end

    always @(posedge clk) begin
        if (is_act) begin
            row_open <= 1;
            open_ba  <= ba;
            open_row <= a;
        end
        if (is_pre) row_open <= 0;

        if (is_rd && row_open) begin
            rd_pend   <= 1;
            rd_wait   <= 2;                       // CL=2
            rd_addr_q <= flat;
        end
        if (rd_pend && rd_wait == 1) begin
            dq_reg  <= mem[rd_addr_q];
            rd_pend <= 0;
        end else if (rd_pend) begin
            rd_wait <= rd_wait - 1;
        end

        if (is_wr && row_open) mem[flat] <= dq;
    end
endmodule
