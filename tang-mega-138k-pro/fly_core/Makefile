TOP   = fly_splash
FILES = fly_splash.v
CST   = fly_splash.cst

include ../Makefile.common

# ── fly_brain: живой мозг (битстрим) ────────────────────────────────────
brain:
	$(MAKE) TOP=fly_brain FILES=fly_brain.v CST=fly_brain.cst OUT=build_brain bitstream

flash-brain: brain
	$(OPENFPGA) --board $(BOARD) -f build_brain/fly_brain.fs

# ── fly_brain: живой мозг (симуляция) ───────────────────────────────────
sim-brain:
	cd $(SIMDIR) && iverilog -g2005 -DFLY_SIM -I .. -o fly_brain.vvp ../fly_brain.v ../tb_fly_brain.v && vvp fly_brain.vvp
	@diff $(SIMDIR)/captured.txt $(SIMDIR)/expected_uart.txt > /dev/null && echo "PASS: UART-отчёты совпали с golden" || (echo "FAIL: см. diff:"; diff $(SIMDIR)/captured.txt $(SIMDIR)/expected_uart.txt | head; exit 1)

expected:
	cd $(SIMDIR) && ~/fly-connectome/.venv/bin/python /mnt/c/Users/unide/ternarium/tools/fly/brain_sim.py /mnt/c/Users/unide/fly-connectome/data --out expected_uart.txt

.PHONY: sim-brain expected
