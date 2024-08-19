`include "../../../../defines/defines.svh"

interface DCacheWayIO;
    logic `N(`DCACHE_BANK) en;
    logic `N(`LOAD_PIPELINE+1) tagv_en;
    logic tagv_we;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_SET_WIDTH) tagv_index;
    logic `N(`DCACHE_SET_WIDTH) tagv_windex;
    logic `N((`LOAD_PIPELINE+1) * (`DCACHE_TAG+1)) tagv;
    logic `N(`DCACHE_TAG+1) tagv_wdata;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_SET_WIDTH) index;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) we;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_SET_WIDTH) windex;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata;
    logic dirty_en;
    logic dirty_we;
    logic `N(`DCACHE_SET_WIDTH) dirty_index;
    logic `N(`DCACHE_SET_WIDTH) dirty_windex;
    logic dirty;
    logic dirty_wdata;
    modport way(input en, tagv_en, tagv_we, tagv_index, tagv_windex, tagv_wdata, index, we, windex, wdata, dirty_en, dirty_we, dirty_index, dirty_windex, dirty_wdata, output tagv, data, dirty);
endinterface

module DCacheWay(
    input logic clk,
    input logic rst,
    DCacheWayIO.way io
);
    MPRAM #(
        .WIDTH(`DCACHE_TAG+1),
        .DEPTH(`DCACHE_SET),
        .READ_PORT(`LOAD_PIPELINE),
        .WRITE_PORT(0),
        .RW_PORT(1),
        .RESET(1)
    ) tagv (
        .clk(clk),
        .rst(rst),
        .en(io.tagv_en),
        .raddr(io.tagv_index),
        .rdata(io.tagv),
        .we(io.tagv_we),
        .waddr(io.tagv_windex),
        .wdata(io.tagv_wdata),
        .ready()
    );

    logic dirty `N(`DCACHE_SET);
    always_ff @(posedge clk)begin
        if(io.dirty_en)begin
            io.dirty <= dirty[io.dirty_index];
        end
        if(io.dirty_we)begin
            dirty[io.dirty_windex] <= io.dirty_wdata;
        end
    end

generate
    for(genvar i=0; i<`DCACHE_BANK; i++)begin
        logic `N(`DCACHE_SET_WIDTH) idx;
        logic `N(`DCACHE_BITS) wdata;
        assign wdata = io.wdata[i];
        assign idx = |io.we[i] ? io.windex[i] : io.index[i];
        SPRAM #(
            .WIDTH(`DCACHE_BITS),
            .DEPTH(`DCACHE_SET),
            .READ_LATENCY(1),
            .BYTE_WRITE(1)
        ) bank (
            .clk(clk),
            .en(io.en[i]),
            .addr(idx),
            .we(io.we[i]),
            .wdata(wdata),
            .rdata(io.data[i])
        );
    end
endgenerate
endmodule