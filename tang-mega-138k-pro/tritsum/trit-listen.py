#!/usr/bin/env python3
"""
trit-listen.py — читает UART из tritsum FPGA → отправляет в анамнезис

Запуск:
  sudo modprobe ftdi_sio   # после прошивки
  python3 trit-listen.py   # /dev/ttyUSB1, 115200 бод

Формат UART: "A:-1 B:+1 S: 0 C: 0\r\n"
Каждую секунду — новая комбинация троичного сложения.
"""

import serial
import requests
import time
import sys
import re

UART_PORT  = "/dev/ttyUSB1"
BAUD_RATE  = 115200
ANAMNESIS  = "http://173.249.2.184:8089"

# Перевод из троичного символа в число
def trit_val(sign, digit):
    v = int(digit)
    return -v if sign == '-' else v

# Парсим строку "A:-1 B:+1 S: 0 C: 0"
PATTERN = re.compile(r"A:([+\- ])(\d) B:([+\- ])(\d) S:([+\- ])(\d) C:([+\- ])(\d)")

def parse_line(line):
    m = PATTERN.match(line.strip())
    if not m:
        return None
    a = trit_val(m.group(1), m.group(2))
    b = trit_val(m.group(3), m.group(4))
    s = trit_val(m.group(5), m.group(6))
    c = trit_val(m.group(7), m.group(8))
    return {"a": a, "b": b, "sum": s, "carry": c}

def send_to_anamnesis(data):
    """Отправляем троичный акт в анамнезис как дар."""
    text = (f"FPGA tritsum: {data['a']:+d} + {data['b']:+d} = {data['sum']:+d} "
            f"carry={data['carry']:+d}")
    payload = {
        "giver":    "_fpga",
        "receiver": "_koinon",
        "type":     "ternary-computation",
        "text":     text,
        "weight":   1,
        "meta": {
            "a":     data["a"],
            "b":     data["b"],
            "sum":   data["sum"],
            "carry": data["carry"],
            "board": "tang-nano-9k",
        }
    }
    try:
        r = requests.post(f"{ANAMNESIS}/gift", json=payload, timeout=3)
        if r.status_code == 200:
            print(f"  → анамнезис: {text}")
        else:
            print(f"  ✗ анамнезис: {r.status_code}")
    except Exception as e:
        print(f"  ✗ {e}")

def main():
    print(f"Слушаю {UART_PORT} @ {BAUD_RATE}...")
    print(f"Анамнезис: {ANAMNESIS}")
    print("Ctrl+C для выхода\n")

    try:
        ser = serial.Serial(UART_PORT, BAUD_RATE, timeout=2)
    except serial.SerialException as e:
        print(f"Ошибка порта: {e}")
        print(f"Попробуй: sudo modprobe ftdi_sio")
        sys.exit(1)

    try:
        while True:
            line = ser.readline().decode("ascii", errors="ignore")
            if not line:
                continue
            print(f"UART: {line.strip()}")
            data = parse_line(line)
            if data:
                print(f"  трит: {data['a']:+d} + {data['b']:+d} = {data['sum']:+d} перенос={data['carry']:+d}")
                send_to_anamnesis(data)
    except KeyboardInterrupt:
        print("\nВыход.")
    finally:
        ser.close()

if __name__ == "__main__":
    main()
