
LOG_PATH=log/
SEED=1168
S=0
E=2000
WB=0
WE=0
T=0
CYCLES=0
D=0
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
TESTBENCH = fadd_tb

export CLK_FREQ_MHZ
export SDC_FILE

SRC = $(shell find src/utils -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/core -name "*.v" -or -name "*.sv" -or -name "*.svh")
SRC += $(shell find src/soc -name "*.v" -or -name "*.sv" -or -name "*.svh")

WITH_DRAMSIM3 := 1
EMU_TRACE := fst
EMU_THREADS := 4
TRACK_INST := 0
TRACE_ARGS := -T ${TRACK_INST}
ENABLE_FORK := 0
ENABLE_DIFF := 1
LLVM := 0
EMU_ARGS :=

export EMU_THREADS
ifeq ($(WITH_DRAMSIM3),1)
	export WITH_DRAMSIM3
	DEFINES += DRAMSIM3=ON;
endif
ifneq (,$(filter $(EMU_TRACE),1 vcd VCD fst FST))
	export EMU_TRACE
	TRACE_ARGS += --dump-wave
endif
ifneq ($(CYCLES), 0)
	TRACE_ARGS += -C $(CYCLES)
endif
ifneq ($(D), 0)
	TRACE_ARGS += -D $(D)
endif
ifeq ($(ENABLE_FORK), 1)
	TRACE_ARGS += --enable-fork
endif
ifeq ($(ENABLE_DIFF), 1)
	TRACE_ARGS += --diff=utils/NEMU/build/riscv64-nemu-interpreter-so
else
	TRACE_ARGS += --no-diff
endif
ifeq ($(LLVM),1)
	EMU_ARGS += PGO_WORKLOAD=`realpath config/bench/coremark.riscv.bin` LLVM_PROFDATA=llvm-profdata
endif

DEFINES += CLK_FREQ=${CLK_FREQ_MHZ};CLK_PERIOD=${CLK_PERIOD};

emu:
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "${DEFINES}"
	make -C utils/difftest emu -j `nproc` $(EMU_ARGS)

emu-run: emu
	mkdir -p $(LOG_PATH)
	build/emu -i "${I}" -s 1168 -b ${S} -e ${E} -B $(WB) -E $(WE) ${TRACE_ARGS} --log-path=${LOG_PATH}

sbi:
	make -C utils/opensbi ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- PLATFORM_RISCV_XLEN=32 PLATFORM=generic FW_PAYLOAD_PATH=${CURDIR}/utils/rv-linux/arch/riscv/boot/Image FW_FDT_PATH=${CURDIR}/utils/opensbi/dts/custom.dtb FW_PAYLOAD_OFFSET=0x400000

convert: build/${TOP}/${TOP}.v
build/${TOP}/${TOP}.v: ${SRC}
	python scripts/parseDef.py -b build/ -p ${CONFIG} -e "DIFFTEST=OFF;ENABLE_LOG=OFF;${DEFINES}"
	mkdir -p build/${TOP}
	sv2v -v --write=build/${TOP} -I=src/defines -I=build --top=Soc ${SRC}

vcs:
	vcs -sverilog +v2k -Mupdate -Mdir=build/ -timescale=1ns/1ns -debug_access+all +warn=noUII-L -cm line+cond+fsm+branch+tgl -cm_name ${TESTBENCH} -cm_dir build/${TESTBENCH}.vdb +define+DUMP_VPD +define+COVERAGE +vpdfile+build/${TESTBENCH}.vpd -cpp g++-4.8 -cc gcc-4.8 -LDFLAGS -Wl,-no-as-needed -f testbench/${TESTBENCH}.f -top ${TESTBENCH} -o build/${TESTBENCH}

vcs_sim:
	build/${TESTBENCH} +vpdfile+build/${TESTBENCH}.vpd -cm line+cond+fsm+branch+tgl -cm_name ${TESTBENCH} -cm_dir build/${TESTBENCH}.vdb -l build/${TESTBENCH}.log

vcs_report:
	urg -dir build/${TESTBENCH}.vdb -report build/${TESTBENCH}_report

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
