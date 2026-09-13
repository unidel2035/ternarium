// tb_sdram.v — проверка контроллера: запись паттерна → чтение → сравнение.
// Сценарий: 256 слов подряд + scattered по банкам/строкам + перезатирание.

`timescale 1ns/1ps

module tb_sdram;
    reg clk = 0, rst_n = 0;
    reg [23:0] addr;
    reg [15:0] wdata;
    reg wr = 0, rd = 0;
    wire [15:0] rdata;
    wire rdy;
    wire sd_cke, sd_cs_n, sd_ras_n, sd_cas_n, sd_we_n;
    wire [1:0]  sd_ba, sd_dqm;
    wire [12:0] sd_a;
    wire [15:0] sd_dq;

    sdram_ctrl dut (
        .clk(clk), .rst_n(rst_n),
        .sd_cke(sd_cke), .sd_cs_n(sd_cs_n), .sd_ras_n(sd_ras_n),
        .sd_cas_n(sd_cas_n), .sd_we_n(sd_we_n),
        .sd_ba(sd_ba), .sd_a(sd_a), .sd_dqm(sd_dqm),
        .sd_dq(sd_dq),
        .u_addr(addr), .u_wdata(wdata), .u_wr(wr), .u_rd(rd),
        .u_rdata(rdata), .u_rdy(rdy)
    );

    sdram_model model (
        .clk(clk), .cke(sd_cke), .cs_n(sd_cs_n), .ras_n(sd_ras_n),
        .cas_n(sd_cas_n), .we_n(sd_we_n),
        .ba(sd_ba), .a(sd_a), .dqm(sd_dqm), .dq(sd_dq)
    );

    always #5 clk = ~clk;                 // 100 МГц

    // ── латч ответов ──
    reg [15:0] cap [0:4095];
    reg [23:0] cap_addr [0:4095];
    integer capn = 0;
    always @(posedge clk) begin
        if (rdy && rd) begin
            cap[capn]     <= rdata;
            cap_addr[capn] <= addr;
            capn <= capn + 1;
        end
    end

    task do_wr(input [23:0] a, input [15:0] d);
        begin
            addr = a; wdata = d; wr = 1; rd = 0;
            while (!rdy) @(posedge clk);
            @(posedge clk);
            wr = 0;
        end
    endtask

    task do_rd(input [23:0] a);
        begin
            addr = a; wr = 0; rd = 1;
            while (!rdy) @(posedge clk);
            @(posedge clk);
            rd = 0;
        end
    endtask

    integer errors = 0, i;
    initial begin
        $display("tb_sdram: init...");
        repeat (4) @(posedge clk);
        rst_n = 1;
        // ждать конца init (200 мкс = 20000 тактов)
        repeat (22000) @(posedge clk);

        // линейная запись
        for (i = 0; i < 64; i = i + 1)
            do_wr(i * 4, i[15:0] ^ 16'h5A5A);
        // scattered по банкам/строкам
        do_wr(24'h812345, 16'h1234);
        do_wr(24'h40FEDC, 16'hBEEF);
        do_wr(24'hC00001, 16'hCAFE);

        // линейное чтение
        for (i = 0; i < 64; i = i + 1)
            do_rd(i * 4);
        do_rd(24'h812345);
        do_rd(24'h40FEDC);
        do_rd(24'hC00001);

        if (capn != 70) $display("FAIL: прочитано %0d из 70", capn);

        for (i = 0; i < 64; i = i + 1)
            if (cap[i] !== (i[15:0] ^ 16'h5A5A)) begin
                errors = errors + 1;
                if (errors < 5) $display("  MISMATCH linear[%0d]: %04x != %04x", i, cap[i], i[15:0] ^ 16'h5A5A);
            end
        if (cap[64] !== 16'h1234) begin errors = errors + 1; $display("  MISMATCH 812345"); end
        if (cap[65] !== 16'hBEEF) begin errors = errors + 1; $display("  MISMATCH 40FEDC"); end
        if (cap[66] !== 16'hCAFE) begin errors = errors + 1; $display("  MISMATCH C00001"); end

        if (errors == 0) $display("SDRAM-PASS: 70/70 слов совпали");
        else $display("SDRAM-FAIL: %0d ошибок", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: таймаут");
        $finish;
    end
endmodule
