#!/usr/bin/env python3
"""Экспорт среза коннектома мухи под BRAM-матvec (fly_core).

Берёт топ-K нейронов по степени, вырезает индуцированный подматрица-срез,
упаковывает CSR в hex-инициализацию BRAM и снимает золотые вектора с CPU.

Формат упаковки entry (14 бит): {col[AW-1:2... ]} -> v = (col << 2) | wcode,
  wcode: 2'b01 = +1, 2'b10 = -1 (0 не хранится).
Два entry в одном 32-битном слове BRAM: word = (v_hi << 16) | v_lo.
x хранится тем же кодом: 16 значений на 32-битное слово.

Запуск: python export_slice.py <data_dir> <out_dir> [K]
Выход:  fly_params.vh, fly_slice_csr.hex, fly_slice_rowptr.hex,
        fly_x_test.hex, fly_y_golden.hex, fly_slice_sel.npy, fly_slice.meta.json
"""
import json
import sys

import numpy as np
import scipy.sparse as sp

data_dir = sys.argv[1] if len(sys.argv) > 1 else "data"
out_dir = sys.argv[2] if len(sys.argv) > 2 else "."
K = int(sys.argv[3]) if len(sys.argv) > 3 else 2048

M = sp.load_npz(f"{data_dir}/ternary.npz").tocsr().astype(np.int8)
N = M.shape[0]
deg = np.asarray((M != 0).sum(axis=1)).ravel() + np.asarray((M != 0).sum(axis=0)).ravel()
sel = np.sort(np.argsort(-deg)[:K])
S = M[sel][:, sel].tocsr()
S.sort_indices()
nnz = S.nnz
AW = max(11, int(np.ceil(np.log2(K))))          # бит на колонку (K=2048 -> 11)
entry_words = (nnz + 1) // 2
xwords = (K + 15) // 16

def wcode(w):
    return 1 if w > 0 else 2                     # 01=+1, 10=-1

# --- entries hex ---
words = []
data = S.data
ind = S.indices
vals = [((int(c) << 2) | wcode(int(w))) & 0x3FFF for c, w in zip(ind, data)]
if len(vals) % 2:
    vals.append(0)
for i in range(0, len(vals), 2):
    words.append(((vals[i + 1] & 0xFFFF) << 16) | vals[i])
with open(f"{out_dir}/fly_slice_csr.hex", "w") as f:
    f.write("\n".join(f"{w:08x}" for w in words) + "\n")

# --- rowptr hex ---
with open(f"{out_dir}/fly_slice_rowptr.hex", "w") as f:
    f.write("\n".join(f"{p:08x}" for p in S.indptr) + "\n")

# --- golden: x тестовый + y = S @ x ---
rng = np.random.default_rng(42)
x = rng.choice(np.array([0, 1, 2], dtype=np.int8), size=K, p=[0.6, 0.2, 0.2])  # 0/+/-
y = (S @ np.where(x == 1, 1, np.where(x == 2, -1, 0)).astype(np.int32)).astype(np.int32)

def pack16(arr):
    a = arr.astype(np.uint32)
    if len(a) % 2:
        a = np.append(a, 0)
    w = (a[1::2] << 16) | a[0::2]
    return w

# x: 16 двухбитных кодов на 32-битное слово (код = wcode: 0/1/2)
xw = []
xc = x.astype(np.uint32)
for i in range(0, K, 16):
    w = 0
    for j in range(16):
        w |= int(xc[i + j]) << (2 * j)
    xw.append(w)
with open(f"{out_dir}/fly_x_test.hex", "w") as f:
    f.write("\n".join(f"{w:08x}" for w in xw) + "\n")
with open(f"{out_dir}/fly_y_golden.hex", "w") as f:
    f.write("\n".join(f"{(int(v) & 0xFFFFFFFF):08x}" for v in y) + "\n")

np.save(f"{out_dir}/fly_slice_sel.npy", sel)
meta = {
    "K": int(K), "nnz": int(nnz), "AW": int(AW), "entry_words": int(entry_words),
    "xwords": int(xwords),
    "img_bytes": int(entry_words * 4),
    "enc": "entry16=(col<<2)|wcode, wcode 01=+1 10=-1; two entries per 32-bit word",
    "x_enc": "2b per neuron, same wcode, 16 per 32-bit word",
    "source": "FAFB v783 ternary.npz (см. build_ternary_matrix.py)",
}
with open(f"{out_dir}/fly_slice.meta.json", "w") as f:
    json.dump(meta, f, indent=2)

# --- fly_params.vh для RTL ---
with open(f"{out_dir}/fly_params.vh", "w") as f:
    f.write(f"// автогенерация: export_slice.py\n")
    f.write(f"localparam integer ROWS        = {K};\n")
    f.write(f"localparam integer COL_AW      = {AW};\n")
    f.write(f"localparam integer ENTRY_WORDS = {entry_words};\n")
    f.write(f"localparam integer XWORDS      = {xwords};\n")

print(json.dumps(meta, indent=2))
print(f"-> hex-файлы в {out_dir}/")
