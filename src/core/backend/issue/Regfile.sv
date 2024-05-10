`include "../../../defines/defines.svh"

module Regfile(
    input logic clk,
    input logic rst,
    RegfileIO.regfile io
);

    MPRAM #(
        .WIDTH(`XLEN),
        .DEPTH(`PREG_SIZE),
        .READ_PORT(`REGFILE_READ_PORT),
        .WRITE_PORT(`REGFILE_WRITE_PORT)
    ) ram (
        .clk(clk),
        .en(io.en),
        .raddr(io.raddr),
        .rdata(io.rdata),
        .we(io.we),
        .waddr(io.waddr),
        .wdata(io.wdata)
    );
    
endmodule