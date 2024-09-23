yosys -import
set lib ../../build/sky130_merge.lib
read_liberty -lib -ignore_miss_dir -setattr blackbox $lib
read_verilog -sv test.sv ../../build/v/MPRAM.v ../../build/v/MPREG.v ../../build/v/MPRAMInner.v ../../build/v/SPRAM.v
hierarchy -check -top test
# synth
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
opt_clean
write_blif mem.blif
memory_bram -rules config/sky130/bram.txt
techmap -map config/sky130/bram_map.v
write_blif map.blif
opt -fast -full
memory_map
opt -full
techmap
opt -fast
# synth end

dfflibmap -liberty $lib
abc -D 2000 -liberty $lib -showtmp -script "+strash;ifraig;retime,-D,{D},-M,6;strash;dch,-f;map,-p,-M,1,{D},-f;topo;dnsize;buffer,-p;upsize;"
hilomap -hicell {*}"sky130_fd_sc_hs__conb_1 HI" -locell {*}"sky130_fd_sc_hs__conb_1 LO"
setundef -zero
splitnets
insbuf -buf {*}"sky130_fd_sc_hs__buf_1 A X"
opt_clean -purge
write_blif test.blif
stat -liberty $lib
write_verilog -noattr -noexpr -nohex -nodec test.v
