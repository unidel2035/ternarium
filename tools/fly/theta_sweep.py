#!/usr/bin/env python3
"""theta_sweep.py — подбор порога theta для живой динамики среза K=256.

Динамика 1:1 с RTL fly_brain_lcd: y=S·x; x'=+1 (y>θ), -1 (y<-θ), 0.
Авто-стимул как в RTL-демо: 4 сенсора подкачиваются каждый шаг (по кругу).
Метрика на серию 16 шагов: изменений состояния (flip-rate), P/N диапазоны.
Живой режим: flips>0 на каждом шаге, P не 0 и не K.
"""
import numpy as np
import scipy.sparse as sp

DATA = "/mnt/c/Users/unide/fly-connectome/data"
K = 256
STEPS = 16
SENS = [0x092, 0x096, 0x05E, 0x032]   # те же сенсоры, что в RTL-демо

M = sp.load_npz(f"{DATA}/ternary.npz").tocsr().astype(np.int32)
deg = np.asarray((M != 0).sum(axis=1)).ravel() + np.asarray((M != 0).sum(axis=0)).ravel()
sel = np.sort(np.argsort(-deg)[:K])
S = M[sel][:, sel].tocsr()
Sd = S.toarray()
nnz_row = (Sd != 0).sum(axis=1)
print(f"K={K} тритов={int((Sd!=0).sum())} средн.тритов/строку={nnz_row.mean():.0f}")

for theta in [1, 2, 4, 6, 8, 12, 16, 20, 24, 28, 32, 40, 48]:
    x = np.zeros(K, dtype=np.int32)
    flips_all, P, N = [], [], []
    for step in range(STEPS):
        y = Sd @ x
        nx = np.where(y > theta, 1, np.where(y < -theta, -1, 0)).astype(np.int32)
        nx[SENS[step % 4]] = 1                    # авто-стимул по кругу
        flips_all.append(int((nx != x).sum()))
        x = nx
        P.append(int((x == 1).sum())); N.append(int((x == -1).sum()))
    alive = sum(1 for f in flips_all if f > 0)
    print(f"θ={theta:3d}: шагов с изменениями={alive:2d}/16  "
          f"flips[мин-макс]={min(flips_all)}-{max(flips_all):4d}  "
          f"P={min(P):3d}-{max(P):3d}  N={min(N):3d}-{max(N):3d}")
