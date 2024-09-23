yosys -import
if {[info exists ::env(FILES)]} {
    set files $::env(FILES)
} else {
    set files [glob build/v/*]
}
set foundry $::env(FOUNDRY)
set CLK_FREQ $::env(CLK_FREQ)
set CLK_PERIOD_NS [expr 1000.0 / $CLK_FREQ]
set LOG_DIR $::env(LOG_DIR)
set SYNTH_V $::env(SYNTH)
set TOP $::env(TOP)
set abc_script  "+strash;ifraig;retime,-D,{D},-M,6;strash;dch,-f;map,-p,-M,1,{D},-f;topo;dnsize;buffer,-p;upsize;"
if { $foundry == "sky130" } {
    if {![file exists build/sky130_merge.lib]} {
        set env(FOUNDRY_DIR) utils/iEDA/scripts/foundry/sky130
        source config/sky130/db_path_setting.tcl
        set output [exec ./scripts/mergeLib.pl sky130_merge {*}$LIB_PATH > build/sky130_merge.lib]
    }
    set lib_file build/sky130_merge.lib
	set TIEHI_PORT "sky130_fd_sc_hd__conb_1 HI"
	set TIELO_PORT "sky130_fd_sc_hd__conb_1 LO"
	set MIN_BUF_PORT "sky130_fd_sc_hd__buf_1 A X"
}
foreach lib $lib_file {
    read_liberty -lib -ignore_miss_dir -setattr blackbox $lib
}

foreach file $files {
    read_verilog -sv -Ibuild/ -Isrc/defines/ $file
}
# synth
hierarchy -check -top $TOP
procs
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
techmap -map config/sky130/bram_map.v
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
abc -D [expr $CLK_PERIOD_NS * 1000] -liberty $lib_file -showtmp -script $abc_script
hilomap -hicell {*}$TIEHI_PORT -locell {*}$TIELO_PORT
setundef -zero
splitnets
insbuf -buf {*}$MIN_BUF_PORT
opt_clean -purge

tee -o $LOG_DIR/synth_check.txt check
tee -o $LOG_DIR/synth_stat.txt stat -liberty $lib_file
write_verilog -noattr -noexpr -nohex -nodec $SYNTH_V
