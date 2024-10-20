export OPENROAD_EXE=$(shell command -v openroad)
export YOSYS_EXE=$(shell command -v yosys)

export DESIGN_NICKNAME = DOoO-riscv
export DESIGN_NAME = Soc
export PLATFORM    = sky130hd

export VERILOG_FILES = $(sort $(wildcard ../../build/Soc/*.v))
export SDC_FILE      = ../../config/sdc/Soc.sdc
export ABC_CLOCK_PERIOD_IN_PS = 20000

# export SYNTH_HIERARCHICAL = 1
export RTLMP_FLOW = 1

export RTLMP_BOUNDARY_WT = 0

export CORE_UTILIZATION = 40
export TNS_END_PERCENT = 100

export REMOVE_ABC_BUFFERS = 1

export MEMORY_BRAM_MAP_FILE = ../../config/sky130/bram.txt
export MEMORY_TECH_MAP_FILE = ../../config/sky130/bram_map.v
export SYNTH_MEMORY_MAX_BITS = 1048576

sram_dir = platforms/sky130ram
1r1w_base = sky130_sram_1r1w0rw_
1r1rw_base = sky130_sram_1r0w1rw_
IO_DIR       = ./platforms/sky130io
export ADDITIONAL_LIBS = ${sram_dir}/${1r1w_base}4x512/${1r1w_base}4x512_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}11x512/${1r1w_base}11x512_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}32x64/${1r1w_base}32x64_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}32x64_8/${1r1w_base}32x64_8_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}54x32/${1r1w_base}54x32_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}60x32/${1r1w_base}60x32_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}68x256/${1r1w_base}68x256_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}156x32/${1r1w_base}156x32_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}184x64_23/${1r1w_base}184x64_23_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}256x64_8/${1r1w_base}256x64_8_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1rw_base}184x64_23/${1r1rw_base}184x64_23_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}256x64_32/${1r1w_base}256x64_32_TT_1p8V_25C.lib

export ADDITIONAL_LEFS = ${sram_dir}/${1r1w_base}4x512/${1r1w_base}4x512.lef \
						 ${sram_dir}/${1r1w_base}11x512/${1r1w_base}11x512.lef \
						 ${sram_dir}/${1r1w_base}32x64/${1r1w_base}32x64.lef \
						 ${sram_dir}/${1r1w_base}32x64_8/${1r1w_base}32x64_8.lef \
						 ${sram_dir}/${1r1w_base}54x32/${1r1w_base}54x32.lef \
						 ${sram_dir}/${1r1w_base}60x32/${1r1w_base}60x32.lef \
						 ${sram_dir}/${1r1w_base}68x256/${1r1w_base}68x256.lef \
						 ${sram_dir}/${1r1w_base}156x32/${1r1w_base}156x32.lef \
						 ${sram_dir}/${1r1w_base}184x64_23/${1r1w_base}184x64_23.lef \
						 ${sram_dir}/${1r1w_base}256x64_8/${1r1w_base}256x64_8.lef \
						 ${sram_dir}/${1r1rw_base}184x64_23/${1r1rw_base}184x64_23.lef \
						 ${sram_dir}/${1r1w_base}256x64_32/${1r1w_base}256x64_32.lef

export ADDITIONAL_GDS = ${sram_dir}/${1r1w_base}4x512/${1r1w_base}4x512.gds \
	${sram_dir}/${1r1w_base}11x512/${1r1w_base}11x512.gds \
	${sram_dir}/${1r1w_base}32x64/${1r1w_base}32x64.gds \
	${sram_dir}/${1r1w_base}32x64_8/${1r1w_base}32x64_8.gds \
	${sram_dir}/${1r1w_base}54x32/${1r1w_base}54x32.gds \
	${sram_dir}/${1r1w_base}60x32/${1r1w_base}60x32.gds \
	${sram_dir}/${1r1w_base}68x256/${1r1w_base}68x256.gds \
	${sram_dir}/${1r1w_base}156x32/${1r1w_base}156x32.gds \
	${sram_dir}/${1r1w_base}184x64_23/${1r1w_base}184x64_23.gds \
	${sram_dir}/${1r1w_base}256x64_8/${1r1w_base}256x64_8.gds \
	${sram_dir}/${1r1rw_base}184x64_23/${1r1rw_base}184x64_23.gds \
	${sram_dir}/${1r1w_base}256x64_32/${1r1w_base}256x64_32.gds
# export MACRO_PLACE_CHANNEL  = 60 60
export MACRO_PLACE_HALO = 40 40

export PDN_TCL = ../../config/sky130/pdn.tcl
