#!/usr/bin/env python3
"""uart_talk.py — живой диалог с fly_brain на плате через /dev/ttyUSB*.

Пример: python uart_talk.py /dev/ttyUSB1 --stim F7F+ F12+ AF4- --theta 01 --steps 03
Печатает всё, что отвечает плата (акры 'k' и строки S=.. P=.. N=..).
"""
import argparse
import time

ap = argparse.ArgumentParser()
ap.add_argument("port", nargs="?", default="/dev/ttyUSB1")
ap.add_argument("--stim", nargs="*", default=[], help="стимулы вида F7F+ / AF4-")
ap.add_argument("--theta", default=None, help="порог, 2 hex")
ap.add_argument("--steps", default="03", help="сколько шагов прогнать, 2 hex")
ap.add_argument("--dump", action="store_true", help="дамп x после прогона")
ap.add_argument("--listen-only", type=float, default=0, help="просто слушать N секунд")
args = ap.parse_args()

import serial  # pip install pyserial

ser = serial.Serial(args.port, 115200, timeout=0.1)
time.sleep(0.3)
ser.reset_input_buffer()

def listen(seconds):
    t0 = time.time()
    buf = b""
    while time.time() - t0 < seconds:
        chunk = ser.read(256)
        if chunk:
            buf += chunk
            print(chunk.decode("cp1251", "replace"), end="", flush=True)
    return buf

def send(s, pause=0.3):
    ser.write(s.encode("latin1"))
    ser.flush()
    time.sleep(pause)
    listen(pause)

if args.listen_only:
    listen(args.listen_only)
    sys.exit(0)

for s in args.stim:
    assert len(s) == 4 and s[3] in "+-"
    send("S" + s)
if args.theta:
    send("H" + args.theta)
send("T" + args.steps)
print()
if args.dump:
    send("D", pause=5.0)
    listen(1.0)
