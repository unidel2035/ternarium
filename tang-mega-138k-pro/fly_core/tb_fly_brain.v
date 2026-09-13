// tb_fly_brain.v — прогон UART-сценария через fly_brain, захват TX в captured.txt
// Эталон: tools/fly/brain_sim.py --out sim/expected_uart.txt → diff делает Makefile.

`timescale 1ns/1ps

module tb_fly_brain;
`include "fly_params.vh"

    reg clk = 0, rst_n = 0, rx_line = 1;
    wire uart_tx_line;
    wire [2:0] state_led;

    fly_brain dut (.clk(clk), .rst_n(rst_n), .rx(rx_line),
                   .uart_tx(uart_tx_line), .state_led(state_led));

    always #10 clk = ~clk;                 // 50 МГц
    localparam BIT = 8681;                 // 115200 бод, нс

    // ── отправка байта в dut.rx ─────────────────────────────────────────
    task send_byte(input [7:0] b);
        integer k;
        begin
            rx_line = 1'b0;                // старт
            #(BIT);
            for (k = 0; k < 8; k = k + 1) begin
                rx_line = b[k];
                #(BIT);
            end
            rx_line = 1'b1;                // стоп
            #(BIT);
            #200;                          // межбайтовый зазор
        end
    endtask

    // ── захват TX ───────────────────────────────────────────────────────
    integer fd;
    integer capn = 0;
    reg [7:0] cur;

    always @(negedge uart_tx_line) begin
        begin
            #(BIT * 3 / 2);                // середина бита 0 (данных)
            for (k = 0; k < 8; k = k + 1) begin
                cur[k] = uart_tx_line;
                #(BIT);
            end
            cap[capn] = cur;
            capn = capn + 1;
            $fwrite(fd, "%c", cur);
        end
    end

    reg [7:0] cap [0:4095];
    integer k;

    // ── сценарий ────────────────────────────────────────────────────────
    initial begin
        fd = $fopen("captured.txt", "wb");
        $display("tb_fly_brain: ROWS=%0d", ROWS);
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (20) @(posedge clk);

        // стимулы: топ out-degree среза K=256 (см. brain_sim.py)
        send_byte("S"); send_byte("0"); send_byte("9"); send_byte("2"); send_byte("+");
        send_byte("S"); send_byte("0"); send_byte("9"); send_byte("6"); send_byte("+");
        send_byte("S"); send_byte("0"); send_byte("5"); send_byte("E"); send_byte("-");
`ifdef BRAIN_DUMP
        send_byte("D");                                    // дамп вместо прогона
        #20_000_000;
        begin : dump_scan
            $display("direct: xaw[0F7]=%08x xaw[0F1]=%08x xaw[0AF]=%08x",
                     dut.xaw[9'h0F7], dut.xaw[9'h0F1], dut.xaw[9'h0AF]);
            $display("direct: theta=%0d steps=%0d run_req=%b mst=%0d cst=%0d",
                     dut.theta, dut.steps, dut.run_req, dut.mst, dut.cst);
        end
        $fclose(fd);
        $finish;
`endif
        send_byte("H"); send_byte("0"); send_byte("1");                 // theta=1
        send_byte("T"); send_byte("0"); send_byte("3");                 // 3 шага

        // ждём 3 отчёта (3 шага ≈ 20 мс + UART) с запасом
        #100_000_000;

        $fclose(fd);
        $display("captured %0d байт:", capn);
        for (k = 0; k < capn; k = k + 1)
            if (cap[k] >= 32 && cap[k] < 127) $write("%c", cap[k]);
            else $write("[%02x]", cap[k]);
        $write("\n");
        $display("TB-DONE (сравнение делает diff с expected_uart.txt)");
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: таймаут");
        $fclose(fd);
        $finish;
    end
endmodule
