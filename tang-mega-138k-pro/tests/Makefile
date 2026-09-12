# Makefile для тестбенчей FPGA модулей
#
# Использование:
#   make            — собрать и запустить все тесты
#   make tritseraphim — только Серафим
#   make failsafe   — только failsafe
#   make clean      — убрать вывод

IVERILOG = iverilog
VVP      = vvp

OUT = build

.PHONY: all clean tritseraphim failsafe

all: tritseraphim failsafe

$(OUT):
	@mkdir -p $(OUT)

tritseraphim: $(OUT)
	$(IVERILOG) -o $(OUT)/tritseraphim_tb tritseraphim_tb.v ../tritgift/tritseraphim.v
	$(VVP) $(OUT)/tritseraphim_tb

failsafe: $(OUT)
	$(IVERILOG) -o $(OUT)/failsafe_tb failsafe_tb.v ../stormbird/failsafe.v
	$(VVP) $(OUT)/failsafe_tb

clean:
	rm -rf $(OUT)
