`include "../../../defines/defines.svh"

task getMask(
    input logic [1: 0] offset,
    input logic [1: 0] size,
    output logic [3: 0] mask
);
    if(size == 2'b10)begin
        mask = 4'b1111;
    end
    else if(size == 2'b01)begin
        case (offset)
        2'b00: mask = 4'b0011;
        2'b01: mask = 4'b0110;
        2'b10: mask = 4'b1100;
        2'b11: mask = 4'b1000;
        endcase
    end
    else begin
        case (offset)
        2'b00: mask = 4'b0001;
        2'b01: mask = 4'b0010;
        2'b10: mask = 4'b0100;
        2'b11: mask = 4'b1000;
        endcase
    end
endtask

module LSU(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_load_io,
    DisIssueIO.issue dis_store_io,
    IssueWakeupIO.spec load_wakeup_io,
    IssueWakeupIO.issue store_wakeup_io,
    WakeupBus wakeupBus,
    WriteBackIO.fu lsu_wb_io,
    WriteBackBus wbBus,
    CommitBus.mem commitBus,
    BackendCtrl backendCtrl,
    DCacheAxi.cache axi_io,
    BackendRedirectIO.mem redirect_io,
    CsrTlbIO.tlb csr_ltlb_io,
    CsrTlbIO.tlb csr_stlb_io,
    PTWRequest.cache ptw_request,
    TlbL2IO.tlb dtlb_io,
    output StoreWBData `N(`STORE_PIPELINE) storeWBData
);
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) loadVAddr, storeVAddr;
    /* verilator lint_off UNOPTFLAT */
    LoadIdx `N(`LOAD_PIPELINE) lqIdxs;
    LoadIdx `N(`STORE_PIPELINE) s_lqIdxs;
    /* verilator lint_off UNOPTFLAT */
    StoreIdx `N(`STORE_PIPELINE) sqIdxs;
    StoreIdx `N(`LOAD_PIPELINE) l_sqIdxs;
    LoadIssueData `N(`LOAD_PIPELINE) load_issue_data;
    logic `N(`LOAD_PIPELINE) load_en, fwd_data_invalid; // fwd_data_invalid from StoreQueue
    LoadUnitIO load_io();
    DCacheLoadIO rio();
    DCacheStoreIO wio();
    LoadQueueIO load_queue_io();
    StoreUnitIO store_io();
    StoreQueueIO store_queue_io();
    StoreCommitIO store_commit_io();
    ViolationIO violation_io();
    LoadForwardIO store_queue_fwd();
    LoadForwardIO commit_queue_fwd();
    IssueWakeupIO #(`LOAD_PIPELINE, `LOAD_PIPELINE) li_w_io();
    DTLBLsuIO tlb_lsu_io();

    LoadIssueQueue load_issue_queue(
        .load_wakeup_io(li_w_io),
        .lqIdx(lqIdxs),
        .sqIdx(l_sqIdxs),
        .*
    );
    DCache dcache(.*, .ptw_io(ptw_request));
    LoadQueue load_queue(.*, .io(load_queue_io));
    StoreIssueQueue store_issue_queue(
        .*,
        .sqIdx(sqIdxs), 
        .lqIdx(s_lqIdxs)
    );
    StoreQueue store_queue(
        .*,
        .io(store_queue_io),
        .issue_queue_io(store_io),
        .queue_commit_io(store_commit_io),
        .loadFwd(store_queue_fwd),
        .store_data(store_wakeup_io.data[`STORE_PIPELINE*2-1: `STORE_PIPELINE])
    );
    StoreCommitBuffer store_commit_buffer (
        .*,
        .io(store_commit_io),
        .loadFwd(commit_queue_fwd)
    );
    ViolationDetect violation_detect(.*, .io(violation_io));
    DTLB dtlb(.*, .tlb_l2_io(dtlb_io));

    assign load_wakeup_io.en = li_w_io.en;
    assign load_wakeup_io.preg = li_w_io.preg;
    assign li_w_io.data = load_wakeup_io.data;
    assign li_w_io.ready = load_wakeup_io.ready;
// load
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) lmask_pre;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_PIPELINE) dis_ls_older;
    logic `N(`LOAD_PIPELINE) lmisalign;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign lqIdxs[i].idx = load_queue_io.lqIdx.idx + i;
        assign lqIdxs[i].dir = load_queue_io.lqIdx.idx[`LOAD_QUEUE_WIDTH-1] & ~lqIdxs[i].idx[`LOAD_QUEUE_WIDTH-1] ? ~load_queue_io.lqIdx.dir : load_queue_io.lqIdx.dir;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : load_sqIdx
        MemIssueBundle loadBundle;
        assign loadBundle = dis_load_io.data[i];
        for(genvar j=0; j<`STORE_PIPELINE; j++)begin
            MemIssueBundle storeBundle;
            logic older;
            assign storeBundle = dis_store_io.data[j];
            LoopCompare #(`ROB_WIDTH) compare_older (storeBundle.robIdx, loadBundle.robIdx, older);
            assign dis_ls_older[i][j] = older & dis_store_io.en[j] & ~dis_store_io.full;
        end
        logic `N($clog2(`STORE_PIPELINE)+1) store_idx;
        StoreIdx l_sqIdx;
        ParallelAdder #(1, `STORE_PIPELINE) adder_store_idx (dis_ls_older[i], store_idx);
        LoopAdder #(`STORE_QUEUE_WIDTH, $clog2(`STORE_PIPELINE)+1) adder_lqIdx(store_idx, store_queue_io.sqIdx, l_sqIdx);
        assign l_sqIdxs[i] = l_sqIdx;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : load_addr
        AGU agu(
            .imm(load_io.loadIssueData[i].imm),
            .data(load_wakeup_io.data[i]),
            .addr(loadVAddr[i])
        );
        always_comb begin
            getMask(loadVAddr[i][1: 0], load_io.loadIssueData[i].size, lmask_pre[i]);
        end
        MisalignDetect misalign_detect (load_io.loadIssueData[i].size, loadVAddr[i][`DCACHE_BYTE_WIDTH-1: 0], lmisalign[i]);
    end
endgenerate
    // load request
    assign rio.req = load_io.en;
    assign rio.vaddr = loadVAddr;

    // tlb
    logic `ARRAY(`LOAD_PIPELINE, `TLB_TAG) lptag;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) lpaddr;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) loadAddrNext;
    logic `ARRAY(`LOAD_PIPELINE, 4) lmask, lmaskNext;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) load_issue_idx;
    logic `N(`LOAD_PIPELINE) redirect_clear_req;
    logic `N(`LOAD_PIPELINE) lmisalign_s2;
    logic `N(`LOAD_PIPELINE) tlb_exception_s2, tlb_exception_s2_pre;

    assign tlb_lsu_io.lreq = load_io.en & ~load_io.exception;
    assign tlb_lsu_io.lidx = load_io.issue_idx;
    assign tlb_lsu_io.laddr = loadVAddr;
    assign tlb_lsu_io.lreq_cancel = lmisalign_s2;
    assign tlb_lsu_io.flush = backendCtrl.redirect;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, load_io.loadIssueData[i].robIdx, older);
        assign redirect_clear_req[i] = backendCtrl.redirect & older;
        assign lptag = tlb_lsu_io.lpaddr[i][`PADDR_SIZE-1: `TLB_OFFSET];
    end
