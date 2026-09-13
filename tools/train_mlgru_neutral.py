#!/usr/bin/env python3
"""train_mlgru_neutral.py — байтовый троичный MLGRU (V=256, L=3, D=24) на НЕЙТРАЛЬНОМ корпусе.

Корпус: вики-статьи о Сетуни, троичной логике, дрозофиле, коннектоме, ПЛИС + доки репо.
Архитектура и чекпойнт-формат 1:1 совместимы с train_mlgru_ru.py / export_ru_rtl.py
(state_dict с теми же именами ключей), но домен — открытые вычисления, не тактика.

Запуск: python train_mlgru_neutral.py [--steps 4000]
Выход:  mlgru_neutral_d24.pt
"""
import json
import math
import random
import sys
import urllib.parse
import urllib.request

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

torch.manual_seed(0); random.seed(0); np.random.seed(0)

D = 24
V, L, S = 256, 3, 48
H = 2 * D

# ── корпус ──────────────────────────────────────────────────────────────────
WIKI_TITLES = [
    "Сетунь (компьютер)",
    "Троичная логика",
    "Троичный компьютер",
    "Дрозофила",
    "Коннектом",
    "ПЛИС",
    "Язык описания аппаратуры",
    "BitNet",
]

def wiki_text(title):
    url = ("https://ru.wikipedia.org/w/api.php?action=query&prop=extracts"
           "&explaintext&format=json&redirects=1&titles="
           + urllib.parse.quote(title))
    req = urllib.request.Request(url, headers={"User-Agent": "ternarium/0.1"})
    with urllib.request.urlopen(req, timeout=30) as r:
        j = json.loads(r.read().decode("utf-8"))
    for p in j["query"]["pages"].values():
        return p.get("extract", "")
    return ""

def build_corpus():
    parts = []
    for t in WIKI_TITLES:
        try:
            txt = wiki_text(t)
            if len(txt) > 400:
                parts.append(txt)
                print(f"  wiki: {t} — {len(txt)} симв.")
        except Exception as e:
            print(f"  wiki: {t} — пропуск ({e})")
    # доки репо как дополнительный материал
    import glob
    for p in glob.glob("*.md") + glob.glob("tang-mega-138k-pro/*.md"):
        try:
            parts.append(open(p, encoding="utf-8", errors="ignore").read())
        except Exception:
            pass
    return "\n\n".join(parts)

CORPUS_TEXT = build_corpus()
if len(CORPUS_TEXT) < 5000:
    # офлайн-фолбэк: нейтральные шаблоны о проекте
    print("  сеть недоступна — встроенный шаблонный корпус")
    MODULES = ["tritalu", "tritcpu", "tritnet", "fly_core", "bitnet_layer", "tritram"]
    FACTS = ["работает", "синтезирован", "верифицирован", "проходит тесты"]
    def tpl():
        return f"модуль {random.choice(MODULES)} {random.choice(FACTS)}.\n"
    CORPUS_TEXT = "".join(tpl() for _ in range(6000))

data = np.frombuffer(CORPUS_TEXT.encode("cp1251", "replace"), dtype=np.uint8).astype(np.int64)
print(f"корпус {len(data)} байт")

# ── модель (1:1 с export_ru_rtl.py) ────────────────────────────────────────
def wq(w):
    s = 1.0 / w.abs().mean().clamp(min=1e-5)
    return (w * s).round().clamp(-1, 1) / s

AQ_S = 32.0
def aq(x):
    return (x * AQ_S).round().clamp(-127, 127) / AQ_S

class BitLin(nn.Module):
    def __init__(s, i, o, norm=True):
        super().__init__()
        s.l = nn.Linear(i, o, bias=False)
        s.n = nn.RMSNorm(i, elementwise_affine=False) if norm else None
    def forward(s, x):
        if s.n is not None:
            x = s.n(x)
        x = x + (aq(x) - x).detach()
        w = s.l.weight + (wq(s.l.weight) - s.l.weight).detach()
        return F.linear(x, w)

