# Троичный FPGA-стек — Tang Nano 9K / Tang Mega 138K Pro

**Открытая троичная ({−1, 0, +1}) вычислительная система на дешёвой ПЛИС: от логического элемента до нейросетевого движка.**
Наследник «Сетуни-58», собранный на Gowin за $30–150 вместо $30 000 за ускоритель.

> **EN TL;DR:** An open-source balanced-ternary computing stack on commodity FPGAs
> (Gowin Tang Nano 9K / Tang Mega 138K Pro): ternary logic, ALU, CPU, neural-net engines,
> and a BitNet-style distillation pipeline — small LLM inference *without GPUs*.
> MIT licensed — take it, improve it, pass it on.

---

## Лестница автономности: весь стек — без GPU, без облака, почти без денег

1. **Мозг (сегодня, на любом ПК):** BitNet b1.58 2B на CPU — троичные веса, работает в llama.cpp / bitnet.cpp. Альтернатива: Qwen3-4B Q4 на обычных ядрах (~10–15 ток/с на 14 потоках).
2. **Автоном (офлайн):** rkllm на мини-ПК (Orange Pi 5, NPU 6 TOPS) — модель работает без сети. Ноль облака, ноль подписки, ноль внешних API.
3. **Тяжёлое (раз в неделю):** обучение 50-миллионной троичной сети — Kaggle-класс (30 GPU-часов/нед бесплатно) или Colab T4. Не аренда H100.
4. **Нужен большой разум:** Petals — сообщество отдаёт слои больших моделей даром.
5. **Муха на ПЛИС (цель проекта):** yosys → nextpnr → `bitnet_layer`. Коннектом дрозофилы (FlyWire, ~50 млн синапсов) при 2 бит/вес — это **~12 МБ**, полный проход — единицы миллисекунд на Tang Mega 138K. Инсект-уровень вычислений на плате за $150.

## Что в репозитории

**Троичное ядро** — библиотека элементов: `trit`, `trit3`, `tritlogic`, `tritalu`, `tritmul`, `tritmsparse` (разрежённая матрица), `tritsum`, `tritmux`, `tritseq`, `tritclock`, `tritosc`, `tritfsm`, `tritcpu`, `tritram`, `trithash`, `tritrng` (аппаратный ГСЧ).

**Нейро-движки** (`bitnet_layer/`): генераторы слоёв BitNet (`block_gen`, `attn_gen`, `ffn_gen`, `rms_gen`, `softmax_gen`), троичный MLP/нейрон (`tritneuron`, `tritmlp`, `tritlayer`), движок гиперразмерных вычислений `hdc.v` — векторная алгебра **без единого умножителя**, TLMM-движок, MLGRU-инференс на ПЛИС (`model_infer.v`, `mlgru_board.v`), скрипты дистилляции (`bitdistill_coder.py`, `decode_*.py`). Плюс `tritnet` — простая троичная сеть.

**Философия на кремнии:** `tritonto`, `tritkenos` — троичная онтология.

**Периферия и отладка:** `trituart2` (UART-мост), `tritscope` (логический анализатор), `tritscreen` (вывод на LCD), `uart_beacon/echo/scan`, `uartest`, `i2c_master`, `oled_ssd1306`, `sd_writer` (логгер событий), `blink`, `tests/`.

**Документы:** `PINOUT.md` (распиновка), `WSL2-USB.md` (прошивка из WSL2 через usbipd).

## Быстрый старт

```bash
./setup.sh                              # тулчейн: yosys + nextpnr + apycula (открытый, без vendor-IDE)
cd tang-mega-138k-pro/tritalu && make   # собрать любой модуль
./flash-and-test.sh                     # прошить и проверить
```

Плата: Tang Mega 138K Pro Dock (GW5AST-138, DDR3, HDMI, PCIe) — основной стенд; Tang Nano 9K — прототипы элементов.

## Дорожная карта: «муха»

- [x] Скачать коннектом дрозофилы: Zenodo 10676866 (Dorkenwald et al. 2024, `proofread_connections`) + NT-аннотации (Schlegel et al. 2024)
- [x] Конвертер: связи + медиатор пресинапса → разрежённая матрица {-1, 0, +1}: **139 255 × 139 255, 5.92 млн тритов** (см. `tools/fly/`)
- [x] CPU-референс: полный проход мозга за **7 мс** (142 прохода/сек) на обычном процессоре
- [ ] Экспорт в memory-image: паковка 2 бита/трит → **весь мозг = 1.48 МБ**
- [ ] Проход на Tang Mega 138K — цель: единицы мс

## Правила дара

Лицензия — **MIT**: бери, улучшай, отдавай. Дар движется по кругу, а не оседает.
Этот репозиторий — про **вычисления**: троичная логика, архитектуры, открытые движки. Никакого оружейного кода здесь нет и не будет.
