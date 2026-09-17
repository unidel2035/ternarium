#!/usr/bin/env python3
"""sitl_capture.py — запись телеметрии ArduPilot SITL в CSV с автометками фаз полёта.

Подключается к udpin:0.0.0.0:<port> (sim_vehicle --out=udpout:127.0.0.1:<port>).
Пишет ~20 Гц: ax..ay (м/с²), gx..gz (рад/с), thr, as (м/с), vz (м/с), alt (м),
roll/pitch (°) и label по ПРАВИЛАМ полной физики (чип эти поля НЕ видит):
  0 GROUND : alt<3 и скорость<3
  1 CLIMB  : vz>2.5
  3 LOITER : |roll|>25° и воздушная>8
  2 CRUISE : воздушная>8 (прочий полёт)
  0 GROUND : иначе (медленный/низкий)

Запуск: python sitl_capture.py <udp_port> <seconds> <out.csv>
"""
import sys
import time

from pymavlink import mavutil

port = int(sys.argv[1]) if len(sys.argv) > 1 else 14560
dur = int(sys.argv[2]) if len(sys.argv) > 2 else 120
out = sys.argv[3] if len(sys.argv) > 3 else "telemetry.csv"

conn = mavutil.mavlink_connection(f"udpin:0.0.0.0:{port}")
conn.wait_heartbeat(timeout=90) or print("NET_HEARTBEAT_90s")
print("heartbeat OK:", conn.target_system)

# ── запрос частот для НАШЕГО линка (по умолчанию второй GCS получает 1 Гц) ──
for msgid, hz in [(27, 50), (30, 50), (74, 10), (33, 10)]:
    conn.mav.command_long_send(1, 0, 511, 0, msgid, int(1e6 / hz), 0, 0, 0, 0, 0, 0)
    time.sleep(0.1)
print("stream rates requested")

st = {"att": (0, 0), "hud": (0, 0), "gpi": (0, 0)}   # держим последние значения
rows = []
t0 = time.time()
last = 0.0
while time.time() - t0 < dur:
    m = conn.recv_match(blocking=True, timeout=1)
    if m is None:
        continue
    t = m._timestamp
    if m.get_type() == "ATTITUDE":
        st["att"] = (m.roll, m.pitch)
    elif m.get_type() == "VFR_HUD":
        st["hud"] = (m.throttle, m.airspeed)
    elif m.get_type() == "GLOBAL_POSITION_INT":
        st["gpi"] = (m.relative_alt / 1000.0, m.vz / 100.0)
    elif m.get_type() == "RAW_IMU":
        if t - last < 0.05:                          # ~20 Гц
            continue
        last = t
        acc = (m.xacc * 0.00981, m.yacc * 0.00981, m.zacc * 0.00981)
        gyr = (m.xgyro / 1000.0, m.ygyro / 1000.0, m.zgyro / 1000.0)
        thr, asp = st["hud"]
        alt, vz = st["gpi"]
        roll, pitch = st["att"]
        roll_d = roll * 57.2958
        if alt < 3 and asp < 3:
            lab = 0
        elif vz > 2.5:
            lab = 1
        elif abs(roll_d) > 25 and asp > 8:
            lab = 3
        elif asp > 8:
            lab = 2
        else:
            lab = 0
        rows.append((*acc, *gyr, thr, asp, vz, alt, roll_d, pitch * 57.2958, lab))

hdr = "ax,ay,az,gx,gy,gz,thr,as,vz,alt,roll,pitch,label"
with open(out, "w") as f:
    f.write(hdr + "\n")
    for r in rows:
        f.write(",".join(f"{v:.4f}" for v in r) + "\n")
import numpy as np
labs = np.array([r[-1] for r in rows], dtype=int)
print(f"записано {len(rows)} строк -> {out}")
print("фазы:", dict(zip(["GROUND", "CLIMB", "CRUISE", "LOITER"],
                        np.bincount(labs, minlength=4))))