endgenerate
    assign rio.req_cancel = redirect_clear_req;
    assign tlb_exception_s2 = tlb_lsu_io.lexception | tlb_exception_s2_pre;
    always_ff @(posedge clk)begin
        loadAddrNext <= loadVAddr;
        load_issue_data <= load_io.loadIssueData;
        lmask <= lmask_pre;
        load_en <= load_io.en & ~redirect_clear_req;
        load_issue_idx <= load_io.issue_idx;
        lmisalign_s2 <= lmisalign;
        tlb_exception_s2_pre <= load_io.exception;
    end
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign lpaddr[i] = {lptag[i], loadAddrNext[i][11: 0]};
        assign rio.lqIdx[i] = load_issue_data[i].lqIdx.idx;
        assign rio.robIdx[i] = load_issue_data[i].robIdx;
    end
endgenerate
    assign rio.ptag = lptag;

    // reply fast
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign load_io.reply_fast[i].en = load_en[i] & rio.conflict[i] | tlb_lsu_io.lmiss[i];
        assign load_io.reply_fast[i].issue_idx = load_issue_idx[i];
        assign load_io.reply_fast[i].reason = tlb_lsu_io.lmiss[i] ? 2'b11 : 2'b00;
    end
endgenerate

    // load data
    logic `ARRAY(`LOAD_PIPELINE, 32) rdata;
    logic `N(`LOAD_PIPELINE) rdata_valid;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic `N(`DCACHE_BITS) combine_queue_data;
        logic `N(`DCACHE_BITS) expand_mask, expand_commit_mask;
        MaskExpand #(`DCACHE_BYTE) mask_expand(store_queue_fwd.mask[i], expand_mask);
        MaskExpand #(`DCACHE_BYTE) mask_expand_commit(commit_queue_fwd.mask[i], expand_commit_mask);
        assign combine_queue_data = (rio.rdata[i] & ~expand_mask) | (store_queue_fwd.data[i] & expand_mask);
        assign rdata[i] = (combine_queue_data & ~expand_commit_mask) | (commit_queue_fwd.data[i] & expand_commit_mask);
        assign rdata_valid[i] = ((store_queue_fwd.mask[i] | commit_queue_fwd.mask[i]) & lmaskNext[i]) == lmaskNext[i];
    end
