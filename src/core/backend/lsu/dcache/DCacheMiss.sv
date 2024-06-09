`include "../../../../defines/defines.svh"

interface DCacheMissIO;
    logic `N(`LOAD_PIPELINE) ren;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) raddr;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) lqIdx;
    RobIdx `N(`LOAD_PIPELINE) robIdx;
    logic `N(`LOAD_PIPELINE) rfull;

    logic wen;
    logic `N(`VADDR_SIZE) waddr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) wmask;
    logic wfull;

    logic req;
    logic `N(`VADDR_SIZE) req_addr;
    logic req_success;
    logic write_ready;
    logic `N(`DCACHE_WAY_WIDTH) replaceWay;

    logic refill_en;
    logic refill_valid;
    logic `N(`DCACHE_WAY_WIDTH) refillWay;
    logic `N(`VADDR_SIZE) refillAddr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refillData;

    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lq_en;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lqData;
    logic `ARRAY(`LOAD_REFILL_SIZE, `LOAD_QUEUE_WIDTH) lqIdx_o;

    modport miss (input ren, raddr, lqIdx, robIdx, req_success, write_ready, replaceWay, refill_valid,
                        wen, waddr, wdata, wmask,
                  output rfull, req, req_addr, wfull, refill_en, refillWay, refillAddr, refillData, lq_en, lqData, lqIdx_o);
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
    MSHREntry mshr `N(`DCACHE_MSHR_SIZE);
    logic `N(`DCACHE_MSHR_SIZE) mshr_en;
    logic `N(`DCACHE_MISS_SIZE) en, we, dataValid, refilled;
    logic `N(`DCACHE_WAY_WIDTH) way `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) mask `N(`DCACHE_MISS_SIZE);

    logic `N(`DCACHE_MISS_WIDTH) mshr_head, head, tail;
    logic `N(`DCACHE_MISS_WIDTH) remain_count;
    logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_MISS_WIDTH) freeIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MSHR_WIDTH) mshrFreeIdx;
    logic `N(`LOAD_PIPELINE+1) free_en;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) free_num;

    logic req_start, req_next;
    logic req_last, rlast;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cache_eq_data;


//load enqueue
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_SIZE) rhit;
    logic `ARRAY(`LOAD_PIPELINE+1, $clog2(`LOAD_PIPELINE+1)+1) req_order;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_WIDTH) rhit_idx, ridx;
    logic `N(`LOAD_PIPELINE) mshr_remain_valid, rhit_combine, remain_valid;
generate
    assign req_order[0] = io.ren[0];
    for(genvar i=1; i<`LOAD_PIPELINE; i++)begin
        assign req_order[i] = io.ren[i] + req_order[i-1];
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign freeIdx[i] = tail + req_order[i];
        for(genvar j=0; j<`DCACHE_MISS_SIZE; j++)begin
            assign rhit[i][j] = en[j] & (io.raddr[i]`DCACHE_BLOCK_BUS == addr[j]);
        end
        Encoder #(`DCACHE_MISS_SIZE) encoder_rhit(rhit[i], rhit_idx[i]);
        assign remain_valid[i] = remain_count > req_order[i];
        assign rhit_combine[i] = |rhit[i];
        assign ridx[i] = rhit_combine[i] ? rhit_idx[i] : freeIdx[i];

        always_ff @(posedge clk)begin
            io.rfull[i] <= io.ren[i] & ((~mshr_remain_valid[i]) | (~remain_valid[i])) & (~rhit_combine[i]);
        end

        assign free_en[i] = io.ren[i] & (mshr_remain_valid[i] & remain_valid[i] & ~rhit_combine[i]);
    end
endgenerate
    /* UNPARAM */
    PEncoder #(`DCACHE_MSHR_SIZE) encoder_mshr1 (~mshr_en, mshrFreeIdx[0]);
    PREncoder #(`DCACHE_MSHR_SIZE) encoder_mshr2 (~mshr_en, mshrFreeIdx[1]);
    assign mshr_remain_valid[0] = |(~mshr_en);
    assign mshr_remain_valid[1] = mshrFreeIdx[0] != mshrFreeIdx[1];

// write enqueue
    logic write_remain_valid, whit_combine;
    logic `N(`DCACHE_MISS_SIZE) whit;
    logic `N(`DCACHE_MISS_WIDTH) widx, whitIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) read_data, combine_data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) read_mask, combine_mask;

    assign req_order[`LOAD_PIPELINE] = req_order[`LOAD_PIPELINE-1]  + io.wen;
    assign freeIdx[`LOAD_PIPELINE] = tail + req_order[`LOAD_PIPELINE];
    assign write_remain_valid = remain_count > req_order[`LOAD_PIPELINE];
    assign whit_combine = |whit;
    Encoder #(`DCACHE_MISS_SIZE) encoder_whit(whit, whitIdx);
    assign widx = whit_combine ? whitIdx : freeIdx[`LOAD_PIPELINE];
    always_ff @(posedge clk)begin
        io.wfull <= io.wen & ~rlast & ~req_last & ~write_remain_valid & ~whit_combine;
    end

    assign free_en[`LOAD_PIPELINE] = io.wen & ~rlast & ~req_last & (write_remain_valid & ~whit_combine);

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
    assign io.refill_en = en[head] & we[head] & dataValid[head];
    assign io.refillWay = way[head];
    assign io.refillAddr = {addr[head], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign io.refillData = data[head];

// mshr refill
    logic `N(`DCACHE_MSHR_SIZE) mshr_hit;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_MSHR_WIDTH) mshrIdx;
