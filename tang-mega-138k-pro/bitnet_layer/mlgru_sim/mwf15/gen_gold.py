#!/usr/bin/env python3
"""gen_gold.py — gold_gen.hex из localparam GTOK_* файла mlgru_vectors.vh.

GTOK_0..GTOK_{NGEN-1} = первые NGEN байт GOLD-потока экспортёра, а GOLD начинается с
промпта (хвоста затравки). Поэтому выравниваем: находим самый длинный суффикс SEED,
совпадающий с префиксом GTOK (для "Сетунь — " это 9 байт), и пишем только
сгенерированную часть GTOK[o..NGEN-1] — её и выдаёт RTL (NGEN токенов).
"""
import re, sys

VEC = "mlgru_vectors.vh"
OUT = "gold_gen.hex"

src = open(VEC, encoding="utf-8").read()
S = int(re.search(r"localparam[^;]*\bS=(\d+)", src).group(1))
NGEN = int(re.search(r"localparam[^;]*\bNGEN=(\d+)", src).group(1))
seed = [int(v) for _, v in sorted(
    ((int(i), int(v)) for i, v in re.findall(r"localparam\s+SEED_(\d+)\s*=\s*(\d+)\s*;", src)),
    key=lambda p: p[0])]
gold = [int(v) for _, v in sorted(
    ((int(i), int(v)) for i, v in re.findall(r"localparam\s+GTOK_(\d+)\s*=\s*(\d+)\s*;", src)),
    key=lambda p: p[0])]
if len(seed) != S:
    sys.exit(f"SEED: ожидалось {S}, найдено {len(seed)}")
if len(gold) != NGEN:
    print(f"внимание: GTOK найдено {len(gold)} из {NGEN}")

off = 0
for o in range(min(S, len(gold)), 0, -1):
    if seed[S - o:S] == gold[0:o]:
        off = o
        break
gen_gold = gold[off:len(gold)]
with open(OUT, "w") as f:
    for b in gen_gold:
        f.write(f"{b & 0xff:02x}\n")
print(f"gold_gen.hex: {len(gen_gold)} байт (сдвиг промпта off={off}); "
      f"golden-продолжение = {bytes(gen_gold).decode('cp1251','replace')!r}")
