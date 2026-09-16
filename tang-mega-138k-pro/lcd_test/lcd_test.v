// lcd_test.v — минимальная проверка LCD-тракта Tang Mega 138K Pro Dock.
// Тайминг и DE скопированы 1:1 из официального примера Sipeed 800_480_screen
// (SYNC-DE, всего 1192×533, DE только в видимом окне). Панель RGB (проверено
// заводскими полосами). Каналы НЕ переставлены. Такт = 25 МГц (делитель /2).
//
// Рисунок: 18 вертикальных шкал R→G→B (как заводские) + 8-пиксельная белая
// рамка по периметру + красная полоса внизу (V=472..479) как маркер конца кадра.

module lcd_test (
    input  wire       clk,      // 50 МГц
    output wire       lcd_clk,
    output wire       lcd_en,
    output wire [5:0] lcd_r,
    output wire [5:0] lcd_g,
    output wire [5:0] lcd_b
);
    // 25 МГц на fabric-делителе (так же, как в fly_brain_lcd — проверяем сам тракт)
    reg clk25 = 1'b0;
    always @(posedge clk) clk25 <= ~clk25;
    assign lcd_clk = clk25;

    // ── тайминг Sipeed 800_480 (SYNC-DE, без HS/VS) ──────────────────────
    localparam H_VALID = 16'd800, H_FP = 16'd210, H_BP = 16'd182;
    localparam V_VALID = 16'd480, V_FP = 16'd45,  V_BP = 16'd8;
    localparam H_TOTAL = H_VALID + H_FP + H_BP;   // 1192
    localparam V_TOTAL = V_VALID + V_FP + V_BP;   // 533

    reg [15:0] hc = 0, vc = 0;
    always @(posedge clk25) begin
        if (hc == H_TOTAL - 1) begin
            hc <= 0;
            vc <= (vc == V_TOTAL - 1) ? 16'd0 : vc + 16'd1;
        end else
            hc <= hc + 16'd1;
    end

    wire in_h = (hc >= H_BP) && (hc < H_BP + H_VALID);
    wire in_v = (vc >= V_BP) && (vc < V_BP + V_VALID);
    wire vis  = in_h && in_v;
    assign lcd_en = vis;

    wire [15:0] px = hc - H_BP;   // 0..799
    wire [15:0] py = vc - V_BP;   // 0..479

    // ── цвет ─────────────────────────────────────────────────────────────
    // шкала: 18 полос шириной 44 px; 1..6 → R 1..32, 7..12 → G 1..32, 13..18 → B 1..32
    wire [4:0] step = px[9:5] >= 18 ? 5'd0 : px[4:0] * 6'd2 + 6'd1;
    reg [5:0] r6, g6, b6;
    always @(*) begin
        r6 = 6'd0; g6 = 6'd0; b6 = 6'd0;
        if (vis) begin
            if (px < 18'd264)      r6 = {step, 1'b0};   // R полосы
            else if (px < 18'd528) g6 = {step, 1'b0};   // G полосы
            else                   b6 = {step, 1'b0};   // B полосы
            // белая рамка 8 px
            if (px < 18'd8 || px >= 18'd792 || py < 16'd8 || py >= 16'd472) begin
                r6 = 6'd63; g6 = 6'd63; b6 = 6'd63;
            end
            // красный маркер нижнего края внутри рамки
            if (py >= 16'd472) begin
                r6 = 6'd63; g6 = 6'd0;  b6 = 6'd0;
            end
        end
    end
    assign lcd_r = r6;
    assign lcd_g = g6;
    assign lcd_b = b6;

endmodule