endgenerate

    // load enqueue
    LoadIssueData `N(`LOAD_PIPELINE) leq_data;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) lpaddrNext;
    logic `N(`LOAD_PIPELINE) leq_en, leq_valid;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx_next;

    logic `N(`LOAD_PIPELINE) redirect_clear_s2, redirect_clear_s3;
    logic `N(`LOAD_PIPELINE) lmisalign_s3;
    logic `N(`LOAD_PIPELINE) tlb_exception_s3;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, load_issue_data[i].robIdx, older);
        assign redirect_clear_s2[i] = backendCtrl.redirect & older;
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, leq_data[i].robIdx, older);
        assign redirect_clear_s3[i] = backendCtrl.redirect & older;
    end
endgenerate
    assign rio.req_cancel_s2 = redirect_clear_s2 | lmisalign_s2 | tlb_exception_s2;
    assign rio.req_cancel_s3 = redirect_clear_s3 | rdata_valid;

    always_ff @(posedge clk)begin
        lpaddrNext <= lpaddr;
        leq_data <= load_issue_data;
        leq_en <= load_en & ~rio.conflict & ~redirect_clear_s2 & ~tlb_lsu_io.lmiss;
        lmaskNext <= lmask;
        issue_idx_next <= load_issue_idx;
        lmisalign_s3 <= lmisalign_s2;
        tlb_exception_s3 <= tlb_exception_s2;
    end
    assign leq_valid = leq_en & ~fwd_data_invalid & ~redirect_clear_s3;
    assign load_queue_io.disNum = load_io.eqNum;
    assign load_queue_io.en = leq_valid;
    assign load_queue_io.data = leq_data;
    assign load_queue_io.paddr = lpaddrNext;
    assign load_queue_io.mask = lmaskNext;
    assign load_queue_io.rmask = (store_queue_fwd.mask | commit_queue_fwd.mask);
    assign load_queue_io.rdata = rdata;
    assign load_queue_io.miss = ~rio.hit & ~rdata_valid & ~lmisalign_s3 & ~tlb_exception_s3;
    assign load_queue_io.wb_valid = ~leq_valid;

    // reply slow
    logic `N(`LOAD_PIPELINE) fwd_data_invalid_n, lreply_en;
    logic `N(`LOAD_PIPELINE) lmiss;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx_n2;
    always_ff @(posedge clk)begin
        fwd_data_invalid_n <= fwd_data_invalid  & ~lmisalign_s3 & ~tlb_exception_s3;
        lreply_en <= leq_en & ~redirect_clear_s3;
        issue_idx_n2 <= issue_idx_next;
        lmiss <= ~rio.hit & ~rdata_valid & ~lmisalign_s3 & ~tlb_exception_s3;
    end
    assign load_io.success = lreply_en & ~fwd_data_invalid_n  & ~(lmiss & rio.full);
    assign load_io.success_idx = issue_idx_n2;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign load_io.reply_slow[i].en = lreply_en[i] & (fwd_data_invalid_n[i] | (lmiss[i] & rio.full[i])) | tlb_lsu_io.lcancel[i];
        assign load_io.reply_slow[i].issue_idx = issue_idx_n2[i];
        assign load_io.reply_slow[i].reason = fwd_data_invalid_n ? 2'b10 : 2'b00;
    end
