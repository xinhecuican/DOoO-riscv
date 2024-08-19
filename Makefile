
LOG_PATH=log/
SEED=1168
S=0
E=2000
WB=0
WE=0
I ?= utils/NEMU/ready-to-run/microbench.bin
CONFIG ?= ""

SRC = $(shell find src/utils -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/core -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/soc -name "*.v" -or -name "*.sv" -or -name "*.svh")

emu:
	python scripts/parseDef.py -b build/ -p ${CONFIG}
	make -C utils/difftest emu -j `nproc`

emu-run: emu
	mkdir -p $(LOG_PATH)
	build/emu -i "${I}" --diff=utils/NEMU/build/riscv64-nemu-interpreter-so -s 1168 -b ${S} -e ${E} -B $(WB) -E $(WE) --dump-wave --log-path=${LOG_PATH}

convert:
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "DIFFTEST=OFF;ENABLE_LOG=OFF"
	mkdir -p build/v
	sv2v --write=build/v -I=src/defines -I=build --top=Soc -v ${SRC}

yosys: VSRC := $(shell find build/v -name "*.v" -or -name "*.sv" -or -name "*.svh")

yosys: convert
	yosys -p "read_verilog ${VSRC}; hierarchy -top Soc; proc; fsm; opt; memory; opt; techmap; opt; write_verilog build/synth.v"

clean:
	make -C utils/difftest clean
