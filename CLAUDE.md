# ternarium — рабочий контекст

Открытый троичный FPGA-стек (Gowin Tang Nano 9K / Tang Mega 138K Pro) + коннектом
мухи. Язык репо — русский, коммиты двуязычные. Лицензия MIT.

## Границы проекта (важно)

Репо — **только про вычисления**: троичная логика, архитектуры, нейро-движки,
открытая нейроморфика. Дрон-темы, оружейного и прикладного «бортового» кода здесь
нет и не должно появляться (осознанное решение владельца, 2026-09). Не добавлять
и не восстанавливать такое из старого приватного репо `tang`.

## Карта

- `tang-mega-138k-pro/trit*` — библиотека троичных элементов (ALU, CPU, RAM, RNG…)
- `tang-mega-138k-pro/bitnet_layer/` — BitNet-генераторы слоёв, HDC/TLMM без умножителей
- `tang-mega-138k-pro/fly_core/` — троичный CSR-матvec среза коннектома мухи (FAFB v783)
- `tools/fly/` — конвейер данных: ternary.npz → export_slice.py → hex для BRAM
- Данные коннектома (852 МБ) НЕ в репо: `~/fly-connectome/data/` (ternary.npz и пр.)

## Команды

```bash
# симуляция fly_core (iverilog установлен в WSL Ubuntu)
cd tang-mega-138k-pro/fly_core && make sim        # из Windows: wsl.exe -d Ubuntu bash -c "cd ... && make sim"

# регенерация среза под BRAM (K=4096 влезает, 423 КБ; K=8192 уже нет)
~/fly-connectome/.venv/bin/python tools/fly/export_slice.py ~/fly-connectome/data tang-mega-138k-pro/fly_core/sim 4096

# полная тернарная матрица из сырых данных (если data/ опустела)
~/fly-connectome/.venv/bin/python tools/fly/build_ternary_matrix.py ~/fly-connectome/data

# тулчейн ПЛИС (yosys/nextpnr/apycula)
./setup.sh
```

## Гочи

- gh-токен владельца БЕЗ `workflow`-скоупа: не пушить `.github/workflows/*`
- CRLF-ворнинги git на Windows — норм, не чинить
- rsync в git-bash нет; для копирования с исключениями — tar с --exclude
- Puš в репо только из `~/tang-clean` (Windows, git identity настроена локально:
  unidel2035 / unidel2035@users.noreply.github.com)
- Прошивка плат из WSL2 — по `WSL2-USB.md` (usbipd attach)
- Старый приватный репо `unidel2035/tang` — архив, 1.3 ГБ артефактов; НЕ мержить
