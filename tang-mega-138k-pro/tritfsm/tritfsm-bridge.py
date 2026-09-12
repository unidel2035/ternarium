#!/usr/bin/env python3
"""
tritfsm-bridge.py — Мост между тритным FSM (FPGA) и анамнезисом

FSM принимает трит-символы: '+' (дар), '-' (жертва), '0' (присутствие)
и отвечает пакетом: "K>P i:+ h:ZPK\r\n"

Переходы:
  KEN(-1) + PLR(+1) → PRS(0)   шаг к полноте
  PRS( 0) + PLR(+1) → PLR(+1)  достижение плеромы
  PLR(+1) + KEN(-1) → PRS(0)   кенозис из полноты
  PRS( 0) + KEN(-1) → KEN(-1)  шаг к кенозису

Запуск:
  python3 tritfsm-bridge.py          # daemon
  python3 tritfsm-bridge.py --once   # один опрос
  python3 tritfsm-bridge.py --demo   # богословская демонстрация
"""

import serial, requests, time, sys, re, argparse

UART_PORT     = "/dev/ttyUSB1"
BAUD_RATE     = 115200
ANAMNESIS     = "http://173.249.2.184:8089"
POLL_INTERVAL = 3

STATE_NAME = {'K': 'кенозис', 'Z': 'присутствие', 'P': 'плерома'}
STATE_SIGN = {'K': '-1', 'Z': '0', 'P': '+1'}

# ── UART ────────────────────────────────────────────────────────────────────

class TritFSM:
    def __init__(self, port=UART_PORT, baud=BAUD_RATE):
        self.ser = serial.Serial(port, baud, timeout=0.5)
        time.sleep(0.2)
        self.ser.reset_input_buffer()

    def send_trit(self, trit_char):
        """'+', '-', '0' → ответ FPGA или None"""
        self.ser.reset_input_buffer()
        self.ser.write(trit_char.encode())
        time.sleep(0.15)
        raw = self.ser.read(30).decode("ascii", "ignore").strip()
        # "K>P i:+ h:ZPK"
        m = re.match(r'([KZP])>([KZP]) i:([+\-0]) h:([KZP])([KZP])([KZP])', raw)
        if not m:
            return None
        return {
            'from':    m.group(1),
            'to':      m.group(2),
            'input':   m.group(3),
            'hist':    [m.group(4), m.group(5), m.group(6)],
            'raw':     raw,
        }

    def close(self):
        self.ser.close()

# ── Анамнезис ───────────────────────────────────────────────────────────────

def get_pending(seen_ids):
    try:
        r = requests.get(f"{ANAMNESIS}/tape", timeout=3)
        if r.status_code != 200: return []
        acts = r.json() if isinstance(r.json(), list) else r.json().get('acts', [])
        return [a for a in acts
                if a.get('type') == 'fsm-command'
                and a.get('id') not in seen_ids]
    except Exception as e:
        print(f"  [poll] {e}")
        return []

def post_transition(act, res):
    from_n = STATE_NAME.get(res['from'], res['from'])
    to_n   = STATE_NAME.get(res['to'],   res['to'])
    moved  = res['from'] != res['to']
    verb   = f"{from_n} → {to_n}" if moved else f"остался в {from_n}"
    text   = f"FSM: {verb}  (вход: '{res['input']}')"
    try:
        r = requests.post(f"{ANAMNESIS}/gift", json={
            "giver":    "_fpga",
            "receiver": "_koinon",
            "type":     "fsm-state",
            "text":     text,
            "weight":   1,
            "meta": {
                "fsm_cmd_id": act.get('id'),
                "from":   res['from'],
                "to":     res['to'],
                "input":  res['input'],
                "hist":   res['hist'],
                "moved":  moved,
            }
        }, timeout=3)
        return r.status_code == 200
    except Exception as e:
        print(f"  [post] {e}")
        return False

# ── Демо ────────────────────────────────────────────────────────────────────

DEMO = [
    ('+', "дар приходит — шаг к плероме"),
    ('+', "дар усиливается — ещё шаг"),
    ('+', "плерома — предел полноты"),
    ('0', "пауза — Дух присутствует"),
    ('-', "жертва — шаг к кенозису"),
    ('-', "углубление кенозиса"),
    ('-', "предел самоумаления"),
    ('0', "ноль — не пустота, а связь"),
    ('+', "воскресение — шаг из кенозиса"),
    ('+', "возвращение к полноте"),
]

def run_demo(fsm):
    print("\n── Богословская демонстрация тритного FSM ───────────────")
    for trit, comment in DEMO:
        res = fsm.send_trit(trit)
        if res:
            arrow = "→" if res['from'] != res['to'] else "="
            print(f"  '{trit}'  {res['from']} {arrow} {res['to']}  — {comment}")
            try:
                requests.post(f"{ANAMNESIS}/gift", json={
                    "giver": "_fpga", "receiver": "_koinon", "type": "fsm-demo",
                    "text": f"FSM demo: '{trit}' → {res['from']}>{res['to']} — {comment}",
                    "weight": 1, "meta": {"from": res['from'], "to": res['to'], "input": trit}
                }, timeout=2)
            except: pass
        else:
            print(f"  '{trit}'  [нет ответа]")
        time.sleep(0.6)

# ── Главный цикл ────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--port', default=UART_PORT)
    args = parser.parse_args()

    print(f"Тритный FSM Bridge")
    print(f"  UART: {args.port} @ {BAUD_RATE}")
    print(f"  Анамнезис: {ANAMNESIS}")

    try:
        fsm = TritFSM(args.port)
        print(f"  FSM online (начало: PRS = присутствие)")
    except Exception as e:
        print(f"  Ошибка: {e}")
        sys.exit(1)

    if args.demo:
        run_demo(fsm)
        fsm.close()
        return

    seen = set()
    print(f"\nОжидаю fsm-command в анамнезисе...")

    while True:
        for act in get_pending(seen):
            seen.add(act.get('id'))
            trit = act.get('meta', {}).get('trit', '0')
            if trit not in ('+', '-', '0'):
                print(f"  [skip] неверный трит: {trit!r}")
                continue
            print(f"  #{act.get('id')}: trit='{trit}'")
            res = fsm.send_trit(trit)
            if res:
                print(f"    → {res['from']} > {res['to']}  hist:{res['hist']}")
                ok = post_transition(act, res)
                print(f"    → анамнезис: {'✓' if ok else '✗'}")
            else:
                print(f"    → [нет ответа от FPGA]")

        if args.once:
            break
        time.sleep(POLL_INTERVAL)

    fsm.close()

if __name__ == "__main__":
    main()
