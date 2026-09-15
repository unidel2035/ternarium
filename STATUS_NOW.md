# STATUS_NOW — хэндофф для параллельной сессии (2026-09-14 ~22:00)

## НЕ ТРОГАТЬ (идёт сборка, 8+ часов работы убьётся)

- **nextpnr-himbaechel ROUTING** в WSL Ubuntu: `~/fly-build/tang-mega-138k-pro/fly_brain_lcd/build.log`
  - дизайн: fly_brain_lcd.v = мозг мухи (K=1024, динамика S·x + порог) + LCD 800×480 (лента 1024 нейронов)
  - фаза: router1 трассировка, ~230К итераций, wirelen ~110K и падает — ШТАТНО, не рестартовать
  - processes: nextpnr-himbaechel (один, 100% одного ядра)
  - после завершения: `build/fly_brain_lcd.fs` → прошить SRAM:
    `wsl → sudo openFPGALoader --board tangmega138k ~/fly-build/.../fly_brain_lcd/build/fly_brain_lcd.fs`
  - usbipd attach уже сделан (busid 2-1, FTDI 0403:6010); при отвале: `usbipd detach --busid 2-1; usbipd attach --wsl --busid 2-1`
- НЕ запускать параллельных make/yosys (конфликт build-каталогов + OOM ВМ 16ГБ)
- pkill шаблоны: всегда с квадратными скобками `pkill -9 -f "[y]osys"` — иначе убивает собственную команду

## Готово и в репо (github unidel2035/ternarium, всё запушено)

- fly_brain.v: мозг K=256 (динамика S·x + порог + UART + автодемо), sim-PASS vs numpy golden,
  битстрим build_brain/fly_brain.fs (K=256) УЖЕ ЗАГРУЖЕН В SRAM ПЛАТЫ (LED J14 пульсирует)
- fly_sdram/: SDR SDRAM контроллер W9825G6KH @100МГц — sim-PASS 70/70 (баг тестбенча:
  импульсные u_wr/u_rd терялись в окнах refresh → level-triggered запросы)
- tools/fly/: export_slice.py (срез K→hex), export_full.py (fly_full.img 18.4МБ весь мозг),
  brain_sim.py (золотая модель), brain_tape_html.py (HTML-визуализация, открыт fly_tape.html),
  train_readout.py (тернарный readout 4×256, 100% чистые/71% шум), make_splash_font.py
- bitnet_layer/mlgru_sim/: нейтральная LLM (D=24) верифицирована в RTL 55/55 vs Python
  (5 багов RTL исправлены: LUTROM depth, DSHIFT, layer selectors, NEXTL reset, sdiv32)
- mlgru_neutral/ + tools/train_mlgru_neutral.py + tools/export_neutral_rtl.py: обучена (2.99 бит/байт),
  корпус = вики (Сетунь/троичность/дрозофила/коннектом) + доки репо

## Факты о плате (проверено)

- Onboard FT2232 = ТОЛЬКО JTAG (канал B к FPGA-UART НЕ подключён) — UART-тесты требуют внешний
  USB-TTL на гребёнку P15/R15 (cst: rx=N16, uart_tx=P15)
- Onboard память = DDR3 1ГБ (2×H5TQ4G63EFR) — только vendor-IP Gowin; SDR SDRAM = внешний
  PMOD (~$20, MiSTer-формат); пины обоих: C:\Users\unide\AppData\Local\Temp\tm138k\*.cst
- Прошивка: fly_brain.fs в SRAM (LED-демо), fly_splash.fs в SPI flash (заставка TERNARIUM на LCD)
  → перетыкание питания = заставка; SRAM-прошивка живёт до перетыкания

## Гочи

- WSL 16ГБ; yosys на /mnt/c (9P) в 5 раз медленнее → собирать на ~/fly-build (нативная ext4)
- iverilog: в ~/oss-cad-suite/bin; venv нейро: ~/fly-connectome/.venv
- synth_gowin НЕ имеет -nofsm; медленный fsm-гринд лечится архитектурно (пакованные слова),
  не флагами
- Инструменты Python: ~/fly-connectome/.venv/bin/python (numpy/scipy/torch/serial)

## Следующие шаги (после прошивки LCD)

1. whole-brain: SDRAM PMOD ($20) + стриминг CSR из fly_full.img (контроллер готов и верифицирован)
2. mlgru на плату: расширить tok_out 16→64, UART-выдача текста
3. reservoir-эксперимент: обучаемый readout vs нарисованные рефлексы на полётных данных
