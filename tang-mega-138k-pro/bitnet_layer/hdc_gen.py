#!/usr/bin/env python3
"""hdc_gen.py — эталон троичной HDC (HDC/VSA) + init для FPGA-движка hdc.v.
Генерит M троичных гипервекторов D-мер {−1,0,+1}, считает bundle/bind/similarity и
ассоциативный поиск (cleanup). Пишет vectors_hdc.vh (init памяти + ожидаемые значения).
Кодировка трита для RTL: -1=2'b00, 0=2'b01, +1=2'b10 (как в tritdot.v)."""
import numpy as np
np.random.seed(7)                      # детерминизм (без Date/random-зависимостей)
D, M = 384, 8                          # размерность гипервектора, число слотов памяти
KEEP = 0.67                            # доля ненулей (как keep=0.67 в ternary_meaning.py)

def rand_hv():
    v = np.zeros(D, dtype=np.int8)
    nz = np.random.choice(D, int(D*KEEP), replace=False)
    v[nz] = np.random.choice([-1, 1], len(nz))
    return v

items = np.stack([rand_hv() for _ in range(M)])        # item memory
def tdot(a,b): return int(np.dot(a.astype(np.int32), b.astype(np.int32)))
def bundle(idxs): return np.sign(items[idxs].sum(axis=0)).astype(np.int8)
def bind(a,b): return (a*b).astype(np.int8)

# ① bundle {0,1,2} → один вектор обстановки; similarity с членами vs не-членом
S = bundle([0,1,2])
sim_S = [tdot(S, items[m]) for m in range(M)]          # высокие к 0,1,2; низкие к остальным
# ② bind(0,1) — ассоциация: similarity с частями ≈ 0 (квази-ортогонально)
B01 = bind(items[0], items[1]); sim_bind = [tdot(B01, items[0]), tdot(B01, items[1])]
# ③ cleanup: зашумлённый запрос из item[3] (перевернём 25% ненулей) → argmax должен дать 3
q = items[3].copy(); nz = np.where(q!=0)[0]; flip = np.random.choice(nz, len(nz)//4, replace=False)
q[flip] = -q[flip]
sim_q = [tdot(q, items[m]) for m in range(M)]; argmax_q = int(np.argmax(sim_q))

enc = {-1:0, 0:1, 1:2}                                 # трит → 2-битный код
def packhv(v):                                          # D тритов → 2*D-битное слово, dim0 в младших
    s = 0
    for i in range(D): s |= enc[int(v[i])] << (2*i)
    return s

with open("vectors_hdc.vh","w") as f:
    f.write(f"// auto: hdc_gen.py  D={D} M={M} KEEP={KEEP}\n")
    f.write(f"localparam D={D}, M={M};\n")
    for m in range(M):
        f.write(f'localparam [2*D-1:0] ITEM{m} = {2*D}\'h{packhv(items[m]):0{(2*D+3)//4}x};\n')
    f.write(f'localparam [2*D-1:0] QNOISY = {2*D}\'h{packhv(q):0{(2*D+3)//4}x};\n')
    # ожидаемые
    f.write(f"// expected\n")
    f.write(f"localparam EXP_ARGMAX = {argmax_q};\n")
    for m in range(M): f.write(f"localparam signed [31:0] EXP_SIM_S{m} = {sim_S[m]};\n")
    f.write(f"localparam signed [31:0] EXP_BIND0 = {sim_bind[0]};\n")
    f.write(f"localparam signed [31:0] EXP_BIND1 = {sim_bind[1]};\n")

print(f"D={D} M={M}")
print("bundle {0,1,2} similarities:", sim_S, "(члены 0,1,2 высокие)")
print("bind(0,1) sim to parts:", sim_bind, "(≈0 — квази-ортогонально)")
print(f"cleanup: noisy query из item3 → argmax={argmax_q} (ожидаем 3); sims={sim_q}")

# ── ROM распаковки base-3 (5 тритов/байт, как pack() в ternary_comms.py) + тестовый радио-пакет ──
def pack_base3(t):                       # реплика ternary_comms.pack
    d=(np.asarray(t,np.int8)+1).astype(np.uint8); pad=(-len(d))%5
    if pad: d=np.concatenate([d,np.zeros(pad,np.uint8)])
    g=d.reshape(-1,5); b=g[:,0]+g[:,1]*3+g[:,2]*9+g[:,3]*27+g[:,4]*81
    return bytes(b.astype(np.uint8))
NB=(D+4)//5                              # байт в пакете
packet=pack_base3(q)                     # пакет зашумлённого запроса (item3)
assert len(packet)==NB
with open("unpack3_rom.vh","w") as f:
    f.write(f"// byte(0..242) -> 5 тритов, код digit_k=(byte//3^k)%3 (=−1/0/+1 → 00/01/10), dim=5*byte+k\n")
    f.write(f"localparam NB={NB};\n")
    f.write("function [9:0] unpack3; input [7:0] b; begin case(b)\n")
    for b in range(256):
        digs=[ (b//(3**k))%3 for k in range(5) ]      # digit0..4
        word=0
        for k in range(5): word |= digs[k] << (2*k)   # код = digit, dim k в позиции 2k
        f.write(f"    8'd{b}:unpack3=10'b{word:010b};\n")
    f.write("    default:unpack3=10'b0101010101; endcase end endfunction\n")
with open("vectors_rx.vh","w") as f:
    f.write(f"// радио-пакет зашумлённого item3: {NB} байт\n")
    f.write(f"localparam NBYTES={NB};\n")
    for i,by in enumerate(packet): f.write(f"localparam [7:0] PKT{i}=8'd{by};\n")
    f.write(f"localparam RX_EXP_ARG={int(np.argmax([int(np.dot(q.astype(np.int32),items[m].astype(np.int32))) for m in range(M)]))};\n")
print(f"unpack3 ROM + пакет {NB} байт, ожидаемый argmax после приёма = {int(np.argmax([int(np.dot(q,items[m])) for m in range(M)]))}")
