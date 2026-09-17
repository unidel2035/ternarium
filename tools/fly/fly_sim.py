#!/usr/bin/env python3
"""fly_sim.py — самолётный SITL без MAVProxy: коннект, параметры, миссия, arm, AUTO,
и запись телеметрии с метками фаз (правила полной физики; чип их поля не видит).

Запуск: arduplane -S --model plane -I0  (в другом процессе, TCP 5760)
        python3 fly_sim.py <seconds> <out.csv>
"""
import sys
import time

from pymavlink import mavutil

dur = int(sys.argv[1]) if len(sys.argv) > 1 else 180
out = sys.argv[2] if len(sys.argv) > 2 else "telemetry.csv"

# (lat, lon, alt) — Канберра PAE, как -L PAE
HOME = (-35.363262, 149.165237)

MISSION = [
    # cmd, p1..p4, lat, lon, alt_m
    (16, 0, 0, 0, HOME[0], HOME[1], 0),                       # 0 home
    (22, 15, 0, 0, HOME[0], HOME[1], 60),                     # 1 TAKEOFF ->60m
    (16, 0, 0, 0, -35.372000, 149.175000, 100),               # 2 WP перегон
    (18, 6, 0, 0, -35.372000, 149.175000, 100),               # 3 LOITER 6 витков
    (16, 0, 0, 0, -35.352000, 149.190000, 100),               # 4 WP перегон
    (18, 5, 0, 0, -35.352000, 149.190000, 100),               # 5 LOITER 5 витков
    (20, 0, 0, 0, 0, 0, 0),                                   # 6 RTL
]

conn = mavutil.mavlink_connection("tcp:127.0.0.1:5760", source_system=255)
conn.wait_heartbeat()
print("heartbeat:", conn.target_system, "mode_map ready")
mav = conn.mav

# частоты сообщений для этого линка (без них RAW_IMU идёт на 1 Гц)
for msgid, hz in [(27, 50), (30, 50), (74, 10), (33, 10)]:
    mav.command_long_send(1, 0, 511, 0, msgid, int(1e6 / hz), 0, 0, 0, 0, 0, 0)
    time.sleep(0.05)

def wait_ack(fmt, timeout=5):
    t0 = time.time()
    while time.time() - t0 < timeout:
        m = conn.recv_match(type=fmt, blocking=True, timeout=timeout)
        if m:
            return m
    return None

# ── параметры: отключить фейлсейфы без GCS/RC ──
for name, val in [("ARMING_CHECK", 0), ("FS_GCS_ENA", 0),
                  ("FS_LONG_FS_ACTION", 0), ("FS_THR_ENABLE", 0),
                  ("FS_SHORT_FS_ACTION", 0), ("ARMING_RUDDER", 0),
                  ("SIM_WIND_SPD", 4)]:
    mav.param_set_send(1, 0, name.encode(), float(val),
                       mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
    r = wait_ack("PARAM_VALUE")
    print(f"param {name}={val}")

# ── миссия (с ретраями: FC может reject'нуть, пока не прогрузился) ──
for attempt in range(5):
    mav.mission_count_send(1, 0, len(MISSION), 0)
    print(f"mission_count отправлен (попытка {attempt + 1})...")
    sent_last = False
    acked = False
    for _ in range(120):
        m = conn.recv_match(blocking=True, timeout=3)
        if m is None:
            continue
        mt = m.get_type()
        if mt in ("MISSION_REQUEST", "MISSION_REQUEST_INT"):
            i = m.seq
            cmd, p1, p2, p3, lat, lon, alt = MISSION[i]
            mav.mission_item_int_send(1, 0, i, 3, cmd, 1, 1, float(p1), float(p2),
                                      float(p3), 0.0,
                                      int(lat * 1e7), int(lon * 1e7), float(alt))
            if i == len(MISSION) - 1:
                sent_last = True
        elif mt == "MISSION_ACK":
            print(f"  mission ack type={m.type}")
            acked = (m.type == 0)
            break
    if sent_last and acked:
        print("миссия принята")
        break
    print("  ретрай...")
    time.sleep(3)

time.sleep(1)

# ── arm + AUTO ──
mav.command_long_send(255, 0, mavutil.mavlink.MAV_CMD_COMPONENT_ARM_DISARM, 0, 1, 0, 0, 0, 0, 0, 0)
time.sleep(1.5)
conn.set_mode_apm("AUTO")
print("AUTO set, летим")
t0 = time.time()

st = {"att": (0, 0), "hud": (0, 0), "gpi": (0, 0), "mode": "?"}
rows = []
last = 0.0
while time.time() - t0 < dur:
    m = conn.recv_match(blocking=True, timeout=1)
    if m is None:
        continue
    mt = m.get_type()
    t = m._timestamp
    if mt == "ATTITUDE":
        st["att"] = (m.roll, m.pitch)
    elif mt == "VFR_HUD":
        st["hud"] = (m.throttle, m.airspeed)
        st["mode"] = getattr(m, "heading", 0) and st["mode"]
    elif mt == "HEARTBEAT" and m.get_srcSystem() == 1:
        st["mode"] = conn.flightmode
    elif mt == "GLOBAL_POSITION_INT":
        st["gpi"] = (m.relative_alt / 1000.0, m.vz / 100.0)
    elif mt == "STATUSTEXT":
        print(f"[{time.time()-t0:5.1f}s] {m.severity}: {m.text}")
    elif mt == "RAW_IMU":
        if t - last < 0.05:
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
        if len(rows) % 400 == 0:
            print(f"[{time.time()-t0:5.1f}s] {len(rows)} строк, mode={st['mode']}, alt={alt:.0f}м, as={asp:.0f}м/с")

with open(out, "w") as f:
    f.write("ax,ay,az,gx,gy,gz,thr,as,vz,alt,roll,pitch,label\n")
    for r in rows:
        f.write(",".join(f"{v:.4f}" for v in r) + "\n")
import numpy as np
labs = np.array([r[-1] for r in rows], dtype=int)
print(f"записано {len(rows)} строк -> {out}")
print("фазы:", dict(zip(["GROUND", "CLIMB", "CRUISE", "LOITER"],
                        np.bincount(labs, minlength=4))))
