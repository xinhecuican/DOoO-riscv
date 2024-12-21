`include "../../../../defines/defines.svh"

module DCacheData(
    input logic clk,
    input logic rst,
    input logic `N(`LOAD_PIPELINE+1) tagv_en,
    input logic `N(`DCACHE_WAY) tagv_we,
    input logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_SET_WIDTH) tagv_index,
    input logic `N(`DCACHE_TAG+1) tagv_wdata,
    output logic `TENSOR(`LOAD_PIPELINE+1, `DCACHE_WAY, `DCACHE_TAG+1) tagv,
    input logic `N(`DCACHE_BANK) en,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_WAY * `DCACHE_BYTE) we,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_SET_WIDTH) index,
    input logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata,
    output logic `TENSOR(`DCACHE_BANK, `DCACHE_WAY, `DCACHE_BITS) data,
    input logic dirty_en,
    input logic `N(`DCACHE_SET_WIDTH) dirty_index,
    output logic `N(`DCACHE_WAY) dirty,
    input logic `N(`DCACHE_WAY) dirty_we,
    input logic `N(`DCACHE_SET_WIDTH) dirty_windex,
    input logic `N(`DCACHE_WAY) dirty_wdata
);
generate
    for(genvar i=0; i<`LOAD_PIPELINE+1; i++)begin
        SPRAM #(
            .WIDTH(`DCACHE_WAY * (`DCACHE_TAG+1)),
            .DEPTH(`DCACHE_SET),
            .RESET(1),
            .BYTE_WRITE(1),
            .READ_LATENCY(1),
            .BYTES(`DCACHE_WAY)
        ) tagv_ram (
            .clk(clk),
            .rst(rst),
            .rst_sync(0),
            .en(tagv_en[i]),
            .addr(tagv_index[i]),
            .rdata(tagv[i]),
            .we(tagv_we),
            .wdata({`DCACHE_WAY{tagv_wdata}}),
            .ready()
        );
    end
endgenerate

    logic `N(`DCACHE_WAY) dirty_ram `N(`DCACHE_SET);
    always_ff @(posedge clk)begin
        if(dirty_en)begin
            dirty <= dirty_ram[dirty_index];
        end
        for(int i=0; i<`DCACHE_WAY; i++)begin
            if(dirty_we[i])begin
                dirty_ram[dirty_windex][i] <= dirty_wdata[i];
            end
        end
    end

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