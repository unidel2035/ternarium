import re, sys
from apycula import chipdb
dev=chipdb.load_chipdb("/home/unidel/.local/lib/python3.12/site-packages/apycula/GW5AST-138C.msgpack.xz")
pk=dev.pinout['GW5AST-138C']['FCPBGA676A']
used={'P16','P15','G16','R15','V16','U16','V22','J14','R26','L20','M25',
 'H21','A24','H19','J19','G25','H18','J18','K17','J16','K15','F22','G22','G21','G20',
 'F20','G19','F19','F18','M17','M16','K16','F15','G15'}
def parse(loc):
    m=re.match(r'IO([TBLR])(\d+)([AB])',loc or "")
    return (m.group(1),int(m.group(2)),m.group(3)) if m else (None,9999,'')
cands=[]
for name,v in pk.items():
    if name in used: continue
    loc=v[0]; side,num,ab=parse(loc)
    if side is None: continue
    # приоритет: банк R, близость к 103
    pr = (0 if side=='R' else 1, abs(num-103) if side=='R' else num)
    cands.append((pr,name,loc))
cands.sort()
order=[c[1] for c in cands]
batch=int(sys.argv[1]) if len(sys.argv)>1 else 0
B=16
sel=order[batch*B:(batch*B+B)]
# дополним до 16 (повтор последнего безвредно, но лучше реальные)
print("BATCH",batch,"pins:",sel)
# пишем .cst
lines=['IO_LOC "clk" P16;','IO_PORT "clk" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;',
       'IO_LOC "tx"  P15;','IO_PORT "tx" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;']
for i,p in enumerate(sel):
    lines.append(f'IO_LOC "c{i}" {p};')
for i,p in enumerate(sel):
    lines.append(f'IO_PORT "c{i}" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;')
for i,p in enumerate(['J14','L20','M25']):
    lines.append(f'IO_LOC "state_led[{i}]" {p};')
    lines.append(f'IO_PORT "state_led[{i}]" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;')
open("uart_scan.cst","w").write("\n".join(lines)+"\n")
open("batch_names.txt","w").write(",".join(sel)+"\n")
