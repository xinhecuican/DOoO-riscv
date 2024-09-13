set PROJ_PATH "[file dirname [info script]]/.."
set SDC_FILE   [lindex $argv 0]
set NETLIST_V  [lindex $argv 1]
set DESIGN     [lindex $argv 2]
set NETLIST_FIXED_V [lindex $argv 3]
set FOUNDRY_NAME [lindex $argv 4]

if { $FOUNDRY_NAME == "sky130" } {
    set env(FOUNDRY_DIR) $PROJ_PATH/utils/iEDA/scripts/foundry/sky130
    source $PROJ_PATH/utils/iEDA/scripts/design/sky130_gcd/script/DB_script/db_path_setting.tcl
    set FIXFANOUT_FILE build/sky130_merge.lib
    set NO_FIXFANOUT_FILE scripts/no_default_config_fixfanout.json
}

db_init -lib_path $FIXFANOUT_FILE
db_init -sdc_path $SDC_FILE
tech_lef_init -path $TECH_LEF_PATH
lef_init -path $LEF_PATH

verilog_init -path $NETLIST_V -top $DESIGN
run_no_fixfanout -config $NO_FIXFANOUT_FILE
netlist_save -path $NETLIST_FIXED_V -exclude_cell_names {}
