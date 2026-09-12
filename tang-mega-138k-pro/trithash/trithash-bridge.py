#!/usr/bin/env python3
"""
trithash-bridge.py — Тритный хеш текстов через FPGA

FPGA вычисляет 3-тритовый GF(3) хеш в кремнии.
27 возможных значений — достаточно для контрольной суммы дара.

Использование:
  python3 trithash-bridge.py "текст"       # хеш одного текста
  python3 trithash-bridge.py --stdin       # читать строки из stdin
  python3 trithash-bridge.py --daemon      # слушать анамнезис
  python3 trithash-bridge.py --demo        # 10 богословских текстов
"""

import serial, time, sys, argparse, requests

UART_PORT = "/dev/ttyUSB1"
BAUD_RATE = 115200
ANAMNESIS = "http://173.249.2.184:8089"

# ── GF(3) хеш в Python (для верификации) ─────────────────────────────────

GF3 = {
    (0,0):1, (0,1):0, (0,2):2,   # -1+x = +1,0,-1 (закодировано как 0,1,2)
    (1,0):0, (1,1):1, (1,2):2,
    (2,0):2, (2,1):2, (2,2):0,
}
# Нет, проще: encode {-1→0, 0→1, +1→2}, add = (a+b)%3, decode

def trit_enc(x):  # 2'b → int_enc
    return {0b00: 0, 0b01: 1, 0b10: 2}.get(x, 1)

def trit_dec(x):  # int_enc → {-1,0,+1}
    return x - 1  # 0→-1, 1→0, 2→+1

def byte_trit(b):
    lo  = b & 0b11
    hi  = (b >> 6) & 0b11
    mid = (b >> 3) & 0b11
    fold = lo ^ hi ^ mid
    if fold == 0b11: fold = 0b00
    return fold  # 2'b encoding

def py_hash(text: str) -> tuple:
    """Вычислить тритный хеш строки (Python-верификация)"""
    h = [1, 1, 1]  # [h0, h1, h2] в int_enc (0=KEN, 1=PRS, 2=PLR)
    for ch in text.encode('utf-8'):
        t = byte_trit(ch)
        t_enc = trit_enc(t)
        new_h0 = (h[1] + t_enc) % 3
        new_h1 = (h[2] + h[0]) % 3
        new_h2 = h[1]
        h = [new_h0, new_h1, new_h2]
    return tuple(trit_dec(x) for x in reversed(h))  # h2, h1, h0

def trit_str(t3):
    return ''.join({-1:'-', 0:'0', 1:'+'}[x] for x in t3)

# ── UART ─────────────────────────────────────────────────────────────────

class TritHash:
    def __init__(self, port=UART_PORT, baud=BAUD_RATE):
        self.ser = serial.Serial(port, baud, timeout=0.5)
        time.sleep(0.2)
        self.ser.reset_input_buffer()
        # Сбросить хеш
        self.ser.write(b'r')
        time.sleep(0.05)
        self.ser.reset_input_buffer()

    def hash_text(self, text: str) -> str | None:
        """Отправить текст, получить хеш "H:+0-" """
        self.ser.reset_input_buffer()
        # Сброс
        self.ser.write(b'r')
        time.sleep(0.05)
        # Данные
        self.ser.write(text.encode('utf-8', 'replace'))
        time.sleep(0.05)
        # Терминатор — вывести хеш
        self.ser.write(b'.')
        time.sleep(0.15)
        raw = self.ser.read(20).decode('ascii', 'ignore').strip()
        # Ищем "H:XXX"
        import re
        m = re.search(r'H:([+\-0]{3})', raw)
        return m.group(1) if m else None

    def close(self):
        self.ser.close()

# ── Демо ─────────────────────────────────────────────────────────────────

DEMO_TEXTS = [
    "дар",
    "кенозис",
    "плерома",
    "Бог есть любовь",
    "отрицание отрицания есть утверждение",
    "ноль умножает всё в ноль",
    "слово стало плотью",
    "kenosis",
    "perichoresis",
    "Дионисий",
]

def run_demo(h):
    print("\n── Тритный хеш: богословские тексты ─────────────────────────")
    print(f"{'Текст':<40} {'FPGA':>6} {'Python':>6} {'OK':>4}")
    print("─" * 62)
    for text in DEMO_TEXTS:
        fpga = h.hash_text(text)
        py   = trit_str(py_hash(text))
        match = '✓' if fpga == py else '✗'
        print(f"  {text:<38} {fpga or '???':>6} {py:>6} {match:>4}")
        try:
            requests.post(f"{ANAMNESIS}/gift", json={
                "giver": "_fpga", "receiver": "_koinon", "type": "trit-hash",
                "text": f"hash({text!r}) = [{fpga or '???'}]",
                "weight": 1,
                "meta": {"text": text, "hash": fpga, "py_hash": py}
            }, timeout=2)
        except: pass
        time.sleep(0.3)

# ── Анамнезис-демон ───────────────────────────────────────────────────────

def run_daemon(h):
    seen = set()
    print("Жду hash-command в анамнезисе...")
    while True:
        try:
            tape = requests.get(f"{ANAMNESIS}/tape", timeout=3).json()
            acts = tape if isinstance(tape, list) else tape.get('acts', [])
            for act in acts:
                if act.get('type') == 'hash-command' and act.get('id') not in seen:
                    seen.add(act.get('id'))
                    text = act.get('meta', {}).get('text', act.get('text', ''))
                    print(f"  #{act['id']}: hash({text!r})")
                    result = h.hash_text(text)
                    print(f"    → [{result}]")
                    if result:
                        requests.post(f"{ANAMNESIS}/gift", json={
                            "giver": "_fpga", "receiver": "_koinon",
                            "type": "trit-hash",
                            "text": f"hash({text!r}) = [{result}]",
                            "weight": 1,
                            "meta": {"cmd_id": act['id'], "text": text, "hash": result}
                        }, timeout=3)
        except Exception as e:
            print(f"  [err] {e}")
        time.sleep(3)

# ── main ──────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('text', nargs='?', help='Текст для хеширования')
    parser.add_argument('--demo',   action='store_true')
    parser.add_argument('--stdin',  action='store_true')
    parser.add_argument('--daemon', action='store_true')
    parser.add_argument('--port', default=UART_PORT)
    parser.add_argument('--verify', action='store_true', help='Только Python (без FPGA)')
    args = parser.parse_args()

    if args.verify:
        texts = DEMO_TEXTS if args.demo else ([args.text] if args.text else [])
        for t in texts:
            print(f"[{trit_str(py_hash(t))}]  {t}")
        return

    print(f"Тритный хеш FPGA  UART:{args.port}  Анамнезис:{ANAMNESIS}")
    try:
        h = TritHash(args.port)
    except Exception as e:
        print(f"Ошибка UART: {e}")
        sys.exit(1)

    if args.demo:
        run_demo(h)
    elif args.daemon:
        run_daemon(h)
    elif args.stdin:
        for line in sys.stdin:
            line = line.strip()
            if line:
                result = h.hash_text(line)
                py = trit_str(py_hash(line))
                print(f"[{result or '???'}]  {line}  (py:[{py}])")
    elif args.text:
        result = h.hash_text(args.text)
        py = trit_str(py_hash(args.text))
        print(f"FPGA: [{result or '???'}]")
        print(f"  py: [{py}]")
        print(f"  27 состояний: ваш текст → одно из них")
    else:
        parser.print_help()

    h.close()

if __name__ == "__main__":
    main()
