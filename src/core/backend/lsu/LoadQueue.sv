`include "../../../defines/defines.svh"

interface LoadQueueIO;
    logic `N($clog2(`LOAD_DIS_PORT)+1) disNum;
    logic `N(`LOAD_PIPELINE) en;
    logic `N(`LOAD_PIPELINE) miss;
    LoadIssueData `N(`LOAD_PIPELINE) data;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) paddr;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) mask;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) rdata;
    LoadIdx lqIdx;
    ViolationData `N(`STORE_PIPELINE) write_violation;
    ViolationData lq_violation;

    WBData `N(`LOAD_PIPELINE) wbData;
    logic `N(`LOAD_PIPELINE) wb_valid;


    modport queue(input en, miss, disNum, data, paddr, rdata, mask, write_violation, wb_valid,
                  output lqIdx, lq_violation, wbData);
endinterface

module LoadQueue(
    input logic clk,
    input logic rst,
    LoadQueueIO.queue io,
    LoadUnitIO.queue load_io,
    CommitBus.mem commitBus,
    BackendCtrl backendCtrl,
    DCacheLoadIO.queue rio
);
    typedef struct packed {
        logic dir;
        logic `N(`PREG_WIDTH) rd;
        RobIdx robIdx;
        FsqIdxInfo fsqInfo;
    } LoadQueueData;

    logic `N(`LOAD_QUEUE_WIDTH) head, tail, head_n, tail_n;
    logic hdir, tdir, hdir_n;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) eqIdx;
    logic violation;
    logic `N(`LOAD_QUEUE_WIDTH) violation_idx;
    logic `ARRAY(`COMMIT_WIDTH, `LOAD_QUEUE_WIDTH) commitIdx;
    LoadIdx redirectIdx;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) redirectRobIdx;
    LoadIdx `N(`LOAD_PIPELINE) redirectLqIdx;
    logic redirect_next;
    logic `ARRAY(`LOAD_PIPELINE, `ROB_WIDTH) dis_rob_idx;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign eqIdx[i] = io.data[i].lqIdx.idx;
        assign redirectRobIdx[i] = io.data[i].robIdx.idx;
        assign redirectLqIdx[i] = io.data[i].lqIdx;
    end
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitIdx[i] = head + i;
    end
    for(genvar i=0; i<`LOAD_DIS_PORT; i++)begin
        assign dis_rob_idx[i] = load_io.dis_rob_idx[i].idx;
    end
endgenerate

    MPRAM #(
        .WIDTH($bits(LoadIdx)),
        .DEPTH(`ROB_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(`LOAD_PIPELINE)
    ) rob_redirect_ram (
        .clk(clk),
        .rst(rst),
        .en(backendCtrl.redirect),
        .raddr(backendCtrl.redirectIdx.idx),
        .rdata(redirectIdx),
        .we(load_io.dis_en),
        .waddr(dis_rob_idx),
        .wdata(load_io.dis_lq_idx)
    );

    assign io.lqIdx.idx = tail;
    assign io.lqIdx.dir = tdir;
    assign head_n = head + commitBus.loadNum;
    assign tail_n = tail + io.disNum;
    assign hdir_n = head[`LOAD_QUEUE_WIDTH-1] & ~head_n[`LOAD_QUEUE_WIDTH-1] ? ~hdir : hdir;
    always_ff @(posedge clk)begin
        redirect_next <= backendCtrl.redirect;
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            hdir <= 0;
            tdir <= 0;
        end
        else begin
            head <= head_n;
            hdir <= hdir_n;
            if(redirect_next)begin
                tail <= redirectIdx.idx;
                tdir <= redirectIdx.dir;
            end
            else begin
                tail <= tail_n;
                tdir <= tail[`LOAD_QUEUE_WIDTH-1] & ~tail_n[`LOAD_QUEUE_WIDTH-1] ? ~tdir : tdir;
            end

        end
    end

    logic `N(`LOAD_QUEUE_SIZE) valid, miss, dataValid, writeback;
    logic `N(`DCACHE_BITS) data `N(`LOAD_QUEUE_SIZE);
    logic `N(`DCACHE_BYTE) mask `N(`LOAD_QUEUE_SIZE);
    logic `N(`LOAD_QUEUE_SIZE) head_mask, head_n_mask, redirect_mask;

    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) refillData, refillDataCombine;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BYTE) refillMask;
