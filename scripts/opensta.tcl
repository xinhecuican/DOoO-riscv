set foundry $::env(FOUNDRY)
set SYNTH_V $::env(SYNTH)
set TOP $::env(TOP)
set SDC_FILE   $::env(SDC_FILE)
set LOG_DIR $::env(LOG_DIR)

if { $foundry == "sky130" } {
    set lib_file build/sky130_merge.lib
}

read_liberty $lib_file
read_verilog $SYNTH_V
link_design $TOP
read_sdc $SDC_FILE

report_checks -sort_by_slack -unique > $LOG_DIR/sta_path.log