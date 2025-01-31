`include "../../../../defines/defines.svh"

module DCacheData(
    input logic clk,
    input logic rst,
    input logic `N(`LOAD_PIPELINE+1) tagv_en,
    input logic `N(`DCACHE_WAY) tag_we,
    input logic `N(`DCACHE_WAY) valid_we,
    input logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_SET_WIDTH) tagv_index,
    input logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_SET_WIDTH) tagv_windex,
    input logic `N(`DCACHE_TAG+1) tagv_wdata,
    output logic `TENSOR(`LOAD_PIPELINE+1, `DCACHE_WAY, `DCACHE_TAG+1) tagv,
    output DCacheMeta `N(`DCACHE_WAY) meta,
    input DCacheMeta wmeta,
    input logic `N(`DCACHE_BANK) en,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_WAY * `DCACHE_BYTE) we,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_SET_WIDTH) index,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata,
    output logic `TENSOR(`DCACHE_BANK, `DCACHE_WAY, `DCACHE_BITS) data
);
    logic `TENSOR(`LOAD_PIPELINE+1, `DCACHE_WAY, `DCACHE_TAG) tag;
    logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_WAY) valid;
generate
    for(genvar i=0; i<`LOAD_PIPELINE+1; i++)begin
        for(genvar j=0; j<`DCACHE_WAY; j++)begin
            assign tagv[i][j][`DCACHE_TAG: 1] = tag[i][j];
            assign tagv[i][j][0] = valid[i][j];
        end
        SPRAM #(
            .WIDTH(`DCACHE_WAY * `DCACHE_TAG),
            .DEPTH(`DCACHE_SET),
            .RESET(1),
            .BYTE_WRITE(1),
            .READ_LATENCY(1),
            .BYTES(`DCACHE_WAY)
        ) tag_ram (
            .clk(clk),
            .rst(rst),
            .rst_sync(0),
            .en(tagv_en[i]),
            .addr(tagv_index[i]),
            .rdata(tag[i]),
            .we(tag_we),
            .wdata({`DCACHE_WAY{tagv_wdata[`DCACHE_TAG: 1]}}),
            .ready()
        );
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        MPRAM #(
            .WIDTH(`DCACHE_WAY),
            .DEPTH(`DCACHE_SET),
            .READ_PORT(1),
            .WRITE_PORT(1),
            .RESET(1),
            .BYTE_WRITE(1),
            .BYTES(`DCACHE_WAY)
        ) valid_ram (
            .clk,
            .rst,
            .rst_sync(0),
            .en(tagv_en[i]),
            .raddr(tagv_index[i]),
            .rdata(valid[i]),
            .we(valid_we[i]),
            .waddr(tagv_windex[i]),
            .wdata({`DCACHE_WAY{tagv_wdata[0]}}),
            .ready()
        );
    end
    MPRAM #(
        .WIDTH(`DCACHE_WAY * $bits(DCacheMeta)),
        .DEPTH(`DCACHE_SET),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1),
        .BYTE_WRITE(1),
        .BYTES(`DCACHE_WAY)
    ) meta_ram (
        .clk,
        .rst,
        .rst_sync(0),
        .en(tagv_en[`LOAD_PIPELINE]),
        .raddr(tagv_index[`LOAD_PIPELINE]),
        .rdata(meta),
        .we(valid_we[`LOAD_PIPELINE]),
        .waddr(tagv_windex[`LOAD_PIPELINE]),
        .wdata({`DCACHE_WAY{wmeta}}),
        .ready()
    );
endgenerate

generate
    for(genvar i=0; i<`DCACHE_BANK; i++)begin
        SPRAM #(
            .WIDTH(`DCACHE_WAY * `DCACHE_BITS),
            .DEPTH(`DCACHE_SET),
            .READ_LATENCY(1),
            .BYTE_WRITE(1)
        ) bank (
            .clk(clk),
            .rst(rst),
            .rst_sync(0),
            .en(en[i]),
            .addr(index[i]),
            .we(we[i]),
            .wdata({`DCACHE_WAY{wdata[i]}}),
            .rdata(data[i]),
            .ready()
        );
    end
endgenerate
endmodule