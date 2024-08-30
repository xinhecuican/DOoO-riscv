`include "../../../../defines/defines.svh"

interface DCacheMissIO;
    logic `N(`LOAD_PIPELINE) ren;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) raddr;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) lqIdx;
    RobIdx `N(`LOAD_PIPELINE) robIdx;
    logic `N(`LOAD_PIPELINE) rfull;

    logic wen;
    logic `N(`PADDR_SIZE) waddr;
    logic `N(`STORE_COMMIT_WIDTH) scIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) wmask;
    logic wfull;

    logic ptw_req;
    logic ptw_refill;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) ptw_refill_data;

    logic req;
    logic `N(`PADDR_SIZE) req_addr;
    logic req_success;
    logic `N(`DCACHE_WAY_WIDTH) replaceWay;

    logic refill_en;
    logic refill_valid;
    logic refill_dirty;
    logic `N(`DCACHE_WAY_WIDTH) refillWay;
    logic `N(`PADDR_SIZE) refillAddr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refillData;
    logic `N(`STORE_COMMIT_WIDTH) refill_scIdx;

    logic `N(`LOAD_REFILL_SIZE) lq_en;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lqData;
    logic `ARRAY(`LOAD_REFILL_SIZE, `LOAD_QUEUE_WIDTH) lqIdx_o;

    modport miss (input ren, raddr, lqIdx, robIdx, req_success, replaceWay, refill_valid,
                        wen, waddr, scIdx, wdata, wmask, ptw_req,
                  output rfull, req, req_addr, wfull, 
                        refill_en, refill_dirty, refillWay, refillAddr, refillData, refill_scIdx,
                        lq_en, lqData, lqIdx_o, ptw_refill, ptw_refill_data);
endinterface

module DCacheMiss(
    input logic clk,
    input logic rst,
    DCacheMissIO.miss io,
    ReplaceQueueIO.miss replace_queue_io,
    DCacheAxi.miss r_axi_io,
    BackendCtrl backendCtrl
);
`ifdef DIFFTEST
    typedef struct packed {
`else
    typedef struct {
`endif
        RobIdx robIdx; // for redirect
        logic `N(`DCACHE_MISS_WIDTH) missIdx;
        logic `N(`LOAD_QUEUE_WIDTH) lqIdx;
        logic `N(`DCACHE_BANK_WIDTH) offset;
    } MSHREntry;
    logic `N(`DCACHE_BLOCK_SIZE) addr `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_MISS_SIZE) ptw_en;
    MSHREntry mshr `N(`DCACHE_MSHR_SIZE);
    logic `N(`DCACHE_MSHR_SIZE) mshr_en;
    logic `N(`DCACHE_MISS_SIZE) en, dataValid, refilled;
    logic `N(`DCACHE_WAY_WIDTH) way `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) mask `N(`DCACHE_MISS_SIZE);
    logic `N(`STORE_COMMIT_WIDTH) scIdxs `N(`DCACHE_MISS_SIZE);

    logic `N(`DCACHE_MISS_WIDTH) mshr_head, head, tail;
    logic `N(`DCACHE_MISS_WIDTH+1) remain_count;
    logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_MISS_WIDTH) freeIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MSHR_WIDTH) mshrFreeIdx;
    logic `N(`LOAD_PIPELINE+1) free_en;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) free_num;

    logic req_start, req_next, req_ptw;
    logic req_last, rlast;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cache_eq_data;


//load enqueue
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_SIZE) rhit;
    logic `ARRAY(`LOAD_PIPELINE+1, $clog2(`LOAD_PIPELINE+1)) req_order;
    logic `ARRAY(`LOAD_PIPELINE, $clog2(`LOAD_PIPELINE)) r_req_order;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_WIDTH) rhit_idx, ridx;
    logic `N(`LOAD_PIPELINE) mshr_remain_valid, rhit_combine, remain_valid;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_PIPELINE) rfree_eq;
    logic `ARRAY(`LOAD_PIPELINE, $clog2(`LOAD_PIPELINE)) rfree_idx;

    CalValidNum #(`LOAD_PIPELINE+1) cal_req_order (free_en, req_order);
    CalValidNum #(`LOAD_PIPELINE) cal_rorder (io.ren & ~rhit_combine, r_req_order);
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            if(i <= j)begin
                assign rfree_eq[i][j] = 0;
            end
            else begin
                assign rfree_eq[i][j] = io.ren[i] & io.ren[j] & (io.raddr[i]`DCACHE_BLOCK_BUS == io.raddr[j]`DCACHE_BLOCK_BUS);
            end
        end
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign freeIdx[i] = tail + req_order[i];
        for(genvar j=0; j<`DCACHE_MISS_SIZE; j++)begin
            assign rhit[i][j] = en[j] & (io.raddr[i]`DCACHE_BLOCK_BUS == addr[j]);
        end
        Encoder #(`DCACHE_MISS_SIZE) encoder_rhit(rhit[i], rhit_idx[i]);
        PEncoder #(`LOAD_PIPELINE) encoder_rfree_eq_idx (rfree_eq[i], rfree_idx[i]);
        assign remain_valid[i] = remain_count > r_req_order[i];
        assign rhit_combine[i] = (|rhit[i]) | (|rfree_eq[i]);
        assign ridx[i] = (|rhit[i]) ? rhit_idx[i] : 
                         |rfree_eq[i] ? freeIdx[rfree_idx[i]] : freeIdx[i];

        always_ff @(posedge clk)begin
            io.rfull[i] <= io.ren[i] & ((~(mshr_remain_valid[i] | io.ptw_req)) | ((~remain_valid[i]) & (~rhit_combine[i])));
        end

        assign free_en[i] = io.ren[i] & ((mshr_remain_valid[i] | io.ptw_req) & remain_valid[i] & ~rhit_combine[i]);
    end
endgenerate
    /* UNPARAM */
    PEncoder #(`DCACHE_MSHR_SIZE) encoder_mshr1 (~mshr_en, mshrFreeIdx[0]);
    PREncoder #(`DCACHE_MSHR_SIZE) encoder_mshr2 (~mshr_en, mshrFreeIdx[1]);
    assign mshr_remain_valid[0] = |(~mshr_en);
    assign mshr_remain_valid[1] = (|(~mshr_en)) && (~io.ren[0] | (mshrFreeIdx[0] != mshrFreeIdx[1]));

// write enqueue
    logic write_remain_valid, whit_combine;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) write_req_order;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) w_req_order;
    logic `N(`DCACHE_MISS_SIZE) whit;
    logic `N(`DCACHE_MISS_WIDTH) widx, whitIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) read_data, combine_data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) read_mask, combine_mask;
    logic `N(`LOAD_PIPELINE) rwfree_eq;
    logic `N($clog2(`LOAD_PIPELINE)) rwfree_idx;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign rwfree_eq[i] = io.ren[i] && io.wen && (io.raddr[i]`DCACHE_BLOCK_BUS == io.waddr`DCACHE_BLOCK_BUS);
    end
endgenerate
    assign write_req_order = req_order[`LOAD_PIPELINE];
    assign w_req_order = r_req_order[`LOAD_PIPELINE-1] + (io.ren[`LOAD_PIPELINE-1] & ~rhit_combine[`LOAD_PIPELINE-1]);
    assign freeIdx[`LOAD_PIPELINE] = tail + write_req_order;
    assign write_remain_valid = remain_count > w_req_order;
    assign whit_combine = |whit | (|rwfree_eq);
    Encoder #(`DCACHE_MISS_SIZE) encoder_whit(whit, whitIdx);
    PEncoder #(`LOAD_PIPELINE) encoder_rwfree_idx (rwfree_eq, rwfree_idx);
    assign widx = |whit ? whitIdx : 
                  |rwfree_eq ? freeIdx[rwfree_idx] : freeIdx[`LOAD_PIPELINE];
    // note: 因为现在CommitBuffer同一时间只允许一个cacheline，所以不存在冲突问题
    // 实际上只需要req_last时禁止写入即可，如果CommitBuffer同一时间有多个同一地址的项
    // 那么req_last, rlast, io.refill_en & io.refill_end都需要考虑冲突问题
    always_ff @(posedge clk)begin
        io.wfull <= io.wen & (req_last | rlast | (~write_remain_valid & ~whit_combine));
    end

    assign free_en[`LOAD_PIPELINE] = io.wen & ~req_last & ~rlast & (write_remain_valid & ~whit_combine);

    assign read_data = data[widx];
    assign read_mask = mask[widx];
generate
    for(genvar i=0; i<`DCACHE_BANK; i++)begin
        logic `N(`DCACHE_BITS) expand_mask;
        MaskExpand #(`DCACHE_BYTE) mask_expand(io.wmask[i], expand_mask);
        assign combine_data[i] = (expand_mask & io.wdata[i]) | (~expand_mask & read_data[i]);
        assign combine_mask[i] = io.wmask[i] | read_mask[i];
    end
endgenerate

generate
    for(genvar i=0; i<`DCACHE_MISS_SIZE; i++)begin
        assign whit[i] = en[i] & io.waddr`DCACHE_BLOCK_BUS == addr[i];
    end
endgenerate

// refill
    assign io.refill_en = en[head] & dataValid[head];
    assign io.refill_dirty = |mask[head];
    assign io.refillWay = way[head];
    assign io.refillAddr = {addr[head], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign io.refillData = data[head];
    assign io.refill_scIdx = scIdxs[head];
    assign io.ptw_refill = req_last & req_ptw;
    assign io.ptw_refill_data = cache_eq_data;

// mshr refill
    logic `N(`DCACHE_MSHR_SIZE) mshr_hit;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_MSHR_WIDTH) mshrIdx;
    logic `N(`LOAD_REFILL_SIZE) lq_en;
generate
    for(genvar i=0; i<`DCACHE_MSHR_SIZE; i++)begin
        assign mshr_hit[i] = mshr_en[i] & (mshr[i].missIdx == mshr_head);
    end
endgenerate
    /* UNPARAM */
    PEncoder #(`DCACHE_MSHR_SIZE) pencoder_mshr_idx (mshr_hit, mshrIdx[0]);
    PREncoder #(`DCACHE_MSHR_SIZE) prencoder_mshr_idx (mshr_hit, mshrIdx[1]);

    assign lq_en[0] = (|mshr_hit) & refilled[mshr_head];
    assign lq_en[1] = (|mshr_hit) & (mshrIdx[0] != mshrIdx[1]) & refilled[mshr_head];
    always_ff @(posedge clk)begin
        io.lq_en <= lq_en;
    end
generate
    for(genvar i=0; i<`LOAD_REFILL_SIZE; i++)begin
        MSHREntry entry;
        assign entry = mshr[mshrIdx[i]];
        always_ff @(posedge clk)begin
            io.lqData[i] <= data[mshr_head][entry.offset];
            io.lqIdx_o[i] <= entry.lqIdx;
        end
    end
endgenerate

// mshr redirect
    logic `N(`DCACHE_MSHR_SIZE) redirect_valid, redirect_valid_n;
    logic redirect_n;
    RobIdx redirectIdx;
generate
    for(genvar i=0; i<`DCACHE_MSHR_SIZE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_rob (mshr[i].robIdx, redirectIdx, older);
        assign redirect_valid[i] = older & mshr_en[i];
    end
endgenerate
    always_ff @(posedge clk)begin
        redirect_n <= backendCtrl.redirect;
        redirectIdx <= backendCtrl.redirectIdx;
        replace_queue_io.replace_idx <= replace_idx[head];
        // redirect_valid_n <= redirect_valid;
    end

    ParallelAdder #(1, `LOAD_PIPELINE+1) adder_free (free_en, free_num);
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            ptw_en <= 0;
            dataValid <= 0;
            refilled <= 0;
            mshr_en <= 0;
            mshr_head <= 0;
            head <= 0;
            tail <= 0;
            remain_count <= `DCACHE_MISS_SIZE;
        end
        else begin
            head <= head + (io.refill_en & io.refill_valid);
            mshr_head <= mshr_head + (refilled[mshr_head] & ~(|mshr_hit));
            tail <= tail + free_num;
            remain_count <= remain_count + (refilled[mshr_head] & ~(|mshr_hit)) - free_num;

            if(redirect_n)begin
                mshr_en <= redirect_valid;
            end

            for(int i=0; i<`LOAD_PIPELINE; i++)begin
                if(io.ren[i] & ((mshr_remain_valid[i] | io.ptw_req) & (remain_valid[i] & ~rhit_combine[i])))begin
                    en[freeIdx[i]] <= 1'b1;
                    addr[freeIdx[i]] <= io.raddr[i]`DCACHE_BLOCK_BUS;
                    dataValid[freeIdx[i]] <= 1'b0;
                end

                if(io.ren[i] & ~io.ptw_req & mshr_remain_valid[i] & (remain_valid[i] | rhit_combine[i]))begin
                    mshr_en[mshrFreeIdx[i]] <= 1'b1;
                    mshr[mshrFreeIdx[i]].robIdx <= io.robIdx[i];
                    mshr[mshrFreeIdx[i]].missIdx <= ridx[i];
                    mshr[mshrFreeIdx[i]].lqIdx <= io.lqIdx[i];
                    mshr[mshrFreeIdx[i]].offset <= io.raddr[i][`DCACHE_BANK_WIDTH+1: 2];
                end
            end

            for(int i=0; i<`LOAD_REFILL_SIZE; i++)begin
                if(lq_en[i])begin
                    mshr_en[mshrIdx[i]] <= 1'b0;
                end
            end

            if(io.ptw_req & (remain_valid[0] & ~rhit_combine[0]))begin
                ptw_en[freeIdx[0]] <= 1'b1;
            end

            if(io.wen & ~rlast & ~req_last & (write_remain_valid & ~whit_combine))begin
                en[freeIdx[`LOAD_PIPELINE]] <= 1'b1;
                addr[freeIdx[`LOAD_PIPELINE]] <= io.waddr`DCACHE_BLOCK_BUS;
                dataValid[freeIdx[`LOAD_PIPELINE]] <= 1'b0;
            end
            if(io.wen & ~rlast & ~req_last & (write_remain_valid | whit_combine))begin
                data[widx] <= combine_data;
                mask[widx] <= combine_mask;
                scIdxs[widx] <= io.scIdx;
            end
            if(req_last)begin
                data[head] <= cache_eq_data;
                dataValid[head] <= 1'b1;
            end
            if(io.req & io.req_success)begin
                replace_idx[head] <= replace_queue_io.idx;
            end
            if(io.refill_en & io.refill_valid)begin
                refilled[head] <= 1'b1;
                en[head] <= 1'b0;
                mask[head] <= 0;
            end
            if(refilled[mshr_head] & ~(|mshr_hit))begin
                refilled[mshr_head] <= 1'b0;
            end
        end
    end

// req
    logic req_cache;
    logic `N(`PADDR_SIZE) cache_addr;
    logic `N($clog2(`DCACHE_LINE / `DATA_BYTE)) cacheIdx;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cacheData, req_data;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `DATA_BYTE) req_mask;
    logic `N(`XLEN) expandMask;
    logic `N(`XLEN) combine_cache_data;

    assign io.req = en[head] & ~req_start;
    assign io.req_addr = {addr[head], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign rlast = r_axi_io.r_valid & r_axi_io.sr.last;

generate
    for(genvar i=0; i<`DCACHE_LINE / `DATA_BYTE; i++)begin
        logic `N(`XLEN) cache_mask;
        MaskExpand #(`DATA_BYTE) expand_cache_mask (req_mask[i], cache_mask);
        assign cache_eq_data[i] = cache_mask & req_data[i] | ~cache_mask & cacheData[i];
    end
endgenerate

    always_ff @(posedge clk)begin
        req_next <= io.req & io.req_success;
        req_last <= r_axi_io.r_valid & r_axi_io.sr.last;
    end
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            req_start <= 1'b0;
            req_cache <= 1'b0;
            req_ptw <= 1'b0;
            cacheIdx <= 0;
            way <= '{default: 0};
        end
        else begin
            if(io.req & io.req_success)begin
                req_start <= 1'b1;
                cache_addr <= io.req_addr;
            end

            // if(req_next & ~io.req_success)begin
            //     req_start <= 1'b0;
            // end

            if(io.refill_en & io.refill_valid)begin
                req_start <= 1'b0;
            end

            if(io.req & io.req_success)begin
                req_cache <= 1'b1;
                req_ptw <= ptw_en[head];
            end

            if(req_next)begin
                way[head] <= io.replaceWay;
            end

            if(req_last)begin
                req_ptw <= 1'b0;
            end

            if(r_axi_io.ar_valid & r_axi_io.ar_ready)begin
                req_cache <= 1'b0;
            end

            if(r_axi_io.r_valid)begin
                cacheIdx <= cacheIdx + 1;
            end
        end
        if(r_axi_io.r_valid)begin
            cacheData[cacheIdx] <= r_axi_io.sr.data;
        end
        if(rlast)begin
            req_data <= data[head];
            req_mask <= mask[head];
        end
    end

    assign r_axi_io.ar_valid = req_cache;
    assign r_axi_io.mar.id = `DCACHE_ID;
    assign r_axi_io.mar.addr = cache_addr;
    assign r_axi_io.mar.len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign r_axi_io.mar.size = $clog2(`DATA_BYTE);
    assign r_axi_io.mar.burst = 2'b01;
    assign r_axi_io.mar.lock = 2'b00;
    assign r_axi_io.mar.cache = 4'b0;
    assign r_axi_io.mar.prot = 3'b0;
    assign r_axi_io.mar.qos = 0;
    assign r_axi_io.mar.region = 0;
    assign r_axi_io.mar.user = 0;

    assign r_axi_io.r_ready = 1'b1;

endmodule