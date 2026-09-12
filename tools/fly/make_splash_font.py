#!/usr/bin/env python3
"""Генератор заставки fly_splash: текст -> fly_splash_text.vh (+ ASCII-превью).

Шрифт: bitnet_layer/font8x16.hex (Terminus 8x16, CP1251, 256 глифов x 16 байт,
глиф g, строка r -> байт g*16+r, бит 7 = левый пиксель).

Запуск: python make_splash_font.py
Выход:  tang-mega-138k-pro/fly_splash/fly_splash_text.vh
"""
import sys

FONT = sys.argv[1] if len(sys.argv) > 1 else "tang-mega-138k-pro/bitnet_layer/font8x16.hex"
OUT = sys.argv[2] if len(sys.argv) > 2 else "tang-mega-138k-pro/fly_splash/fly_splash_text.vh"

# ── текст заставки: (текст, масштаб, y0) — x считаем авто-центром ──────────
LINES = [
    ("TERNARIUM", 4, 110),
    ("троичный стек", 2, 240),
    ("мозг мухи - 1.48 МБ", 2, 292),
    ("github.com/unidel2035/ternarium", 1, 356),
]
H_ACTIVE = 800

font = [int(l, 16) for l in open(FONT) if l.strip()]
assert len(font) == 4096, f"ожидал 4096 байт, got {len(font)}"


def glyph(code):
    return font[code * 16: code * 16 + 16]


def cp(text):
    return [ord(c) for c in text.encode("cp1251").decode("latin1")]


# ── геометрия ───────────────────────────────────────────────────────────────
geo = []
for text, scale, y0 in LINES:
    codes = cp(text)
    w = len(codes) * 8 * scale
    h = 16 * scale
    x0 = (H_ACTIVE - w) // 2
    geo.append({"codes": codes, "scale": scale, "x0": x0, "y0": y0, "w": w, "h": h})

# ── ASCII-превью первого глифа для проверки раскладки ───────────────────────
print("превью 'T':")
for b in glyph(cp("T")[0]):
    print("".join("#" if (b >> (7 - i)) & 1 else "." for i in range(8)))
print("превью 'т':")
for b in glyph(cp("т")[0]):
    print("".join("#" if (b >> (7 - i)) & 1 else "." for i in range(8)))

# ── RTL ─────────────────────────────────────────────────────────────────────
out = []
out.append("// АВТОГЕНЕРАЦИЯ tools/fly/make_splash_font.py — не править руками")
out.append("")
for i, g in enumerate(geo):
    out.append(f"localparam [15:0] L{i}_X0 = 16'd{g['x0']};")
    out.append(f"localparam [15:0] L{i}_Y0 = 16'd{g['y0']};")
    out.append(f"localparam [15:0] L{i}_W  = 16'd{g['w']};")
    out.append(f"localparam [15:0] L{i}_H  = 16'd{g['h']};")
    out.append(f"localparam [15:0] L{i}_S  = 16'd{g['scale']};")
    out.append(f"localparam [15:0] L{i}_N  = 16'd{len(g['codes'])};")
out.append("")

# строки -> функции char по индексу
for i, g in enumerate(geo):
    out.append(f"function [7:0] line{i}_char(input [15:0] ci);")
    out.append("    begin")
    out.append("        case (ci)")
    for j, code in enumerate(g["codes"]):
        out.append(f"            16'd{j}: line{i}_char = 8'h{code:02X};")
    out.append(f"            default: line{i}_char = 8'h20;")
    out.append("        endcase")
    out.append("    end")
    out.append("endfunction")
    out.append("")

# шрифтовой ROM как функция (код, строка)
used = sorted({c for g in geo for c in g["codes"]})
out.append("function [7:0] font_byte(input [7:0] code, input [3:0] row);")
out.append("    begin")
out.append("        case ({code, row})")
for c in used:
    for r, b in enumerate(glyph(c)):
        out.append(f"            {{8'h{c:02X},4'd{r}}}: font_byte = 8'h{b:02X};")
out.append("            default: font_byte = 8'h00;")
out.append("        endcase")
out.append("    end")
out.append("endfunction")

open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"\n-> {OUT}  ({len(out)} строк, уникальных глифов: {len(used)})")
for i, g in enumerate(geo):
    print(f"   L{i}: '{''.join(chr(c) for c in g['codes'])}' x0={g['x0']} w={g['w']} scale={g['scale']}")
