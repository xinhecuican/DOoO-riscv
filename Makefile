
LOG_PATH=log/
SEED=1168
S=0
E=2000
WB=0
WE=0
I ?= utils/NEMU/ready-to-run/microbench.bin
CONFIG ?= ""
CLK_FREQ_MHZ ?= 100
CLK_PERIOD = $(shell expr 1000 / ${CLK_FREQ_MHZ})
TOP ?= Soc
SYNTH_V ?= build/${TOP}.synth.v
SYNTH_FIX_V ?= build/${TOP}.synth.fix.v
SDC_FILE ?= config/sdc/Soc.sdc
TIMING_RPT ?= build/${TOP}.rpt
SYNTH_LOG = ${LOG_PATH}synth
FOUNDRY ?= sky130
DESIGN_CONFIG = ../../config/config.mk

export CLK_FREQ_MHZ
export SDC_FILE

SRC = $(shell find src/utils -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/core -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/soc -name "*.v" -or -name "*.sv" -or -name "*.svh")

WITH_DRAMSIM3 := 1
EMU_TRACE := 1
EMU_THREADS := 0
TRACE_ARGS := 
ENABLE_FORK := 0
ENABLE_DIFF := 1
DIFF_ARGS :=

export EMU_THREADS
ifeq ($(WITH_DRAMSIM3),1)
	export WITH_DRAMSIM3
	DEFINES += DRAMSIM3=ON;
endif
ifeq ($(EMU_TRACE), 1)
	export EMU_TRACE
	TRACE_ARGS = --dump-wave
endif
ifeq ($(ENABLE_FORK), 1)
	TRACE_ARGS += --enable-fork
endif
ifeq ($(ENABLE_DIFF), 1)
	DIFF_ARGS := --diff=utils/NEMU/build/riscv64-nemu-interpreter-so
else
	DIFF_ARGS := --no-diff
endif

DEFINES += CLK_FREQ=${CLK_FREQ_MHZ};CLK_PERIOD=${CLK_PERIOD};

emu:
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "${DEFINES}"
	make -C utils/difftest emu -j `nproc`

emu-run: emu
	mkdir -p $(LOG_PATH)
	build/emu -i "${I}" ${DIFF_ARGS} -s 1168 -b ${S} -e ${E} -B $(WB) -E $(WE) ${TRACE_ARGS} --log-path=${LOG_PATH}

convert: build/${TOP}/${TOP}.v
build/${TOP}/${TOP}.v: ${SRC}
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "DIFFTEST=OFF;ENABLE_LOG=OFF;${DEFINES}"
	mkdir -p build/${TOP}
	sv2v -v --write=build/${TOP} -I=src/defines -I=build --top=Soc ${SRC}

# VSRC := $(shell test -d build/v && find build/v -name "*.v" -or -name "*.sv" -or -name "*.svh")
# VSRC_PREFIX = $(patsubst %,../../%,$(VSRC))
yosys: ${SYNTH_V}
${SYNTH_V}: scripts/gen_netlist.tcl build/${TOP}/${TOP}.v
	mkdir -p ${SYNTH_LOG}
	env CLK_FREQ=${CLK_FREQ_MHZ} FOUNDRY=${FOUNDRY} LOG_DIR=${SYNTH_LOG} SYNTH=${SYNTH_V} TOP=${TOP} yosys -c scripts/gen_netlist.tcl > ${SYNTH_LOG}/yosys_build.log

# fix-fanout: ${SYNTH_FIX_V}
# ${SYNTH_FIX_V}: scripts/fix-fanout.tcl ${SDC_FILE} ${SYNTH_V}
# 	utils/iEDA/bin/iEDA -script $^ ${TOP} $@ ${FOUNDRY} 2>&1 | tee ${SYNTH_LOG}/fix-fanout.log

sta: ${TIMING_RPT}
${TIMING_RPT}: scripts/opensta.tcl ${SDC_FILE} ${SYNTH_V}
	env CLK_FREQ_MHZ=${CLK_FREQ_MHZ} FOUNDRY=${FOUNDRY} SYNTH=${SYNTH_V} SDC_FILE=${SDC_FILE} TOP=${TOP} LOG_DIR=${SYNTH_LOG} sta -exit -threads 4 scripts/opensta.tcl > ${SYNTH_LOG}/sta.log

flow: build/${TOP}/${TOP}.v
	make -C utils/flow DESIGN_CONFIG=${DESIGN_CONFIG}

floorplan: 
	make -C utils/flow floorplan DESIGN_CONFIG=${DESIGN_CONFIG}

flow_command:
	make -C utils/flow ${FLOW_COMMAND} DESIGN_CONFIG=${DESIGN_CONFIG}

clean_flow:
	make -C utils/flow clean_all DESIGN_CONFIG=${DESIGN_CONFIG}

clean_emu:
	rm -rf build/emu-compile
	rm -f build/emu
	rm -f build/time.log

clean:
	make -C utils/difftest clean
