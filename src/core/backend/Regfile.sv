`include "../../defines/defines.svh"

module Regfile(
    input logic clk,
    input logic rst,
    RegfileIO.regfile io
);
    logic `N(`XLEN) regs `N(`PREG_SIZE);

generate
    for(genvar i=0; i<`REGFILE_READ_PORT; i++)begin
        assign io.rdata[i] = regs[io.raddr[i]];
    end
endgenerate
endmodule