class MLGRU(nn.Module):
    def __init__(s):
        super().__init__()
        s.f = BitLin(D, D); s.c = BitLin(D, D)
        s.g = BitLin(D, D); s.o = BitLin(D, D, norm=False)
    def forward(s, x):
        B, T, _ = x.shape
        f = torch.sigmoid(s.f(x)); c = F.silu(s.c(x)); g = torch.sigmoid(s.g(x))
        h = torch.zeros(B, D, device=x.device); outs = []
        for t in range(T):
            h = f[:, t] * h + (1 - f[:, t]) * c[:, t]
            outs.append(g[:, t] * h)
        return s.o(torch.stack(outs, 1))

class GLU(nn.Module):
    def __init__(s):
        super().__init__()
        s.g = BitLin(D, H); s.u = BitLin(D, H); s.d = BitLin(H, D, norm=False)
    def forward(s, x):
        return s.d(F.silu(s.g(x)) * s.u(x))

class Block(nn.Module):
    def __init__(s):
        super().__init__()
        s.mix = MLGRU(); s.ffn = GLU()
    def forward(s, x):
        x = x + s.mix(x)
        return x + s.ffn(x)

class Net(nn.Module):
    def __init__(s):
        super().__init__()
        s.emb = nn.Embedding(V, D)
        s.ly = nn.ModuleList([Block() for _ in range(L)])
        s.fn = nn.RMSNorm(D, elementwise_affine=False)
        s.out = BitLin(D, V, norm=False)
    def forward(s, seq):
        x = s.emb(seq)
        for l in s.ly:
            x = l(x)
        return s.out(s.fn(x))

m = Net()
LR = 1e-3
opt = torch.optim.Adam(m.parameters(), lr=LR)
STEPS = int(sys.argv[sys.argv.index("--steps") + 1]) if "--steps" in sys.argv else 4000
print(f"нейтральный байтовый MLGRU: V={V} D={D} L={L} S={S} H={H} | параметров {sum(p.numel() for p in m.parameters())} | шагов {STEPS}")

def batch(B=64):
    ix = np.random.randint(0, len(data) - S - 1, B)
    xs = np.stack([data[i:i + S] for i in ix])
    ys = np.stack([data[i + 1:i + S + 1] for i in ix])
    return torch.tensor(xs), torch.tensor(ys)

sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=STEPS, eta_min=LR * 0.05)
best = 1e9
for step in range(STEPS):
    xi, yi = batch()
    lo = m(xi)
    loss = F.cross_entropy(lo.reshape(-1, V), yi.reshape(-1))
    opt.zero_grad(); loss.backward()
    torch.nn.utils.clip_grad_norm_(m.parameters(), 1.0)
    opt.step(); sched.step()
    if loss.item() < best and step > 200:
        best = loss.item()
        torch.save(m.state_dict(), "mlgru_neutral_d24.pt")
    if step % 500 == 0:
        print(f"  step {step} loss {loss.item():.3f} (bits/byte {loss.item()/math.log(2):.2f}) best {best:.3f}", flush=True)

print(f"[чекпойнт] mlgru_neutral_d24.pt best {best:.3f} ({best/math.log(2):.2f} bits/byte)")
m.load_state_dict(torch.load("mlgru_neutral_d24.pt")); m.eval()

def gen(prompt, n=160, temp=0.5):
    ids = list(np.frombuffer(prompt.encode("cp1251"), dtype=np.uint8))
    for _ in range(n):
        ctx = torch.tensor([ids[-S:]], dtype=torch.long)
        lo = m(ctx)[0, -1] / temp
        p = F.softmax(lo, -1)
        nt = int(torch.multinomial(p, 1))
        ids.append(nt)
        if nt == 10 and len(ids) > len(prompt) + 30:
            break
    return bytes(ids).decode("cp1251", "replace")

print("\n── генерация (нейтральная) ──")
for pr in ["Сетунь — ", "троичный ", "коннектом "]:
    print(f"  «{pr}» → {gen(pr)!r}")
