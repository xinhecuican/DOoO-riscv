set search_path [list config/sky130/lib ./ src/defines build/ src/defines/bus]
set target_library [list sky130_fd_sc_hd__tt_025C_1v80.db]
set link_library [list {*} sky130_fd_sc_hd__tt_025C_1v80.db]
set work_path build/work
define_design_lib work -path $work_path
set verilogout_no_tri true

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

set_svf build/$TOP.svf
foreach file $files {
    analyze -format sverilog $file
}
elaborate $TOP
link

source -echo -verbose config/sdc/Soc.sdc

#compile
set high_fanout_net_threshold 0

uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

set_structure -timing true

compile
compile -map_effort high -inc

# Output
current_design [get_designs $TOP]
remove_unconnected_ports -blast_buses [get_cells -hierarchical *]

set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed {a-z A-Z 0-9 _}   -max_length 255 -type cell
define_name_rules name_rule -allowed {a-z A-Z 0-9 _[]} -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule

write -format ddc -hierarchy -output build/%{TOP}.ddc
write_file -format verilog -hierarchy    -output         ${SYNTH_V}
write_sdf -version 2.0 -context verilog  -load_delay net build/${TOP}.sdf
write_sdc -version 2.0 build/${TOP}.sdc
report_area   > $LOG_DIR/area.log
report_timing > $LOG_DIR/timing.log
report_power  > $LOG_DIR/power.log
report_qor    > $LOG_DIR/top.qor
exit