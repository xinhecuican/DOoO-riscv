yosys -import
set files [split $::env(VSRC)]

set lib_file utils/iEDA/scripts/foundry/sky130/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set CLK_FREQ $::env(CLK_FREQ)
set CLK_PERIOD_NS [expr 1000.0 / $CLK_FREQ]
set abc_script  "+strash;ifraig;retime,-D,{D},-M,6;strash;dch,-f;map,-p,-M,1,{D},-f;topo;dnsize;buffer,-p;upsize;"


read_liberty -lib -ignore_miss_dir -setattr blackbox $lib_file
foreach file $files {
    read_verilog -sv -Ibuild/ -Isrc/defines/ $file
}
synth -top Soc
opt -purge
dfflibmap -liberty $lib_file
opt -undriven
abc -D [expr $CLK_PERIOD_NS * 1000] -liberty $lib_file -showtmp -script $abc_script
setundef -zero
splitnets
opt_clean -purge

tee -o log/synth_check.txt check
tee -o log/synth_stat.txt stat -liberty $lib_file
write_verilog build/synth.v
show -format dot -viewer none -prefix log/netlist