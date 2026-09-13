#!/usr/bin/env python3
"""Золотая модель «живого мозга» — эталон для fly_brain RTL.

Математика совпадает с RTL:
  x        — троичная активность нейронов (0/±1), стартово 0
  шаг:     y = S·x  (CSR, веса {−1,0,+1})
  порог:   x' = +1 если y >  θ;  −1 если y < −θ;  иначе 0
  отчёт:   строка "S=ss P=ppp N=nnn\r\n" после каждого шага
           (ss=номер шага 2 hex, ppp/nnn = количество +/- нейронов 3 hex)

UART-протокол (115200, 8N1):
  'S' id3hex ('+'|'-')  → x[id] = ±1,  ответ 'k'
  'T' steps2hex         → прогнать steps шагов с отчётом
  'D'                   → дамп x: 4096 байт '0'/'1'/'2'
  'H' th2hex            → установить порог (по умолчанию 3)

Запуск: python brain_sim.py [data_dir] — печатает ожидаемые строки отчёта
для тест-сценария TB (стимулы 0002+,0005+,000A-, затем T=03, θ=3).
"""
import sys

import numpy as np
import scipy.sparse as sp

args = [a for a in sys.argv[1:] if not a.startswith("--")]
out_file = None
if "--out" in sys.argv:
    out_file = sys.argv[sys.argv.index("--out") + 1]
data_dir = args[0] if args else "data"
theta = 1

M = sp.load_npz(f"{data_dir}/ternary.npz").tocsr().astype(np.int32)
# тот же срез, что и в export_slice.py (топ-K по степени, сортированный)
K = 4096
deg = np.asarray((M != 0).sum(axis=1)).ravel() + np.asarray((M != 0).sum(axis=0)).ravel()
sel = np.sort(np.argsort(-deg)[:K])
S = M[sel][:, sel].tocsr()

x = np.zeros(K, dtype=np.int32)  # −1/0/+1


def fmt(step, p, n):
    return f"S={step:02X} P={p:03X} N={n:03X}\r\n"


print("ожидаемые строки отчёта для сценария TB:")
# стимулы: топ-3 нейрона по ИСХОЩЕЙ степени (чтобы точно было чем распространять)
out_deg = np.asarray((S != 0).sum(axis=0)).ravel()
ids = np.argsort(-out_deg)[:3]
print(f"(стимулы: {ids[0]:03X}+, {ids[1]:03X}+, {ids[2]:03X}-; theta={theta})")

# инъекции (по UART 'S')
x[ids[0]] = 1
x[ids[1]] = 1
x[ids[2]] = -1
print(f"стимульные id в hex: {ids[0]:03X} {ids[1]:03X} {ids[2]:03X}")

STEPS = 3
lines = []
for step in range(1, STEPS + 1):
    y = S @ x
    nx = np.where(y > theta, 1, np.where(y < -theta, -1, 0)).astype(np.int32)
    p = int((nx == 1).sum())
    n = int((nx == -1).sum())
    lines.append(fmt(step, p, n))
    x = nx

if out_file:
    with open(out_file, "w", newline="") as f:
        f.write("kkk")                # три ack на стимулы
        f.write("".join(lines))
    print(f"-> эталон записан: {out_file}")
else:
    for l in lines:
        print(f"'{l}'", end="")
    print()
    print(f"итоговый x: ненулевых {int((x != 0).sum())} из {K}")

print()
print(f"итоговый x: ненулевых {int((x != 0).sum())} из {K}")