generate
    for(genvar i=0; i<`DCACHE_MSHR_SIZE; i++)begin
        assign mshr_hit[i] = mshr_en[i] & (mshr[i].missIdx == mshr_head);
    end
endgenerate
    /* UNPARAM */
    PEncoder #(`DCACHE_MSHR_SIZE) pencoder_mshr_idx (mshr_hit, mshrIdx[0]);
    PREncoder #(`DCACHE_MSHR_SIZE) prencoder_mshr_idx (mshr_hit, mshrIdx[1]);

generate
    always_ff @(posedge clk)begin
        io.lq_en[0] <= |mshr_hit & refilled[mshr_head];
        io.lq_en[1] <= (mshrIdx[0] != mshrIdx[1]) & refilled[mshr_head];
    end
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
generate
    for(genvar i=0; i<`DCACHE_MSHR_SIZE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_rob (mshr[i].robIdx, backendCtrl.redirectIdx, older);
        assign redirect_valid[i] = older & mshr_en[i];
    end
endgenerate
    always_ff @(posedge clk)begin
        redirect_n <= backendCtrl.redirect;
        redirect_valid_n <= redirect_valid;
    end

    ParallelAdder #(1, `LOAD_PIPELINE+1) adder_free (free_en, free_num);
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            en <= 0;
            dataValid <= 0;
            we <= 0;
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

            for(int i=0; i<`LOAD_PIPELINE; i++)begin
                if(io.ren[i] & (mshr_remain_valid[i] & remain_valid[i] & ~rhit_combine[i]))begin
                    en[freeIdx[i]] <= 1'b1;
                    addr[freeIdx[i]] <= io.raddr[i]`DCACHE_BLOCK_BUS;
                    dataValid[freeIdx[i]] <= 1'b0;
                end

                if(io.ren[i] & (mshr_remain_valid[i] & remain_valid[i] | rhit_combine[i]))begin
                    mshr_en[mshrFreeIdx[i]] <= 1'b1;
                    mshr[mshrFreeIdx[i]].robIdx <= io.robIdx[i];
                    mshr[mshrFreeIdx[i]].missIdx <= ridx[i];
                    mshr[mshrFreeIdx[i]].lqIdx <= io.lqIdx[i];
                    mshr[mshrFreeIdx[i]].offset <= io.raddr[i][`DCACHE_BANK_WIDTH+1: 2];
                end
            end

            for(int i=0; i<`LOAD_REFILL_SIZE; i++)begin
                if(io.lq_en[i])begin
                    mshr_en[mshrIdx[i]] <= 1'b0;
                end
            end

            if(redirect_n)begin
                mshr_en <= redirect_valid_n;
            end

            if(io.wen & ~rlast & ~req_last & (write_remain_valid & ~whit_combine))begin
                en[freeIdx[`LOAD_PIPELINE]] <= 1'b1;
                addr[freeIdx[`LOAD_PIPELINE]] <= io.waddr`DCACHE_BLOCK_BUS;
                dataValid[freeIdx[`LOAD_PIPELINE]] <= 1'b0;
            end
            if(io.wen & ~rlast & ~req_last & (write_remain_valid | whit_combine))begin
                data[widx] <= combine_data;
                mask[widx] <= combine_mask;
            end
            if(req_last)begin
                data[head] <= cache_eq_data;
                dataValid[head] <= 1'b1;
            end
            if(req_next & io.req_success)begin
                we[head] <= io.write_ready;
            end
            if(replace_queue_io.wend)begin
                we[replace_queue_io.missIdx_o] <= 1'b1;
            end
            if(io.refill_en & io.refill_valid)begin
                refilled[head] <= 1'b1;
                en[head] <= 1'b0;
            end
            if(refilled[mshr_head] & ~(|mshr_hit))begin
                refilled[mshr_head] <= 1'b0;
            end
        end
    end

