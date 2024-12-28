`include "../../defines/defines.svh"

module Replace #(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter READ_PORT = 1,
    parameter REPLACE_METHOD = "plru",
    parameter WAY_WIDTH = idxWidth(WAY_NUM),
    parameter ADDR_WIDTH = idxWidth(DEPTH)
)(
    input logic clk,
    input logic rst,
    ReplaceIO.replace replace_io
);
generate
    if(REPLACE_METHOD == "plru")begin
        PLRU #(
            .DEPTH(DEPTH),
            .WAY_NUM(WAY_NUM),
            .READ_PORT(READ_PORT)
        ) plru (.*);
    end
    else begin
        RandomReplace #(
            .DEPTH(DEPTH),
            .WAY_NUM(WAY_NUM)
        ) random (.*);
    end
endgenerate
endmodule