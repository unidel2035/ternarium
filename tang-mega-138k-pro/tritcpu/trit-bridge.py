#!/usr/bin/env python3
"""
trit-bridge.py — Мост между тритным CPU (FPGA) и анамнезисом

Архитектура:
  Анамнезис → [poll] → тritcpu (UART) → [ответ] → Анамнезис

Команды в анамнезисе (POST /gift с type="fpga-command"):
  {"giver":"_bot","receiver":"_fpga","type":"fpga-command",
   "text":"compute","weight":1,
   "meta":{"op":"+","a":5,"b":3}}

Поддерживаемые операции: + - * ! & |

Результат записывается обратно как:
  {"giver":"_fpga","receiver":"_koinon","type":"fpga-result",
   "text":"5 + 3 = 8 = {+,0,-1}","meta":{...}}

Запуск:
  sudo modprobe ftdi_sio
  python3 trit-bridge.py          # режим демона (polling)
  python3 trit-bridge.py --once   # одна сессия
  python3 trit-bridge.py --demo   # демо без анамнезиса
"""

import serial, requests, time, sys, re, json, argparse

UART_PORT  = "/dev/ttyUSB1"
BAUD_RATE  = 115200
ANAMNESIS  = "http://173.249.2.184:8089"
POLL_INTERVAL = 5  # секунд

# ── Тритное ↔ Десятичное ─────────────────────────────────

TRIT_CHARS = {'+': 1, '0': 0, '-': -1}

def trit_to_dec(trit_str):
    """'0+-' → int (t2*9 + t1*3 + t0*1)"""
    t = trit_str.replace(' ', '0')
    return TRIT_CHARS[t[0]]*9 + TRIT_CHARS[t[1]]*3 + TRIT_CHARS[t[2]]

def dec_to_trit(n):
    """int → '0+-' строка (3 трита)"""
    result = []
    for base in [9, 3, 1]:
        # Находим ближайший трит (-1,0,+1) * base
        candidates = [(-1, n+base), (0, n), (1, n-base)]
        # Выбираем с минимальным |остатком|
        _, r = min(candidates, key=lambda x: abs(x[1]))
        t = round((n - r) / base)
        result.append({-1:'-', 0:'0', 1:'+'}[t])
        n = r
    return ''.join(result)

# ── UART CPU ─────────────────────────────────────────────

class TritCPU:
    def __init__(self, port=UART_PORT, baud=BAUD_RATE):
        self.ser = serial.Serial(port, baud, timeout=0.5)
        time.sleep(0.2)
        self._flush()
        self.reset()

    def _flush(self):
        self.ser.reset_input_buffer()
        t = time.time()
        while time.time()-t < 0.3: self.ser.read(200)
        self.ser.reset_input_buffer()

    def _cmd(self, c):
        """Отправить команду, прочитать ответ"""
        self.ser.reset_input_buffer()
        self.ser.write(c.encode())
        time.sleep(0.12)
        r = self.ser.read(80).decode("ascii","ignore").strip()
        return r

    def _parse(self, resp):
        """'A:0+0 B:0+- C:00+' → {'A':'+3','B':'+2','C':'+1'}"""
        m = re.match(r'A:(...) B:(...) C:(...)', resp)
        if not m: return None
        return {
            'A_trit': m.group(1), 'A': trit_to_dec(m.group(1)),
            'B_trit': m.group(2), 'B': trit_to_dec(m.group(2)),
            'C_trit': m.group(3), 'C': trit_to_dec(m.group(3)),
        }

    def reset(self):
        r = self._cmd('r')
        return self._parse(r)

    def set_a(self, n):
        """Установить регистр A в n (-13..+13)"""
        self.reset()
        c = 'a' if n >= 0 else 'A'
        for _ in range(abs(n)):
            r = self._cmd(c)
        return self._parse(r) if abs(n) > 0 else self._parse(self._cmd('r'))

    def set_b(self, n):
        """Установить регистр B в n (не сбрасывает A)"""
        c = 'b' if n >= 0 else 'B'
        r = None
        for _ in range(abs(n)):
            r = self._cmd(c)
        return self._parse(r) if abs(n) > 0 else None

    def compute(self, op, a, b=None):
        """Вычислить op(a, b) → результат dict"""
        # Зажимаем значения в [-13, +13]
        a = max(-13, min(13, a))
        if b is not None: b = max(-13, min(13, b))

        state = self.set_a(a)
        if b is not None: self.set_b(b)

        op_map = {'+': '+', '-': '-', '*': '*', '&': '&', '|': '|', '!': '!'}
        op_cmd = op_map.get(op, '+')
        r = self._cmd(op_cmd)
        state = self._parse(r)

        if state is None:
            return None

        return {
            'a': a, 'b': b, 'op': op,
            'result': state['C'],
            'result_trit': state['C_trit'],
            'state': state,
        }

    def close(self):
        self.ser.close()

# ── Анамнезис ─────────────────────────────────────────────

