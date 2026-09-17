#!/usr/bin/env python3
"""flight_reservoir_train.py — обучение троичного readout фаз полёта на резервуаре-срезе мухи.

Пайплайн:
  CSV телеметрии (sitl_capture.py) → окна 0.5 c → 12 признаков IMU/газа
  → инжект в срез K=256 (hash-нейроны, знак = знак отклонения)
  → 4 шага резервуара (математика 1:1 с RTL: y=S·x, порог ±θ)
  → снимок состояния x (256) → ridge → тернаризация → class_ro.hex

Классы (4, ширина readout в RTL): 0=GROUND 1=CLIMB 2=CRUISE 3=LOITER.
Метки в CSV считаются в capture по полной физике сима (высота/скорость),
чип видит ТОЛЬКО IMU+газ — задача инференциальная.

Запуск: python flight_reservoir_train.py <telemetry.csv> [out_dir]
"""
import json
import sys

import numpy as np
import scipy.sparse as sp

DATA = "/mnt/c/Users/unide/fly-connectome/data"
K = 256
THETA = 1
NSTEPS = 4                      # шагов резервуара на окно
NCLS = 4
CLASSES = ["GROUND", "CLIMB", "CRUISE", "LOITER"]
FEATS = ["ax", "ay", "az", "gx", "gy", "gz", "thr", "as", "vz", "alt", "roll", "pitch"]
SENS = [0x092, 0x096, 0x05E, 0x032]

def main(csv_path, out_dir="."):
    raw = np.genfromtxt(csv_path, delimiter=",", names=True)
    F = np.stack([np.nan_to_num(raw[f], nan=0.0) for f in FEATS], axis=1)
    y_lab = raw["label"].astype(int)

    # ── срез мухи — тот же, что в RTL (топ-K по степени) ──
    M = sp.load_npz(f"{DATA}/ternary.npz").tocsr().astype(np.int32)
    deg = np.asarray((M != 0).sum(axis=1)).ravel() + np.asarray((M != 0).sum(axis=0)).ravel()
    sel = np.sort(np.argsort(-deg)[:K])
    S = M[sel][:, sel].toarray()

    # ── нормализация признаков (z-score по данным) ──
    mu, sd = F.mean(0), F.std(0) + 1e-9
    Z = np.clip((F - mu) / sd, -3, 3)

    # ── инжект: признак d → нейрон hash(d), знак трита = знак z ──
    rng = np.random.default_rng(7)
    inj = rng.permutation(K)[: len(FEATS)]           # 12 фиксированных нейронов

    def window_to_state(w):                          # w: [T × 12]
        # накопление знаковых тычков за окно (порог резервуара вытирает
        # одиночные тычки — срез не распространяет слабый сигнал)
        x = np.zeros(K, dtype=np.int32)
        for t in range(w.shape[0]):
            for d in range(len(FEATS)):
                if abs(w[t, d]) >= 0.5:
                    x[inj[d]] = int(np.clip(x[inj[d]] + (1 if w[t, d] > 0 else -1), -2, 2))
        x = np.sign(x).astype(np.int32)
        # один шаг смешивания через срез мухи + порог (математика RTL)
        yy = S @ x
        return np.where(yy > THETA, 1, np.where(yy < -THETA, -1, 0)).astype(np.int32)

    print("развёртка резервуара по окнам...")
    W, L = [], []
    T = wlen = 10                                    # окно 0.5 c @ 20 Гц
    for i in range(0, len(Z) - T, T // 2):           # шаг 0.25 c
        lab = np.bincount(y_lab[i:i + T].astype(int), minlength=NCLS).argmax()
        if (y_lab[i:i + T] == lab).mean() < 0.8:     # окно со смешанными фазами — мимо
            continue
        W.append(window_to_state(Z[i:i + T]))
        L.append(lab)
    X = np.array(W, dtype=np.int32)
    L = np.array(L)
    print(f"окон: {len(L)}, по классам: {np.bincount(L, minlength=NCLS)}")
    print(f"уникальных состояний: {len(np.unique(X, axis=0))}")

    # ── train/test 70/30 (стратифицированно по времени: чётные окна train) ──
    idx = np.arange(len(L))
    tr, te = idx[idx % 5 < 3], idx[idx % 5 >= 3]     # 60/40 через каждые 5 окон
    Y = np.zeros((len(L), NCLS)); Y[np.arange(len(L)), L] = 1
    lam = 1.0
    Wm = np.linalg.solve(X[tr].T @ X[tr] + lam * np.eye(K), X[tr].T @ Y[tr]).T
    Wt = np.zeros_like(Wm, dtype=np.int32)
    for r in range(NCLS):
        s = 1.0 / max(1e-5, np.abs(Wm[r]).mean())
        Wt[r] = np.clip(np.round(Wm[r] * s), -1, 1)

    def acc(set_idx, noise):
        ok = tot = 0
        for i in set_idx:
            st = X[i].copy()
            if noise:
                flip = rng.choice(K, K // 10, replace=False)
                st[flip] = rng.choice([-1, 0, 1], len(flip))
            ok += int((Wt @ st).argmax() == L[i]); tot += 1
        return ok / tot

    print(f"train: {acc(tr, False):.1%}   test (интерполяция): {acc(te, False):.1%}")
    print(f"test с шумом 10% нейронов: {acc(te, True):.1%}")

    # ── экспорт class_ro.hex (формат train_readout/RTL: 16 весов × 2 бита) ──
    enc = {-1: 2, 0: 0, 1: 1}
    with open(f"{out_dir}/class_ro.hex", "w") as f:
        f.write("// readout фаз полёта: банк c = класс c; 16 весов по 2 бита в слове\n")
        for c in range(NCLS):
            f.write(f"// class {c} = {CLASSES[c]}\n")
            for w0 in range(0, K, 16):
                word = 0
                for j in range(16):
                    idx = w0 + j
                    word |= enc[int(Wt[c][idx])] << (2 * j)
                f.write(f"{word:08x}\n")
    np.savez(f"{out_dir}/flight_gold.npz", mu=mu, sd=sd, inj=inj, Wt=Wt)
    json.dump({"K": K, "theta": THETA, "nsteps": NSTEPS, "feats": FEATS,
               "classes": CLASSES, "inj": inj.tolist()},
              open(f"{out_dir}/flight_gold.json", "w"), indent=1)
    print(f"-> {out_dir}/class_ro.hex, flight_gold.npz/.json")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "telemetry.csv",
         sys.argv[2] if len(sys.argv) > 2 else ".")
