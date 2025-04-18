`include "../../../../defines/defines.svh"

interface DCacheMissIO;
    logic `N(`LOAD_PIPELINE) ren;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) raddr;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) raddr_pre;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) lqIdx;
    RobIdx `N(`LOAD_PIPELINE) robIdx;
    logic `N(`LOAD_PIPELINE) rfull;

    logic wen;
    logic wdata_valid;
    logic `N(`PADDR_SIZE) waddr;
    logic `N(`PADDR_SIZE) waddr_pre;
    logic `N(`STORE_COMMIT_WIDTH) scIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) wmask;
    logic wfull;
    logic wowned;
    logic replaceHit;
    logic `N(`DCACHE_WAY_WIDTH) replaceHitWay;

`ifdef RVA
    logic amo_en;
    logic amo_refill;
`endif

    logic req;
    logic `N(`PADDR_SIZE) req_addr;
    logic req_success;
    logic `N(`DCACHE_WAY_WIDTH) replaceWay;
    logic `N(`L2MSHR_WIDTH) l2_idx;

    logic refill_en;
    logic refill_valid;
    logic refill_write;
    logic refill_replace_hit;
    logic refill_nodata;
    logic `N(`DCACHE_WAY_WIDTH) refillWay;
    logic `N(`PADDR_SIZE) refillAddr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) refillMask;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refillData;
    logic `N(`L2MSHR_WIDTH) refill_l2idx;
    logic `N(`STORE_COMMIT_WIDTH) refill_scIdx;
    DirectoryState refill_state;

    logic `N(`LOAD_REFILL_SIZE) lq_en;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lqData;
    logic `ARRAY(`LOAD_REFILL_SIZE, `LOAD_QUEUE_WIDTH) lqIdx_o;

    modport miss (input ren, raddr, lqIdx, robIdx, req_success, replaceHit, replaceHitWay, replaceWay, refill_valid, l2_idx,
                wen, waddr, scIdx, wdata, wmask, raddr_pre, waddr_pre, wdata_valid, wowned,
`ifdef RVA
                  input amo_en, output amo_refill,
`endif
                  output rfull, req, req_addr, wfull, lq_en, lqData, lqIdx_o, refill_l2idx,
        refill_en, refill_write, refill_replace_hit, refillWay, refillAddr, refillMask, refillData, refill_scIdx, refill_state, refill_nodata);
endinterface

module DCacheMiss(
    input logic clk,
    input logic rst,
    DCacheMissIO.miss io,
    ReplaceQueueIO.miss replace_queue_io,
    CacheBus.masterr r_axi_io,
    input BackendCtrl backendCtrl
);
    typedef struct packed {
        RobIdx robIdx; // for redirect
        logic `N(`DCACHE_MISS_WIDTH) missIdx;
        logic `N(`LOAD_QUEUE_WIDTH) lqIdx;
        logic `N(`DCACHE_BANK_WIDTH) offset;
    } MSHREntry;
    logic `N(`DCACHE_BLOCK_SIZE) addr `N(`DCACHE_MISS_SIZE);
    MSHREntry `N(`DCACHE_MSHR_BANK) mshr `N(`LOAD_PIPELINE);
    logic `N(`DCACHE_MSHR_BANK) mshr_en `N(`LOAD_PIPELINE);
    logic `N(`DCACHE_MISS_SIZE) en, dataValid, refilled;
    logic `N(`DCACHE_WAY_WIDTH) way `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) mask `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_MISS_SIZE) data_valid_all, wvalid;
    logic `N(`STORE_COMMIT_WIDTH) scIdxs `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_MISS_SIZE, `L2MSHR_WIDTH) l2_idxs;
    logic `N(`DCACHE_MISS_SIZE) replaceHit, wowned;
    logic `ARRAY(`DCACHE_MISS_SIZE, `DCACHE_WAY_WIDTH) replaceHitWay;

    logic `N(`DCACHE_MISS_WIDTH) mshr_head, head, tail;
    logic `N(`DCACHE_MISS_WIDTH+1) remain_count;
    logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_MISS_WIDTH) freeIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MSHR_BANK_WIDTH) mshrFreeIdx;
    logic `N(`LOAD_PIPELINE+1) free_en;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) free_num;

    logic req_start, req_next;
    logic req_valid_all, req_wvalid;
    logic req_last, rlast, data_refilled;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cache_eq_data;

    logic `N(`DCACHE_MISS_SIZE) w_refill_eq, head_decode;
    logic refill_eq;
    logic w_invalid;

    logic req_cache;
    logic `N(`PADDR_SIZE) cache_addr;
    logic `N($clog2(`DCACHE_LINE / `DATA_BYTE)) cacheIdx;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cacheData, req_data;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `DATA_BYTE) req_mask;
    logic `N(`XLEN) expandMask;
    logic `N(`XLEN) combine_cache_data;
    logic `N(`DCACHE_WAY_WIDTH) req_way;
    DirectoryState req_state;
    logic req_replace_hit, req_owned, req_owned_after;
    logic req_nodata;

//load enqueue
    // 有三种情况
    // 1. 没有命中, 需要mshr_en和en有空闲
    // 2. 命中，需要mshr_en有空闲
    // 3. 和前面的请求在同一个缓存行中，需要前一个请求成功并且mshr有空闲
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_SIZE) rhit;
    logic `ARRAY(`LOAD_PIPELINE+1, $clog2(`LOAD_PIPELINE+1)) req_order;
    logic `ARRAY(`LOAD_PIPELINE, $clog2(`LOAD_PIPELINE)) r_req_order;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_WIDTH) rhit_idx, ridx;
    logic `N(`LOAD_PIPELINE) mshr_remain_valid, rhit_combine, remain_valid;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_PIPELINE) rfree_eq, raddr_eq_pre, raddr_eq;
    logic `ARRAY(`LOAD_PIPELINE, $clog2(`LOAD_PIPELINE)) rfree_idx;

    CalValidNum #(`LOAD_PIPELINE+1) cal_req_order (free_en, req_order);
    CalValidNum #(`LOAD_PIPELINE) cal_rorder (io.ren & ~rhit_combine & mshr_remain_valid, r_req_order);
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            if(i <= j)begin
                assign rfree_eq[i][j] = 0;
                assign raddr_eq_pre[i][j] = 0;
            end
            else begin
                assign raddr_eq_pre[i][j] = (io.raddr_pre[i]`DCACHE_BLOCK_BUS == io.raddr_pre[j]`DCACHE_BLOCK_BUS);
                assign rfree_eq[i][j] = io.ren[i] & io.ren[j] & raddr_eq[i][j] &
                            mshr_remain_valid[i] & mshr_remain_valid[j];
            end
        end
    end
    `SIG_N(raddr_eq_pre, raddr_eq)
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign freeIdx[i] = tail + req_order[i];
        for(genvar j=0; j<`DCACHE_MISS_SIZE; j++)begin
            assign rhit[i][j] = en[j] & (io.raddr[i]`DCACHE_BLOCK_BUS == addr[j]);
        end
        Encoder #(`DCACHE_MISS_SIZE) encoder_rhit(rhit[i], rhit_idx[i]);
        PEncoder #(`LOAD_PIPELINE) encoder_rfree_eq_idx (rfree_eq[i], rfree_idx[i]);
        PEncoder #(`DCACHE_MSHR_BANK) encoder_mshr (~mshr_en[i], mshrFreeIdx[i]);
        assign mshr_remain_valid[i] = |(~mshr_en[i]);
        assign remain_valid[i] = remain_count > r_req_order[i];
        assign rhit_combine[i] = (|rhit[i]) | (|rfree_eq[i]);
        assign ridx[i] = (|rhit[i]) ? rhit_idx[i] : 
                         |rfree_eq[i] ? freeIdx[rfree_idx[i]] : freeIdx[i];

        always_ff @(posedge clk)begin
            io.rfull[i] <= (io.ren[i]) & ((~(mshr_remain_valid[i])) | ((~remain_valid[i]) & (~rhit_combine[i])));
        end

        assign free_en[i] = io.ren[i] & ((mshr_remain_valid[i]) & remain_valid[i] & ~rhit_combine[i]);
    end
endgenerate

// write enqueue
    logic write_remain_valid, whit_combine;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) write_req_order;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) w_req_order;
    logic `N(`DCACHE_MISS_SIZE) whit;
    logic `N(`DCACHE_MISS_WIDTH) widx, whitIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) read_data, combine_data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) read_mask, combine_mask;
    logic `N(`LOAD_PIPELINE) rwfree_eq, rwaddr_eq_pre, rwaddr_eq;
    logic `N($clog2(`LOAD_PIPELINE)) rwfree_idx;
    logic wen;
    logic `N(`DCACHE_BYTE) wmask_all;
    logic w_req_conflict;

