#!/usr/bin/env python3
"""train_readout.py — обучение тернарного readout над reservoir-динамикой среза мухи.

Задача: 4 класса = 4 «сенсорных» входа. Паттерн класса c = пульсы на сенсоре c
(по одному за шаг) + шум. Резервуар: y=S·x, порог θ (динамика fly_brain).
Readout: тернарная W[4×K], класс = argmax_c Σ_i W[c][i]·x[i].

Квантование и fixed-point проверка повторяют арифметику RTL (term(): ±1×±1).
Выход: class_ro.hex (4 банка × K веса, 2б/вес), class_gold.json, точность.

Запуск: python train_readout.py <data_dir> <out_dir>
"""
import json
import sys

import numpy as np
import scipy.sparse as sp

data_dir = sys.argv[1] if len(sys.argv) > 1 else "data"
out_dir = sys.argv[2] if len(sys.argv) > 2 else "."
K = 256
THETA = 1
NCLS = 4
STEPS = 8                       # шагов на пример
NTRAIN = 400                    # примеров на класс
SENS = [0x092, 0x096, 0x05E, 0x032]   # «сенсорные» нейроны (внутри среза)

M = sp.load_npz(f"{data_dir}/ternary.npz").tocsr().astype(np.int32)
deg = np.asarray((M != 0).sum(axis=1)).ravel() + np.asarray((M != 0).sum(axis=0)).ravel()
sel = np.sort(np.argsort(-deg)[:K])
S = M[sel][:, sel].tocsr()

rng = np.random.default_rng(7)

def run_step(x, stim_id):
    y = S @ x
    nx = np.where(y > THETA, 1, np.where(y < -THETA, -1, 0)).astype(np.int32)
    nx[stim_id] = 1                                  # сенсор подкачивается каждый шаг
    return nx

def episode(cls, noise=0.15):
    """Эпизод: STEPS шагов, стимул на сенсоре класса cls; вернуть состояния после каждого шага."""
    x = np.zeros(K, dtype=np.int32)
    states = []
    for s in range(STEPS):
        x = run_step(x, SENS[cls])
        if noise > 0:                                 # случайные ложные сенсоры
            for j in range(NCLS):
                if j != cls and rng.random() < noise:
                    x[SENS[j]] = 1 if rng.random() < 0.5 else -1
        states.append(x.copy())
    return states

print("генерация данных + состояния резервуара...")
Xtr, ytr = [], []
for cls in range(NCLS):
    for e in range(NTRAIN):
        for st in episode(cls, noise=0.25):
            Xtr.append(st); ytr.append(cls)
Xtr = np.array(Xtr, dtype=np.int32); ytr = np.array(ytr)
print(f"  примеров: {len(ytr)}")

# ── обучение readout: ridge-регрессия one-hot ───────────────────────────
Y = np.zeros((len(ytr), NCLS)); Y[np.arange(len(ytr)), ytr] = 1
lam = 1.0
W = np.linalg.solve(Xtr.T @ Xtr + lam * np.eye(K), Xtr.T @ Y).T   # [NCLS × K]
print("readout обучен")

# ── тернаризация readout (как BitNet wq) ───────────────────────────────
def tern_rows(Wm):
    Wrows = []
    for r in range(Wm.shape[0]):
        s = 1.0 / max(1e-5, np.abs(Wm[r]).mean())
        Wrows.append(np.clip(np.round(Wm[r] * s), -1, 1).astype(np.int32))
    return np.array(Wrows, dtype=np.int32)
Wt = tern_rows(W)

# ── fixed-point проверка (тернарный readout, x тернарный) ──────────────
def fp_classify(states):
    scores = (Wt @ states.T)                        # [4 × len]
    return np.argmax(scores, axis=0)

acc_tr = 0; tot_tr = 0
for cls in range(NCLS):
    for e in range(50):
        st = np.array(episode(cls, noise=0.25))
        pr = fp_classify(st)
        acc_tr += int((pr == cls).sum()); tot_tr += len(pr)
print(f"fixed-point точность (train-noise): {acc_tr}/{tot_tr} = {acc_tr/tot_tr:.1%}")

# чистые эпизоды без шума — на них смотрит демо
ok = 0; tot = 0
for cls in range(NCLS):
    st = np.array(episode(cls, noise=0.0))
    pr = fp_classify(st)
    ok += int((pr == cls).sum()); tot += len(pr)
print(f"fixed-point точность (чистые): {ok}/{tot} = {ok/tot:.1%}")

# ── экспорт: 4 банка × K, 2 бита/вес ────────────────────────────────────
enc = {-1: 2, 0: 0, 1: 1}
lines = []
for c in range(NCLS):
    words = []
    for w0 in range(0, K, 16):
        word = 0
        for j in range(16):
            idx = w0 + j
            v = int(Wt[c][idx]) if idx < K else 0
            word |= enc[v] << (2 * j)
        words.append(word)
    lines.append((c, words))
with open(f"{out_dir}/class_ro.hex", "w") as f:
    f.write("// 4 банка readout: банк c = класс c; 16 весов по 2 бита в слове\n")
    for c, ws in lines:
        f.write(f"// class {c}\n")
        f.write("\n".join(f"{w:08x}" for w in ws) + "\n")

gold = {
    "K": K, "theta": THETA, "nclasses": NCLS, "sens": SENS,
    "stim_sensors": SENS,
    "note": "класс = активный сенсор; readout тернарный 4x256",
}
with open(f"{out_dir}/class_gold.json", "w") as f:
    json.dump(gold, f, indent=2)
print(f"-> {out_dir}/class_ro.hex, class_gold.json")
