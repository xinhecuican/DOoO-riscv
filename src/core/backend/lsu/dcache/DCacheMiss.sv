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
        refill_en, refill_write, refillWay, refillAddr, refillMask, refillData, refill_scIdx, refill_state, refill_nodata);
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
        RobIdx robIdx;
        logic `N(`DCACHE_MISS_WIDTH) missIdx;
        logic `N(`LOAD_QUEUE_WIDTH) lqIdx;
        logic `N(`DCACHE_BANK_WIDTH) offset;
    } MSHREntry;

    logic `N(`DCACHE_MISS_SIZE) en;
    logic `N(`DCACHE_BLOCK_SIZE) addr `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_MSHR_BANK) mshr_en `N(`LOAD_PIPELINE);
    MSHREntry `N(`DCACHE_MSHR_BANK) mshr `N(`LOAD_PIPELINE);
    logic `N(`DCACHE_MISS_SIZE) remain_count;
    logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_MISS_WIDTH) freeIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MSHR_BANK_WIDTH) mshrFreeIdx;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) free_num;
    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx `N(`DCACHE_MISS_SIZE);

    logic `N(`DCACHE_MISS_SIZE) cache_req, axi_req, axi_req_end, refill_req, data_valid;
    logic `N(`DCACHE_MISS_SIZE) replaceHit, wowned, data_valid_all, wvalid;;
    logic `ARRAY(`DCACHE_MISS_SIZE, `DCACHE_WAY_WIDTH) replaceHitWay;
    logic `N(`STORE_COMMIT_WIDTH) scIdxs `N(`DCACHE_MISS_SIZE);

    logic `N(`LOAD_PIPELINE+1) free_en;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_SIZE) rhit;
    logic `ARRAY(`LOAD_PIPELINE+1, $clog2(`LOAD_PIPELINE+1)) req_order;
    logic `ARRAY(`LOAD_PIPELINE, $clog2(`LOAD_PIPELINE)) r_req_order;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_WIDTH) rhit_idx, ridx;
    logic `N(`LOAD_PIPELINE) mshr_remain_valid, rhit_combine, remain_valid;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_PIPELINE) rfree_eq, raddr_eq_pre, raddr_eq, rfree_eq_last;
    logic `ARRAY(`LOAD_PIPELINE, $clog2(`LOAD_PIPELINE)) rfree_idx;

    logic write_remain_valid, whit_combine;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) write_req_order;
    logic `N($clog2(`LOAD_PIPELINE+1)+1) w_req_order;
    logic `N(`DCACHE_MISS_SIZE) whit;
    logic `N(`DCACHE_MISS_WIDTH) widx, whitIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) combine_data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) combine_mask;
    logic `N(`LOAD_PIPELINE) rwfree_eq, rwaddr_eq_pre, rwaddr_eq;
    logic `N($clog2(`LOAD_PIPELINE)) rwfree_idx;
    logic wen;
    logic `N(`DCACHE_BYTE) wmask_all;
    logic w_invalid;

    logic `N(`DCACHE_MISS_SIZE) cache_req_valid, replace_hit_valid, axi_req_valid;
    logic `N(`DCACHE_MISS_WIDTH) cache_req_idx, cache_req_idx_n, replace_hit_idx, req_idx;
    logic req_next;
    logic `N(`DCACHE_WAY_WIDTH) way `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_MISS_WIDTH) axi_req_idx, axi_req_idx_n;
    typedef enum  { IDLE, REQ } AxiState;
    AxiState axi_state;
    logic ar_valid;
    logic `N(`PADDR_SIZE) ar_addr;
    logic `N(`DCACHE_ID_WIDTH) ar_id, free_id;
    logic `N(`DCACHE_ID_SIZE) id_valids;
    logic `N(`DCACHE_MISS_WIDTH) id_map `N(`DCACHE_ID_SIZE);
    logic [3: 0] ar_snoop;
    logic req_last, rlast;
    logic [2: 0] r_resp;
    logic `ARRAY(`DCACHE_ID_SIZE, `DCACHE_BANK_WIDTH) cacheIdx;
    logic `N(`DCACHE_MISS_WIDTH) map_idx;
    logic `ARRAY(`DCACHE_MISS_SIZE, `L2MSHR_WIDTH) l2_idxs;
    logic `TENSOR(`DCACHE_ID_SIZE, `DCACHE_LINE / `DATA_BYTE, `XLEN) cacheData;
    DirectoryState `N(`DCACHE_MISS_SIZE) refill_state;
    logic `N(`DCACHE_MISS_SIZE) req_owned_after, req_nodata;
    logic refill_nodata_valid;
    logic `N(`DCACHE_ID_WIDTH) r_id, r_id_n;

    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data `N(`DCACHE_MISS_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) mask `N(`DCACHE_MISS_SIZE);
    logic `N(`DCACHE_MISS_WIDTH) data_idx, axi_refill_idx;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `XLEN) cache_eq_data, req_data, cache_req_data;
    logic `ARRAY(`DCACHE_LINE / `DATA_BYTE, `DATA_BYTE) req_mask;

    logic `N(`DCACHE_MISS_SIZE) refill_valid;
    logic `N(`DCACHE_MISS_WIDTH) refill_idx;

    `CONSTRAINT(LOAD_REFILL_SIZE, `LOAD_PIPELINE, "LOAD_REFILL_SIZE equal to LOAD_PIPELINE")
    logic `N(`DCACHE_MISS_SIZE) mshr_refill_valid, mshr_waiting;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MSHR_BANK) mshr_hit;
    logic `TENSOR(`LOAD_PIPELINE, `DCACHE_MSHR_BANK, `DCACHE_MISS_SIZE) mshr_waiting_idx, mshr_waiting_en;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_MISS_SIZE) mshr_waiting_combine;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_MSHR_BANK_WIDTH) mshrIdx;
    logic `N(`LOAD_REFILL_SIZE) lq_en;

    logic `N(`DCACHE_MISS_SIZE) miss_end;
    logic `N(`DCACHE_MISS_WIDTH) miss_end_idx;

    FreeBankIO #(
        .DEPTH(`DCACHE_MISS_SIZE),
        .DATA_WIDTH(`DCACHE_MISS_WIDTH),
        .READ_PORT(`LOAD_PIPELINE+2),
        .WRITE_PORT(1)
    ) free_io ();

    FreeBank #(
        .DEPTH(`DCACHE_MISS_SIZE),
        .DATA_WIDTH(`DCACHE_MISS_WIDTH),
        .READ_PORT(`LOAD_PIPELINE+2),
        .WRITE_PORT(1)
    ) free_bank (
        .*, .io(free_io)
    );
    assign remain_count = free_io.remain_count;
    assign free_io.en = |free_en;
    ParallelAdder #(1, `LOAD_PIPELINE+1) adder_free (free_en, free_num);
    assign free_io.rdNum = free_num;
    assign free_io.we = |miss_end;
    assign free_io.wrNum = 1'b1;
    assign free_io.w_idxs[0] = miss_end_idx;

