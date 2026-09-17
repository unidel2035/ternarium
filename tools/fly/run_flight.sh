#!/bin/bash
# run_flight.sh — пересоздать обёртку mavproxy.py и запустить SITL-полёт с захватом.
set -x
mkdir -p ~/.local/bin
printf '#!/bin/bash\nexec python3 -m MAVProxy.mavproxy "$@"\n' > ~/.local/bin/mavproxy.py
chmod +x ~/.local/bin/mavproxy.py
export PATH="$HOME/.local/bin:$PATH"
which mavproxy.py || exit 1

pkill -x arduplane 2>/dev/null
sleep 2

cd ~/fly-build/tang-mega-138k-pro/flight || exit 1
cp wing_mission.txt /tmp/wing.txt

(
  sleep 60
  echo "param set ARMING_CHECK 0"
  echo "param set FS_GCS_ENA 0"
  echo "param set FS_LONG_FS_ACTION 0"
  echo "param set FS_THR_FS_ACTION 0"
  sleep 2
  echo "wp load /tmp/wing.txt"
  sleep 3
  echo "arm throttle"
  sleep 2
  echo "mode auto"
  sleep 400
  echo "exit"
) | timeout 500 python3 ~/ardupilot/Tools/autotest/sim_vehicle.py -v ArduPlane -f plane --custom-location=-35.363262,149.165237,584,0 --speedup=2 --out=udpout:127.0.0.1:14560 > sim.log 2>&1 &
SIM_PID=$!

sleep 30
~/fly-connectome/.venv/bin/python sitl_capture.py 14560 300 telemetry.csv
echo "CAPTURE_DONE"
wait $SIM_PID
echo "ALL_DONE"
tail -5 sim.log
