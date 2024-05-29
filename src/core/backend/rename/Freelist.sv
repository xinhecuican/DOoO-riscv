`include "../../../defines/defines.svh"

interface FreelistIO;
    logic `N(`FETCH_WIDTH+1) rdNum;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) old_prd;
    logic full;

    modport freelist(input rdNum, old_prd, output prd, full);
    modport rename(output rdNum, old_prd, input prd, full);
endinterface

module Freelist(
    input logic clk,
    input logic rst,
    FreelistIO.freelist fl_io,
    CommitBus.in commitBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);
    logic `N(`PREG_WIDTH) freelist `N(`PREG_SIZE);
    logic `N(`PREG_WIDTH) head, tail, tail_n;
    logic `N($clog2(`FETCH_WIDTH)+1) tail_add_num;
    logic `N(`PREG_WIDTH+1) remainCount;

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : rd_prd
        logic `N(`PREG_WIDTH) prdIdx;
        assign prdIdx = tail + i;
        assign fl_io.prd[i] = freelist[prdIdx];
    end
endgenerate

    assign fl_io.full = remainCount < fl_io.rdNum;
    assign tail_add_num = backendCtrl.redirect || backendCtrl.rename_full || backendCtrl.rob_full || backendCtrl.dis_full ? 0 : fl_io.rdNum;
    assign tail_n = commitWalk.walk ? tail - commitWalk.weNum : tail + tail_add_num;
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<`FREELIST_DEPTH; i++)begin
                freelist[i] <= i + 32;
            end
            for(int i=`FREELIST_DEPTH; i<`PREG_SIZE; i++)begin
                freelist[i] <= 0;
            end
            head <= `FREELIST_DEPTH;
            tail <= 0;
            remainCount <= `FREELIST_DEPTH;
        end
        else begin
            tail <= tail_n;
            head <= head + commitBus.wenum;
            if(commitWalk.walk)begin
                remainCount <= remainCount - commitWalk.weNum;
            end
            else begin
                remainCount <= remainCount - tail_add_num + commitBus.wenum;
            end
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(commitBus.en[i] & commitBus.we[i])begin
                    freelist[head + i] <= fl_io.old_prd[i];
                end
            end
        end
    end
endmodule