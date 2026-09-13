#!/usr/bin/env python3
"""export_neutral_rtl.py — нейтральная байтовая модель → RTL hex для model_mlgru.v.

Клон export_ru_rtl.py (та же fixed-point семантика и форматы), но:
  - грузит mlgru_neutral_d24.pt (нейтральный корпус, tools/train_mlgru_neutral.py)
  - затравка/предохранитель — нейтральные слова, без тактического лексикона
  - выход в указанный каталог (по умолчанию bitnet_layer/)

Запуск: python export_neutral_rtl.py <pt_file> <out_dir>
"""
import math
import os
import sys

import numpy as np
import torch

HERE = os.path.dirname(os.path.abspath(__file__))
PT = sys.argv[1] if len(sys.argv) > 1 else "mlgru_neutral_d24.pt"
OUTDIR = sys.argv[2] if len(sys.argv) > 2 else "tang-mega-138k-pro/bitnet_layer"
D = 24
V, L, S = 256, 3, 48; H = 2 * D
PROMPT = "Сетунь — "; NGEN = 64

import torch.nn as nn
def wq(w): s = 1.0 / w.abs().mean().clamp(min=1e-5); return (w * s).round().clamp(-1, 1) / s
AQ_S = 32.0
def aq(x): return (x * AQ_S).round().clamp(-127, 127) / AQ_S
class BitLin(nn.Module):
    def __init__(s, i, o, norm=True): super().__init__(); s.l = nn.Linear(i, o, bias=False); s.n = nn.RMSNorm(i, elementwise_affine=False) if norm else None
    def forward(s, x):
        if s.n is not None: x = s.n(x)
        x = x + (aq(x) - x).detach(); w = s.l.weight + (wq(s.l.weight) - s.l.weight).detach(); return F.linear(x, w)
class MLGRU(nn.Module):
    def __init__(s): super().__init__(); s.f = BitLin(D, D); s.c = BitLin(D, D); s.g = BitLin(D, D); s.o = BitLin(D, D, norm=False)
class GLU(nn.Module):
    def __init__(s): super().__init__(); s.g = BitLin(D, H); s.u = BitLin(D, H); s.d = BitLin(H, D, norm=False)
class Block(nn.Module):
    def __init__(s): super().__init__(); s.mix = MLGRU(); s.ffn = GLU()
class Net(nn.Module):
    def __init__(s): super().__init__(); s.emb = nn.Embedding(V, D); s.ly = nn.ModuleList([Block() for _ in range(L)]); s.fn = nn.RMSNorm(D, elementwise_affine=False); s.out = BitLin(D, V, norm=False)

m = Net(); m.load_state_dict(torch.load(PT)); m.eval()
print(f"загружен {PT} | D={D} L={L} V={V} H={H}")

AS = int(AQ_S); FXONE = 256; LN = 128; HALF = LN // 2
def tern_np(w):
    w = w.detach().numpy(); s = 1.0 / max(1e-5, np.abs(w).mean()); return np.clip(np.round(w * s), -1, 1).astype(np.int64), float(np.abs(w).mean())
Wf = []; Wc = []; Wg = []; Wo = []; W2g = []; W2u = []; W2d = []
for l in range(L):
    b = m.ly[l]
    Wf.append(tern_np(b.mix.f.l.weight)); Wc.append(tern_np(b.mix.c.l.weight))
    Wg.append(tern_np(b.mix.g.l.weight)); Wo.append(tern_np(b.mix.o.l.weight))
    W2g.append(tern_np(b.ffn.g.l.weight)); W2u.append(tern_np(b.ffn.u.l.weight)); W2d.append(tern_np(b.ffn.d.l.weight))
OUT = tern_np(m.out.l.weight)
emb = m.emb.weight.detach().numpy(); ES = AS / max(1e-5, np.abs(emb).std()); embq = np.clip(np.round(emb * ES), -512, 512).astype(np.int64)
def isqrt(n):
    n = int(max(0, n)); r = int(n ** 0.5)
    while r * r > n: r -= 1
    while (r + 1) * (r + 1) <= n: r += 1
    return r
