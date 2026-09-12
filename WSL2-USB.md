# USB passthrough WSL2 → Tang Mega 138K Pro

WSL2 не видит USB напрямую. Два пути:

## Путь 1 — usbipd-win (рекомендуется)

На **Windows** (PowerShell от администратора):
```powershell
# Установить usbipd-win (если ещё нет)
winget install --interactive --exact dorssel.usbipd-win

# После подключения Tang Mega 138K Pro:
usbipd list                          # найти FTDI 0403:6010 (Sipeed USB Debugger)
usbipd bind --busid <BUSID>          # один раз
usbipd attach --wsl --busid <BUSID>  # каждый раз при подключении
```

После этого в WSL2:
```bash
lsusb                   # должен появиться FTDI 0403:6010
openFPGALoader --detect # должен найти GW5AST-138
```

## Путь 2 — программировать через Gowin EDA на Windows

Синтез в WSL2 (yosys + nextpnr-himbaechel + gowin_pack) → получаем `.fs` файл.
Программирование через Gowin Programmer на Windows.

1. Открыть Gowin Programmer (Windows)
2. Файл → `~/tang/tang-mega-138k-pro/blink/build/blink.fs`
3. Cable → Gowin USB Cable (FT2CH/A) → Auto-detect
4. Program → Run

## Проверка подключения

```bash
# В WSL2 после usbipd attach:
lsusb | grep -i "0403\|1a86\|sipeed"
openFPGALoader --detect
```

Ожидаемый вывод:
```
index 0:
    idcode 0x1081b
    manufacturer Gowin
    family GW5AST
    model  GW5AST-138
    irlength 8
```

## SRAM vs SPI Flash

```bash
make flash             # прошить SRAM — теряется при выключении (быстрая итерация)
make flash-permanent   # прошить во встроенный SPI flash — сохраняется
```

После `flash-permanent` плата автоматически загружает прошивку при подаче питания.