generate
    for(genvar i=0; i<`LOAD_REFILL_SIZE; i++)begin
        assign refillData[i] = data[rio.lqIdx_o[i]];
        assign refillMask[i] = mask[rio.lqIdx_o[i]];
        logic `N(`DCACHE_BITS) expand_mask;
        MaskExpand #(`DCACHE_BYTE) expand_refill_mask (refillMask[i], expand_mask);
        assign refillDataCombine[i] = refillData[i] & expand_mask | rio.lqData[i] & ~expand_mask;
    end
endgenerate

    logic `N(`LOAD_QUEUE_SIZE) waiting_wb;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) wbIdx;
    LoadQueueData `N(`LOAD_PIPELINE) wb_queue_data;

    assign waiting_wb = valid & miss & dataValid & ~writeback;
    /* UNPRARM */
    PEncoder #(`LOAD_QUEUE_SIZE) pencoder_wb_idx (waiting_wb, wbIdx[0]);
    PREncoder #(`LOAD_QUEUE_SIZE) prencoder_wb_idx (waiting_wb, wbIdx[1]);
    assign io.wbData[0].en = |waiting_wb;
    assign io.wbData[1].en = wbIdx[0] != wbIdx[1];
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign io.wbData[i].robIdx = wb_queue_data[i].robIdx;
        assign io.wbData[i].rd = wb_queue_data[i].rd;
        always_ff @(posedge clk)begin
            io.wbData[i].res <= data[wbIdx[i]];
        end
    end
endgenerate

    MaskGen #(`LOAD_QUEUE_SIZE) mask_gen_redirect (redirectIdx.idx, redirect_mask);
    MaskGen #(`LOAD_QUEUE_SIZE) mask_gen_head_n (head_n, head_n_mask);
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            valid <= 0;
            miss <= 0;
            dataValid <= 0;
            writeback <= 0;
        end
        else begin
            for(int i=0; i<`LOAD_DIS_PORT; i++)begin
                if(load_io.dis_en[i])begin
                    valid[load_io.dis_lq_idx[i].idx] <= 1'b1;
                end
            end
            for(int i=0; i<`LOAD_PIPELINE; i++)begin
                if(io.en[i])begin
                    miss[eqIdx[i]] <= io.miss[i];
                    dataValid[eqIdx[i]] <= ~io.miss[i];
                    writeback[eqIdx[i]] <= ~io.miss[i];
                    data[eqIdx[i]] <= io.rdata[i];
                    mask[eqIdx[i]] <= io.mask[i];
                end
                if(io.wbData[i].en & io.wb_valid[i])begin
                    writeback[wbIdx[i]] <= 1'b1;
                end
            end
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(i < commitBus.loadNum)begin
                    valid[commitIdx[i]] <= 1'b0;
                end
            end
            if(redirect_next)begin
                valid <= hdir_n ^ redirectIdx.dir ? ~(head_n_mask ^ redirect_mask) : head_n_mask ^ redirect_mask;
            end
            for(int i=0; i<`LOAD_REFILL_SIZE; i++)begin
                if(rio.lq_en[i])begin
                    dataValid[rio.lqIdx_o[i]] <= 1'b1;
                    data[rio.lqIdx_o[i]] <= refillDataCombine[i];
                end
            end
        end
    end

    LoadQueueData vio_storeData;
    LoadQueueData `N(`LOAD_PIPELINE) writeData;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign writeData[i].dir = io.data[i].lqIdx.dir;
        assign writeData[i].rd = io.data[i].rd;
        assign writeData[i].robIdx = io.data[i].robIdx;
        assign writeData[i].fsqInfo = io.data[i].fsqInfo;
    end
endgenerate
    MPRAM #(
        .WIDTH($bits(LoadQueueData)),
        .DEPTH(`LOAD_QUEUE_SIZE),
        .READ_PORT(`LOAD_PIPELINE+1),
        .WRITE_PORT(`STORE_PIPELINE)
    ) load_queue_data (
        .clk(clk),
        .rst(rst),
        .en({2'b11, violation}),
        .raddr({wbIdx, violation_idx}),
        .rdata({wb_queue_data, vio_storeData}),
        .we(io.en),
        .waddr(eqIdx),
        .wdata(writeData)
    );

    logic `N(`VADDR_SIZE+2) addr_mask `N(`LOAD_QUEUE_SIZE);
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            addr_mask <= '{default: 0};
        end
        else begin
            for(int i=0; i<`LOAD_PIPELINE; i++)begin
                if(io.en[i])begin
                    addr_mask[eqIdx[i]] <= {io.paddr[i][`VADDR_SIZE-1: 2], io.mask[i]};
                end
            end
        end
    end

