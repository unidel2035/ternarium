// fly_splash.v — заставка ternarium на 5" 800×480 RGB LCD
// Tang Mega 138K Pro Dock. DE-режим панели, pclk 25 МГц (clk/2).
// Текст: tools/fly/make_splash_font.py -> fly_splash_text.vh (шрифт 8×16, CP1251)

module fly_splash (
    input  wire        clk,        // 50 МГц
    input  wire        rst_n,      // active LOW
    output wire        lcd_clk,
    output wire        lcd_en,
    output wire [5:0]  lcd_r,
    output wire [5:0]  lcd_g,
    output wire [5:0]  lcd_b,
    output wire [2:0]  state_led   // active LOW
);
`include "fly_splash_text.vh"

    // ── 25 МГц pixel clock ──────────────────────────────────────────────
    reg clk25 = 1'b0;
    always @(posedge clk) clk25 <= ~clk25;
    assign lcd_clk = clk25;

    // ── тайминги 800×480 (Sipeed 5", DE-режим) ──────────────────────────
    localparam [15:0] H_VALID = 16'd800, H_FP = 16'd210, H_BP = 16'd182;
    localparam [15:0] V_VALID = 16'd480, V_FP = 16'd45,  V_BP = 16'd8;

    reg [15:0] h_cnt = 0, v_cnt = 0;
    always @(posedge clk25 or negedge rst_n) begin
        if (!rst_n) begin
            h_cnt <= 16'd0;
            v_cnt <= 16'd0;
        end else if (h_cnt == H_VALID + H_FP + H_BP - 1) begin
            h_cnt <= 16'd0;
            v_cnt <= (v_cnt == V_VALID + V_FP + V_BP - 1) ? 16'd0 : v_cnt + 16'd1;
        end else
            h_cnt <= h_cnt + 16'd1;
    end

    wire visible = (h_cnt >= H_BP) && (h_cnt < H_BP + H_VALID) &&
                   (v_cnt >= V_BP) && (v_cnt < V_BP + V_VALID);
    assign lcd_en = visible;

    wire [15:0] x = h_cnt - H_BP;   // 0..799
    wire [15:0] y = v_cnt - V_BP;   // 0..479

    // ── строки текста: попадание + координаты глифа ─────────────────────
    // масштаб = 2^k: cell = 8*2^k x 16*2^k px
    wire [15:0] ry0 = y - L0_Y0;
    wire [15:0] ry1 = y - L1_Y0;
    wire [15:0] ry2 = y - L2_Y0;
    wire [15:0] ry3 = y - L3_Y0;
    wire [15:0] rx0 = x - L0_X0;
    wire [15:0] rx1 = x - L1_X0;
    wire [15:0] rx2 = x - L2_X0;
    wire [15:0] rx3 = x - L3_X0;

    wire in0s = (x >= L0_X0) && (x < L0_X0 + L0_W) && (y >= L0_Y0) && (y < L0_Y0 + L0_H);
    wire in1s = (x >= L1_X0) && (x < L1_X0 + L1_W) && (y >= L1_Y0) && (y < L1_Y0 + L1_H);
    wire in2s = (x >= L2_X0) && (x < L2_X0 + L2_W) && (y >= L2_Y0) && (y < L2_Y0 + L2_H);
    wire in3s = (x >= L3_X0) && (x < L3_X0 + L3_W) && (y >= L3_Y0) && (y < L3_Y0 + L3_H);

    wire [7:0] f0 = font_byte(line0_char(rx0 >> 7),  ry0[7:2] & 4'hF);  // k=2: row=ry>>2
    wire [7:0] f1 = font_byte(line1_char(rx1 >> 4),  ry1[4:1] & 4'hF);  // k=1
    wire [7:0] f2 = font_byte(line2_char(rx2 >> 4),  ry2[4:1] & 4'hF);  // k=1
    wire [7:0] f3 = font_byte(line3_char(rx3 >> 3),  ry3[3:0] & 4'hF);  // k=0

    wire b0 = f0[7 - rx0[4:2]];
    wire b1 = f1[7 - rx1[3:1]];
    wire b2 = f2[7 - rx2[3:1]];
    wire b3 = f3[7 - rx3[2:0]];

    wire pix = (in0s & b0) | (in1s & b1) | (in2s & b2) | (in3s & b3);

    // акцентная линия под заголовком
    wire accent = (y >= L0_Y0 + L0_H + 16'd14) && (y < L0_Y0 + L0_H + 16'd18) &&
                  (x >= 16'd240) && (x < 16'd560);

    // ── палитра ─────────────────────────────────────────────────────────
    reg [5:0] r, g, b;
    always @(*) begin
        if (!visible)          {r, g, b} = 18'h00000;
        else if (pix && in0s)  {r, g, b} = {6'b111111, 6'b111111, 6'b111000}; // тёплый белый
        else if (pix && in1s)  {r, g, b} = {6'b011000, 6'b100000, 6'b101000}; // серо-бирюзовый
        else if (pix && in2s)  {r, g, b} = {6'b011000, 6'b100000, 6'b101000};
        else if (pix && in3s)  {r, g, b} = {6'b010100, 6'b011000, 6'b011100}; // приглушённый
        else if (accent)       {r, g, b} = {6'b001000, 6'b110000, 6'b010000}; // зелёная линия
        else                   {r, g, b} = {6'b000100, 6'b001100, 6'b110000}; // тёмно-синий фон
    end

    assign lcd_r = r;
    assign lcd_g = g;
    assign lcd_b = b;

    // ── LED-сердцебиение 1 Гц (active LOW) ──────────────────────────────
    reg [25:0] hb = 0;
    always @(posedge clk25 or negedge rst_n) begin
        if (!rst_n)          hb <= 0;
        else if (hb == 26'd24_999_999) hb <= 0;
        else                 hb <= hb + 26'd1;
    end
    assign state_led[0] = hb[25];               // 0.5 Гц мигание
    assign state_led[1] = 1'b1;                 // off
    assign state_led[2] = 1'b1;                 // off

endmodule
