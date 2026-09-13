#!/usr/bin/env python3
"""decode_out.py — независимая сверка вывода симуляции (out_gen.hex) с golden GTOK_*.
Декодирует cp1251, считает совпадения, печатает текст. Запуск: python3 decode_out.py
"""
import re

src = open("mlgru_vectors.vh", encoding="utf-8").read()
S = int(re.search(r"localparam[^;]*\bS=(\d+)", src).group(1))
seed = [int(v) for _, v in sorted(
    ((int(i), int(v)) for i, v in re.findall(r"localparam\s+SEED_(\d+)\s*=\s*(\d+)\s*;", src)),
    key=lambda p: p[0])]
gold = [int(v) for _, v in sorted(
    ((int(i), int(v)) for i, v in re.findall(r"localparam\s+GTOK_(\d+)\s*=\s*(\d+)\s*;", src)),
    key=lambda p: p[0])]
gen = [int(l, 16) for l in open("out_gen.hex").read().split()]

off = next(o for o in range(min(S, len(gold)), 0, -1) if seed[S - o:] == gold[:o])
cmp = [(gen[i], gold[off + i]) for i in range(len(gen)) if off + i < len(gold)]
match = sum(1 for a, b in cmp if a == b)

print(f"затравка   (cp1251): {bytes(seed).decode('cp1251','replace')!r}")
print(f"golden-gen (cp1251): {bytes(gold[off:]).decode('cp1251','replace')!r}")
print(f"RTL-gen    (cp1251): {bytes(gen).decode('cp1251','replace')!r}")
print(f"сравнимо {len(cmp)}, совпало {match}, расхождений {len(cmp) - match}")
for i, (a, b) in enumerate(cmp):
    if a != b:
        print(f"  tok[{i}]: RTL={a:02x} {chr(a) if 32 <= a < 127 else ''} "
              f"golden={b:02x} {chr(b) if 32 <= b < 127 else ''}")
print("PASS" if match == len(cmp) and cmp else "FAIL")
