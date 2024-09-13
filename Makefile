
LOG_PATH=log/
SEED=1168
S=0
E=2000
WB=0
WE=0
I ?= utils/NEMU/ready-to-run/microbench.bin
CONFIG ?= ""
CLK_FREQ ?= 500
CLK_PERIOD = $(shell expr 1000 / ${CLK_FREQ})
SYNTH_V ?= build/synth.v
SYNTH_FIX_V ?= build/synth.fix.v
SDC_FILE ?= config/sdc/Soc.sdc
TIMING_RPT ?= build/Soc.rpt
SYNTH_LOG = ${LOG_PATH}synth
FOUNDRY ?= sky130

export CLK_FREQ
export SDC_FILE

SRC = $(shell find src/utils -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/core -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/soc -name "*.v" -or -name "*.sv" -or -name "*.svh")

WITH_DRAMSIM3 := 1


ifeq ($(WITH_DRAMSIM3),1)
	export WITH_DRAMSIM3
	DEFINES += DRAMSIM3=ON;
endif
DEFINES += CLK_FREQ=${CLK_FREQ};CLK_PERIOD=${CLK_PERIOD};

emu:
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "${DEFINES}"
	make -C utils/difftest emu -j `nproc`

emu-run: emu
	mkdir -p $(LOG_PATH)
	build/emu -i "${I}" --diff=utils/NEMU/build/riscv64-nemu-interpreter-so -s 1168 -b ${S} -e ${E} -B $(WB) -E $(WE) --dump-wave --log-path=${LOG_PATH}

convert: build/v/Soc.v
build/v/Soc.v: ${SRC}
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "DIFFTEST=OFF;ENABLE_LOG=OFF;${DEFINES}"
	mkdir -p build/v
	sv2v -v --write=build/v -I=src/defines -I=build --top=Soc ${SRC}

# VSRC := $(shell test -d build/v && find build/v -name "*.v" -or -name "*.sv" -or -name "*.svh")
# VSRC_PREFIX = $(patsubst %,../../%,$(VSRC))
yosys: ${SYNTH_V}
${SYNTH_V}: build/v/Soc.v scripts/gen_netlist.tcl
	mkdir -p ${SYNTH_LOG}
	env CLK_FREQ=${CLK_FREQ} FOUNDRY=${FOUNDRY} LOG_DIR=${SYNTH_LOG} SYNTH=${SYNTH_V} yosys -c scripts/gen_netlist.tcl > ${SYNTH_LOG}/yosys_build.log

fix-fanout: ${SYNTH_FIX_V}
${SYNTH_FIX_V}: scripts/fix-fanout.tcl ${SDC_FILE} ${SYNTH_V}
	utils/iEDA/bin/iEDA -script $^ Soc $@ ${FOUNDRY} 2>&1 | tee ${SYNTH_LOG}/fix-fanout.log

sta: ${TIMING_RPT}
${TIMING_RPT}: scripts/sta.tcl ${SDC_FILE} ${SYNTH_FIX_V}
	utils/iEDA/bin/iEDA -script $^ Soc ${SYNTH_LOG} ${FOUNDRY} 2>&1 | tee ${SYNTH_LOG}/sta.log

clean:
	make -C utils/difftest clean
