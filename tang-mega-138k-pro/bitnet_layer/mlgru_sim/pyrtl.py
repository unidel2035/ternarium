#!/usr/bin/env python3
"""pyrtl.py — бит-точная эмуляция model_mlgru.v на Python для локализации расхождения
с golden (GTOK_*). Повторяет арифметику RTL: mul16 == точное 16x16 знаковое умножение,
sdiv32 == деление с ОКРУГЛЕНИЕМ К НУЛЮ, ">>" == арифметический сдвиг (floor).

Режимы округления (флаги):
  --rtl   : как RTL  (sdiv -> trunc к нулю; proj/u -> floor через >>>)
  --gold  : как экспортёр (numpy: // -> floor; np.round -> round-half-even)
"""
import math, re, sys

D, L, H, V, S, NGEN = 24, 3, 48, 256, 48, 64
RW, SHIN, FXONE, AS, LN, HALF, MWF = 48, 3, 256, 32, 128, 64, 12

MODE = "rtl" if "--rtl" in sys.argv else "gold"
FLOORRMS = "--floorrms" in sys.argv   # sdiv32 -> округление вниз (как // в numpy)
RNDPROJ = "--rndproj" in sys.argv     # PROJ/SCALED -> округление к ближайшему

def sd(v, bits=16):                       # знаковое приведение
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v

def sdiv32(a, b):                         # RTL: trunc к нулю
    if MODE == "gold" or FLOORRMS:        # numpy // : floor
        return a // b
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q

def shift_r(v, n):                        # арифметический сдвиг вправо (floor) — как >>>
    return v >> n

def proj_fx(mw, pre):                     # PROJ/SCALED: (pre*mw)>>>MWF в RTL
    if MODE == "gold":                    # экспортёр: np.round(meanW*pre), meanW≈mw/2^12
        return int(np.round((mw * pre) / (1 << MWF)))
    if RNDPROJ:                           # округление к ближайшему: (x + 2^(MWF-1))>>>MWF
        return shift_r(mw * pre + (1 << (MWF - 1)), MWF)
    return shift_r(mw * pre, MWF)

import numpy as np

# ── загрузка ROM ──
wrom = []
for line in open("mlgru_wt.hex"):
    line = line.strip()
    if line:
        wrom.append(int(line, 16))
embrom = [sd(int(line, 16)) for line in open("mlgru_emb.hex") if line.strip()]
lutrom = [sd(int(line, 16)) for line in open("mlgru_lut.hex") if line.strip()]

vh = open("mlgru_vectors.vh", encoding="utf-8").read()
P = {}
for lp in re.findall(r"localparam\s+([^;]+);", vh):          # localparam a=1,b=2; — списки
    for name, val in re.findall(r"([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\d+)", lp):
        P[name] = int(val)
B = {k[2:]: v for k, v in P.items() if k.startswith("B_")}
BL = {k[3:]: v for k, v in P.items() if k.startswith("BL_")}
SEED = [int(v) for _, v in sorted((int(i), int(v)) for i, v in
        re.findall(r"localparam\s+SEED_(\d+)\s*=\s*(\d+)\s*;", vh))]
GOLD = [int(v) for _, v in sorted((int(i), int(v)) for i, v in
        re.findall(r"localparam\s+GTOK_(\d+)\s*=\s*(\d+)\s*;", vh))]

def wval(row, c):                          # троичный вес: 00=-1 01=0 10=+1
    return (wrom[row] >> (2 * c)) & 3

def mvw(row, n, av):                       # как функция mvw в RTL
    s = 0
    for c in range(RW):
        if c < n:
            w = wval(row, c)
            if w == 2:
                s += av[c]
            elif w == 0:
                s -= av[c]
    return s

def clf(v):  return max(-127, min(127, v))
def clf2(v): return max(-8192, min(8192, v))
def lutidx(pre): return max(0, min(LN - 1, shift_r(pre, SHIN) + HALF))

def isqrt(n):
    return math.isqrt(max(0, n))

def rms(x):                                # RTL RMS+DVV/DVR/DVW (с патчем ss/D)
    ss = sum(int(xi) * int(xi) for xi in x)
    ms = ss // D
    den = isqrt(ms * AS * AS) or 1
    return [clf(sdiv32(int(xi) * AS * AS, den)) for xi in x]