// enqueue
    CalValidNum #(`LOAD_PIPELINE+1) cal_req_order (free_en, req_order);
    CalValidNum #(`LOAD_PIPELINE) cal_rorder (io.ren & ~rhit_combine & mshr_remain_valid, r_req_order);
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            if(i <= j)begin
                assign rfree_eq[i][j] = 0;
                assign raddr_eq_pre[i][j] = 0;
                assign rfree_eq_last[i][j] = 0;
            end
            else begin
                assign raddr_eq_pre[i][j] = (io.raddr_pre[i]`DCACHE_BLOCK_BUS == io.raddr_pre[j]`DCACHE_BLOCK_BUS);
                assign rfree_eq[i][j] = io.ren[i] & io.ren[j] & raddr_eq[i][j] &
                            mshr_remain_valid[i] & mshr_remain_valid[j];
                assign rfree_eq_last[i][j] = rfree_eq[i][j] & remain_valid[j];
            end
        end
    end
    `SIG_N(raddr_eq_pre, raddr_eq)
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign freeIdx[i] = free_io.r_idxs[req_order[i]];
        for(genvar j=0; j<`DCACHE_MISS_SIZE; j++)begin
            assign rhit[i][j] = en[j] & (io.raddr[i]`DCACHE_BLOCK_BUS == addr[j]);
        end
        Encoder #(`DCACHE_MISS_SIZE) encoder_rhit(rhit[i], rhit_idx[i]);
        PEncoder #(`LOAD_PIPELINE) encoder_rfree_eq_idx (rfree_eq[i], rfree_idx[i]);
        PEncoder #(`DCACHE_MSHR_BANK) encoder_mshr (~mshr_en[i], mshrFreeIdx[i]);
        assign mshr_remain_valid[i] = |(~mshr_en[i]);
        assign remain_valid[i] = remain_count > r_req_order[i];
        assign rhit_combine[i] = (|rhit[i]) | (|rfree_eq_last[i]);
        assign ridx[i] = (|rhit[i]) ? rhit_idx[i] : 
                         |rfree_eq[i] ? freeIdx[rfree_idx[i]] : freeIdx[i];

        always_ff @(posedge clk)begin
            io.rfull[i] <= (io.ren[i]) & ((~(mshr_remain_valid[i])) | ((~remain_valid[i]) & (~rhit_combine[i])));
        end

        assign free_en[i] = io.ren[i] & ((mshr_remain_valid[i]) & remain_valid[i] & ~rhit_combine[i]);
    end
