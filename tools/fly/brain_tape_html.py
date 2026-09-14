#!/usr/bin/env python3
"""brain_tape_html.py — анимированная HTML-визуализация динамики мозга мухи.
Точная золотая модель (та же математика, что в fly_brain.v): y=S·x, порог θ.
Серии по 16 шагов с паузами и авто-стимуляцией сенсоров — как на плате.
Выход: fly_tape.html — открыть в браузере.
"""
import json
import sys

import numpy as np
import scipy.sparse as sp

data_dir = sys.argv[1] if len(sys.argv) > 1 else "data"
K = 256
THETA = 1
BATCH = 16
BATCHES = 4
PAUSE_STEPS = 4          # «пауза 2 с» между сериями (для анимации)

M = sp.load_npz(f"{data_dir}/ternary.npz").tocsr().astype(np.int32)
deg = np.asarray((M != 0).sum(axis=1)).ravel() + np.asarray((M != 0).sum(axis=0)).ravel()
sel = np.sort(np.argsort(-deg)[:K])
S = M[sel][:, sel].tocsr()

out_deg = np.asarray((S != 0).sum(axis=0)).ravel()
stim_ids = np.argsort(-out_deg)[:4]
STIM = [int(stim_ids[k % 4]) for k in range(BATCH * BATCHES)]

x = np.zeros(K, dtype=np.int32)
frames = []
for b in range(BATCHES):
    for s in range(BATCH):
        # авто-стимул в начале каждого шага (как в RTL M_YWR)
        sid = STIM[(b * BATCH + s) % len(STIM)]
        x[sid] = 1
        y = S @ x
        nx = np.where(y > THETA, 1, np.where(y < -THETA, -1, 0)).astype(np.int32)
        p = int((nx == 1).sum()); n = int((nx == -1).sum())
        frames.append({"batch": b + 1, "step": s + 1, "p": p, "n": n,
                       "x": [int(v) for v in nx], "sid": sid})
        x = nx
    for s in range(PAUSE_STEPS):                       # пауза 2 с
        frames.append({"batch": b + 1, "step": f"pause{b+1}", "p": 0, "n": 0,
                       "x": [0] * K, "sid": 0})

colors = {"1": "#19c94a", "-1": "#e03a3a", "0": "#12305e"}
cells_html = "".join(
    f'<div class="c" id="c{i}"></div>' for i in range(K))

frames_js = json.dumps([{ "x": f["x"], "p": f["p"], "n": f["n"],
                          "label": f"серия {f['batch']} · шаг {f['step']} · P={f['p']:02X} N={f['n']:02X}",
                          "sid": f["sid"]} for f in frames])

html = f"""<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8">
<title>Мозг мухи — 256 нейронов, живая динамика</title>
<style>
body {{ background:#0a0e1a; color:#9fb8d8; font-family:monospace; text-align:center; margin:20px; }}
h1 {{ color:#ffd769; font-size:22px; }}
.grid {{ display:grid; grid-template-columns:repeat(16, 26px); gap:3px; justify-content:center; margin:16px auto; }}
.c {{ width:26px; height:26px; border-radius:4px; background:{colors["0"]}; transition:background .12s; }}
.leg span {{ display:inline-block; width:14px; height:14px; border-radius:3px; margin:0 6px -2px 18px; }}
#lbl {{ color:#ffd769; font-size:16px; margin-top:10px; min-height:20px; }}
.bars {{ width:600px; margin:6px auto; }}
.bar {{ height:16px; border-radius:4px; }}
#pb {{ background:#19c94a; }} #nb {{ background:#e03a3a; }}
button {{ background:#1c2b4a; color:#9fb8d8; border:1px solid #2c4a7a; border-radius:6px;
         padding:8px 18px; font-family:monospace; cursor:pointer; }}
</style></head>
<body>
<h1>🪰 МОЗГ МУХИ — живой срез коннектома (FAFB v783)</h1>
<div>256 нейронов · 31 738 троичных связей · порог θ=1 · {colors["1"] if False else ""}</div>
<div class="leg">
  <span style="background:{colors['1']}"></span>возбуждение (+1)
  <span style="background:{colors['-1']}"></span>торможение (−1)
  <span style="background:{colors['0']}"></span>покой
</div>
<div class="grid">{cells_html}</div>
<div id="lbl"></div>
<div class="bars">
  <div>P (возбуждение): <span id="pv">0</span></div>
  <div class="bar" style="background:#0c2018"><div id="pb" class="bar" style="width:0%"></div></div>
  <div>N (торможение): <span id="nv">0</span></div>
  <div class="bar" style="background:#200c0c"><div id="nb" class="bar" style="width:0%;background:#e03a3a"></div></div>
</div>
<button onclick="location.reload()">⟳ повторить</button>
<script>
const FRAMES = {frames_js};
const COLORS = {{"1":"#19c94a","2":"#e03a3a","0":"#12305e"}};
let fi = 0;
function show() {{
  const F = FRAMES[fi];
  document.getElementById("lbl").textContent = F.label;
  document.getElementById("pv").textContent = F.p;
  document.getElementById("nv").textContent = F.n;
  document.getElementById("pb").style.width = (F.p / 128 * 100) + "%";
  document.getElementById("nb").style.width = (F.n / 128 * 100) + "%";
  for (let i = 0; i < {K}; i++) {{
    document.getElementById("c" + i).style.background = COLORS[String(F.x[i])] || "{colors['0']}";
  }}
  fi = (fi + 1) % FRAMES.length;
  setTimeout(show, 450);
}}
show();
</script>
</body></html>
"""
open("fly_tape.html", "w", encoding="utf-8").write(html)
print(f"-> fly_tape.html: {len(frames)} кадров динамики (K={K}, θ={THETA})")
