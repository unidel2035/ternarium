// tb_fly_matvec.v — золотая проверка: RTL-проход vs CPU (numpy)
// запуск из sim/:  make sim

`timescale 1ns/1ps

module tb_fly_matvec;
`include "fly_params.vh"

    reg clk = 0, rst_n = 0, start = 0;
    wire done, busy;
    wire [31:0] dbg_row;

    fly_matvec dut (.clk(clk), .rst_n(rst_n), .start(start),
                    .done(done), .dbg_row(dbg_row), .busy(busy));

    always #10 clk = ~clk;                 // 50 МГц

    reg [31:0] golden [0:ROWS-1];
    integer errors = 0, i;
    integer first_shown = 0;

    initial begin
        $readmemh("fly_y_golden.hex", golden);
    end

    initial begin
        $display("fly_matvec tb: ROWS=%0d ENTRY_WORDS=%0d", ROWS, ENTRY_WORDS);
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 1;                          // держим start до done (S_FIN ждёт снятия)

        wait (done);
        $display("done после %0d тактов (~%0d.%02d мс @50МГц)", dut.cyc,
                 (dut.cyc * 20) / 1000000, ((dut.cyc * 20) / 10000) % 100);

        // старт заново, чтобы FSM вышел в IDLE (done снимается при !start)
        start = 0;
        repeat (4) @(posedge clk);

        for (i = 0; i < ROWS; i = i + 1) begin
            if (dut.ymem[i] !== $signed(golden[i])) begin
                errors = errors + 1;
                if (first_shown < 5) begin
                    $display("  MISMATCH y[%0d]: rtl=%0d golden=%0d",
                             i, dut.ymem[i], $signed(golden[i]));
                    first_shown = first_shown + 1;
                end
            end
        end

        if (errors == 0)
            $display("PASS: все %0d значений y совпали с CPU-эталоном", ROWS);
        else
            $display("FAIL: расхождений %0d из %0d", errors, ROWS);
        $finish;
    end

    // страховка от зависания
    initial begin
        #200_000_000;                       // 200 мс симуляционного времени
        $display("FAIL: таймаут, done не пришёл");
        $finish;
    end
endmodule
