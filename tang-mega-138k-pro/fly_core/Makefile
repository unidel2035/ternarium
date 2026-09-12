# fly_core — троичный матvec среза коннектома мухи
# hex-артефакты генерирует tools/fly/export_slice.py -> sim/

SIMDIR = sim

sim:
	cd $(SIMDIR) && iverilog -g2005 -I . -o fly_sim.vvp ../fly_matvec.v ../tb_fly_matvec.v && vvp fly_sim.vvp

lint:
	iverilog -g2005 -I $(SIMDIR) -t null fly_matvec.v

clean:
	rm -f $(SIMDIR)/fly_sim.vvp

.PHONY: sim lint clean
