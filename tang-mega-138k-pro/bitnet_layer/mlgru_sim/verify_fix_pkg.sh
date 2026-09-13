#!/usr/bin/env bash
# verify_fix_pkg.sh — проверка ПОЛНОГО пакета исправлений в отдельном каталоге mwf15/:
#   RTL: 4 бага (patch_sim_copy.py) + sdiv32 -> округление вниз (floor) вместо trunc к нулю
#   Экспорт: MWF 12 -> 15 (множители MW* точнее)
# Ожидание: PASS 55/55 против golden GTOK_*.
set -e
SIM=/mnt/c/Users/unide/ternarium/tang-mega-138k-pro/bitnet_layer/mlgru_sim
W=$SIM/mwf15
PT=/mnt/c/Users/unide/ternarium/mlgru_neutral_d24.pt
PY=~/fly-connectome/.venv/bin/python

rm -rf "$W"; mkdir -p "$W"; cd "$W"
cp "$SIM/fxops.v" "$SIM/tb_neutral.v" "$SIM/gen_seedrom.py" "$SIM/gen_gold.py" .
cp "$SIM/mlgru_wt.hex" "$SIM/mlgru_emb.hex" "$SIM/mlgru_lut.hex" .

# RTL: 4 фикса в model_mlgru.v
python3 - "$SIM/model_mlgru.v" "$W/model_mlgru.v" <<'EOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = src.replace("reg signed [15:0] lutrom[0:8*LN-1];", "reg signed [15:0] lutrom[0:12*LN-1];")
assert src.count("ms=ss>>>DSHIFT;") == 3
src = src.replace("ms=ss>>>DSHIFT;", "ms=ss/D;")
src, n = re.subn(r"\(l==0\)\?(\w+)\s*:\s*(\w+)", lambda m: f"(l==0)?{m.group(1)}:(l==1)?{m.group(2)}:{m.group(2)[:-1]}2", src)
assert n == 14, n
src = src.replace("else begin t<=t+1; stt<=LD; end end", "else begin t<=t+1; l<=0; stt<=LD; end end")
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(src)
print("model_mlgru.v: 4 фикса ->", sys.argv[2])
EOF

# fxops.v: sdiv32 — отрицательный неполный результат округляем ВНИЗ (floor), а не к нулю
python3 - "$SIM/fxops.v" "$W/fxops.v" <<'EOF'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
old = "if (cnt==0) begin busy<=0; done<=1; q <= sgn ? (~nquo+1) : nquo; end else cnt<=cnt-1;"
new = "if (cnt==0) begin busy<=0; done<=1; q <= (sgn && (|nrem)) ? ~nquo : (sgn ? (~nquo+1) : nquo); end else cnt<=cnt-1;"
assert src.count(old) == 1
open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(src.replace(old, new))
print("fxops.v: sdiv32 floor ->", sys.argv[2])
EOF

"$PY" "$SIM/gen_vectors_mwf.py" "$PT" "$SIM/mlgru_vectors.vh" "$W"
python3 gen_seedrom.py
python3 gen_gold.py

iverilog -g2005 -o sim.vvp model_mlgru.v fxops.v tb_neutral.v
timeout 900 vvp sim.vvp 2>&1 | grep -v "Too many\|Not enough" | tail -6
