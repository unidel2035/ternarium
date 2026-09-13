#!/usr/bin/env bash
# setup.sh — собрать рабочие файлы для симуляции model_mlgru (нейтральная модель).
# RTL/веса НЕ меняются: копируются как есть из репо.
set -e
SRC=/mnt/c/Users/unide/ternarium
BL="$SRC/tang-mega-138k-pro/bitnet_layer"
SIM="$BL/mlgru_sim"
cp "$BL/model_mlgru.v" "$BL/fxops.v" "$SIM/"
cp "$SRC/mlgru_neutral/mlgru_vectors.vh" "$SRC/mlgru_neutral/mlgru_wt.hex" \
   "$SRC/mlgru_neutral/mlgru_emb.hex" "$SRC/mlgru_neutral/mlgru_lut.hex" "$SIM/"
# seedrom.hex — отсутствует в репо; model_mlgru.v читает 4 ситуации x S токенов.
# Ситуация 0 (и все прочие) = SEED_0..SEED_47 из mlgru_vectors.vh.
python3 gen_seedrom.py
echo "--- файлы ---"
ls -la "$SIM"
