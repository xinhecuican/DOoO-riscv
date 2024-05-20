`include "../../../defines/defines.svh"

interface FreelistIO;
    logic `N(`FETCH_WIDTH) rdNum;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) old_prd;

    modport freelist(input rdNum, output prd);
    modport rename(output rdNum, input prd);
endinterface

module Freelist(
    input logic clk,
    input logic rst,
    FreelistIO.freelist fl_io,
    CommitBus commitBus
);
    logic `N(`PREG_WIDTH) freelist `N(`FREELIST_DEPTH);
    logic `N($clog2(`FREELIST_DEPTH)) head, tail;
    logic `N($clog2(`FREELIST_DEPTH)+1) remainCount;

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign fl_io.prd[i] = freelist[tail + i];
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<`FREELIST_DEPTH; i++)begin
                freelist[i] <= i + 32;
            end
            head <= 0;
            tail <= 0;
            remainCount <= `FREELIST_DEPTH;
        end
        else begin
            tail <= tail + fl_io.rdNum;
            head <= head + commitBus.wenum;
            remainCount <= remainCount - fl_io.rdNum + commitBus.wenum;
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(commitBus.en[i] & commitBus.we[i])begin
                    freelist[head + i] <= fl_io.old_prd[i];
                end
            end
        end
    end
endmodule