def rms(x):
    ss = int((x.astype(np.int64) ** 2).sum()); ms = ss // len(x); den = isqrt(ms * AS * AS) or 1
    return np.clip(np.array([int(xi) * AS * AS // den for xi in x], dtype=np.int64), -127, 127)
sig = lambda z: 1.0 / (1.0 + math.exp(-max(-30, min(30, z)))); silu = lambda z: z * sig(z)
def gate(Wm, a8, fn, outscale, SHIN):
    W, meanW = Wm; pre = W @ a8
    tab = np.array([int(round(outscale * fn(((k - HALF) << SHIN) * meanW / AQ_S))) for k in range(LN)], dtype=np.int64)
    return tab[np.clip((pre >> SHIN) + HALF, 0, LN - 1)]
def proj(Wm, a8):
    W, meanW = Wm; return np.round(meanW * (W @ a8)).astype(np.int64)
def i8(v): return np.clip(v, -127, 127)
def fx_forward(seq, SHIN):
    x = np.stack([embq[t] for t in seq]).astype(np.int64); h = np.zeros(D, dtype=np.int64)
    for l in range(L):
        for t in range(S):
            xn = rms(x[t])
            f = gate(Wf[l], xn, sig, FXONE, SHIN); c = gate(Wc[l], xn, silu, AS, SHIN); g = gate(Wg[l], xn, sig, FXONE, SHIN)
            h = (f * h + (FXONE - f) * c) >> 8; gh = i8((g * h) >> 8)
            x[t] = np.clip(x[t] + proj(Wo[l], gh), -8192, 8192)
        for t in range(S):
            xn = rms(x[t]); g2 = gate(W2g[l], xn, silu, AS, SHIN); u = i8(proj(W2u[l], xn))
            gu = i8((g2 * u) >> 5); x[t] = np.clip(x[t] + proj(W2d[l], gu), -8192, 8192)
        h[:] = 0
    xn = rms(x[S - 1]); W, _ = OUT; return int(np.argmax(W @ xn))

pb = list(PROMPT.encode("cp1251"))
def fx_gen(SHIN, n=NGEN):
    seq = ([0x20] * (S - len(pb)) + pb)[-S:] if len(pb) < S else pb[-S:]
    out = list(pb)
    for _ in range(n):
        nt = fx_forward(seq[-S:], SHIN); out.append(nt); seq.append(nt)
        if nt == 10 and len(out) > len(pb) + 15: break
    return out

print("=== ПРОВЕРКА fixed-point генерации ===")
best = None
for SHIN in (3, 4, 5, 6):
    out = fx_gen(SHIN); txt = bytes(out).decode("cp1251", "replace")
    bad = txt.count("�"); printable = sum(1 for c in txt if c.isprintable() or c == "\n")
    score = printable - bad * 5
    print(f"  SHIN={SHIN}: {txt!r}")
    if best is None or score > best[0]: best = (score, SHIN, txt)
score, SHIN, txt = best
print(f"\n=== ЛУЧШИЙ SHIN={SHIN} ===\n{txt!r}")
GOLD = fx_gen(SHIN)
NEUTRAL_WORDS = ("троичн", "сетун", "плат", "мозг", "регистр", "модул", "двоичн", "логик")
GATE_OK = txt.count("�") < 6 and any(w in txt.lower() for w in NEUTRAL_WORDS)
print(f"\nПРЕДОХРАНИТЕЛЬ: {'✅ связный нейтральный текст → можно в RTL' if GATE_OK else '❌ fixed-point рассыпался → не экспортирую'}")
if not GATE_OK:
    print("STOP"); sys.exit(1)

RW = max(D, H)
MATS = []
for l in range(L):
    MATS += [(f"Wf{l}", Wf[l], D, D), (f"Wc{l}", Wc[l], D, D), (f"Wg{l}", Wg[l], D, D), (f"Wo{l}", Wo[l], D, D),
             (f"W2g{l}", W2g[l], D, H), (f"W2u{l}", W2u[l], D, H), (f"W2d{l}", W2d[l], H, D)]
MATS.append(("OUT", OUT, D, V))
base = {}; addr = 0; rows_hex = []; enc = {-1: 0, 0: 1, 1: 2}
for nm, (Wm, _mw), indim, outdim in [(m_[0], (m_[1][0], m_[1][1]), m_[2], m_[3]) for m_ in MATS]:
    base[nm] = addr
    for r in range(outdim):
        word = 0
        for c in range(indim): word |= enc[int(Wm[r][c])] << (2 * c)
        rows_hex.append(f"{word:0{(2 * RW + 3) // 4}x}"); addr += 1
open(f"{OUTDIR}/mlgru_wt.hex", "w").write("\n".join(rows_hex) + "\n")
open(f"{OUTDIR}/mlgru_emb.hex", "w").write("\n".join(f"{int(embq[r][c]) & 0xffff:04x}" for r in range(V) for c in range(D)) + "\n")
LUTMATS = []
for l in range(L):
    LUTMATS += [(f"Lf{l}", Wf[l][1], sig, FXONE), (f"Lc{l}", Wc[l][1], silu, AS), (f"Lg{l}", Wg[l][1], sig, FXONE), (f"L2g{l}", W2g[l][1], silu, AS)]
lut_hex = []; lbase = {}; li = 0
for nm, meanW, fn, outscale in LUTMATS:
    lbase[nm] = li
    for k in range(LN): lut_hex.append(f"{int(round(outscale * fn(((k - HALF) << SHIN) * meanW / AQ_S))) & 0xffff:04x}"); li += 1
open(f"{OUTDIR}/mlgru_lut.hex", "w").write("\n".join(lut_hex) + "\n")
MWF = 12
def mwfp(mw): return int(round(mw * (1 << MWF)))
SEED = ([0x20] * (S - len(pb)) + pb)[-S:]
with open(f"{OUTDIR}/mlgru_vectors.vh", "w") as f:
    f.write("// НЕЙТРАЛЬНАЯ БАЙТОВАЯ MLGRU (CP1251) — экспорт для RTL (трасса C)\n")
    f.write(f"localparam V={V},D={D},L={L},H={H},S={S},NGEN={NGEN},RW={RW},SHIN={SHIN},FXONE={FXONE},AS={AS},LN={LN},HALF={HALF},MWF={MWF};\n")
    f.write(f"localparam WROWS={addr};\n")
    for nm in base: f.write(f"localparam B_{nm}={base[nm]};\n")
    for nm in lbase: f.write(f"localparam BL_{nm}={lbase[nm]};\n")
    for l in range(L): f.write(f"localparam MWo_{l}={mwfp(Wo[l][1])}, MWu_{l}={mwfp(W2u[l][1])}, MWd_{l}={mwfp(W2d[l][1])};\n")
    for i, t in enumerate(SEED): f.write(f"localparam SEED_{i}={t};\n")
    for i, t in enumerate(GOLD[:NGEN]): f.write(f"localparam GTOK_{i}={t};\n")
print(f"экспорт в {OUTDIR}: mlgru_wt.hex ({addr} строк), mlgru_emb.hex, mlgru_lut.hex ({li}), mlgru_vectors.vh | NGEN={NGEN}")
print(f"golden (fixed-point) = {bytes(GOLD).decode('cp1251','replace')!r}")
