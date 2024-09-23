export OPENROAD_EXE=$(shell command -v openroad)
export YOSYS_EXE=$(shell command -v yosys)
export DESIGN_NICKNAME = test
export DESIGN_NAME = test
export PLATFORM    = sky130hd

export VERILOG_FILES = ../../testbench/sram_map/test.sv ../../build/v/MPRAM.v ../../build/v/MPREG.v ../../build/v/MPRAMInner.v ../../build/v/SPRAM.v
export SDC_FILE      = ../../config/sdc/Soc.sdc

# export SYNTH_HIERARCHICAL = 1
export RTLMP_FLOW = 1

# export RTLMP_BOUNDARY_WT = 0

export CORE_UTILIZATION = 40
export PLACE_DENSITY_LB_ADDON = 0.2
export TNS_END_PERCENT = 100

export REMOVE_ABC_BUFFERS = 1

export MEMORY_BRAM_MAP_FILE = ../../config/sky130/bram.txt
export MEMORY_TECH_MAP_FILE = ../../config/sky130/bram_map.v
export SYNTH_MEMORY_MAX_BITS = 1048576

sram_dir = platforms/sky130ram
1r1w_base = sky130_sram_1r1w0rw_
IO_DIR       = ./platforms/sky130io
export ADDITIONAL_LIBS = ${sram_dir}/${1r1w_base}4x512/${1r1w_base}4x512_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}11x512/${1r1w_base}11x512_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}32x64/${1r1w_base}32x64_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}32x64_8/${1r1w_base}32x64_8_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}54x32/${1r1w_base}54x32_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}60x32/${1r1w_base}60x32_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}68x256/${1r1w_base}68x256_TT_1p8V_25C.lib \
						 ${sram_dir}/${1r1w_base}156x32/${1r1w_base}156x32_TT_1p8V_25C.lib \
						 platforms/sky130io/lib/sky130_dummy_io.lib

export ADDITIONAL_LEFS = $(IO_DIR)/lef/sky130_ef_io__gpiov2_pad_wrapped.lef \
                         $(IO_DIR)/lef/sky130_ef_io__com_bus_slice_10um.lef \
                         $(IO_DIR)/lef/sky130_ef_io__com_bus_slice_1um.lef \
                         $(IO_DIR)/lef/sky130_ef_io__com_bus_slice_20um.lef \
                         $(IO_DIR)/lef/sky130_ef_io__com_bus_slice_5um.lef \
                         $(IO_DIR)/lef/sky130_ef_io__corner_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vccd_hvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vccd_lvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vdda_hvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vdda_lvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vddio_hvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vddio_lvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vssa_hvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vssa_lvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vssd_hvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vssd_lvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vssio_hvc_pad.lef \
                         $(IO_DIR)/lef/sky130_ef_io__vssio_lvc_pad.lef \
						 ${sram_dir}/${1r1w_base}4x512/${1r1w_base}4x512.lef \
						 ${sram_dir}/${1r1w_base}11x512/${1r1w_base}11x512.lef \
						 ${sram_dir}/${1r1w_base}32x64/${1r1w_base}32x64.lef \
						 ${sram_dir}/${1r1w_base}32x64_8/${1r1w_base}32x64_8.lef \
						 ${sram_dir}/${1r1w_base}54x32/${1r1w_base}54x32.lef \
						 ${sram_dir}/${1r1w_base}60x32/${1r1w_base}60x32.lef \
						 ${sram_dir}/${1r1w_base}68x256/${1r1w_base}68x256.lef \
						 ${sram_dir}/${1r1w_base}156x32/${1r1w_base}156x32.lef

export ADDITIONAL_GDS = ${sram_dir}/${1r1w_base}4x512/${1r1w_base}4x512.gds \
	${sram_dir}/${1r1w_base}11x512/${1r1w_base}11x512.gds \
	${sram_dir}/${1r1w_base}32x64/${1r1w_base}32x64.gds \
	${sram_dir}/${1r1w_base}32x64_8/${1r1w_base}32x64_8.gds \
	${sram_dir}/${1r1w_base}54x32/${1r1w_base}54x32.gds \
	${sram_dir}/${1r1w_base}60x32/${1r1w_base}60x32.gds \
	${sram_dir}/${1r1w_base}68x256/${1r1w_base}68x256.gds \
	${sram_dir}/${1r1w_base}156x32/${1r1w_base}156x32.gds


export PLACE_DENSITY = 0.65
export PDN_TCL = ../../config/sky130/pdn.tcl