// violation detect
    logic `ARRAY(`STORE_PIPELINE, `LOAD_QUEUE_SIZE) cmp_vec, valid_vec, violation_vec;
    logic `N(`LOAD_QUEUE_SIZE) violation_vec_combine, violation_vec_mask;
    logic `N(`LOAD_QUEUE_WIDTH) violation_encode, violation_mask_encode;
    logic `N(`LOAD_QUEUE_WIDTH) vio_enc_next, vio_mask_next;
    logic `N(`STORE_PIPELINE) span;
    logic span_combine, span_next, span_en;
    // r 0 0000 0 0111 1 0011
    // w 0 0001 1 0000 0 0001
    // ^   0001   1000   1101
    MaskGen #(`LOAD_QUEUE_SIZE) maskgen_head (head, head_mask);
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_QUEUE_SIZE; j++)begin
            assign cmp_vec[i][j] = io.write_violation[i].en & 
                                   (io.write_violation[i].addr[`VADDR_SIZE-1: 2] == addr_mask[j][`VADDR_SIZE+1: 4]) &
                                   (|(io.write_violation[i].mask & addr_mask[j][3: 0]));
        end
        logic `N(`LOAD_QUEUE_SIZE) store_mask;
        assign span[i] = hdir ^ io.write_violation[i].lqIdx.dir;
        MaskGen #(`LOAD_QUEUE_SIZE) maskgen_store (io.write_violation[i].lqIdx.idx, store_mask);
        assign valid_vec[i] = span[i] ? ~(head_mask ^ store_mask) : head_mask ^ store_mask;
    end
    assign violation_vec = valid_vec & cmp_vec;
    ParallelOR #(`LOAD_QUEUE_SIZE, `STORE_PIPELINE) or_violation_vec(violation_vec, violation_vec_combine);
    ParallelOR #(1, `STORE_PIPELINE) or_span (span, span_combine);
    assign violation_vec_mask = violation_vec_combine & ~head_mask;
    PREncoder #(`LOAD_QUEUE_SIZE) encoder_violation(violation_vec_combine, violation_encode);
    PREncoder #(`LOAD_QUEUE_SIZE) encoder_violation_mask(violation_vec_mask, violation_mask_encode);
endgenerate
    always_ff @(posedge clk)begin
        violation <= |violation_vec;
        vio_enc_next <= violation_encode;
        vio_mask_next <= violation_mask_encode;
        span_en <= |violation_vec_mask;
        span_next <= span_combine;
    end
    assign violation_idx = span_en & span_next ? vio_mask_next : vio_enc_next;

    always_ff @(posedge clk)begin
        io.lq_violation.en <= violation;
        io.lq_violation.lqIdx.idx <= violation_idx;
    end
    assign io.lq_violation.addr = 0;
    assign io.lq_violation.mask = 0;
    assign io.lq_violation.lqIdx.dir = vio_storeData.dir;
    assign io.lq_violation.robIdx = vio_storeData.robIdx;
    assign io.lq_violation.fsqInfo = vio_storeData.fsqInfo;
endmodule