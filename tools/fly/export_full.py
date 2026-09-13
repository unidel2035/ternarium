#!/usr/bin/env python3
"""export_full.py — whole-brain memory-image для внешней памяти (трасса B).

Весь коннектом (5.92М тритов) упаковывается под стриминг из SDRAM/DDR3:

  сегмент W (веса):      CSR data, 2 бита/трит, little-endian паковка  → ~1.48 МБ
  сегмент C (колонки):   delta-код: col[j]-col[j-1] в u16 (нарастающие пробелы
                         эскалируются escape 0xFFFF + u32), /4 джампами     → ~2-4 МБ
  сегмент R (rowptr):    u32 × (N+1)                                        → ~0.56 МБ

Формат заголовка (256 байт, little-endian):
  magic 'TRNF' | version u32 | N u32 | nnz u32 | off_W u32 | off_C u32 | off_R u32

Запуск: python export_full.py <ternary.npz> <out_dir>
Выход:  fly_full.img (одним файлом) + fly_full.meta.json
Плата:  Tang Mega 138K Pro Dock, SDRAM — с запасом ×20.
"""
import json
import struct
import sys

import numpy as np
import scipy.sparse as sp

npz = sys.argv[1] if len(sys.argv) > 1 else "data/ternary.npz"
out_dir = sys.argv[2] if len(sys.argv) > 2 else "."

M = sp.load_npz(npz).tocsr().astype(np.int8)
M.sort_indices()
N = M.shape[0]
nnz = M.nnz

# ── сегмент W: 2 бита на трит (01=+1, 10=−1) ────────────────────────────────
data = M.data
codes = np.where(data < 0, 2, 1).astype(np.uint8)
bits = codes
pad = (-len(bits)) % 4
bits = np.append(bits, np.zeros(pad, dtype=np.uint8))
W = np.zeros(len(bits) // 4, dtype=np.uint32)
for k in range(4):
    W |= bits[k::4].astype(np.uint32) << (2 * k)

# ── сегмент C: delta u16 + escape ───────────────────────────────────────────
indices = M.indices.astype(np.int64)
indptr = M.indptr.astype(np.uint32)
C_list = []
escapes = 0
for row in range(N):
    lo, hi = indptr[row], indptr[row + 1]
    prev = -1
    for j in range(lo, hi):
        d = indices[j] - prev
        prev = indices[j]
        if d < 0xFFFF:
            C_list.append(d)
        else:
            C_list.append(0xFFFF)
            C_list.append((d >> 16) & 0xFFFF)
            C_list.append(d & 0xFFFF)
            escapes += 1
C_arr = np.array(C_list, dtype=np.uint16)
while len(C_arr) % 2:
    C_arr = np.append(C_arr, np.uint16(0))
C = (C_arr[1::2].astype(np.uint32) << 16) | C_arr[0::2].astype(np.uint32)

# ── сегмент R ───────────────────────────────────────────────────────────────
R = indptr

# ── сборка образа ───────────────────────────────────────────────────────────
off_W = 256
off_C = off_W + len(W) * 4
off_R = off_C + len(C) * 4
header = struct.pack(
    "<4sIIIIII", b"TRNF", 1, N, nnz, off_W, off_C, off_R)
header += b"\x00" * (256 - len(header))

img = bytearray(header)
img += W.tobytes()
img += C.tobytes()
img += R.tobytes()
open(f"{out_dir}/fly_full.img", "wb").write(img)

meta = {
    "neurons": int(N),
    "nnz": int(nnz),
    "W_bytes": int(len(W) * 4),
    "C_bytes": int(len(C) * 4),
    "R_bytes": int(len(R) * 4),
    "C_escapes": int(escapes),
    "img_bytes": len(img),
    "layout": "hdr256 | W(2b/trit) | C(u16 delta, 0xFFFF=escape+u32) | R(u32 rowptr)",
}
with open(f"{out_dir}/fly_full.meta.json", "w") as f:
    json.dump(meta, f, indent=2)
print(json.dumps(meta, indent=2))
print(f"-> {out_dir}/fly_full.img")
