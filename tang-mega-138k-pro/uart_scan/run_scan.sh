#!/bin/bash
export PATH=$HOME/oss-cad-suite/bin:$PATH
cd /home/unidel/tang/tang-mega-138k-pro/uart_scan
B=$1
python3 gencand.py $B >/dev/null
make >/tmp/scanbuild.log 2>&1
if grep -qiE "error|not found" /tmp/scanbuild.log; then
  echo "BUILD-ERR:"; grep -iE "error|not found" /tmp/scanbuild.log | head -3; exit 1
fi
timeout 120 openFPGALoader -b tangmega138k build/uart_scan.fs >/tmp/scanflash.log 2>&1
grep -q DONE /tmp/scanflash.log && echo "flashed" || { echo "FLASH-ERR"; tail -3 /tmp/scanflash.log; exit 1; }
python3 - <<PY
import serial,time,threading
names=open("batch_names.txt").read().strip().split(",")
s=serial.Serial('/dev/ttyUSB1',115200,timeout=1.0); time.sleep(0.3); s.reset_input_buffer()
stop=[False]
def flood():
    while not stop[0]: s.write(b'\x55'*64); time.sleep(0.001)
threading.Thread(target=flood,daemon=True).start()
time.sleep(0.7); data=s.read(5000); stop[0]=True; time.sleep(0.2); s.close()
mask=0;fr=0
for i in range(len(data)-2):
    if data[i]==0xAA: mask|=data[i+1]|(data[i+2]<<8); fr+=1
hit=[names[i] for i in range(len(names)) if mask&(1<<i)]
print(f"batch=$B кадров={fr} маска={mask:016b}")
print(">>> RX-ПИН:", hit if hit else "нет в батче")
PY
