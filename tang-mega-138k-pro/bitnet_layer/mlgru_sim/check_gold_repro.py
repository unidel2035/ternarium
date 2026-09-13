#!/usr/bin/env python3
"""check_gold_repro.py — воспроизводим ли golden GTOK_* из ЭКСПОРТИРОВАННЫХ артефактов?

Экспортёр считает fixed-point генерацию с ПЛНОТОЧНЫМИ scale (float meanW) в proj()/gate(),
а в RTL экспортирует только MWo/MWu/MWd = round(meanW*2^12). Если заменить meanW на
квантованное mw/4096 и текст изменится — golden в принципе не воспроизводится из hex,
значит бит-в-бит совпадения RTL с GTOK быть не может.

Запуск (нужен torch): ~/fly-connectome/.venv/bin/python check_gold_repro.py <pt> <vectors.vh>
"""
import math, re, sys
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

PT, VEC = sys.argv[1], sys.argv[2]
D = 24
V, L, S = 256, 3, 48; H = 2 * D
PROMPT = "Сетунь — "; NGEN = 64

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
AS = int(AQ_S); FXONE = 256; LN = 128; HALF = LN // 2
def tern_np(w):
    w = w.detach().numpy(); s = 1.0 / max(1e-5, np.abs(w).mean()); return np.clip(np.round(w * s), -1, 1).astype(np.int64), float(np.abs(w).mean())
Wf, Wc, Wg, Wo, W2g, W2u, W2d = [], [], [], [], [], [], []
for l in range(L):
    b = m.ly[l]
    Wf.append(tern_np(b.mix.f.l.weight)); Wc.append(tern_np(b.mix.c.l.weight))
    Wg.append(tern_np(b.mix.g.l.weight)); Wo.append(tern_np(b.mix.o.l.weight))
    W2g.append(tern_np(b.ffn.g.l.weight)); W2u.append(tern_np(b.ffn.u.l.weight)); W2d.append(tern_np(b.ffn.d.l.weight))
OUT = tern_np(m.out.l.weight)
emb = m.emb.weight.detach().numpy(); ES = AS / max(1e-5, np.abs(emb).std()); embq = np.clip(np.round(emb * ES), -512, 512).astype(np.int64)

# MW-множители из mlgru_vectors.vh (то, что реально доступно RTL)
vh = open(VEC, encoding="utf-8").read()
MW = {n: int(v) for n, v in re.findall(r"(MWo_\d+|MWu_\d+|MWd_\d+)\s*=\s*(\d+)", vh)}
SHIN = int(re.search(r"\bSHIN=(\d+)", vh).group(1))
MWF = 12
QUANT = False
def sc_eff(Wm):     # эффективный scale proj(): float meanW или round(meanW*2^MWF)/2^MWF
    if not QUANT:
        return Wm[1]
    return round(Wm[1] * (1 << MWF)) / (1 << MWF)
RTLROUND = "--rtlround" in sys.argv
FLOORPROJ = RTLROUND or "--floorproj" in sys.argv
TRUNCRMS = RTLROUND or "--truncrms" in sys.argv
def proj(Wm, a8):
    pre = (Wm[0] @ a8).astype(np.int64)
    if FLOORPROJ:                     # как RTL: (pre*MW)>>>MWF, MW=round(meanW*2^MWF), floor
        return (int(round(Wm[1] * (1 << MWF))) * pre) >> MWF
    return np.round(sc_eff(Wm) * pre).astype(np.int64)
def isqrt(n):
    n = int(max(0, n)); r = int(n ** 0.5)
    while r * r > n: r -= 1
    while (r + 1) * (r + 1) <= n: r += 1
    return r
def rms(x):
    ss = int((x.astype(np.int64) ** 2).sum()); ms = ss // len(x); den = isqrt(ms * AS * AS) or 1
    if TRUNCRMS:                      # sdiv32 округляет к нулю, а не к -inf
        q = [int(abs(int(xi)) * AS * AS // den) * (1 if xi >= 0 else -1) for xi in x]
        return np.clip(np.array(q, dtype=np.int64), -127, 127)
    return np.clip(np.array([int(xi) * AS * AS // den for xi in x], dtype=np.int64), -127, 127)
sig = lambda z: 1.0 / (1.0 + math.exp(-max(-30, min(30, z)))); silu = lambda z: z * sig(z)
def gate(Wm, a8, fn, outscale, shin):
    W, meanW = Wm; pre = W @ a8
    tab = np.array([int(round(outscale * fn(((k - HALF) << SHIN) * meanW / AQ_S))) for k in range(LN)], dtype=np.int64)
    return tab[np.clip((pre >> shin) + HALF, 0, LN - 1)]
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
    seq = ([0x20] * (S - len(pb)) + pb)[-S:]
    out = list(pb)
    for _ in range(n):
        nt = fx_forward(seq[-S:], SHIN); out.append(nt); seq.append(nt)
        if nt == 10 and len(out) > len(pb) + 15: break
    return out

gold = [int(v) for _, v in sorted((int(i), int(v)) for i, v in
        re.findall(r"localparam\s+GTOK_(\d+)\s*=\s*(\d+)\s*;", vh))]

MWF = 15 if ("--mwf15" in sys.argv or "--mwfscan" in sys.argv) else 12
a = fx_gen(SHIN)
print(f"SHIN={SHIN}")
print(f"float meanW  : {bytes(a).decode('cp1251','replace')!r}")
print(f"float == GTOK  : {a[:len(gold)] == gold}")
MFF = [MWF]
QUANT = True
import itertools
base_f, base_r = FLOORPROJ, TRUNCRMS
for fp_, tr_ in (((False, True),) if "--mwfscan" in sys.argv else ((base_f, base_r),)):
    FLOORPROJ, TRUNCRMS = fp_, tr_
    for mwf in MFF:
        MWF = mwf
    MWF = mwf
    b = fx_gen(SHIN)
    same = b[:len(gold)] == gold
    # множитель MWo при таком MWF должен влезать в 16 бит (mul16 в RTL берёт b[15:0])
    mx = max(round(Wm[1] * (1 << mwf)) for Wm in list(Wo) + list(W2u) + list(W2d))
    print(f"MWF={mwf:2d} (max MW={mx}, 16бит: {'да' if mx < 32768 else 'НЕТ'}) -> "
          f"{bytes(b).decode('cp1251','replace')!r}  совпадает с GTOK: {same}")
