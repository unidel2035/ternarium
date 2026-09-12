#!/bin/bash
# flash-and-test.sh — Прошивка и тест Tang Nano 9K
# Запуск из WSL: bash flash-and-test.sh [модуль]
# Пример: bash flash-and-test.sh tritpwm
# Пример: bash flash-and-test.sh tritservo
# Пример: bash flash-and-test.sh uartest

MODULE=${1:-tritpwm}
BASE=/home/unidel/fpga/tang-nano-9k
BITSTREAM=$BASE/$MODULE/build/$MODULE.fs

if [ ! -f "$BITSTREAM" ]; then
  echo "Bitstream not found: $BITSTREAM"
  echo "Building..."
  cd $BASE/$MODULE && make
  if [ $? -ne 0 ]; then echo "Build failed!"; exit 1; fi
fi

echo "=== Flashing $MODULE to SRAM ==="
sudo rmmod ftdi_sio 2>/dev/null
sleep 1
sudo openFPGALoader --board tangnano9k --freq 250000 "$BITSTREAM"

if [ $? -ne 0 ]; then
  echo "Flash failed! Retrying..."
  sleep 2
  sudo openFPGALoader --board tangnano9k --freq 250000 "$BITSTREAM"
fi

echo "=== Testing UART via pyftdi ==="
python3 << 'PYEOF'
from pyftdi.ftdi import Ftdi
import time, sys

ftdi = Ftdi()
ftdi.open(vendor=0x0403, product=0x6010, interface=1)
ftdi.set_bitmode(0, Ftdi.BitMode.RESET)
ftdi.set_baudrate(115200)
time.sleep(1)

def read_clean():
    """Read from FTDI and strip modem status bytes (0xFA prefix)"""
    d = ftdi.read_data(500)
    clean = bytearray()
    i = 0
    while i < len(d):
        if d[i] == 0xFA and i+1 < len(d):
            clean.append(d[i+1])
            i += 2
        else:
            clean.append(d[i])
            i += 1
    return bytes(clean)

# Interactive mode
print("UART connected. Type commands (q to quit):")
try:
    while True:
        cmd = input("> ")
        if cmd == 'q':
            break
        ftdi.write_data(cmd.encode())
        time.sleep(0.5)
        resp = read_clean()
        if resp:
            print(f"Response: {resp.decode(errors='replace')}")
        else:
            print("(no response)")
except (KeyboardInterrupt, EOFError):
    pass

ftdi.close()
print("Done.")
PYEOF
