`include "../../../../defines/defines.svh"

module DCacheData(
    input logic clk,
    input logic rst,
    input logic `N(`LOAD_PIPELINE+1) tagv_en,
    input logic `N(`DCACHE_WAY) tag_we,
    input logic `N(`DCACHE_WAY) meta_we,
    input logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_SET_WIDTH) tagv_index,
    input logic `N(`DCACHE_SET_WIDTH) tagv_windex,
    input logic `N(`DCACHE_SET_WIDTH) meta_windex,
    input logic `N(`DCACHE_TAG+1) tagv_wdata,
    output logic `TENSOR(`LOAD_PIPELINE+1, `DCACHE_WAY, `DCACHE_TAG+1) tagv,
    output logic `ARRAY(`DCACHE_WAY, `DCACHE_TAG+1) rtagv,
    output DCacheMeta `N(`DCACHE_WAY) meta,
    output DCacheMeta `N(`DCACHE_WAY) rmeta,
    input DCacheMeta wmeta,
    input logic `N(`DCACHE_BANK) en,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_WAY * `DCACHE_BYTE) we,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_SET_WIDTH) index,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata,
    output logic `TENSOR(`DCACHE_BANK, `DCACHE_WAY, `DCACHE_BITS) data
);
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        SPRAM #(
            .WIDTH(`DCACHE_WAY * (`DCACHE_TAG+1)),
            .DEPTH(`DCACHE_SET),
            .RESET(1),
            .BYTE_WRITE(1),
            .READ_LATENCY(1),
            .BYTES(`DCACHE_WAY)
        ) tag_ram (
            .clk(clk),
            .rst(rst),
            .rst_sync(1'b0),
            .en(tagv_en[i]),
            .addr(|tag_we ? tagv_windex : tagv_index[i]),
            .rdata(tagv[i]),
            .we(tag_we),
            .wdata({`DCACHE_WAY{tagv_wdata}}),
            .ready()
        );
    end

    logic `N(`DCACHE_TAG+1) tagv_wdata_n;
    logic `N(`DCACHE_WAY) tag_we_n, meta_we_n;
    logic wtagv_first, write_first;
    DCacheMeta wmeta_n;

    MPRAM #(
        .WIDTH(`DCACHE_WAY * (`DCACHE_TAG+1)),
        .DEPTH(`DCACHE_SET),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1),
        .BYTE_WRITE(1),
        .BYTES(`DCACHE_WAY)
    ) wtag_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(1'b0),
        .en(tagv_en[`LOAD_PIPELINE]),
        .raddr(tagv_index[`LOAD_PIPELINE]),
        .waddr(tagv_windex),
        .rdata(rtagv),
        .we(tag_we),
        .wdata({`DCACHE_WAY{tagv_wdata}}),
        .ready()
    );

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
        .rst_sync(1'b0),
        .en(tagv_en[`LOAD_PIPELINE]),
        .raddr(tagv_index[`LOAD_PIPELINE]),
        .rdata(rmeta),
        .we(meta_we),
        .waddr(meta_windex),
        .wdata({`DCACHE_WAY{wmeta}}),
        .ready()
    );
    // write first
    always_ff @(posedge clk)begin
        wmeta_n <= wmeta;
        meta_we_n <= meta_we;
        write_first <= tagv_en[`LOAD_PIPELINE] & (|meta_we) & (tagv_index[`LOAD_PIPELINE] == meta_windex);
        wtagv_first <= tagv_en[`LOAD_PIPELINE] & (|tag_we) & (tagv_index[`LOAD_PIPELINE] == tagv_windex);
        tagv_wdata_n <= tagv_wdata;
        tag_we_n <= tag_we;
    end
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        assign meta[i] = write_first & meta_we_n[i] ? wmeta_n : rmeta[i];
        assign tagv[`LOAD_PIPELINE][i] = wtagv_first & tag_we_n[i] ? tagv_wdata_n : rtagv[i];
    end


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
            .rst_sync(1'b0),
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