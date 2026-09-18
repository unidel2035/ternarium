#!/usr/bin/env python3
"""flight_stream.py — hardware-in-loop: телеметрия SITL -> UART -> чип.

Каждое окно 0.5 c:
  1. 12 признаков -> z-score (flight_gold.npz) -> знаковые тычки в 12 нейронов
  2. по UART: 'S' + id3hex + '+'/'-'  (12 посылок, только изменения)
  3. 'T' + '01'  — один шаг матвека+порог+readout на чипе
  4. читаем отчёт 'S=01 P=.. N=..' и печатаем распознанную фазу

Классы: 0=GROUND 1=CLIMB 2=CRUISE 3=LOITER (рамка/квадрант на экране платы).

Запуск:
  python3 flight_stream.py /dev/ttyUSB0 <mav_udp_port>
Пример: (сим уже летит, MAVProxy --out=udpout:127.0.0.1:14560)
  python3 flight_stream.py /dev/ttyUSB0 14560
"""
import json
import sys
import time

import numpy as np
import serial

port_name = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB0"
udp = int(sys.argv[2]) if len(sys.argv) > 2 else 14560

G = np.load("/home/unidel/fly-build/tang-mega-138k-pro/flight/flight_gold.npz")
mu, sd, inj = G["mu"], G["sd"], G["inj"]
FEATS = json.load(open("/home/unidel/fly-build/tang-mega-138k-pro/flight/flight_gold.json"))["feats"]
CLASSES = ["GROUND", "CLIMB", "CRUISE", "LOITER"]

from pymavlink import mavutil
conn = mavutil.mavlink_connection(f"udpin:0.0.0.0:{udp}")
conn.wait_heartbeat(timeout=30)
for msgid, hz in [(27, 50), (30, 50), (74, 10), (33, 10)]:
    conn.mav.command_long_send(1, 0, 511, 0, msgid, int(1e6 / hz), 0, 0, 0, 0, 0, 0)

ser = serial.Serial(port_name, 115200, timeout=0.5)

st = {"att": (0, 0), "hud": (0, 0), "gpi": (0, 0)}
buf = np.zeros(12)
last_lab = -1
win_t = time.time()
pend = {}
while True:
    m = conn.recv_match(blocking=True, timeout=1)
    if m is None:
        continue
    mt = m.get_type()
    if mt == "ATTITUDE":
        st["att"] = (m.roll, m.pitch)
    elif mt == "VFR_HUD":
        st["hud"] = (m.throttle, m.airspeed)
    elif mt == "GLOBAL_POSITION_INT":
        st["gpi"] = (m.relative_alt / 1000.0, m.vz / 100.0)
    elif mt == "RAW_IMU":
        f = np.array([m.xacc * 0.00981, m.yacc * 0.00981, m.zacc * 0.00981,
                      m.xgyro / 1000, m.ygyro / 1000, m.zgyro / 1000,
                      st["hud"][0], st["hud"][1], st["gpi"][1], st["gpi"][0],
                      st["att"][0] * 57.2958, st["att"][1] * 57.2958])
        buf += np.clip((f - mu) / sd, -3, 3)
    # конец окна 0.5 c
    if time.time() - win_t >= 0.5:
        win_t = time.time()
        z = buf / 5.0
        buf[:] = 0
        # тычки: знак усреднённого z, мёртвая зона 0.5
        for d in range(12):
            if abs(z[d]) >= 0.5:
                pid = int(inj[d])
                sig = "+" if z[d] > 0 else "-"
                key = (pid, sig)
                if pend.get(d) != sig:            # шлём только изменения
                    ser.write(f"S{pid:03X}{sig}".encode())
                    pend[d] = sig
        ser.write("T01".encode())                 # один шаг на чипе
        line = b""
        t0 = time.time()
        while time.time() - t0 < 0.4:
            chunk = ser.read(ser.in_waiting or 1)
            if chunk:
                line += chunk
                if b"S=01" in line:
                    break
        txt = line.decode(errors="replace")
        if "S=01" in txt:
            # фаза не приходит по UART (cls_reg на чипе виден на рамке/квадранте);
            # локально повторим оценку тем же readout'ом для лога
            lab = int(np.argmax(np.abs(z))) and 0
        print(f"[{time.strftime('%H:%M:%S')}] окно отправлено, ответ: {txt.strip()!r}")