endgenerate
    
    // wb
    logic `N(`LOAD_PIPELINE) from_issue;
    RobIdx `N(`LOAD_PIPELINE) lrobIdx_n;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) lrd_n;
    logic `ARRAY(`LOAD_PIPELINE, `XLEN) ldata_n, ldata_shift;
    logic `ARRAY(`LOAD_PIPELINE, `EXC_WIDTH) lexccode;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : rdata_wb
        logic wb_data_en, wb_pipeline_en;
        RDataGen data_gen (leq_data[i].uext, leq_data[i].size, lpaddrNext[`DCACHE_BYTE_WIDTH-1: 0], rdata[i], ldata_shift[i]);
        assign wb_pipeline_en = leq_en[i] & (lmisalign_s3[i] | tlb_exception_s3 | 
                                ((rio.hit[i] | rdata_valid[i]) & ~fwd_data_invalid[i])) &
                                ~redirect_clear_s3[i];
        always_ff @(posedge clk)begin
            wb_data_en <= wb_pipeline_en | load_queue_io.wbData[i].en;
            from_issue[i] <= wb_pipeline_en;
            lrobIdx_n[i] <= leq_data[i].robIdx;
            lrd_n[i] <= leq_data[i].rd;
            ldata_n[i] <= ldata_shift[i];
            lexccode[i] <= tlb_exception_s3[i] ? `EXC_LPF : 
                           lmisalign_s3[i] ? `EXC_LAM : `EXC_NONE;
        end
        assign lsu_wb_io.datas[i].en = wb_data_en;
        assign lsu_wb_io.datas[i].robIdx = from_issue[i] ? lrobIdx_n[i] : load_queue_io.wbData[i].robIdx;
        assign lsu_wb_io.datas[i].rd = from_issue[i] ? lrd_n[i] : load_queue_io.wbData[i].rd;
        assign lsu_wb_io.datas[i].res = from_issue[i] ? ldata_n[i] : load_queue_io.wbData[i].res;
        assign lsu_wb_io.datas[i].exccode = lexccode;
        assign load_wakeup_io.wakeup_en[i] = wb_data_en;
        assign load_wakeup_io.rd[i] = lsu_wb_io.datas[i].rd;
    end
endgenerate

// store
    logic `ARRAY(`STORE_PIPELINE, `TLB_TAG) sptag;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE) spaddr;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) storeAddrNext;
    logic `ARRAY(`STORE_PIPELINE, 4) smask;
    logic `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) dis_sl_older;
    logic `N(`STORE_PIPELINE) store_en;
    StoreIssueData `N(`STORE_PIPELINE) store_issue_data;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx;

    logic `N(`STORE_PIPELINE) store_redirect_clear_req;
    logic `N(`STORE_PIPELINE) store_redirect_s2;
    logic `N(`STORE_PIPELINE) smisalign, smisalign_s2;
    logic `N(`STORE_PIPELINE) stlb_exception, stlb_exception_s2;
    logic `N(`STORE_PIPELINE) stlb_miss;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx_s2;

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, store_io.storeIssueData[i].robIdx, older);
        assign store_redirect_clear_req[i] = backendCtrl.redirect & older;
    end
endgenerate


generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign sqIdxs[i].idx = store_queue_io.sqIdx.idx + i;
        assign sqIdxs[i].dir = store_queue_io.sqIdx.idx[`STORE_QUEUE_WIDTH-1] & ~sqIdxs[i].idx[`STORE_QUEUE_WIDTH-1] ? ~store_queue_io.sqIdx.dir : store_queue_io.sqIdx.dir;
    end

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin : store_lqIdx
        MemIssueBundle storeBundle;
        assign storeBundle = dis_store_io.data[i];
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            MemIssueBundle loadBundle;
            logic older;
            assign loadBundle = dis_load_io.data[j];
            LoopCompare #(`ROB_WIDTH) compare_older (loadBundle.robIdx, storeBundle.robIdx, older);
            assign dis_sl_older[i][j] = older & dis_load_io.en[j] & ~dis_load_io.full;
        end
        logic `N($clog2(`LOAD_PIPELINE)+1) load_idx;
        LoadIdx s_lqIdx;
        ParallelAdder #(1, `LOAD_PIPELINE) adder_load_idx (dis_sl_older[i], load_idx);
        LoopAdder #(`LOAD_QUEUE_WIDTH, $clog2(`LOAD_PIPELINE)+1) adder_lqIdx(load_idx, load_queue_io.lqIdx, s_lqIdx);
        assign s_lqIdxs[i] = s_lqIdx;
    end
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin : store_addr
        AGU agu(
            .imm(store_io.storeIssueData[i].imm),
            .data(store_wakeup_io.data[i]),
            .addr(storeVAddr[i])
        );
        assign sptag[i] = tlb_lsu_io.spaddr[i][`PADDR_SIZE-1: `TLB_OFFSET];
        always_ff @(posedge clk)begin
            store_en[i] <= store_io.en[i] & ~store_redirect_clear_req;
            store_issue_data[i] <= store_io.storeIssueData[i];
            storeAddrNext[i] <= storeVAddr[i];
            smisalign_s2[i] <= smisalign[i];
            stlb_exception[i] <= store_io.exception[i];
            sissue_idx_s2[i] <= sissue_idx[i];
        end
        always_comb begin
            getMask(storeAddrNext[i][1: 0], store_issue_data[i].size, smask[i]);
        end
        MisalignDetect misalign_detect (store_io.storeIssueData[i].size, storeVAddr[i][`DCACHE_BYTE_WIDTH-1: 0], smisalign[i]);
        assign spaddr[i] = {sptag[i], storeAddrNext[i][11: 0]};
    end

    assign stlb_exception_s2 = stlb_exception | tlb_lsu_io.sexception;

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, store_issue_data[i].robIdx, older);
        assign store_redirect_s2[i] = backendCtrl.redirect & older;
    end
endgenerate

    assign sissue_idx = store_io.issue_idx;
    assign tlb_lsu_io.sreq = store_io.en & ~store_io.exception;
    assign tlb_lsu_io.sreq_cancel = smisalign_s2;
    assign tlb_lsu_io.sidx = sissue_idx;
    assign tlb_lsu_io.saddr = storeVAddr;

    //store enqueue
    assign stlb_miss = tlb_lsu_io.smiss;
    assign store_queue_io.en = store_en & ~store_redirect_s2 & ~stlb_miss;
    assign store_queue_io.data = store_issue_data;
    assign store_queue_io.paddr = spaddr;
    assign store_queue_io.mask = smask;

    // store wb
    // delay two cycle for violation detect
    logic `N(`STORE_PIPELINE) store_en_s3;
    RobIdx `N(`STORE_PIPELINE) store_robIdx_s3;
    logic `ARRAY(`STORE_PIPELINE, `EXC_WIDTH) exccode_s3;
    logic `N(`STORE_PIPELINE) store_redirect_s3;
    logic `N(`STORE_PIPELINE) stlb_miss_s3;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx_s3;
    logic `N(`STORE_PIPELINE) store_en_s4;
    RobIdx `N(`STORE_PIPELINE) store_robIdx_s4;
    logic `ARRAY(`STORE_PIPELINE, `EXC_WIDTH) exccode_s4;
    logic `N(`STORE_PIPELINE) store_redirect_s4;
    logic `N(`STORE_PIPELINE) stlb_miss_s4;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx_s4;

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic bigger;
        LoopCompare #(`ROB_WIDTH) cmp_bigger (backendCtrl.redirectIdx, store_robIdx_s3[i], bigger);
        assign store_redirect_s3[i] = backendCtrl.redirect & bigger;

        logic bigger_s4;
        LoopCompare #(`ROB_WIDTH) cmp_bigger_s4 (backendCtrl.redirectIdx, store_robIdx_s4[i], bigger_s4);
        assign store_redirect_s4[i] = backendCtrl.redirect & bigger_s4;
        always_ff @(posedge clk)begin
            store_en_s3[i] <= store_en[i] & ~store_redirect_s2[i];
            store_robIdx_s3[i] <= store_issue_data[i].robIdx;
            exccode_s3[i] <= tlb_exception_s2[i] ? `EXC_SPF: 
                             smisalign_s2[i] ? `EXC_SAM : `EXC_NONE;
            stlb_miss_s3[i] <= stlb_miss[i];
            sissue_idx_s3[i] <= sissue_idx_s2[i];
            store_en_s4[i] <= store_en_s3[i] & ~store_redirect_s3[i];
            store_robIdx_s4[i] <= store_robIdx_s3[i];
            exccode_s4[i] <= exccode_s3[i];
            stlb_miss_s4[i] <= stlb_miss_s3[i];
            sissue_idx_s4[i] <= sissue_idx_s3[i];

            storeWBData[i].en <= store_en_s4[i] & ~store_redirect_s4[i] & ~stlb_miss_s4[i];
            storeWBData[i].robIdx <= store_robIdx_s4[i];
            storeWBData[i].exccode <= exccode_s4[i];
        end
    end
endgenerate

    assign store_io.success = store_en_s4 & ~stlb_miss_s4;
    assign store_io.success_idx = sissue_idx_s4;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign store_io.reply[i].en = store_en_s4[i] & (stlb_miss_s4[i] | tlb_lsu_io.scancel[i]);
        assign store_io.reply[i].issue_idx = sissue_idx_s4;
        assign store_io.reply[i].reason = tlb_lsu_io.scancel[i] ? 2'b00 : 2'b11;
    end
endgenerate

// store load detect
    assign violation_io.lq_data = load_queue_io.lq_violation;
    assign load_queue_io.write_violation = violation_io.wdata;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign violation_io.wdata[i].en = store_en[i];
        assign violation_io.wdata[i].addr = spaddr[i];
        assign violation_io.wdata[i].mask = smask[i];
        assign violation_io.wdata[i].lqIdx = store_issue_data[i].lqIdx;
        assign violation_io.wdata[i].robIdx = store_issue_data[i].robIdx;
        assign violation_io.wdata[i].fsqInfo = store_issue_data[i].fsqInfo;
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign violation_io.s1_data[i].en = load_en[i];
        assign violation_io.s1_data[i].addr = lpaddr[i];
        assign violation_io.s1_data[i].mask = lmask[i];
        assign violation_io.s1_data[i].lqIdx = load_issue_data[i].lqIdx;
        assign violation_io.s1_data[i].robIdx = load_issue_data[i].lqIdx;
        assign violation_io.s1_data[i].fsqInfo = load_issue_data[i].fsqInfo;

        assign violation_io.s2_data[i].en = leq_en[i];
        assign violation_io.s2_data[i].addr = lpaddrNext[i];
        assign violation_io.s2_data[i].mask = lmaskNext[i];
        assign violation_io.s2_data[i].lqIdx = leq_data[i].lqIdx;
        assign violation_io.s2_data[i].robIdx = leq_data[i].lqIdx;
        assign violation_io.s2_data[i].fsqInfo = leq_data[i].fsqInfo;
    end
endgenerate

// forward
    LoadFwdData `N(`LOAD_PIPELINE) fwdData;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign fwdData[i].en = load_io.en[i];
        assign fwdData[i].sqIdx = load_io.loadIssueData[i].sqIdx;
        assign fwdData[i].vaddrOffset = loadVAddr[i][`TLB_OFFSET-1: 0];
        assign fwdData[i].ptag = lptag[i];
    end
endgenerate
    assign store_queue_fwd.fwdData = fwdData;
    assign commit_queue_fwd.fwdData = fwdData;

endmodule

interface ViolationIO;
    ViolationData `N(`STORE_PIPELINE) wdata;
    ViolationData `N(`LOAD_PIPELINE) s1_data;
    ViolationData `N(`LOAD_PIPELINE) s2_data;
    ViolationData lq_data;

    modport violation(input wdata, s1_data, s2_data, lq_data);
