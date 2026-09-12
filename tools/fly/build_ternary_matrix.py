#!/usr/bin/env python3
"""FAFB v783 (Zenodo) -> тернарная матрица весов {-1, 0, +1}.

Вход (data/):
  proofread_connections_783.feather  — связи нейрон-нейрон (Zenodo 10676866, Dorkenwald et al. 2024)
  proofread_root_ids_783.npy         — канонический список нейронов
  neuron_annotations.tsv             — тип нейромедиатора на нейрон (Schlegel et al. 2024,
                                       flyconnectome/flywire_annotations)

Полярность связки = полярность ПРЕСИНАПТИЧЕСКОГО нейрона:
  acetylcholine, glutamate -> +1
  gaba                     -> -1
  dopamine/serotonin/octopamine/unknown/NaN -> 0 (честный ноль)
Вес пары = полярность, если syn_count >= min_syn, иначе 0.

Запуск (WSL, venv fly-connectome):
  python build_ternary_matrix.py [data_dir] [min_syn]
Выход: data/ternary.npz, data/ternary_ids.npy, data/ternary_stats.json
"""
import json
import re
import sys

import numpy as np
import pandas as pd
import scipy.sparse as sp

data_dir = sys.argv[1] if len(sys.argv) > 1 else "data"
min_syn = int(sys.argv[2]) if len(sys.argv) > 2 else 2

EXC = {"acetylcholine", "glutamate"}
INH = {"gaba"}

print("-> root ids ...")
ids = np.load(f"{data_dir}/proofread_root_ids_783.npy")
n = len(ids)
print(f"   нейронов: {n:,}")
idx = pd.Series(np.arange(n, dtype=np.int64), index=ids)

print("-> connections feather ...")
cons = pd.read_feather(f"{data_dir}/proofread_connections_783.feather")
cols = list(cons.columns)
print(f"   строк: {len(cons):,}; колонки: {cols}")


def find(pat):
    for c in cols:
        if re.search(pat, c, re.I):
            return c
    raise KeyError(f"колонка ~/{pat}/ не найдена в {cols}")


c_pre = find(r"pre.*(root|id)")
c_post = find(r"post.*(root|id)")
c_w = find(r"syn.*count|syn_count|eff.*weight|weight")
print(f"   pre={c_pre} post={c_post} weight={c_w}")

print("-> NT аннотации ...")
nt = pd.read_csv(f"{data_dir}/neuron_annotations.tsv", sep="\t",
                 usecols=["root_id", "top_nt", "known_nt"], low_memory=False)
# known_nt (курируемый) приоритетнее предсказания top_nt
nt["nt"] = nt["known_nt"].where(nt["known_nt"].notna() & (nt["known_nt"].astype(str).str.len() > 0),
                                nt["top_nt"])
nt["nt"] = nt["nt"].astype(str).str.lower()
pol = nt["nt"].map(lambda s: 1 if s in EXC else (-1 if s in INH else 0))
pol.index = nt["root_id"]
print("   распределение полярности нейронов:")
print(pol.value_counts().to_string())

print("-> сборка ...")
pre = cons[c_pre].to_numpy()
post = cons[c_post].to_numpy()
w_syn = cons[c_w].to_numpy()

pp = pol.reindex(pre).fillna(0).to_numpy(dtype=np.int8)
keep = (pp != 0) & (w_syn >= min_syn) & (pre != post)

r = idx.reindex(pre[keep]).to_numpy(dtype=np.int64)
c = idx.reindex(post[keep]).to_numpy(dtype=np.int64)
w = pp[keep]

M = sp.coo_matrix((w.astype(np.int8), (r, c)), shape=(n, n)).tocsr()
M.sum_duplicates()
M.data = np.sign(M.data).astype(np.int8)  # встречные связки схлопываются в знак перевеса
M.eliminate_zeros()

from collections import Counter
cnt = Counter(int(x) for x in M.data)
stats = {
    "neurons": int(n),
    "connections_raw": int(len(cons)),
    "min_syn": min_syn,
    "pairs_nonzero": int(M.nnz),
    "pos_trits": cnt.get(1, 0),
    "neg_trits": cnt.get(-1, 0),
    "density_pct": round(100.0 * M.nnz / (n * n), 4),
    "bytes_csr_int8": int(M.data.nbytes + M.indptr.nbytes + M.indices.nbytes),
    "bytes_2bit_packed_est": int(M.nnz / 4),
    "source": "FAFB v783, Zenodo 10676866 (Dorkenwald et al. 2024) + flywire_annotations (Schlegel et al. 2024)",
}
sp.save_npz(f"{data_dir}/ternary.npz", M)
np.save(f"{data_dir}/ternary_ids.npy", ids)
with open(f"{data_dir}/ternary_stats.json", "w") as f:
    json.dump(stats, f, indent=2)
print(json.dumps(stats, indent=2))
print(f"-> готово: {data_dir}/ternary.npz")
