#!/usr/bin/env python3
"""model_budget.py — точный бюджет on-chip памяти GW5AST-138 и подбор byte-level
троичной модели, влезающей целиком в BRAM (подход TerEffic/TeLLMe). Гейт-решение."""
# Память чипа (из P&R-отчётов nextpnr этого проекта)
BSRAM_BLOCKS = 340; BSRAM_KBIT = 18           # Gowin BSRAM: 18 Кбит/блок
DRAM_CELLS   = 17280; DRAM_BIT = 64           # RAM16SDP4 distributed (ест LUT — резерв под активации/KV)
bsram_mbit = BSRAM_BLOCKS*BSRAM_KBIT/1024
dram_mbit  = DRAM_CELLS*DRAM_BIT/1e6
print(f"BSRAM: {BSRAM_BLOCKS}×{BSRAM_KBIT}Кбит = {bsram_mbit:.2f} Мбит  (под веса)")
print(f"distributed: {dram_mbit:.2f} Мбит (под активации/KV/LUT — не для весов)\n")
WEIGHT_BUDGET = bsram_mbit*1e6 * 0.85          # 85% BSRAM под веса, остальное — буферы/контроль
print(f"бюджет под веса (85% BSRAM): {WEIGHT_BUDGET/1e6:.2f} Мбит\n")

def model(V, d, L, H, heads, seq):
    # биты: троичные веса @2 бит, эмбеддинг/выход @8 бит (int8), KV @8 бит
    embed  = V*d*8                              # таблица эмбеддингов (int8)
    out    = d*V*2                              # выходная проекция (троичная)
    per_layer = (4*d*d + 2*d*H)*2               # attn(Wq,k,v,o) + FFN(W1,W2) троичные @2бит
    layers = L*per_layer
    kv     = heads*(d//heads)*seq*2*8           # K,V кэш @int8
    total  = embed+out+layers
    return dict(embed=embed,out=out,layers=layers,kv=kv,total=total,per_layer=per_layer)

print("=== перебор конфигов (V=256 byte-level, d=256) ===")
best=None
for L in (2,3,4,5,6):
  for H in (512,683):                           # FFN hidden (2× и 2.67×d)
    m=model(256,256,L,H,4,256)
    fit = m['total']<=WEIGHT_BUDGET
    flag="✓ влезает" if fit else "✗"
    print(f" L={L} H={H}: тело {m['layers']/1e6:.2f} + эмбед {m['embed']/1e6:.2f} + выход {m['out']/1e6:.2f} = {m['total']/1e6:.2f} Мбит  {flag}")
    if fit and (best is None or L>best[0]): best=(L,H,m)
print()
if best:
  L,H,m=best
  params=(4*256*256+2*256*H)*L + 256*256 + 256*256
  print(f"=== ВЫБОР: byte-level, V=256, d=256, L={L}, heads=4, FFN_hidden={H}, seq=256 ===")
  print(f"  всего ≈ {params/1e6:.2f}M параметров, {m['total']/1e6:.2f} Мбит весов (влезает в {bsram_mbit:.1f} Мбит BSRAM)")
  print(f"  KV-кэш: {m['kv']/1e6:.2f} Мбит (в distributed/BSRAM)")
  print(f"  на слой: {m['per_layer']/1e6:.2f} Мбит весов")
  import json
  json.dump(dict(vocab=256,d=256,n_layers=L,n_heads=4,ffn_hidden=H,seq=256,
                 weight_bits=2,act_bits=8,total_mbit=round(m['total']/1e6,2)),
            open("model_config.json","w"),indent=2)
  print("  → model_config.json записан")