endgenerate

// write enqueue
`ifdef RVA
    assign wen = io.wen | io.amo_en;
`else
    assign wen = io.wen;
`endif

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign rwaddr_eq_pre[i] = io.raddr_pre[i]`DCACHE_BLOCK_BUS == io.waddr_pre`DCACHE_BLOCK_BUS;
        assign rwfree_eq[i] = io.ren[i] & wen & rwaddr_eq[i] & mshr_remain_valid[i];
    end
    for(genvar i=0; i<`DCACHE_MISS_SIZE; i++)begin
        assign whit[i] = en[i] & io.waddr`DCACHE_BLOCK_BUS == addr[i];
    end
endgenerate
    `SIG_N(rwaddr_eq_pre, rwaddr_eq)
    assign write_req_order = req_order[`LOAD_PIPELINE];
    assign w_req_order = r_req_order[`LOAD_PIPELINE-1] + (io.ren[`LOAD_PIPELINE-1] & ~rhit_combine[`LOAD_PIPELINE-1] & mshr_remain_valid[`LOAD_PIPELINE-1]);
    assign freeIdx[`LOAD_PIPELINE] = free_io.r_idxs[write_req_order];
    assign write_remain_valid = remain_count > w_req_order;
    assign whit_combine = |whit | (|rwfree_eq);
    assign w_invalid = rlast | req_last | (|(whit & axi_req_end));
    Encoder #(`DCACHE_MISS_SIZE) encoder_whit(whit, whitIdx);
    PEncoder #(`LOAD_PIPELINE) encoder_rwfree_idx (rwfree_eq, rwfree_idx);
    ParallelAND #(`DCACHE_BYTE, `DCACHE_BANK) or_wmask (io.wmask, wmask_all);
    assign widx = |whit ? whitIdx : 
                  |rwfree_eq ? freeIdx[rwfree_idx] : freeIdx[`LOAD_PIPELINE];
    // note: 因为现在CommitBuffer同一时间只允许一个cacheline，所以不存在冲突问题
    // 实际上只需要req_last时禁止写入即可，如果CommitBuffer同一时间有多个同一地址的项
    // 那么req_last, rlast, io.refill_en & io.refill_end都需要考虑冲突问题
    always_ff @(posedge clk)begin
        io.wfull <= io.wen & (w_invalid | (~write_remain_valid & ~whit_combine));
    end

    assign free_en[`LOAD_PIPELINE] = wen & ~w_invalid & (write_remain_valid & ~whit_combine);


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
        if(req_next & io.req_success)begin
            replace_idx[req_idx] <= replace_queue_io.idx;
        end
        replace_queue_io.replace_idx <= replace_idx[refill_idx];

        for(int i=0; i<`LOAD_PIPELINE; i++)begin
            if(io.ren[i] & ((mshr_remain_valid[i]) & (remain_valid[i] & ~rhit_combine[i])))begin
                addr[freeIdx[i]] <= io.raddr[i]`DCACHE_BLOCK_BUS;
            end
            if(io.ren[i] & mshr_remain_valid[i] & (remain_valid[i] | rhit_combine[i]))begin
                mshr[i][mshrFreeIdx[i]].robIdx <= io.robIdx[i];
                mshr[i][mshrFreeIdx[i]].missIdx <= ridx[i];
                mshr[i][mshrFreeIdx[i]].lqIdx <= io.lqIdx[i];
                mshr[i][mshrFreeIdx[i]].offset <= io.raddr[i][`DCACHE_BANK_WIDTH+1: 2];
            end
        end
        if(wen & ~w_invalid & (write_remain_valid & ~whit_combine))begin
            replaceHitWay[freeIdx[`LOAD_PIPELINE]] <= io.replaceHitWay;
            addr[freeIdx[`LOAD_PIPELINE]] <= io.waddr`DCACHE_BLOCK_BUS;
        end
        if(io.wen & ~w_invalid & (write_remain_valid | whit_combine))begin
            scIdxs[widx] <= io.scIdx;
        end
    end

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            mshr_en <= '{default: 0};
            cache_req <= 0;
            replaceHit <= 0;
            wowned <= 0;
            data_valid_all <= 0;
        end
        else begin
            if(redirect_n)begin
                mshr_en <= redirect_valid;
            end
            for(int i=0; i<`LOAD_PIPELINE; i++)begin
                if(io.ren[i] & ((mshr_remain_valid[i]) & (remain_valid[i] & ~rhit_combine[i])))begin
                    en[freeIdx[i]] <= 1'b1;
                    cache_req[freeIdx[i]] <= 1'b1;
                end
                if(io.ren[i] & mshr_remain_valid[i] & (remain_valid[i] | rhit_combine[i]))begin
                    mshr_en[i][mshrFreeIdx[i]] <= 1'b1;
                end
            end
            for(int i=0; i<`LOAD_REFILL_SIZE; i++)begin
                if(lq_en[i])begin
                    mshr_en[i][mshrIdx[i]] <= 1'b0;
                end
            end
            if(wen & ~w_invalid & (write_remain_valid & ~whit_combine))begin
                en[freeIdx[`LOAD_PIPELINE]] <= 1'b1;
                cache_req[freeIdx[`LOAD_PIPELINE]] <= ~io.replaceHit;
                replaceHit[freeIdx[`LOAD_PIPELINE]] <= io.replaceHit;
                wowned[freeIdx[`LOAD_PIPELINE]] <= io.wowned;
            end
            if(io.wen & ~w_invalid & (write_remain_valid | whit_combine))begin
                data_valid_all[widx] <= &wmask_all | io.wdata_valid;
                wvalid[widx] <= 1'b1;
            end

            if(io.req)begin
                cache_req[cache_req_idx] <= 1'b0;
            end
            if(req_next & ~io.req_success)begin
                cache_req[cache_req_idx_n] <= 1'b1;
            end
            if(|miss_end)begin
                en[miss_end_idx] <= 1'b0;
                wvalid[miss_end_idx] <= 1'b0;
                replaceHit[miss_end_idx] <= 1'b0;
                data_valid_all[miss_end_idx] <= 1'b0;
            end
        end
    end

`ifdef RVA
    logic `N(`DCACHE_MSHR_SIZE) amo;
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            amo <= 0;
        end
        else begin
            if(io.amo_en & ~w_invalid & (write_remain_valid | whit_combine))begin
                amo[widx] <= 1'b1;
            end
            if(|miss_end)begin
                amo[miss_end_idx] <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk)begin
        io.amo_refill <= io.amo_en & (w_invalid | (~write_remain_valid & ~whit_combine)) |
                      (|miss_end) & amo[miss_end_idx];
    end
`endif

// req
    assign cache_req_valid = en & cache_req;
    assign replace_hit_valid = en & replaceHit & ~axi_req;
    assign axi_req_valid = axi_req & ~axi_req_end;
    PEncoder #(`DCACHE_MISS_SIZE) encoder_cache_req(cache_req_valid, cache_req_idx);
    PEncoder #(`DCACHE_MISS_SIZE) encoder_replace_hit(replace_hit_valid, replace_hit_idx);
    PEncoder #(`DCACHE_MISS_SIZE) encoder_axi_req(axi_req_valid, axi_req_idx);
    PEncoder #(`DCACHE_ID_SIZE) encoder_free_id(~id_valids, free_id);
    assign io.req = |cache_req_valid;
    assign io.req_addr = {addr[cache_req_idx], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign req_idx = req_next & io.req_success ? cache_req_idx_n : replace_hit_idx;
    assign rlast = r_axi_io.r_valid & r_axi_io.r_last;
    assign map_idx = id_map[r_axi_io.r_id];
    always_ff @(posedge clk)begin
        req_next <= io.req;
        cache_req_idx_n <= cache_req_idx;
        req_last <= rlast;
        refill_nodata_valid <= rlast & (cacheIdx[r_id] == 0);
        r_resp <= r_axi_io.r_resp[4: 2];
        if(req_next & io.req_success | (|replace_hit_valid))begin
            way[req_idx] <= req_next & io.req_success ? io.replaceWay : replaceHitWay[replace_hit_idx];
        end
        if((|axi_req_valid) & (|(~id_valids)))begin
            id_map[free_id] <= axi_req_idx;
        end
        if(r_axi_io.r_valid & (cacheIdx[r_id] == 0))begin
            l2_idxs[map_idx] <= io.l2_idx;
        end
        if(r_axi_io.r_valid & ~(r_axi_io.r_last & (cacheIdx[r_id] == 0)))begin
            cacheData[r_id][cacheIdx[r_id]] <= r_axi_io.r_data;
        end
        if(req_last)begin
            refill_state[axi_refill_idx] <= wvalid[axi_refill_idx] | data_valid_all[axi_refill_idx]
`ifdef RVA
                        | amo[axi_refill_idx]
`endif
                        ? 3'b101 : r_resp;
        end
    end

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            axi_req <= 0;
            axi_req_end <= 0;
            axi_state <= IDLE;
            ar_valid <= 0;
            ar_id <= 0;
            ar_addr <= 0;
            id_valids <= 0;
            ar_snoop <= 0;
            cacheIdx <= 0;
            refill_req <= 0;
            data_valid <= 0;
            req_owned_after <= 0;
            req_nodata <= 0;
            axi_req_idx_n <= 0;
        end
        else begin
            if(req_next & io.req_success | (|replace_hit_valid))begin
                axi_req[req_idx] <= 1'b1;
                req_nodata[req_idx] <= 1'b0;
            end

            if(r_axi_io.r_valid & ~(r_axi_io.r_last & (cacheIdx[r_id] == 0)))begin
                cacheIdx[r_id] <= cacheIdx[r_id] + 1;
            end

            if(req_last)begin
                refill_req[axi_refill_idx] <= 1'b1;
                data_valid[axi_refill_idx] <= 1'b1;
            end
            if(io.refill_en & io.refill_valid)begin
                refill_req[refill_idx] <= 1'b0;
            end

            if(req_last & (cacheIdx[r_id] == 0) & wowned[axi_refill_idx] & replaceHit[axi_refill_idx])begin
                req_owned_after[axi_refill_idx] <= 1'b1;
            end
            else if(req_last)begin
                req_owned_after[axi_refill_idx] <= 1'b0;
            end

            if(refill_nodata_valid)begin
                req_nodata[axi_refill_idx] <= 1'b1;
            end

            case(axi_state)
            IDLE:begin
                if((|axi_req_valid) & (|(~id_valids)))begin
                    ar_valid <= 1'b1;
                    ar_addr <= {addr[axi_req_idx], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
                    ar_id <= free_id;
                    id_valids[free_id] <= 1'b1;
                    ar_snoop <= 
`ifdef RVA
                               amo[axi_req_idx] ? `ACEOP_READ_UNIQUE :
`endif
                               data_valid_all[axi_req_idx] ? `ACEOP_MAKE_UNIQUE :
                               wvalid[axi_req_idx] & replaceHit[axi_req_idx] & wowned[axi_req_idx] ? `ACEOP_CLEAN_UNIQUE :
                               wvalid[axi_req_idx] ? `ACEOP_READ_UNIQUE : `ACEOP_READ_SHARED;
                    axi_req_idx_n <= axi_req_idx;
                    axi_state <= REQ;
                end
            end
            REQ: begin
                if(r_axi_io.ar_valid & r_axi_io.ar_ready)begin
                    axi_state <= IDLE;
                    axi_req_end[axi_req_idx_n] <= 1'b1;
                    ar_valid <= 1'b0;
                end
            end
            endcase

            if(|miss_end)begin
                axi_req[miss_end_idx] <= 1'b0;
                axi_req_end[miss_end_idx] <= 1'b0;
                data_valid[miss_end_idx] <= 1'b0;
            end
            if(rlast)begin
                id_valids[r_axi_io.r_id] <= 1'b0;
            end
        end
    end

    assign r_axi_io.ar_valid = ar_valid;
    assign r_axi_io.ar_id = ar_id;
    assign r_axi_io.ar_addr = ar_addr;
    assign r_axi_io.ar_len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign r_axi_io.ar_size = $clog2(`DATA_BYTE);
    assign r_axi_io.ar_burst = 2'b01;
    assign r_axi_io.ar_user = 0;
    assign r_axi_io.ar_snoop = ar_snoop;
    assign r_axi_io.r_ready = 1'b1;
    assign r_id = r_axi_io.r_id;

    assign data_idx = req_last ? axi_refill_idx : widx;
    assign req_mask = mask[data_idx];
    assign req_data = data[data_idx];
    assign cache_req_data = cacheData[r_id_n];
generate
    for(genvar i=0; i<`DCACHE_LINE / `DATA_BYTE; i++)begin
        logic `N(`XLEN) cache_mask;
        MaskExpand #(`DATA_BYTE) expand_cache_mask (req_mask[i], cache_mask);
        assign cache_eq_data[i] = cache_mask & req_data[i] | ~cache_mask & cache_req_data[i];
    
        logic `N(`DCACHE_BITS) expand_mask;
        MaskExpand #(`DCACHE_BYTE) mask_expand(io.wmask[i], expand_mask);
        assign combine_data[i] = (expand_mask & io.wdata[i]) | (~expand_mask & req_data[i]);
        assign combine_mask[i] = io.wmask[i] | req_mask[i];
    end
endgenerate
    always_ff @(posedge clk)begin
        axi_refill_idx <= map_idx;
        r_id_n <= r_id;
        if(req_last)begin
            data[data_idx] <= cache_eq_data;
        end
        else if(io.wen & ~w_invalid & (write_remain_valid | whit_combine))begin
            data[data_idx] <= combine_data;
        end
        if(req_last)begin
            mask[data_idx] <= 0;
        end
        else if(io.wen & ~w_invalid & (write_remain_valid | whit_combine))begin
            mask[data_idx] <= combine_mask;
        end
    end

// refill

    assign refill_valid = en & refill_req;
    PEncoder #(`DCACHE_MISS_SIZE) encoder_refill_idx (refill_valid, refill_idx);
    assign io.refill_en = |refill_valid;
    assign io.refill_state = refill_state[refill_idx];
    assign io.refillWay = way[refill_idx];
    assign io.refillAddr = {addr[refill_idx], {`DCACHE_BANK_WIDTH{1'b0}}, 2'b0};
    assign io.refillMask = {`DCACHE_BANK*`DCACHE_BYTE{~req_owned_after[refill_idx]}};
    assign io.refillData = data[refill_idx];
    assign io.refill_scIdx = scIdxs[refill_idx];
    assign io.refill_l2idx = l2_idxs[refill_idx];
    assign io.refill_write = wvalid[refill_idx];
    assign io.refill_nodata = req_nodata[refill_idx];

// mshr refill
    assign mshr_refill_valid = en & data_valid;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_MSHR_BANK; j++)begin
            assign mshr_hit[i][j] = mshr_en[i][j] & mshr_refill_valid[mshr[i][j].missIdx];
            Decoder #(`DCACHE_MISS_SIZE) decoder_mshr_idx (mshr[i][j].missIdx, mshr_waiting_idx[i][j]);
            assign mshr_waiting_en[i][j] = {`DCACHE_MISS_SIZE{mshr_en[i][j]}} & mshr_waiting_idx[i][j];
        end
        PEncoder #(`DCACHE_MSHR_BANK) pencoder_mshr_idx (mshr_hit[i], mshrIdx[i]);
        ParallelOR #(`DCACHE_MISS_SIZE, `DCACHE_MSHR_BANK) or_mshr_waiting (mshr_waiting_en[i], mshr_waiting_combine[i]);
        assign lq_en[i] = (|mshr_hit[i]);
    end
endgenerate
    ParallelOR #(`DCACHE_MISS_SIZE, `LOAD_PIPELINE) or_mshr_waiting_cmb (mshr_waiting_combine, mshr_waiting);

    always_ff @(posedge clk)begin
        io.lq_en <= lq_en;
    end
generate
    for(genvar i=0; i<`LOAD_REFILL_SIZE; i++)begin
        MSHREntry entry;
        assign entry = mshr[i][mshrIdx[i]];
        always_ff @(posedge clk)begin
            io.lqData[i] <= data[entry.missIdx][entry.offset];
            io.lqIdx_o[i] <= entry.lqIdx;
        end
    end
endgenerate

// miss end
    assign miss_end = en & data_valid & ~refill_valid & ~mshr_waiting;
    PEncoder #(`DCACHE_MISS_SIZE) encoder_miss_end (miss_end, miss_end_idx);

    `PERF(dcache_miss, r_axi_io.ar_valid & r_axi_io.ar_ready)
endmodule