endinterface

module ViolationDetect(
    input logic clk,
    input logic rst,
    ViolationIO.violation io,
    BackendRedirectIO.mem redirect_io
);
    ViolationData `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) s1_cmp;
    ViolationData `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) s2_cmp;
    ViolationData `N(`STORE_PIPELINE) s1_result, s1_result_o;
    ViolationData `N(`STORE_PIPELINE) s2_result, s2_result_o;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            ViolationCompare cmp_s1(io.wdata[i], io.s1_data[j], s1_cmp[i][j]);
            ViolationCompare cmp_s2(io.wdata[i], io.s2_data[j], s2_cmp[i][j]);
        end
        /* UNPARAM */
        ViolationOlderCompare cmp_s1_result (s1_cmp[i][0], s1_cmp[i][1], s1_result[i]);
        ViolationOlderCompare cmp_s2_result (s2_cmp[i][0], s2_cmp[i][1], s2_result[i]);
    end
endgenerate

    always_ff @(posedge clk)begin
        s1_result_o <= s1_result;
        s2_result_o <= s2_result;
    end
    ViolationData s1_older, s2_older, pipeline_result, pipeline_o;
    /* UNPARAM */
    ViolationOlderCompare cmp_s1_older (s1_result_o[0], s1_result_o[1], s1_older);
    ViolationOlderCompare cmp_s2_older (s2_result_o[0], s2_result_o[1], s2_older);
    ViolationOlderCompare cmp_pipeline (s1_older, s2_older, pipeline_result);

    always_ff @(posedge clk)begin
        pipeline_o <= pipeline_result;
    end
    ViolationData out;
    ViolationOlderCompare cmp_out (pipeline_o, io.lq_data, out);
    logic `N(`ROB_WIDTH) robIdx_p;
    assign robIdx_p = out.robIdx.idx - 1;
    assign redirect_io.memRedirect.en = out.en;
    assign redirect_io.memRedirect.robIdx.idx = robIdx_p;
    assign redirect_io.memRedirect.robIdx.dir = robIdx_p[`ROB_WIDTH-1] & ~out.robIdx.idx[`ROB_WIDTH-1] ? ~out.robIdx.dir : out.robIdx.dir;
    assign redirect_io.memRedirect.fsqInfo = out.fsqInfo;
    assign redirect_io.memRedirectIdx = out.robIdx;
