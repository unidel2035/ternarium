#!/usr/bin/env python3
"""patch_sim_copy.py — минимальный патч КОПИИ model_mlgru.v в каталоге симуляции
(оригинал в bitnet_layer/ не трогается). Четыре фикса под конфигурацию нейтральной
модели D=24, L=3, LN=128 (коммит RTL писался под L=2 и D=8/16/32):

 1) lutrom[0:8*LN-1] -> lutrom[0:12*LN-1]
    8*LN=1024 слов рассчитано на L=2; при L=3 адреса BL_Lf2..BL_L2g2+127 (1024..1535)
    вне ROM -> чтение x. iverilog прямо ругается: "Too many words ... range [0:1023]".
 2) ms=ss>>>DSHIFT -> ms=ss/D  (в RMS/FRMS/LOG)
    DSHIFT для D=24 даёт fallback 3, т.е. ss/8, а эталон экспортёра: ms = ss // len(x) = ss/24.
 3) селекторы базовых адресов: (l==0)?X0:X1 -> (l==0)?X0:(l==1)?X1:X2
    14 функций (bWf,bWc,bWg,bWo,bW2g,bW2u,bW2d,blf,blc,blg,bl2g,mwo,mwu,mwd) написаны
    под L=2: для слоя 2 возвращают ВЕСА СЛОЯ 1.
 4) NEXTL: при переходе к следующему токену l не сбрасывается в 0
    ("else begin t<=t+1; stt<=LD; end") -> после первого токена выполняется ТОЛЬКО слой 2,
    слои 0 и 1 пропускаются для токенов 1..S-1.

Без правок RTL выдаёт 64 пробела (0x20); с правками 1-2 — мусор (слои 2/1 перепутаны,
слои 0-1 пропущены). Только все четыре дают корректную работу конвейера.
"""
import re

SRC, DST = "model_mlgru.v", "model_mlgru_sim.v"
src = open(SRC, encoding="utf-8").read()
rep = []

# 1
a = "reg signed [15:0] lutrom[0:8*LN-1];"
b = "reg signed [15:0] lutrom[0:12*LN-1];"
assert src.count(a) == 1; src = src.replace(a, b); rep.append("1: lutrom 8*LN -> 12*LN")

# 2
a = "ms=ss>>>DSHIFT;"
assert src.count(a) == 3
src = src.replace(a, "ms=ss/D;"); rep.append("2: RMS ms=ss>>>DSHIFT -> ms=ss/D (x3)")

# 3 — 14 селекторов: имя слоя 2 = имя слоя 1 с последним символом '2'
def sel(m):
    a0, a1 = m.group(1), m.group(2)
    assert a1.endswith("1"), a1
    return f"(l==0)?{a0}:(l==1)?{a1}:{a1[:-1]}2"
pat = re.compile(r"\(l==0\)\?(\w+)\s*:\s*(\w+)")
src, n = pat.subn(sel, src)
assert n == 14, n
rep.append(f"3: селекторы баз/масштабов под L=3 ({n} функций)")

# 4
a = "else begin t<=t+1; stt<=LD; end end"
assert src.count(a) == 1
src = src.replace(a, "else begin t<=t+1; l<=0; stt<=LD; end end")
rep.append("4: NEXTL сбрасывает l в 0 для следующего токена")

open(DST, "w", encoding="utf-8", newline="\n").write(src)
for r in rep:
    print("патч:", r)
print(f"-> {DST}")