out = []
seq = list(SEED)
hs = [0] * (L * D)
for g in range(NGEN):
    x = [embrom[seq[len(seq) - S + t] * D + d] for t in range(S) for d in range(D)]  # окно seq[-S:]
    hs = [0] * (L * D)          # RTL обнуляет hs в NXT/IDLE; экспортёр: h[:]=0 после каждого слоя
    for l in range(L):
        for t in range(S):
            xt = x[t * D:(t + 1) * D]
            xn = rms(xt)
            fg = [lutrom[BL[f"Lf{l}"] + lutidx(mvw(B[f"Wf{l}"] + dd, D, xn))] for dd in range(D)]
            cg = [lutrom[BL[f"Lc{l}"] + lutidx(mvw(B[f"Wc{l}"] + dd, D, xn))] for dd in range(D)]
            gg = [lutrom[BL[f"Lg{l}"] + lutidx(mvw(B[f"Wg{l}"] + dd, D, xn))] for dd in range(D)]
            if l == 2 and t == S - 1:
                print("REC fg =", " ".join(str(v) for v in fg))
                print("REC cg =", " ".join(str(v) for v in cg))
                print("REC gg =", " ".join(str(v) for v in gg))
                print("REC hs_prev =", " ".join(str(hs[l * D + d]) for d in range(D)))
            for d in range(D):
                hs[l * D + d] = shift_r(fg[d] * hs[l * D + d] + (FXONE - fg[d]) * cg[d], 8)
            av = [clf(shift_r(gg[d] * hs[l * D + d], 8)) for d in range(D)]
            for d in range(D):
                pre = mvw(B[f"Wo{l}"] + d, D, av)
                v = clf2(int(xt[d]) + proj_fx(P[f"MWo_{l}"], pre))
                xt[d] = v
            x[t * D:(t + 1) * D] = xt
        for t in range(S):
            xt = x[t * D:(t + 1) * D]
            xn = rms(xt)
            g2 = [lutrom[BL[f"L2g{l}"] + lutidx(mvw(B[f"W2g{l}"] + dd, D, xn))] for dd in range(H)]
            u = []
            for dd in range(H):
                pre = mvw(B[f"W2u{l}"] + dd, D, xn)
                u.append(clf(proj_fx(P[f"MWu_{l}"], pre)))
            av = [clf(shift_r(g2[d] * u[d], 5)) for d in range(H)]
            for d in range(D):
                pre = mvw(B[f"W2d{l}"] + d, H, av)
                v = clf2(int(xt[d]) + proj_fx(P[f"MWd_{l}"], pre))
                xt[d] = v
            x[t * D:(t + 1) * D] = xt
    xn = rms(x[(S - 1) * D:])
    best, barg = -2**31, 0
    for r in range(V):
        pre = mvw(B["OUT"] + r, D, xn)
        if pre > best:
            best, barg = pre, r
    if g == 0:
        print(f"g=0: barg={barg} best={best}")
        print("x  =", " ".join(str(v) for v in x[(S - 1) * D:]))
        print("xn =", " ".join(str(v) for v in xn))
        print("hs2=", " ".join(str(v) for v in hs[2 * D:]))
    out.append(barg)
    seq.append(barg)

print(f"режим={MODE} floorrms={FLOORRMS} rndproj={RNDPROJ}")
print("RTL-emul:", bytes(out).decode("cp1251", "replace"))
print("golden  :", bytes(GOLD[len(GOLD) - (NGEN - 9):]).decode("cp1251", "replace")
      if len(GOLD) >= NGEN - 9 else "?")
off = next(o for o in range(min(S, len(GOLD)), 0, -1) if SEED[S - o:] == GOLD[:o])
g = GOLD[off:]
m = sum(1 for i in range(min(len(g), len(out))) if g[i] == out[i])
print(f"совпало {m}/{min(len(g), len(out))}")
open("pyrtl_out.hex", "w").write("\n".join(f"{b:02x}" for b in out) + "\n")
print("hex:", " ".join(f"{b:02x}" for b in out[:16]))
