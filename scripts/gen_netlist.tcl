yosys -import
set foundry $::env(FOUNDRY)
set CLK_FREQ $::env(CLK_FREQ)
set CLK_PERIOD_NS [expr 1000.0 / $CLK_FREQ]
set LOG_DIR $::env(LOG_DIR)
set SYNTH_V $::env(SYNTH)
set TOP $::env(TOP)
if {[info exists ::env(FILES)]} {
    set files $::env(FILES)
} else {
    set files [glob build/$TOP/*]
}
set abc_script  "+strash;ifraig;retime,-D,{D},-M,6;strash;dch,-f;map,-p,-M,1,{D},-f;topo;dnsize;buffer,-p;upsize;"
set abc_args [list -script $abc_script \
    -D [expr $CLK_PERIOD_NS * 1000]]
if { $foundry == "sky130" } {
    # if {![file exists build/sky130_merge.lib]} {
    #     set LIB_PATH [glob config/sky130/lib/*.lib]
    #     set output [exec ./scripts/mergeLib.pl sky130_merge {*}$LIB_PATH > build/sky130_merge.lib]
    # }
	set lib_files [glob config/sky130/lib/*.lib]
    set lib_file config/sky130/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
	set TIEHI_PORT "sky130_fd_sc_hd__conb_1 HI"
	set TIELO_PORT "sky130_fd_sc_hd__conb_1 LO"
	set MIN_BUF_PORT "sky130_fd_sc_hd__buf_4 A X"
    set ABC_DRIVER_CELL "sky130_fd_sc_hd__buf_1"
    set ABC_LOAD_IN_FF "5"
    set DONT_USE_CELLS "sky130_fd_sc_hd__probe_p_8 sky130_fd_sc_hd__probec_p_8 sky130_fd_sc_hd__lpflow_bleeder_1 sky130_fd_sc_hd__lpflow_clkbufkapwr_1 sky130_fd_sc_hd__lpflow_clkbufkapwr_16 sky130_fd_sc_hd__lpflow_clkbufkapwr_2 sky130_fd_sc_hd__lpflow_clkbufkapwr_4 sky130_fd_sc_hd__lpflow_clkbufkapwr_8 sky130_fd_sc_hd__lpflow_clkinvkapwr_1 sky130_fd_sc_hd__lpflow_clkinvkapwr_16 sky130_fd_sc_hd__lpflow_clkinvkapwr_2 sky130_fd_sc_hd__lpflow_clkinvkapwr_4 sky130_fd_sc_hd__lpflow_clkinvkapwr_8 sky130_fd_sc_hd__lpflow_decapkapwr_12 sky130_fd_sc_hd__lpflow_decapkapwr_3 sky130_fd_sc_hd__lpflow_decapkapwr_4 sky130_fd_sc_hd__lpflow_decapkapwr_6 sky130_fd_sc_hd__lpflow_decapkapwr_8 sky130_fd_sc_hd__lpflow_inputiso0n_1 sky130_fd_sc_hd__lpflow_inputiso0p_1 sky130_fd_sc_hd__lpflow_inputiso1n_1 sky130_fd_sc_hd__lpflow_inputiso1p_1 sky130_fd_sc_hd__lpflow_inputisolatch_1 sky130_fd_sc_hd__lpflow_isobufsrc_1 sky130_fd_sc_hd__lpflow_isobufsrc_16 sky130_fd_sc_hd__lpflow_isobufsrc_2 sky130_fd_sc_hd__lpflow_isobufsrc_4 sky130_fd_sc_hd__lpflow_isobufsrc_8 sky130_fd_sc_hd__lpflow_isobufsrckapwr_16 sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_1 sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_2 sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_4 sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_4 sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_1 sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_2 sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_4"
    foreach cell $DONT_USE_CELLS {
        lappend abc_args -dont_use $cell
    }
}

set constr [open $LOG_DIR/abc.constr w]
puts $constr "set_driving_cell $ABC_DRIVER_CELL"
puts $constr "set_load $ABC_LOAD_IN_FF"
close $constr
lappend abc_args -constr $LOG_DIR/abc.constr
lappend abc_args -liberty $lib_file



foreach lib $lib_files {
    read_liberty -lib -ignore_miss_dir -setattr blackbox $lib
}

foreach file $files {
    read_verilog -sv -Ibuild/ -Isrc/defines/ $file
}
# synth
hierarchy -check -top $TOP
procs
flatten
opt_expr
opt_clean
check
opt -nodffe -nosdff
fsm
opt
wreduce
peepopt                                                                                 
opt_clean
alumacc
share
opt
memory -nomap
memory_bram -rules config/sky130/bram.txt
techmap -map config/sky130/bram_map.v -autoproc
opt_clean
opt -fast -full
memory_map
opt -full
techmap
opt -fast
# synth end
opt -purge
dfflibmap -liberty $lib_file
opt -undriven
abc {*}$abc_args
hilomap -hicell {*}$TIEHI_PORT -locell {*}$TIELO_PORT
setundef -zero
splitnets
insbuf -buf {*}$MIN_BUF_PORT
opt_clean -purge

tee -o $LOG_DIR/synth_check.txt check
tee -o $LOG_DIR/synth_stat.txt stat -liberty $lib_file
write_verilog -noattr -noexpr -nohex -nodec -norename $SYNTH_V
