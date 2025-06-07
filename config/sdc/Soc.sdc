set clk_name  core_clock
set clk_port_name clk
set clk_io_pct 0.2
if {[info exists env(CLK_FREQ)]} {
  set CLK_FREQ_MHZ $::env(CLK_FREQ)
} else {
  set CLK_FREQ_MHZ 100
}
set clk_period [expr 1000.0 / $CLK_FREQ_MHZ]
set rtc_clk_period [expr 1000.0 / 0.032768]
set clk_port [get_ports $clk_port_name]
set rtc_clk_port [get_ports rtc_clk]

create_clock -name $clk_name -period $clk_period $clk_port
create_clock -name rtc_clock -period $rtc_clk_period $rtc_clk_port

set_clock_uncertainty  0.1  [all_clocks]
set_clock_latency      1.0  [all_clocks]
set_clock_transition   0.15 [all_clocks]

set_input_delay  [expr $clk_period * $clk_io_pct] -clock $clk_name rst
set_input_delay  [expr $clk_period * $clk_io_pct] -clock $clk_name rxd
set_output_delay [expr $clk_period * $clk_io_pct] -clock $clk_name [all_outputs]

set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
set_drive        0.1   [all_inputs]
set_load         0.03344   [all_outputs]
set_max_fanout 10 [current_design]
set auto_wire_load_selection

set_false_path -from rtc_clock -to core_clock
set_false_path -from core_clock -to rtc_clock