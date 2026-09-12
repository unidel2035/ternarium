#!/usr/bin/env python3
"""FlyWire connectome -> ternary weight matrix {-1, 0, +1}.

Источник: таблица synapses_nt_v1 (проверенные синапсы взрослой мухи,
с основным нейромедиатором; Eckstein et al. 2024, materialization v783).

Полярность трита:
  ach, glut          -> +1  (возбуждающие)
  gaba               -> -1  (тормозные)
  da, ser, oct и пр. ->  0  (модуляторные/неизвестно — честный ноль)

Трит пары нейронов = sign(#exc - #inh), если |#exc - #inh| >= min_syn, иначе 0.

Запуск:
  python flywire_to_ternary.py --token <CAVE_TOKEN> [--min-syn 2]

Токен (бесплатно, нужен Google-логин): https://codex.flywire.ai  ->  API Tokens
Выход: ternary.npz (CSR int8) + ternary_ids.csv (маппинг root_id -> индекс) + ternary_stats.json
"""
import argparse
import json
import time

import numpy as np
import pandas as pd
import scipy.sparse as sp
from caveclient import CAVEclient

EXC = {"ach", "glut"}
INH = {"gaba"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", required=True, help="CAVE auth token с codex.flywire.ai")
    ap.add_argument("--min-syn", type=int, default=2,
                    help="минимальный перевес возбуждения/торможения для ненулевого трита")
    ap.add_argument("--out", default="ternary", help="префикс выходных файлов")
    a = ap.parse_args()

    client = CAVEclient("flywire_fafb_production", token=a.token)
    t0 = time.time()
    print("-> запрашиваю synapses_nt_v1 (это десятки млн строк, займёт время) ...")
    df = client.materialize.query_table(
        "synapses_nt_v1",
        select_columns=["pre_pt_root_id", "post_pt_root_id", "primary_nt"],
    )
    print(f"   строк: {len(df):,} за {time.time() - t0:.0f} с")

    df = df.dropna(subset=["pre_pt_root_id", "post_pt_root_id"])
    df = df[df.pre_pt_root_id != df.post_pt_root_id]

    ids = pd.unique(pd.concat([df.pre_pt_root_id, df.post_pt_root_id]))
    remap = pd.Series(np.arange(len(ids), dtype=np.int32), index=ids)
    r = remap[df.pre_pt_root_id].to_numpy(np.int32)
    c = remap[df.post_pt_root_id].to_numpy(np.int32)
    nt = df.primary_nt.fillna("unknown").astype(str).str.lower()
    w = np.where(nt.isin(EXC), 1, np.where(nt.isin(INH), -1, 0)).astype(np.int32)

    n = len(ids)
    m = coo = sp.coo_matrix((w, (r, c)), shape=(n, n)).tocsr()
    m.sum_duplicates()
    m.data = np.sign(m.data) * (np.abs(m.data) >= a.min_syn)
    m = m.astype(np.int8)
    m.eliminate_zeros()

    from collections import Counter
    cnt = Counter(int(x) for x in m.data)
    stats = {
        "neurons": int(n),
        "synapses_raw": int(len(df)),
        "pairs_nonzero": int(m.nnz),
        "pos_trits": cnt.get(1, 0),
        "neg_trits": cnt.get(-1, 0),
        "zero_share_pct": round(100.0 * (1 - m.nnz / (n * n)), 4),
        "min_syn": a.min_syn,
        "bytes_csr_int8": int(m.data.nbytes + m.indptr.nbytes + m.indices.nbytes),
        "bytes_2bit_packed_est": int(m.nnz / 4),
    }
    sp.save_npz(a.out + ".npz", m)
    pd.DataFrame({"root_id": ids}).to_csv(a.out + "_ids.csv", index=False)
    with open(a.out + "_stats.json", "w") as f:
        json.dump(stats, f, indent=2)
    print(json.dumps(stats, indent=2))
    print(f"-> готово: {a.out}.npz, {a.out}_ids.csv, {a.out}_stats.json")


if __name__ == "__main__":
    main()
