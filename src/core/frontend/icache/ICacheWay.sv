`include "../../../defines/defines.svh"

module ICacheData(
    input logic clk,
    input logic rst,
    input logic tagv_en,
    input logic `N(`ICACHE_WAY) tagv_we,
    input logic `N(`ICACHE_SET_WIDTH) tagv_index,
    input logic `N(`ICACHE_SET_WIDTH) tagv_windex,
    input logic `N(`ICACHE_TAG+1) tagv_wdata,
    output logic `ARRAY(`ICACHE_WAY, `ICACHE_TAG+1) tagv0,
    output logic `ARRAY(`ICACHE_WAY, `ICACHE_TAG+1) tagv1,
    input logic `N(`ICACHE_BANK) en,
    input logic `ARRAY(`ICACHE_BANK, `ICACHE_WAY) we,
    input logic `ARRAY(`ICACHE_BANK, `ICACHE_SET_WIDTH) index,
    input logic `ARRAY(`ICACHE_BANK, `ICACHE_BITS) wdata,
    output logic `TENSOR(`ICACHE_BANK, `ICACHE_WAY, `ICACHE_BITS) data
);
    logic `N(`ICACHE_SET_WIDTH) tagv_waddr, tagv_index_p1;
    assign tagv_index_p1 = tagv_index + 1;
    assign tagv_waddr = |tagv_we ? tagv_windex : tagv_index_p1;
    MPRAM #(
        .WIDTH(`ICACHE_WAY * (`ICACHE_TAG+1)),
        .DEPTH(`ICACHE_SET),
        .READ_PORT(1),
        .RW_PORT(1),
        .WRITE_PORT(0),
        .RESET(1),
        .BYTE_WRITE(1),
        .BYTES(`ICACHE_WAY)
    ) tagv_ram (
        .clk,
        .rst,
        .en({2{tagv_en}}),
        .raddr(tagv_index),
        .rdata({tagv1, tagv0}),
        .we(tagv_we),
        .waddr(tagv_waddr),
        .wdata({`ICACHE_WAY{tagv_wdata}}),
        .ready()
    );

    generate;
        for(genvar i=0; i<`ICACHE_BANK; i++)begin
            SPRAM #(
                .WIDTH(`ICACHE_WAY * `ICACHE_BITS),
                .DEPTH(`ICACHE_SET),
                .READ_LATENCY(1),
                .BYTE_WRITE(1),
                .BYTES(`ICACHE_WAY)
            ) bank (
                .clk(clk),
                .en(en[i]),
                .addr(index[i]),
                .we(we[i]),
                .wdata({`ICACHE_WAY{wdata[i]}}),
                .rdata(data[i])
            );
        end
    endgenerate
endmodule