`ifdef RVA
    assign wen = io.wen | io.amo_en;
`else
    assign wen = io.wen;
`endif

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign rwaddr_eq_pre[i] = io.raddr_pre[i]`DCACHE_BLOCK_BUS == io.waddr_pre`DCACHE_BLOCK_BUS;
        assign rwfree_eq[i] = io.ren[i] && wen && rwaddr_eq[i] && mshr_remain_valid[i];
    end
endgenerate
    `SIG_N(rwaddr_eq_pre, rwaddr_eq)
    assign write_req_order = req_order[`LOAD_PIPELINE];
    assign w_req_order = r_req_order[`LOAD_PIPELINE-1] + (io.ren[`LOAD_PIPELINE-1] & ~rhit_combine[`LOAD_PIPELINE-1] & mshr_remain_valid[`LOAD_PIPELINE-1]);
    assign freeIdx[`LOAD_PIPELINE] = tail + write_req_order;
    assign write_remain_valid = remain_count > w_req_order;
    assign whit_combine = |whit | (|rwfree_eq);
    assign w_invalid = rlast | req_last | refill_eq | w_req_conflict;
    Encoder #(`DCACHE_MISS_SIZE) encoder_whit(whit, whitIdx);
    PEncoder #(`LOAD_PIPELINE) encoder_rwfree_idx (rwfree_eq, rwfree_idx);
    ParallelAND #(`DCACHE_BYTE, `DCACHE_BANK) or_wmask (io.wmask, wmask_all);
    assign widx = |whit ? whitIdx : 
                  |rwfree_eq ? freeIdx[rwfree_idx] : freeIdx[`LOAD_PIPELINE];
    assign w_req_conflict = (req_start | replaceHit[head]) & (|whit) & (whitIdx == head);
    // note: 因为现在CommitBuffer同一时间只允许一个cacheline，所以不存在冲突问题
    // 实际上只需要req_last时禁止写入即可，如果CommitBuffer同一时间有多个同一地址的项
    // 那么req_last, rlast, io.refill_en & io.refill_end都需要考虑冲突问题
    always_ff @(posedge clk)begin
        io.wfull <= io.wen & (w_invalid | (~write_remain_valid & ~whit_combine));
    end

    assign free_en[`LOAD_PIPELINE] = wen & ~w_invalid & (write_remain_valid & ~whit_combine);

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
    assign io.refill_state = req_state;
    assign io.refillWay = way[head];
    assign io.refillAddr = {addr[head], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign io.refillMask = req_mask | {`DCACHE_BANK*`DCACHE_BYTE{~req_owned_after}};
    assign io.refillData = data[head];
    assign io.refill_scIdx = scIdxs[head];
    assign io.refill_l2idx = l2_idxs[head];
    assign io.refill_write = wvalid[head];
    assign io.refill_replace_hit = req_replace_hit;
    assign io.refill_nodata = req_nodata;

    Decoder #(`DCACHE_MISS_SIZE) decoder_head (head, head_decode);
    assign w_refill_eq = {`DCACHE_MISS_SIZE{data_refilled}} & whit & head_decode;
    assign refill_eq = |w_refill_eq;

// mshr refill
    `CONSTRAINT(LOAD_REFILL_SIZE, `LOAD_PIPELINE, "LOAD_REFILL_SIZE equal to LOAD_PIPELINE")
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MSHR_BANK) mshr_hit;
    logic `N(`LOAD_PIPELINE) mshr_hit_combine;
    logic mshr_hit_valid;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_MSHR_BANK_WIDTH) mshrIdx;
    logic `N(`LOAD_REFILL_SIZE) lq_en;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_MSHR_BANK; j++)begin
            assign mshr_hit[i][j] = mshr_en[i][j] & (mshr[i][j].missIdx == mshr_head);
        end
        PEncoder #(`DCACHE_MSHR_BANK) pencoder_mshr_idx (mshr_hit[i], mshrIdx[i]);
        assign lq_en[i] = (|mshr_hit[i]) & refilled[mshr_head];
        assign mshr_hit_combine[i] = |mshr_hit[i];
    end
endgenerate
    assign mshr_hit_valid = |mshr_hit_combine;
    always_ff @(posedge clk)begin
        io.lq_en <= lq_en;
    end
generate
    for(genvar i=0; i<`LOAD_REFILL_SIZE; i++)begin
        MSHREntry entry;
        assign entry = mshr[i][mshrIdx[i]];
        always_ff @(posedge clk)begin
            io.lqData[i] <= data[mshr_head][entry.offset];
            io.lqIdx_o[i] <= entry.lqIdx;
        end
    end
endgenerate

// mshr redirect
    logic `N(`DCACHE_MSHR_BANK) redirect_valid `N(`LOAD_PIPELINE);
    logic redirect_n;
    RobIdx redirectIdx;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_MSHR_BANK; j++)begin
            logic older;
            LoopCompare #(`ROB_WIDTH) compare_rob (mshr[i][j].robIdx, redirectIdx, older);
            assign redirect_valid[i][j] = older & mshr_en[i][j];
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        redirect_n <= backendCtrl.redirect;
        redirectIdx <= backendCtrl.redirectIdx;
        replace_queue_io.replace_idx <= replace_idx[head];
    end

    ParallelAdder #(1, `LOAD_PIPELINE+1) adder_free (free_en, free_num);
    always_ff @(posedge clk)begin
        if(io.wen & ~w_invalid & (write_remain_valid | whit_combine))begin
            data[widx] <= combine_data;
            mask[widx] <= combine_mask;
        end
        if(req_last)begin
            data[head] <= cache_eq_data;
        end
        if(io.refill_en & io.refill_valid)begin
            mask[head] <= 0;
        end
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            addr <= '{default: 0};
            mshr <= '{default: 0};
            dataValid <= 0;
            refilled <= 0;
            mshr_en <= '{default: 0};
            mshr_head <= 0;
            head <= 0;
            tail <= 0;
            scIdxs <= '{default: 0};
            remain_count <= `DCACHE_MISS_SIZE;
            data_refilled <= 0;
            data_valid_all <= 0;
            wvalid <= 0;
            replaceHit <= 0;
            replaceHitWay <= 0;
            wowned <= 0;
            replace_idx <= '{default: 0};
        end
        else begin
            head <= head + (io.refill_en & io.refill_valid);
            mshr_head <= mshr_head + (refilled[mshr_head] & ~(mshr_hit_valid));
            tail <= tail + free_num;
            remain_count <= remain_count + (refilled[mshr_head] & ~(mshr_hit_valid)) - free_num;

            if(redirect_n)begin
                mshr_en <= redirect_valid;
            end

            for(int i=0; i<`LOAD_PIPELINE; i++)begin
                if(io.ren[i] & ((mshr_remain_valid[i]) & (remain_valid[i] & ~rhit_combine[i])))begin
                    en[freeIdx[i]] <= 1'b1;
                    addr[freeIdx[i]] <= io.raddr[i]`DCACHE_BLOCK_BUS;
                    dataValid[freeIdx[i]] <= 1'b0;
                end

                if(io.ren[i] & mshr_remain_valid[i] & (remain_valid[i] | rhit_combine[i]))begin
                    mshr_en[i][mshrFreeIdx[i]] <= 1'b1;
                    mshr[i][mshrFreeIdx[i]].robIdx <= io.robIdx[i];
                    mshr[i][mshrFreeIdx[i]].missIdx <= ridx[i];
                    mshr[i][mshrFreeIdx[i]].lqIdx <= io.lqIdx[i];
                    mshr[i][mshrFreeIdx[i]].offset <= io.raddr[i][`DCACHE_BANK_WIDTH+1: 2];
                end
            end

            for(int i=0; i<`LOAD_REFILL_SIZE; i++)begin
                if(lq_en[i])begin
                    mshr_en[i][mshrIdx[i]] <= 1'b0;
                end
            end

            if(wen & ~w_invalid & (write_remain_valid & ~whit_combine))begin
                en[freeIdx[`LOAD_PIPELINE]] <= 1'b1;
                addr[freeIdx[`LOAD_PIPELINE]] <= io.waddr`DCACHE_BLOCK_BUS;
                dataValid[freeIdx[`LOAD_PIPELINE]] <= 1'b0;
                replaceHit[freeIdx[`LOAD_PIPELINE]] <= io.replaceHit;
                replaceHitWay[freeIdx[`LOAD_PIPELINE]] <= io.replaceHitWay;
                wowned[freeIdx[`LOAD_PIPELINE]] <= io.wowned;
            end
            if(io.wen & ~w_invalid & (write_remain_valid | whit_combine))begin
                scIdxs[widx] <= io.scIdx;
                data_valid_all[widx] <= &wmask_all | io.wdata_valid;
                wvalid[widx] <= 1'b1;
            end
            if(rlast)begin
                data_refilled <= 1'b1;
            end
            if(req_last)begin
                dataValid[head] <= 1'b1;
            end
            if(req_next & io.req_success)begin
                replace_idx[head] <= replace_queue_io.idx;
            end
            if(io.refill_en & io.refill_valid)begin
                refilled[head] <= 1'b1;
                en[head] <= 1'b0;
                data_refilled <= 1'b0;
                data_valid_all[head] <= 1'b0;
                wvalid[head] <= 1'b0;
                replaceHit[head] <= 1'b0;
            end
            if(refilled[mshr_head] & ~(mshr_hit_valid))begin
                refilled[mshr_head] <= 1'b0;
            end
        end
    end

`ifdef RVA
    logic `N(`DCACHE_MSHR_SIZE) amo;
    logic amo_req;
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            amo <= 0;
            amo_req <= 0;
        end
        else begin
            if(io.amo_en & ~w_invalid & (write_remain_valid | whit_combine))begin
                amo[widx] <= 1'b1;
            end
            if(io.refill_en & io.refill_valid)begin
                amo[head] <= 1'b0;
            end
            if(req_next & io.req_success | replaceHit[head] & ~req_start)begin
                amo_req <= amo[head];
            end
        end
    end

    always_ff @(posedge clk)begin
        io.amo_refill <= io.amo_en & (w_invalid | (~write_remain_valid & ~whit_combine)) |
                      io.refill_en & io.refill_valid & amo[head];
    end
`endif

// req
    assign io.req = en[head] & ~replaceHit[head] & ~req_start;
    assign io.req_addr = {addr[head], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign rlast = r_axi_io.r_valid & r_axi_io.r_last;

generate
    for(genvar i=0; i<`DCACHE_LINE / `DATA_BYTE; i++)begin
        logic `N(`XLEN) cache_mask;
        MaskExpand #(`DATA_BYTE) expand_cache_mask (req_mask[i], cache_mask);
        assign cache_eq_data[i] = cache_mask & req_data[i] | ~cache_mask & cacheData[i];
    end
endgenerate

    always_ff @(posedge clk)begin
        req_next <= io.req;
        req_last <= r_axi_io.r_valid & r_axi_io.r_last;
    end
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            req_start <= 1'b0;
            req_cache <= 1'b0;
            cacheIdx <= 0;
            way <= '{default: 0};
            req_way <= 0;
            req_valid_all <= 0;
            req_wvalid <= 0;
            req_state <= 0;
            l2_idxs <= 0;
            req_replace_hit <= 1'b0;
            req_owned <= 0;
            req_owned_after <= 0;
            req_nodata <= 0;
        end
        else begin
            if(io.req | replaceHit[head] & ~req_start)begin
                req_start <= 1'b1;
                req_replace_hit <= replaceHit[head];
                req_owned <= wowned[head];
            end

            if(req_next & ~io.req_success)begin
                req_start <= 1'b0;
            end

            if(io.refill_en & io.refill_valid)begin
                req_start <= 1'b0;
            end

            if(req_next & io.req_success | replaceHit[head] & ~req_start)begin
                req_cache <= 1'b1;
                cache_addr <= io.req_addr;
                req_way <= io.replaceWay;
                req_valid_all <= data_valid_all[head];
                req_wvalid <= wvalid[head];
                way[head] <= replaceHit[head] ? replaceHitWay[head] : io.replaceWay;
                req_nodata <= 1'b0;
            end

            if(r_axi_io.ar_valid & r_axi_io.ar_ready)begin
                req_cache <= 1'b0;
            end

            // MAKE_UNIQUE OR CLEAN_UNIQUE
            if(r_axi_io.r_valid & ~(r_axi_io.r_last & (cacheIdx == 0)))begin
                cacheIdx <= cacheIdx + 1;
            end
            if(r_axi_io.r_valid & (cacheIdx == 0))begin
                l2_idxs[head] <= io.l2_idx;
            end
        end
        if(r_axi_io.r_valid & ~(r_axi_io.r_last & (cacheIdx == 0)))begin
            cacheData[cacheIdx] <= r_axi_io.r_data;
        end
        if(r_axi_io.r_valid & r_axi_io.r_last & (cacheIdx == 0) & req_owned & req_replace_hit)begin
            req_owned_after <= 1'b1;
        end
        else if(r_axi_io.r_valid & r_axi_io.r_last)begin
            req_owned_after <= 1'b0;
        end

        if(r_axi_io.r_valid & r_axi_io.r_last & (cacheIdx == 0))begin
            req_nodata <= 1'b1;
        end
    
        if(rlast)begin
            req_data <= data[head];
            req_mask <= mask[head];
            req_state <= req_wvalid | req_valid_all 
`ifdef RVA
                        | amo_req
`endif
            ? 3'b101 : r_axi_io.r_resp[4: 2];
        end
    end

    assign r_axi_io.ar_valid = req_cache;
    assign r_axi_io.ar_id = `DCACHE_ID;
    assign r_axi_io.ar_addr = cache_addr;
    assign r_axi_io.ar_len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign r_axi_io.ar_size = $clog2(`DATA_BYTE);
    assign r_axi_io.ar_burst = 2'b01;
    assign r_axi_io.ar_user = 0;
    assign r_axi_io.ar_snoop = 
`ifdef RVA
                               amo_req ? `ACEOP_READ_UNIQUE :
`endif
                               req_valid_all ? `ACEOP_MAKE_UNIQUE :
                               req_wvalid & req_replace_hit & req_owned ? `ACEOP_CLEAN_UNIQUE :
                               req_wvalid ? `ACEOP_READ_UNIQUE : `ACEOP_READ_SHARED;

    assign r_axi_io.r_ready = 1'b1;

    `PERF(load_miss, rlast & (|mshr_hit_combine))
    `PERF(dcache_miss, r_axi_io.ar_valid & r_axi_io.ar_ready)

endmodule