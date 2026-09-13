#!/usr/bin/env python3
"""gen_vectors_mwf.py — вариант mlgru_vectors.vh с более точными scale-множителями.

MWo/MWu/MWd в экспорте = round(meanW*2^MWF) при MWF=12 (относит. ошибка ~1.2e-4) —
этого не хватает, золотая траектория сбивается. Проверено: MWF=15..17 воспроизводит
golden, и при MWF<=17 множители ещё влезают в 16 бит (mul16 в RTL использует b[15:0]).
Пишем копию .vh с MWF=15 и пересчитанными MW*; остальное (B_*, BL_*, SEED_*, GTOK_*) — без изменений.

Запуск: ~/fly-connectome/.venv/bin/python gen_vectors_mwf.py <pt> <vectors.vh> <out_dir>
"""
import re, sys
import numpy as np
import torch
import torch.nn as nn

PT, VEC, OUTDIR = sys.argv[1], sys.argv[2], sys.argv[3]
D = 24; L = 3; V = 256; H = 2 * D
MWF = 15

class BitLin(nn.Module):
    def __init__(s, i, o, norm=True): super().__init__(); s.l = nn.Linear(i, o, bias=False)
class MLGRU(nn.Module):
    def __init__(s): super().__init__(); s.f = BitLin(D, D); s.c = BitLin(D, D); s.g = BitLin(D, D); s.o = BitLin(D, D, norm=False)
class GLU(nn.Module):
    def __init__(s): super().__init__(); s.g = BitLin(D, H); s.u = BitLin(D, H); s.d = BitLin(H, D, norm=False)
class Block(nn.Module):
    def __init__(s): super().__init__(); s.mix = MLGRU(); s.ffn = GLU()
class Net(nn.Module):
    def __init__(s): super().__init__(); s.emb = nn.Embedding(V, D); s.ly = nn.ModuleList([Block() for _ in range(L)]); s.fn = nn.RMSNorm(D, elementwise_affine=False); s.out = BitLin(D, V, norm=False)

m = Net(); m.load_state_dict(torch.load(PT)); m.eval()
vals = {}
for l in range(L):
    b = m.ly[l]
    vals[f"MWo_{l}"] = round(float(np.abs(b.mix.o.l.weight.detach().numpy()).mean()) * (1 << MWF))
    vals[f"MWu_{l}"] = round(float(np.abs(b.ffn.u.l.weight.detach().numpy()).mean()) * (1 << MWF))
    vals[f"MWd_{l}"] = round(float(np.abs(b.ffn.d.l.weight.detach().numpy()).mean()) * (1 << MWF))

src = open(VEC, encoding="utf-8").read()
src, n = re.subn(r"localparam (MWo_\d+=[0-9]+, MWu_\d+=[0-9]+, MWd_\d+=[0-9]+);",
                 lambda mm: "localparam " + ",".join(
                     f"{p[0]}={vals[p[0]]}"
                     for p in (tok.split("=") for tok in mm.group(1).replace(" ", "").split(","))) + ";", src)
assert n == L, n
src, n2 = re.subn(r"\bMWF=\d+;", f"MWF={MWF};", src)
assert n2 == 1, n2
open(f"{OUTDIR}/mlgru_vectors.vh", "w", encoding="utf-8", newline="\n").write(src)
print(f"MWF={MWF}: " + ", ".join(f"{k}={v}" for k, v in vals.items()))
print(f"макс. множитель = {max(vals.values())} (влезает в 16 бит: {'да' if max(vals.values()) < 32768 else 'НЕТ'})")
