`include "../../defines/defines.svh"

module RandomReplace #(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    ReplaceIO.replace replace_io
);
    logic `N(WAY_NUM) random;
    LFSRRandom #(WAY_NUM, 64'hc043bdaefc2ab09d) ranGen(clk, rst, random);
    assign replace_io.miss_way = random;
endmodule

module RandomReplaceD1 #(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    ReplaceD1IO.replace replace_io
);
    logic `N(WAY_NUM) random;
    LFSRRandom #(WAY_NUM, 64'hc043bdaefc2ab09d) ranGen(clk, rst, random);
    assign replace_io.miss_way = random[WAY_WIDTH-1: 0];
endmodule