endmodule

module ViolationCompare(
    input ViolationData cmp1,
    input ViolationData cmp2,
    output ViolationData out
);
    logic older, conflict;
    LoopCompare #(`LOAD_QUEUE_WIDTH) compare_lq (cmp1.lqIdx, cmp2.lqIdx, older);
    assign conflict = (cmp1.addr[`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH] == cmp2.addr[`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH]) &&
                      (|(cmp1.mask & cmp2.mask));
    assign out.addr = cmp2.addr;
    assign out.mask = cmp2.mask;
    assign out.lqIdx = cmp2.lqIdx;
    assign out.robIdx = cmp2.robIdx;
    assign out.fsqInfo = cmp2.fsqInfo;
    assign out.en = cmp1.en & cmp2.en & older & conflict;
endmodule

module ViolationOlderCompare(
    input ViolationData cmp1,
    input ViolationData cmp2,
    output ViolationData out
);
    logic older;
    LoopCompare #(`LOAD_QUEUE_WIDTH) compare_lq (cmp1.lqIdx, cmp2.lqIdx, older);
    assign out = cmp1.en & older | cmp1.en & ~cmp2.en ? cmp1 : cmp2;
endmodule

module RDataGen(
    input logic uext,
    input logic [1: 0] size,
    input logic [`DCACHE_BYTE_WIDTH-1: 0] offset,
    input logic [`XLEN-1: 0] data,
    output logic [`XLEN-1: 0] data_o
);
    logic [7: 0] byte_data;
    logic [15: 0] half;
    logic [31: 0] word;
    logic `ARRAY(`DCACHE_BYTE, 8) db;
    logic `ARRAY(`DCACHE_BYTE, `DCACHE_BYTE_WIDTH) idx;
generate
    for(genvar i=0; i<`DCACHE_BYTE; i++)begin
        assign idx[i] = offset + i;
    end
endgenerate
    assign db = data;
    assign byte_data = db[idx[0]];
    assign half = {db[idx[1]], byte_data};
    assign word = {db[idx[3]], db[idx[2]], half};
    always_comb begin
        case(size)
        2'b00: data_o = {{`XLEN-8{~uext & byte_data[7]}}, byte_data};
        2'b01: data_o = {{`XLEN-16{~uext & half[15]}}, half};
        2'b10: data_o = {{`XLEN-32{~uext & word[31]}}, word};
        default: data_o = 0;
        endcase
    end
endmodule

module MisalignDetect(
    input logic [1: 0] size,
    input logic `N(`DCACHE_BYTE_WIDTH) offset,
    output misalign
);
    always_comb begin
        case(size)
        2'b10: misalign = |offset[1: 0];
        2'b01: misalign = offset[0];
        default: misalign = 1'b0;
        endcase
    end
endmodule