`include "../../../defines/defines.svh"

interface FreelistIO;
    logic `N(`FETCH_WIDTH+1) rdNum;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) commit_prd;
    logic full;

    modport freelist(input rdNum, commit_prd, output prd, full);
    modport rename(output rdNum, commit_prd, input prd, full);
endinterface

module Freelist #(
    parameter FPV=0,
    parameter PREG_SIZE=128,
    parameter PREG_WIDTH=$clog2(PREG_SIZE),
    parameter FREELIST_DEPTH=PREG_SIZE-32
)(
    input logic clk,
    input logic rst,
    FreelistIO.freelist fl_io,
    CommitBus.in commitBus,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl
);
    logic `N(`PREG_WIDTH) freelist `N(PREG_SIZE);
    logic `N(`PREG_WIDTH) head, tail, tail_n;
    logic `N($clog2(`FETCH_WIDTH)+1) tail_add_num;
    logic `N(`PREG_WIDTH+1) remainCount;
    logic `N(`COMMIT_WIDTH) we, walk_we;
    logic `ARRAY(`COMMIT_WIDTH, $clog2(`COMMIT_WIDTH)) we_add_idx;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) weIdx;
    logic `N($clog2(`COMMIT_WIDTH)+1) commit_we_num, walk_we_num;

generate
    if(FPV)begin
        assign we = commitBus.en & commitBus.fp_we & ~commitBus.excValid;
        assign walk_we = commitWalk.en & commitWalk.fp_we;
    end
    else begin
        assign we = commitBus.en & commitBus.we & ~commitBus.fp_we & ~commitBus.excValid;
        assign walk_we = commitWalk.en & commitWalk.we & ~commitWalk.fp_we;
    end
endgenerate
    CalValidNum #(`FETCH_WIDTH) cal_rd_num (we, we_add_idx);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH), .WIDTH(1)) adder_commit_we_num (we, commit_we_num);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH), .WIDTH(1)) adder_walk_we_num (walk_we, walk_we_num);
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : rd_prd
        logic `N(`PREG_WIDTH) prdIdx;
        assign prdIdx = tail + i;
        assign fl_io.prd[i] = freelist[prdIdx];
        assign weIdx[i] = head + we_add_idx[i];
    end
endgenerate

    assign fl_io.full = remainCount < fl_io.rdNum;
    assign tail_add_num = backendCtrl.redirect || backendCtrl.rename_full || backendCtrl.dis_full ? 0 : fl_io.rdNum;
    assign tail_n = commitWalk.walk ? tail - walk_we_num : tail + tail_add_num;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            for(int i=0; i<FREELIST_DEPTH; i++)begin
                freelist[i] <= i + 32;
            end
            for(int i=FREELIST_DEPTH; i<PREG_SIZE; i++)begin
                freelist[i] <= 0;
            end
            head <= FREELIST_DEPTH;
            tail <= 0;
            remainCount <= FREELIST_DEPTH;
        end
        else begin
            tail <= tail_n;
            head <= head + commit_we_num;
            remainCount <= remainCount - tail_add_num + commit_we_num + walk_we_num;
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(we[i])begin
                    freelist[weIdx[i]] <= fl_io.commit_prd[i];
                end
            end
        end
    end
endmodule