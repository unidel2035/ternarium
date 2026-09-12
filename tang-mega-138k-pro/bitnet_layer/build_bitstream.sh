#!/usr/bin/env bash
# build_bitstream.sh — собирает bitstream доменной модели через oss-поток, ОБХОДЯ баг yosys
# (gowin-примитив ALU/DFF помечен lib_whitebox+always → write_json падает «contains processes»,
#  а пасс autoname роняет yosys сегфолтом). Обход: synth до map_cells (без autoname) → write_rtlil →
#  Python-хирургия (вырезать ТОЛЬКО module dom_board) → дочитать чистые blackbox-примитивы → JSON.
# ВСЁ под ulimit (yosys/nextpnr иначе валят ОС). Конфиг: D=8,S=4 (что oss осиливает). fmax 54.7 МГц.
# Предусловие: model_infer_dom.v/model_vectors.vh сгенерены (python3 train_domain.py && python3 gen_infer.py)
set -e
cd "$(dirname "$0")"
export PATH="$HOME/oss-cad-suite/bin:$HOME/oss-cad-suite/lib:$HOME/oss-cad-suite/py3bin:$PATH"
mkdir -p build
MEM=8500000   # ulimit -v KB; защита ОС

echo "[1/5] synth (abc9) до map_cells, без autoname → RTLIL"
cat > build/_s1.ys <<'EOF'
read_verilog dom_board.v model_infer_dom.v fxops.v uart_tx.v
synth_gowin -top dom_board -nodsp -run begin:map_cells
techmap -map +/gowin/cells_map.v
opt_lut_ins -tech gowin
hilomap -singleton -hicell VCC V -locell GND G
clean
write_rtlil build/dom.il
EOF
( ulimit -v $MEM; yosys -s build/_s1.ys > build/_s1.log 2>&1 )

echo "[2/5] хирургия: вырезать ТОЛЬКО module dom_board (без lib-модулей с процессами)"
python3 - <<'PY'
l=open("build/dom.il").read().split("\n")
mi=next(i for i,x in enumerate(l) if x.startswith("module \\dom_board"))
s=mi; j=mi-1
while j>=0 and (l[j].startswith("attribute ") or l[j].strip()==""): s=j; j-=1
e=next(i for i in range(mi+1,len(l)) if l[i]=="end")
h=[x for x in l[:s] if x.startswith("autoidx")]
open("build/dom_only.il","w").write("\n".join(h+l[s:e+1]+[""]))
PY

echo "[3/5] генерю чистые blackbox-заглушки примитивов (порты/направления из cells_sim)"
python3 - <<'PY'
import re,os
G=os.path.expanduser("~/oss-cad-suite/share/yosys/gowin")
src="".join(open(os.path.join(G,f)).read()+"\n" for f in
    ("cells_sim.v","cells_xtra_gw5a.v","cells_xtra_gw1n.v") if os.path.exists(os.path.join(G,f)))
need={'LUT1','LUT2','LUT3','LUT4','MUX2_LUT5','MUX2_LUT6','MUX2_LUT7','MUX2_LUT8','ALU',
      'DFFE','DFFRE','DFF','DFFSE','DFFR','DFFS','DFFP','DFFC','DFFN','DFFNE',
      'VCC','GND','IBUF','OBUF','TBUF','IOBUF'}
out=[]; done=set()
for m in re.finditer(r'module\s+(\w+)\s*\((.*?)\);(.*?)endmodule', src, re.S):
    n=m.group(1)
    if n not in need or n in done: continue
    done.add(n); ps=m.group(2); body=m.group(3)
    params=re.findall(r'parameter\s+(\w+)\s*=\s*([^;]+);', body)
    out.append("(* blackbox *)")
    if re.search(r'\b(input|output|inout)\b', ps):
        out.append(f"module {n} ({ps.strip()});")
    else:
        pl=[p.strip() for p in ps.split(',')]; d={}
        for dd in re.finditer(r'\b(input|output|inout)\b\s*(?:\[[^\]]*\])?\s*([\w\s,]+?);', body):
            for pn in dd.group(2).split(','):
                pn=pn.strip()
                if pn in pl: d[pn]=dd.group(1)
        out.append(f"module {n} ({', '.join(pl)});")
        for pn in pl: out.append(f"  {d.get(pn,'input')} {pn};")
    for pn,pv in params: out.append(f"  parameter {pn} = {pv.strip().splitlines()[0]};")
    out.append("endmodule\n")
open("build/prims_bb.v","w").write("\n".join(out))
PY

echo "[4/5] JSON: dom_board + blackbox-примитивы, убрать \$scopeinfo"
cat > build/_s2.ys <<'EOF'
read_rtlil build/dom_only.il
read_verilog build/prims_bb.v
delete dom_board/t:$scopeinfo
write_json build/dom_board.json
EOF
( ulimit -v $MEM; yosys -s build/_s2.ys > build/_s2.log 2>&1 )

echo "[5/5] nextpnr (router2) → gowin_pack → bitstream"
( ulimit -v 10000000; nextpnr-himbaechel --router router2 \
   --json build/dom_board.json --write build/dom_board_pnr.json \
   --device GW5AST-LV138FPG676AC1/I0 --vopt family=GW5AST-138C --vopt cst=dom_board.cst \
   > build/pnr.log 2>&1 )
( ulimit -v 9000000; gowin_pack -d GW5AST-138C -o build/dom_board.fs build/dom_board_pnr.json > build/pack.log 2>&1 )
echo "ГОТОВО: build/dom_board.fs"
ls -lh build/dom_board.fs
grep -i "Max frequency" build/pnr.log | tail -1
echo "Прошить (SRAM, обратимо): openFPGALoader --board tangmega138k build/dom_board.fs"