def get_pending_commands(seen_ids):
    """Читаем ленту анамнезиса, возвращаем необработанные fpga-command"""
    try:
        r = requests.get(f"{ANAMNESIS}/tape", timeout=3)
        if r.status_code != 200: return []
        acts = r.json() if isinstance(r.json(), list) else r.json().get('acts', [])
        return [a for a in acts
                if a.get('type') == 'fpga-command'
                and a.get('id') not in seen_ids]
    except Exception as e:
        print(f"  [poll] Ошибка: {e}")
        return []

def post_result(act, res):
    """Записать результат вычисления в анамнезис"""
    b_str = f" B:{res['b']:+d}" if res['b'] is not None else ""
    text = (f"FPGA tritcpu: {res['a']:+d} {res['op']}{b_str} = {res['result']:+d} "
            f"[{res['result_trit']}]")
    try:
        r = requests.post(f"{ANAMNESIS}/gift", json={
            "giver":    "_fpga",
            "receiver": "_koinon",
            "type":     "fpga-result",
            "text":     text,
            "weight":   1,
            "meta":     {
                "compute_id": act.get('id'),
                "op":     res['op'],
                "a":      res['a'],
                "b":      res['b'],
                "result": res['result'],
                "result_trit": res['result_trit'],
            }
        }, timeout=3)
        return r.status_code == 200
    except Exception as e:
        print(f"  [post] Ошибка: {e}")
        return False

# ── Демо-режим ────────────────────────────────────────────

DEMO_PROGRAM = [
    ('+', 5,  3,  "+8: дар порождает избыток"),
    ('+', -5, 5,  "0: кенозис — жертва сравнялась с даром"),
    ('+', -7, -6, "-13: максимальная тьма в троичной системе"),
    ('-', 0,  5,  "-5: разность — тоже дар"),
    ('*', 3,  3,  "+9: благодать воспроизводит себя"),
    ('*', -1, -1, "+1: отрицание отрицания есть утверждение"),
    ('*', 0,  13, "0: ноль умножает всё в ноль"),
    ('!', 7,  None, "-7: инверсия — зеркало"),
    ('&', 9,  -4, "AND(+9,-4) — наименьшее"),
    ('|', -9, 4,  "OR(-9,+4) — наибольшее"),
]

def run_demo(cpu):
    print("\n── Демонстрация тритного CPU ──────────────────────")
    for op, a, b, comment in DEMO_PROGRAM:
        res = cpu.compute(op, a, b)
        if res:
            b_str = f" {op} {b:+d}" if b is not None else ""
            print(f"  {a:+3d}{b_str} = {res['result']:+3d}  [{res['result_trit']}]  — {comment}")
            # Записываем в анамнезис
            try:
                b_part = f" {op} {b:+d}" if b is not None else ""
                requests.post(f"{ANAMNESIS}/gift", json={
                    "giver":"_fpga","receiver":"_koinon","type":"fpga-demo",
                    "text":f"FPGA demo: {a:+d}{b_part} = {res['result']:+d} — {comment}",
                    "weight":1,"meta":{"op":op,"a":a,"b":b,"result":res['result']}
                }, timeout=2)
            except: pass
        time.sleep(0.5)

# ── Основной цикл ─────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo', action='store_true', help='Режим демо')
    parser.add_argument('--once', action='store_true', help='Один опрос и выход')
    parser.add_argument('--port', default=UART_PORT)
    args = parser.parse_args()

    print(f"Тритный CPU Bridge")
    print(f"  UART: {args.port} @ {BAUD_RATE}")
    print(f"  Анамнезис: {ANAMNESIS}")

    try:
        cpu = TritCPU(args.port)
        print(f"  CPU online: A=0 B=0 C=0")
    except serial.SerialException as e:
        print(f"  Ошибка порта: {e}")
        print(f"  Попробуй: sudo modprobe ftdi_sio")
        sys.exit(1)

    if args.demo:
        run_demo(cpu)
        cpu.close()
        return

    seen_ids = set()
    print(f"\nОжидаю команд (type=fpga-command) в анамнезисе...")
    print(f"  Команды: curl -X POST {ANAMNESIS}/gift -H 'Content-Type: application/json'")
    print(f"           -d '{{\"giver\":\"user\",\"receiver\":\"_fpga\",\"type\":\"fpga-command\",")
    print(f"               \"text\":\"compute\",\"weight\":1,\"meta\":{{\"op\":\"+\",\"a\":5,\"b\":3}}}}'")
    print()

    while True:
        cmds = get_pending_commands(seen_ids)
        for act in cmds:
            seen_ids.add(act.get('id'))
            meta = act.get('meta', {})
            op = meta.get('op', '+')
            a  = int(meta.get('a', 0))
            b  = meta.get('b')
            if b is not None: b = int(b)

            print(f"  Команда #{act.get('id')}: {a:+d} {op} {b if b is not None else ''}")
            res = cpu.compute(op, a, b)
            if res:
                print(f"    → {res['result']:+d} [{res['result_trit']}]")
                ok = post_result(act, res)
                print(f"    → анамнезис: {'✓' if ok else '✗'}")

        if args.once:
            break
        time.sleep(POLL_INTERVAL)

    cpu.close()

if __name__ == "__main__":
    main()
