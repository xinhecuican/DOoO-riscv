set search_path [list config/sky130/lib ./ src/defines build/ src/defines/bus]
set target_library [list sky130_fd_sc_hd__tt_025C_1v80.db]
set link_library [list {*} sky130_fd_sc_hd__tt_025C_1v80.db]
set_host_options -max_cores 8