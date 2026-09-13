#!/usr/bin/env python3
"""gen_seedrom.py — генерирует seedrom.hex для model_mlgru.v из localparam SEED_0..SEED_{S-1}
файла mlgru_vectors.vh. RTL читает seedrom[sit*S+j] (4 ситуации x S токенов) при use_ext=0.
seed_flat в RTL всего 64 бита, поэтому для S=48 единственный путь подать SEED — ситуация-ROM.
Заполняем все 4 ситуации одинаково — результат не зависит от sit.
"""
import re, sys

VEC = "mlgru_vectors.vh"
OUT = "seedrom.hex"
SITS = 4

src = open(VEC, encoding="utf-8").read()
pairs = re.findall(r"localparam\s+SEED_(\d+)\s*=\s*(\d+)\s*;", src)
pairs.sort(key=lambda p: int(p[0]))
seed = [int(v) for _, v in pairs]
m = re.search(r"localparam[^;]*\bS=(\d+)", src)
S = int(m.group(1))
if len(seed) != S:
    sys.exit(f"ожидалось SEED_0..SEED_{S-1}, найдено {len(seed)}")

with open(OUT, "w") as f:
    for _ in range(SITS):
        for b in seed:
            f.write(f"{b & 0xff:02x}\n")
print(f"seedrom.hex: {SITS} ситуаций x {S} байт; seed = {bytes(seed).decode('cp1251','replace')!r}")
