`include "../../defines/defines.svh"

// only support 4-way
module PLRU#(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    ReplaceIO.replace replace_io
);
    logic [2: 0] control0, control1;
    logic [3: 0][1: 0] rdata0, rdata1;
    logic [10: 0] wdata0, wdata1;
    logic [1: 0] select_index;

    TDPRAM #(
        .WIDTH(11),
        .DEPTH(DEPTH)
    )lru(
        .clk(clk),
        .rst(rst),
        .en0(hit_en),
        .en1(miss_en),
        .addr0(replace_io.hit_index),
        .addr1(replace_io.miss_index),
        .we0(hit_en),
        .we1(miss_en),
        .wdata0(wdata0),
        .wdata1(wdata1),
        .rdata0({control0, rdata0}),
        .rdata1({control1, rdata1})
    );

    assign select_index[1] = control1[2];
    assign select_index[0] = control1[2] ? control1[1] : control1[0];
    assign replace_io.miss_way = rdata1[select_index];
    always_comb begin
        case(control0)
        3'b000: wdata0 = {3'b101, rdata0[3], rdata0[2], rdata0[1], replace_io.hit_way};
        3'b001: wdata0 = {3'b100, rdata0[3], rdata0[2], replace_io.hit_way, rdata0[0]};
        3'b010: wdata0 = {3'b111, rdata0[3], rdata0[2], rdata0[1], replace_io.hit_way};
        3'b011: wdata0 = {3'b110, rdata0[3], rdata0[2], replace_io.hit_way, rdata0[0]};
        3'b100: wdata0 = {3'b010, rdata0[3], replace_io.hit_way, rdata0[1], rdata0[0]};
        3'b101: wdata0 = {3'b011, rdata0[3], replace_io.hit_way, rdata0[1], rdata0[0]};
        3'b110: wdata0 = {3'b000, replace_io.hit_way, rdata0[2], rdata0[1], rdata0[0]};
        3'b111: wdata0 = {3'b001, replace_io.hit_way, rdata0[2], rdata0[1], rdata0[0]};
        endcase

        case(control1)
        3'b000: wdata1 = {3'b101, rdata1[3], rdata1[2], rdata1[1], replace_io.miss_way};
        3'b001: wdata1 = {3'b100, rdata1[3], rdata1[2], replace_io.miss_way, rdata1[0]};
        3'b010: wdata1 = {3'b111, rdata1[3], rdata1[2], rdata1[1], replace_io.miss_way};
        3'b011: wdata1 = {3'b110, rdata1[3], rdata1[2], replace_io.miss_way, rdata1[0]};
        3'b100: wdata1 = {3'b010, rdata1[3], replace_io.miss_way, rdata1[1], rdata1[0]};
        3'b101: wdata1 = {3'b011, rdata1[3], replace_io.miss_way, rdata1[1], rdata1[0]};
        3'b110: wdata1 = {3'b000, replace_io.miss_way, rdata1[2], rdata1[1], rdata1[0]};
        3'b111: wdata1 = {3'b001, replace_io.miss_way, rdata1[2], rdata1[1], rdata1[0]};
        endcase
    end


endmodule