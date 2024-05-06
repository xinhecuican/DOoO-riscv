`include "../../../defines/defines.svh"

module Dispatch(
    input logic clk,
    input logic rst,
    RenameDisIO.dis rename_dis_io
);
    BusyTableIO busytable_io;

    ROB rob(.*, .dis_io(rename_dis_io.rob));

    assign busytable_io.dis_en = rename_dis_io.wen;
    assign busytable_io.dis_rd = rename_dis_io.prd;
    assign busytable_io.rs1 = rename_dis_io.prs1;
    assign busytable_io.rs2 = rename_dis_io.prs2;
    BusyTable busy_table(.*, .io(busytable_io.busytable));
endmodule