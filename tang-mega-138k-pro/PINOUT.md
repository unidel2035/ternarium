# Tang Mega 138K Pro — пинаут

Источник: официальные примеры Sipeed `TangMega-138KPro-example` (`led/`, `key_led/`, `udp_rgmii_send/`).

## Тактовые сигналы

| Сигнал | Пин | Частота | Описание |
|---|---|---|---|
| `clk` / `sys_clk` | **P16** | 50 МГц | основной системный тактовый |
| `osc_clk` | V22 | переменная | внешний осциллятор на 2x20 PinHeader |

## LED (6 шт., активные LOW — как на Nano 9K)

| Сигнал | Пин |
|---|---|
| `led[0]` / `led0` | **J14** |
| `led[1]` / `led1` | **R26** |
| `led[2]` / `led2` | **L20** |
| `led[3]` / `led3` | **M25** |
| `led[4]` / `led4` | **N21** |
| `led[5]` / `led5` | **N23** |

## Кнопки

| Сигнал | Пин | Pull | Описание |
|---|---|---|---|
| `rst_n` | K16 | UP | reset (активный LOW) |
| `key0` | F15 | UP | пользовательская кнопка 0 |
| `key1` | G15 | UP | пользовательская кнопка 1 |

## UART (через FT2232H Channel B → /dev/ttyUSB1)

| Сигнал | Пин | Подтверждено |
|---|---|---|
| `uart_tx` | **P15** | Sipeed `udp_rgmii_send` |
| `uart_rx` | R15 | TODO: проверить по schematic |

## GPIO 2x20 PinHeader

Тестово известный пин из Sipeed примеров:
- **V22** — bottom-left угол PinHeader

Остальные пины header — TODO: уточнить по schematic Tang Mega 138K Pro.
До уточнения GPIO-проекты (`tritosc` и GPIO-проекты)
используют пины-заглушки с пометкой `// TODO: verify`.

## Изменения относительно Tang Nano 9K

| Параметр | Tang Nano 9K | Tang Mega 138K Pro |
|---|---|---|
| Чип | GW1NR-LV9QN88PC6/I5 | GW5AST-LV138FPG676AC1/I0 |
| Корпус | QFN88 | FCPBG676A |
| Семейство | GW1N-9C | GW5AST-138B (Arora-V) |
| LUT | 8 640 | ~138 000 (×16) |
| Тактовая | 27 МГц | 50 МГц |
| LED | 6 (пины 10,11,13,14,15,16) | 6 (J14,R26,L20,M25,N21,N23) |
| LED полярность | active LOW | active LOW (без изменений) |

Полярность LED не изменилась: Sipeed `led/src/led.v` подтверждает `assign led[5:0] = ~led_reg[5:0]`
(active LOW). Существующий RTL (`assign led0 = ~cnt[24]`) работает без правок.

## Тулчейн

```bash
# Активация OSS CAD Suite
source ~/oss-cad-suite/environment

# В подпроекте:
make           # синтез + bitstream
make flash     # прошить SRAM (через openFPGALoader -b tangmega138kpro)
```

## ⚠️ Эмпирически (HDC bitnet_layer, проверено на железе)

- **Корпус: FPG676 (FCPBGA), device-строка nextpnr-himbaechel = `GW5AST-LV138FPG676AC1`.**
  `PG676` (PBGA) и `FPG676` — РАЗНАЯ распайка шариков! Сборка под PG676 даёт неверные пины.
  Голые партномера дают «No package»; нужен speed-суффикс (`...AC1`/`AC0`/`AI0`).
- **Такт P16 = живой 50 МГц по умолчанию** (офиц. `led/src/led.v` — голый счётчик `50000000/8`,
  без PLL/MS5351-init). Подтверждено.
- **UART-пин `uart_tx=P15`** — так делают офиц. `pro_ddr_test` и `udp_rgmii_send`. НО:
  прошитый маяк (0x55 @115200) на P15 НЕ доходит до onboard FT2232 (канал B = COM9/ttyUSB1):
  0 байт и через WSL, и напрямую из Windows. Вывод: **на этой плате onboard FT2232 — только JTAG
  (канал A); FPGA-UART выведен на GPIO-гребёнку, а не на USB-мост.** Для чтения UART с хоста нужен
  внешний USB-TTL на пине P15 гребёнки, либо наблюдать результат на LED (J14/R26/L20/M25/N21, active-LOW).