// req
    logic req_cache;
    logic `N(`VADDR_SIZE) cache_addr;
    logic `N($clog2(`DCACHE_LINE / `DATA_BYTE)) cacheIdx;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cacheData, req_data;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `DATA_BYTE) req_mask;
    logic `N(`XLEN) expandMask;
    logic `N(`XLEN) combine_cache_data;

    assign miss_io.req = en[head] & ~req_start;
    assign miss_io.req_addr = {addr[head], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign rlast = r_axi_io.sr.valid & r_axi_io.sr.last;
    assign replace_queue_io.missIdx = head;

generate
    for(genvar i=0; i<`DCACHE_LINE / `DATA_BYTE; i++)begin
        logic `N(`XLEN) cache_mask;
        MaskExpand #(`DATA_BYTE) expand_cache_mask (req_mask[i], cache_mask);
        assign cache_eq_data[i] = cache_mask & req_data[i] | ~cache_mask & cacheData[i];
    end
endgenerate

    always_ff @(posedge clk)begin
        req_next <= miss_io.req;
        req_last <= r_axi_io.sr.valid & r_axi_io.sr.last;
        if(rst == `RST)begin
            req_start <= 1'b0;
            req_cache <= 1'b0;
            cacheIdx <= 0;
            way <= '{default: 0};
        end
        else begin
            if(miss_io.req)begin
                req_start <= 1'b1;
                cache_addr <= miss_io.req_addr;
            end

            if(req_next & ~io.req_success)begin
                req_start <= 1'b0;
            end

            if(io.refill_en & io.refill_valid)begin
                req_start <= 1'b0;
            end

            if(req_next & io.req_success)begin
                req_cache <= 1'b1;
                way[head] <= io.replaceWay;
            end

            if(r_axi_io.mar.valid & r_axi_io.sar.ready)begin
                req_cache <= 1'b0;
            end

            if(r_axi_io.sr.valid)begin
                cacheIdx <= cacheIdx + 1;
            end
        end
        if(r_axi_io.sr.valid)begin
            cacheData[cacheIdx] <= r_axi_io.sr.data;
        end
        if(rlast)begin
            req_data <= data[head];
            req_mask <= mask[head];
        end
    end

    assign r_axi_io.mar.valid = req_cache;
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

    assign r_axi_io.mr.ready = 1'b1;

endmodule