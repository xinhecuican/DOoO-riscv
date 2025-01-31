`include "../../../defines/defines.svh"

module L2CacheData #(
    parameter MSHR_SIZE=4,
    parameter DATA_BANK = 1,
    parameter WAY_NUM = 4,
    parameter SET_SIZE = 64,
    parameter CACHE_BANK = 16,
    parameter PREPEND_PIPE = 0,
    parameter APPEND_PIPE = 0,
    parameter MSHR_WIDTH=$clog2(MSHR_SIZE)
)(
    input logic clk,
    input logic rst,
    L2MSHRDataIO.data mshr_data_io
);

generate
    for(genvar i=0; i<DATA_BANK; i++)begin
        L2DataBank #(
            .MSHR_SIZE(MSHR_SIZE),
            .WAY_NUM(WAY_NUM),
            .CACHE_BANK(CACHE_BANK),
            .SET_SIZE(SET_SIZE / DATA_BANK),
            .PREPEND_PIPE(PREPEND_PIPE),
            .APPEND_PIPE(APPEND_PIPE)
        ) bank (
            .clk,
            .rst,
            .req(mshr_data_io.req[i]),
            .rway(mshr_data_io.rway[i]),
            .raddr(mshr_data_io.raddr[i]),
            .mshr_idx(mshr_data_io.mshr_idx[i]),
            .ready(mshr_data_io.ready[i]),
            .rvalid(mshr_data_io.rvalid[i]),
            .mshr_idx_o(mshr_data_io.mshr_idx_o[i]),
            .rdata(mshr_data_io.rdata[i]),
            .we(mshr_data_io.we[i]),
            .wway(mshr_data_io.wway[i]),
            .wmshr_idx(mshr_data_io.wmshr_idx[i]),
            .waddr(mshr_data_io.waddr[i]),
            .wvalid(mshr_data_io.wvalid[i]),
            .wmshr_idx_o(mshr_data_io.wmshr_idx_o[i]),
            .wdata(mshr_data_io.wdata[i])
        );
    end
endgenerate

endmodule

module L2DataBank #(
    parameter MSHR_SIZE = 4,
    parameter WAY_NUM = 4,
    parameter SET_SIZE = 64,
    parameter CACHE_BANK = 16,
    parameter PREPEND_PIPE = 0,
    parameter APPEND_PIPE = 0,
    parameter MSHR_WIDTH = $clog2(MSHR_SIZE),
    parameter SET_WIDTH = $clog2(SET_SIZE),
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter CACHE_BITS = (`CACHELINE_SIZE / CACHE_BANK) * 8
)(
    input logic clk,
    input logic rst,
    input logic req,
    input logic `N(MSHR_WIDTH) mshr_idx,
    input logic `N(WAY_WIDTH) rway,
    input logic `N(SET_WIDTH) raddr,
    output logic ready,
    output logic rvalid,
    output logic `N(MSHR_WIDTH) mshr_idx_o,
    output logic `ARRAY(CACHE_BANK, CACHE_BITS) rdata,
    input logic we,
    input logic `N(WAY_WIDTH) wway,
    input logic `N(MSHR_WIDTH) wmshr_idx,
    input logic `N(SET_WIDTH) waddr,
    output logic wvalid,
    output logic `N(MSHR_WIDTH) wmshr_idx_o,
    input logic `ARRAY(CACHE_BANK, CACHE_BITS) wdata
);
    logic `ARRAY(PREPEND_PIPE+1, SET_WIDTH) ridx/*verilator split_var*/;
    logic `TENSOR(PREPEND_PIPE+1, CACHE_BANK, CACHE_BITS) wdata_r/*verilator split_var*/;
    logic `ARRAY(PREPEND_PIPE+APPEND_PIPE+2, MSHR_WIDTH+2) mshr_idx_r/*verilator split_var*/;
    logic `ARRAY(PREPEND_PIPE+2, WAY_WIDTH) rway_r/*verilator split_var*/;
    logic `N(SET_WIDTH) idx;
    logic `ARRAY(WAY_NUM, CACHE_BANK * CACHE_BITS) rdata_ram;
    logic `ARRAY(APPEND_PIPE+1, CACHE_BANK * CACHE_BITS) rdata_append/*verilator split_var*/;

    assign idx = ridx[PREPEND_PIPE];
    assign mshr_idx_r[0] = we ? {wmshr_idx, 1'b1, 1'b0} : {mshr_idx, 1'b0, req & ready};
    assign rway_r[0] = we ? wway : rway;
    assign wdata_r[0] = wdata;
    assign rdata_append[0] = rdata_ram[rway_r[PREPEND_PIPE+1]];
    always_ff @(posedge clk)begin
        mshr_idx_r[PREPEND_PIPE+1] <= mshr_idx_r[PREPEND_PIPE]; // data read cycle
        rway_r[PREPEND_PIPE+1] <= rway_r[PREPEND_PIPE];
    end

    assign rvalid = mshr_idx_r[PREPEND_PIPE+APPEND_PIPE+1][0];
    assign wvalid = mshr_idx_r[PREPEND_PIPE+APPEND_PIPE+1][1];
    assign mshr_idx_o = mshr_idx_r[PREPEND_PIPE+APPEND_PIPE+1][2 +: MSHR_WIDTH];
    assign wmshr_idx_o = mshr_idx_r[PREPEND_PIPE+APPEND_PIPE+1][2 +: MSHR_WIDTH];
    assign rdata = rdata_append[APPEND_PIPE];
    assign ridx[0] = we ? waddr : raddr;
    assign ready = ~we;
generate
    for(genvar i=0; i<PREPEND_PIPE; i++)begin
        always_ff @(posedge clk)begin
            ridx[i+1] <= ridx[i];
            mshr_idx_r[i+1] <= mshr_idx_r[i];
            rway_r[i+1] <= rway_r[i];
            wdata_r[i+1] <= wdata_r[i];
        end
    end
    for(genvar i=0; i<APPEND_PIPE; i++)begin
        always_ff @(posedge clk)begin
            rdata_append[i+1] <= rdata_append[i];
            mshr_idx_r[PREPEND_PIPE+2+i] <= mshr_idx_r[PREPEND_PIPE+1+i];
        end
    end
    for(genvar i=0; i<WAY_NUM; i++)begin
        SPRAM #(
            .WIDTH(`DCACHE_BANK * `DCACHE_BITS),
            .DEPTH(SET_SIZE),
            .READ_LATENCY(1)
        ) ram (
            .clk,
            .rst,
            .rst_sync(0),
            .en(mshr_idx_r[PREPEND_PIPE][0]),
            .we(mshr_idx_r[PREPEND_PIPE][1]),
            .addr(idx),
            .rdata(rdata_ram[i]),
            .wdata(wdata_r[PREPEND_PIPE]),
            .ready()
        );
    end
endgenerate
endmodule