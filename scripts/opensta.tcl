set foundry $::env(FOUNDRY)
set SYNTH_V $::env(SYNTH)
set TOP $::env(TOP)
set SDC_FILE   $::env(SDC_FILE)
set LOG_DIR $::env(LOG_DIR)

if { $foundry == "sky130" } {
    set lib_file [glob config/sky130/lib/*.lib]
}

foreach lib $lib_file {
    read_liberty $lib
}
read_verilog $SYNTH_V
link_design $TOP
read_sdc $SDC_FILE
report_checks -path_group core_clock -sort_by_slack -unique -endpoint_count 10 > $LOG_DIR/sta_path.log