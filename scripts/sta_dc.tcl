source scripts/dc_setup.tcl

set foundry $::env(FOUNDRY)
set CLK_FREQ $::env(CLK_FREQ)
set CLK_PERIOD_NS [expr 1000.0 / $CLK_FREQ]
set LOG_DIR $::env(LOG_DIR)
set BUILD_DIR $::env(BUILD_DIR)
set TOP $::env(TOP)

read_verilog $BUILD_DIR/$TOP.synth.dc.v
link $TOP
source config/sdc/$TOP.sdc
read_sdf $BUILD_DIR/$TOP.sdf

update_timing
check_timing
get_timing_paths  -delay_type max  -path_type full_clock_expanded  -max_paths 10  -nworst 1  -slack_lesser_than 9999  -include_hierarchical_pins  -group {core_clock} > $LOG_DIR/$TOP.rpt
