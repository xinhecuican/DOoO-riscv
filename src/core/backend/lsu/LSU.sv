`include "../../../defines/defines.svh"

module getMask(
    input logic [1: 0] offset,
    input logic [1: 0] size,
    output logic [3: 0] mask
);
    always_comb begin
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
    end
endmodule

module LSU(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_load_io,
    DisIssueIO.issue dis_store_io,
`ifdef RVA
    DisIssueIO.issue dis_amo_io,
    IssueRegIO.issue amo_reg_io,
`endif
    IssueRegIO.issue load_reg_io,
    IssueRegIO.issue store_reg_io,
    IssueWakeupIO.issue load_wakeup_io,
    input WakeupBus int_wakeupBus,
`ifdef RVF
    input WakeupBus fp_wakeupBus,
`endif
    WriteBackIO.fu lsu_wb_io,
    CommitBus.mem commitBus,
    input BackendCtrl backendCtrl,
    AxiIO.master axi_io,
    AxiIO.master ducache_io,
    NativeSnoopIO.master snoop_io,
    BackendRedirectIO.mem redirect_io,
    CsrTlbIO.tlb csr_ltlb_io,
    CsrTlbIO.tlb csr_stlb_io,
    TlbL2IO.tlb dtlb_io,
    FenceBus.lsu fenceBus,
    output StoreWBData `N(`STORE_PIPELINE) storeWBData,
    output LoadIdx lqIdx,
    output StoreIdx sqIdx,
    output logic `N(`VADDR_SIZE) exc_vaddr
);
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) loadVAddr, storeVAddr;
    LoadIssueData `N(`LOAD_PIPELINE) load_issue_data;
    logic `N(`LOAD_PIPELINE) load_en, fwd_data_invalid; // fwd_data_invalid from StoreQueue
    logic sc_buffer_empty;
    logic sc_queue_empty;
    
    logic `N(`LOAD_PIPELINE) from_issue;

    LoadUnitIO load_io();
    DCacheLoadIO rio();
    DCacheStoreIO wio();
    LoadQueueIO load_queue_io();

    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, 1
    ) laxi_io();
    StoreUnitIO store_io();
    StoreQueueIO store_queue_io();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, 1
    ) saxi_io();
    StoreCommitIO store_commit_io();
    ViolationIO violation_io();
    LoadForwardIO store_queue_fwd();
    LoadForwardIO commit_queue_fwd();
    DTLBLsuIO tlb_lsu_io();
    FenceBus fenceBus_tlb();

`ifdef RVA
    DCacheAmoIO amo_io();
    logic amo_valid;
    RobIdx amo_idx;
    logic `N(`LOAD_PIPELINE) amo_conflict;
    logic amo_flush, amo_flush_end, amo_ready;
    WBData amo_wdata;
    assign amo_flush_end = sc_buffer_empty & sc_queue_empty;
    assign amo_ready = ~from_issue[0] & ~load_queue_io.int_wbData[0].en;
    AmoQueue amo_queue(
        .*,
        .tlb_req(tlb_lsu_io.amo_req),
        .amo_vaddr(tlb_lsu_io.amo_addr),
        .tlb_valid(tlb_lsu_io.amo_valid),
        .tlb_error(tlb_lsu_io.amo_error),
        .tlb_exception(tlb_lsu_io.amo_exception),
        .fence_valid(fenceBus.valid),
        .amo_paddr(tlb_lsu_io.amo_paddr),
        .store_flush(amo_flush),
        .flush_end(amo_flush_end),
        .wb_ready(amo_ready),
        .wbData(amo_wdata)
    );
`endif
    LoadIssueQueue load_issue_queue(
        .*,
        .wakeupBus(int_wakeupBus)
    );
    DCache dcache(.*);
    LoadQueue load_queue(.*, .io(load_queue_io), .fence_valid(fenceBus.valid | commitBus.fence_valid));
    StoreIssueQueue store_issue_queue(.*);
    StoreQueue store_queue(
        .*,
        .io(store_queue_io),
        .issue_queue_io(store_io),
        .queue_commit_io(store_commit_io),
        .loadFwd(store_queue_fwd),
        .fence_valid(fenceBus.valid | commitBus.fence_valid),
`ifdef RVF
        .store_data(store_reg_io.data[`STORE_PIPELINE +: `STORE_PIPELINE * 2]),
`else
        .store_data(store_reg_io.data[`STORE_PIPELINE*2-1: `STORE_PIPELINE]),
`endif
        .commit_empty(sc_queue_empty)
    );
    StoreCommitBuffer store_commit_buffer (
        .*,
`ifdef RVA
        .flush(fenceBus.store_flush | amo_flush),
`else
        .flush(fenceBus.store_flush),
`endif
        .io(store_commit_io),
        .loadFwd(commit_queue_fwd),
        .empty(sc_buffer_empty)
    );
    ViolationDetect violation_detect(.*, .tail(load_queue_io.lqIdx), .io(violation_io));
    DTLB dtlb(.*, .tlb_l2_io(dtlb_io), .fenceBus(fenceBus_tlb.mmu));

    assign lqIdx = load_queue_io.lqIdx;
    assign sqIdx = store_queue_io.sqIdx;
    `AXI_ASSIGN_R_REQ(ducache_io, laxi_io)
    `AXI_ASSIGN_W_REQ(ducache_io, saxi_io)
    always_ff @(posedge clk)begin
        fenceBus.store_flush_end <= sc_buffer_empty & sc_queue_empty;
    end
    assign fenceBus_tlb.mmu_flush = fenceBus.mmu_flush;
    assign fenceBus_tlb.mmu_flush_all = fenceBus.mmu_flush_all;
    assign fenceBus_tlb.vma_vaddr = fenceBus.vma_vaddr;
    assign fenceBus_tlb.vma_asid = fenceBus.vma_asid;
// load
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) lmask_pre;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_PIPELINE) dis_ls_older;
    logic `N(`LOAD_PIPELINE) lmisalign;
generate

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : load_addr
        AGU agu(
            .imm(load_io.loadIssueData[i].imm),
            .data(load_reg_io.data[i]),
            .addr(loadVAddr[i])
        );
        getMask get_mask(loadVAddr[i][1: 0], load_io.loadIssueData[i].size, lmask_pre[i]);
        MisalignDetect misalign_detect (load_io.loadIssueData[i].size, loadVAddr[i][`DCACHE_BYTE_WIDTH-1: 0], lmisalign[i]);
    end
endgenerate
    // load request
    assign rio.req = load_io.en;
    assign rio.vaddr = loadVAddr;
    /* verilator lint_off UNOPTFLAT */
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_PIPELINE) oldest_cmp;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            if(i == j)begin
                assign oldest_cmp[i][j] = 1'b1;
            end
            else if(i < j)begin
                LoopCompare #(`LOAD_QUEUE_WIDTH) cmp_older (load_io.loadIssueData[i].lqIdx, load_io.loadIssueData[j].lqIdx, oldest_cmp[i][j]); 
            end
            else begin
                assign oldest_cmp[i][j] = ~oldest_cmp[j][i];
            end
        end
        assign rio.oldest[i] = &oldest_cmp[i];
    end
endgenerate

    // tlb
    logic `ARRAY(`LOAD_PIPELINE, `TLB_TAG) lptag;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) lpaddr;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) loadAddrNext;
    logic `ARRAY(`LOAD_PIPELINE, 4) lmask, lmaskNext;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) load_issue_idx;
    logic `N(`LOAD_PIPELINE) redirect_clear_req;
    logic `N(`LOAD_PIPELINE) lmisalign_s2;
    logic `N(`LOAD_PIPELINE) tlb_exception_s2, tlb_exception_s2_pre;
    logic `N(`LOAD_PIPELINE) luncache_s2, luncache_s3;
    logic `N(`LOAD_PIPELINE) uncache_full_s3, uncache_full_s4;
    logic `N(`LOAD_PIPELINE) redirect_clear_s2, redirect_clear_s3;
`ifdef RVA
    logic amo_req;
    always_ff @(posedge clk)begin
        amo_req <= tlb_lsu_io.amo_req;
    end
`endif

    assign tlb_lsu_io.lreq = load_io.en & ~load_io.exception;
    assign tlb_lsu_io.lreq_s2 = load_en & ~lmisalign_s2 & ~redirect_clear_s2;
    assign tlb_lsu_io.lidx = load_io.issue_idx;
    assign tlb_lsu_io.laddr = loadVAddr;
    assign tlb_lsu_io.flush = backendCtrl.redirect;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, load_io.loadIssueData[i].robIdx, older);
        assign redirect_clear_req[i] = backendCtrl.redirect & older;
        assign lptag[i] = tlb_lsu_io.lpaddr[i][`PADDR_SIZE-1: `TLB_OFFSET];
    end
endgenerate
    assign rio.req_cancel = redirect_clear_req;
    assign tlb_exception_s2 = tlb_lsu_io.lexception | tlb_exception_s2_pre;
    assign luncache_s2 = tlb_lsu_io.luncache;
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
        assign lpaddr[i] = {lptag[i], loadAddrNext[i][`TLB_OFFSET-1: 0]};
        assign rio.lqIdx[i] = load_issue_data[i].lqIdx.idx;
        assign rio.robIdx[i] = load_issue_data[i].robIdx;
    end
endgenerate
    assign rio.ptag = lptag;

    // reply fast
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
`ifdef RVA
        logic amo_older;
        LoopCompare #(`ROB_WIDTH) cmp_amo_bigger (amo_idx, load_io.loadIssueData[i].robIdx, amo_older);
        always_ff @(posedge clk)begin
            amo_conflict[i] <= amo_older & amo_valid;
        end
        if(i == 0)begin
            assign load_io.reply_fast[i].en = load_en[i] & (rio.conflict[i] | amo_req | amo_conflict[i]);
            assign load_io.reply_fast[i].issue_idx = load_issue_idx[i];
            assign load_io.reply_fast[i].reason = 2'b00;
        end
        else begin
            assign load_io.reply_fast[i].en = load_en[i] & (rio.conflict[i] | amo_conflict[i]);
            assign load_io.reply_fast[i].issue_idx = load_issue_idx[i];
            assign load_io.reply_fast[i].reason = 2'b00;
        end
`else
        assign load_io.reply_fast[i].en = load_en[i] & (rio.conflict[i]);
        assign load_io.reply_fast[i].issue_idx = load_issue_idx[i];
        assign load_io.reply_fast[i].reason = 2'b00;
`endif
    end
endgenerate

    // load data
    logic `ARRAY(`LOAD_PIPELINE, 32) rdata;
    logic `N(`LOAD_PIPELINE) rdata_valid;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : data_gen
        logic `N(`DCACHE_BITS) combine_queue_data;
        logic `N(`DCACHE_BITS) expand_mask, expand_commit_mask;
        MaskExpand #(`DCACHE_BYTE) mask_expand(store_queue_fwd.mask[i], expand_mask);
        MaskExpand #(`DCACHE_BYTE) mask_expand_commit(commit_queue_fwd.mask[i], expand_commit_mask);
        assign combine_queue_data = (rio.rdata[i] & ~expand_commit_mask) | (commit_queue_fwd.data[i] & expand_commit_mask);
        assign rdata[i] = (combine_queue_data & ~expand_mask) | (store_queue_fwd.data[i] & expand_mask);
        assign rdata_valid[i] = ((store_queue_fwd.mask[i] | commit_queue_fwd.mask[i]) & lmaskNext[i]) == lmaskNext[i];
    end
endgenerate

    // load enqueue
    LoadIssueData `N(`LOAD_PIPELINE) leq_data;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) lpaddrNext;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lvaddr_s3;
    logic `N(`LOAD_PIPELINE) leq_en, leq_valid;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx_next;

    logic `N(`LOAD_PIPELINE) lmisalign_s3;
    logic `N(`LOAD_PIPELINE) tlb_exception_s3;
    logic `N(`LOAD_PIPELINE) tlb_miss_s3;
    logic `N(`LOAD_PIPELINE) rhit;
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
    assign rio.req_cancel_s2 = redirect_clear_s2 | lmisalign_s2 | tlb_exception_s2 | luncache_s2 |
                                tlb_lsu_io.lmiss
`ifdef RVA
    | {{`LOAD_PIPELINE-1{1'b0}}, amo_req} | amo_conflict;
`endif
    ;
    assign rio.req_cancel_s3 = redirect_clear_s3 | rdata_valid;

    always_ff @(posedge clk)begin
        lpaddrNext <= lpaddr;
        leq_data <= load_issue_data;
        leq_en <= load_en & ~rio.conflict & ~redirect_clear_s2
`ifdef RVA
        & ~{{`LOAD_PIPELINE-1{1'b0}}, amo_req} & ~amo_conflict;
`endif
        ;
        lmaskNext <= lmask;
        issue_idx_next <= load_issue_idx;
        lmisalign_s3 <= lmisalign_s2;
        tlb_exception_s3 <= tlb_exception_s2;
        luncache_s3 <= luncache_s2 & ~lmisalign_s2 & ~tlb_exception_s2;
        rhit <= rio.hit;
        lvaddr_s3 <= loadAddrNext;
        tlb_miss_s3 <= tlb_lsu_io.lmiss;
    end
    assign leq_valid = leq_en & ~fwd_data_invalid & ~redirect_clear_s3 & ~uncache_full_s3 & ~tlb_miss_s3;
    assign uncache_full_s3 = luncache_s3 & load_queue_io.uncache_full;
    assign load_queue_io.en = leq_valid;
    assign load_queue_io.data = leq_data;
    assign load_queue_io.paddr = lpaddrNext;
    assign load_queue_io.mask = lmaskNext;
    assign load_queue_io.rmask = (store_queue_fwd.mask | commit_queue_fwd.mask);
    assign load_queue_io.rdata = rdata;
    assign load_queue_io.miss = ~rhit & ~rdata_valid & ~lmisalign_s3 & ~tlb_exception_s3;
    assign load_queue_io.wb_ready = ~leq_valid;
    assign load_queue_io.uncache = luncache_s3;

    // reply slow
    logic `N(`LOAD_PIPELINE) fwd_data_invalid_n, lreply_en;
    logic `N(`LOAD_PIPELINE) lmiss, lexception_s4;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx_n2;
    logic `N(`LOAD_PIPELINE) redirect_clear_s4;
    logic `N(`LOAD_PIPELINE) tlb_miss_s4;
    RobIdx `N(`LOAD_PIPELINE) robIdx_s4;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        always_ff @(posedge clk)begin
            robIdx_s4[i] <= leq_data[i].robIdx;
        end
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, robIdx_s4[i], older);
        assign redirect_clear_s4[i] = backendCtrl.redirect & older;
    end
endgenerate
    always_ff @(posedge clk)begin
        fwd_data_invalid_n <= fwd_data_invalid  & ~lmisalign_s3 & ~tlb_exception_s3;
        lreply_en <= leq_en & ~redirect_clear_s3;
        issue_idx_n2 <= issue_idx_next;
        lmiss <= ~rhit & ~rdata_valid & ~lmisalign_s3 & ~tlb_exception_s3;
        lexception_s4 <= lmisalign_s3 | tlb_exception_s3;
        uncache_full_s4 <= uncache_full_s3;
        tlb_miss_s4 <= tlb_miss_s3;
    end
    assign load_io.success = lreply_en & ~fwd_data_invalid_n & ~redirect_clear_s4 & ~(lmiss & rio.full) & ~uncache_full_s4 & ~tlb_miss_s4;
    assign load_io.success_idx = issue_idx_n2;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign load_io.reply_slow[i].en = lreply_en[i] & (fwd_data_invalid_n[i] | (lmiss[i] & rio.full[i]) | uncache_full_s4[i] | tlb_miss_s4[i] | tlb_lsu_io.lcancel[i]) & ~lexception_s4[i];
        assign load_io.reply_slow[i].issue_idx = issue_idx_n2[i];
        assign load_io.reply_slow[i].reason = tlb_miss_s4[i] & ~tlb_lsu_io.lcancel[i] ? 2'b11 :
                                              fwd_data_invalid_n ? 2'b10 : 2'b00;
    end
endgenerate
    
    // wb
    logic `N(`LOAD_PIPELINE) wb_pipeline_en;
    RobIdx `N(`LOAD_PIPELINE) lrobIdx_n;
    logic `N(`LOAD_PIPELINE) lwe_n;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) lrd_n;
    logic `ARRAY(`LOAD_PIPELINE, `XLEN) ldata_n, ldata_shift;
    logic `ARRAY(`LOAD_PIPELINE, `EXC_WIDTH) lexccode;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : rdata_wb
        WBData pipe_data;
        logic from_pipe;
        RDataGen data_gen (leq_data[i].uext, leq_data[i].size, lpaddrNext[i][`DCACHE_BYTE_WIDTH-1: 0], rdata[i], ldata_shift[i]);
        assign wb_pipeline_en[i] = leq_en[i] & (lmisalign_s3[i] | tlb_exception_s3[i] | 
                                ((rhit[i] | rdata_valid[i]) & ~fwd_data_invalid[i] & ~luncache_s3[i])) & ~redirect_clear_s3[i] & ~tlb_miss_s3[i];
        assign from_pipe = wb_pipeline_en[i] 
`ifdef RVF
                          & ~leq_data[i].frd_en;
`endif
        ;
        always_ff @(posedge clk)begin
            pipe_data.en <= from_pipe;
            pipe_data.robIdx <= leq_data[i].robIdx;
            pipe_data.rd <= leq_data[i].rd;
            pipe_data.we <= leq_data[i].we;
            pipe_data.exccode <= tlb_exception_s3[i] ? `EXC_LPF : 
                           lmisalign_s3[i] ? `EXC_LAM : `EXC_NONE;
            pipe_data.res <= ldata_shift[i];
            from_issue[i] <= from_pipe;
        end
`ifdef RVA
        if(i == 0)begin
            assign lsu_wb_io.datas[i] = from_issue[i] ? pipe_data : 
                                        load_queue_io.int_wbData[i].en ? load_queue_io.int_wbData[i] :
                                        amo_wdata;
        end
        else begin
            assign lsu_wb_io.datas[i] = from_issue[i] ? pipe_data : load_queue_io.int_wbData[i];
        end
`else
        assign lsu_wb_io.datas[i] = from_issue[i] ? pipe_data : load_queue_io.int_wbData[i];
`endif
        assign load_wakeup_io.en[i] = lsu_wb_io.datas[i].en;
        assign load_wakeup_io.we[i] = lsu_wb_io.datas[i].we;
        assign load_wakeup_io.rd[i] = lsu_wb_io.datas[i].rd;
    end
`ifdef RVF
    for(genvar i=0; i<`LOAD_PIPELINE; i++) begin : rdata_fwb
        WBData pipe_data;
        logic from_pipe;
        always_ff @(posedge clk)begin
            pipe_data.en <= wb_pipeline_en[i] & leq_data[i].frd_en;
            pipe_data.robIdx <= leq_data[i].robIdx;
            pipe_data.rd <= leq_data[i].rd;
            pipe_data.we <= 1'b1;
            pipe_data.exccode <= tlb_exception_s3[i] ? `EXC_LPF :
                                lmisalign_s3[i] ? `EXC_LAM : `EXC_NONE;
            pipe_data.res <= ldata_shift[i];
            from_pipe <= wb_pipeline_en[i] & leq_data[i].frd_en;
        end
        assign lsu_wb_io.datas[i+`LOAD_PIPELINE] = from_pipe ? pipe_data : load_queue_io.fp_wbData[i];
        assign load_wakeup_io.en[i+`LOAD_PIPELINE] = lsu_wb_io.datas[i+`LOAD_PIPELINE].en;
        assign load_wakeup_io.we[i+`LOAD_PIPELINE] = lsu_wb_io.datas[i+`LOAD_PIPELINE].we;
        assign load_wakeup_io.rd[i+`LOAD_PIPELINE] = lsu_wb_io.datas[i+`LOAD_PIPELINE].rd;
    end
`endif
endgenerate

// store
    logic `ARRAY(`STORE_PIPELINE, `TLB_TAG) sptag;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE) spaddr;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) storeAddrNext;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) smask;
    logic `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) dis_sl_older;
    logic `N(`STORE_PIPELINE) store_en;
    StoreIssueData `N(`STORE_PIPELINE) store_issue_data;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx;

    logic `N(`STORE_PIPELINE) store_redirect_clear_req;
    logic `N(`STORE_PIPELINE) store_redirect_s2;
    logic `N(`STORE_PIPELINE) smisalign, smisalign_s2;
    logic `N(`STORE_PIPELINE) suncache_s2;
    logic `N(`STORE_PIPELINE) stlb_exception, stlb_exception_s2;
    logic `N(`STORE_PIPELINE) stlb_miss;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx_s2;
    logic `N(`STORE_PIPELINE) store_en_s4, store_en_s4_unexc;
    logic `N(`STORE_PIPELINE) store_redirect_s4;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, store_io.storeIssueData[i].robIdx, older);
        assign store_redirect_clear_req[i] = backendCtrl.redirect & older;
    end
endgenerate


generate

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin : store_addr
        AGU agu(
            .imm(store_io.storeIssueData[i].imm),
            .data(store_reg_io.data[i]),
            .addr(storeVAddr[i])
        );
        assign sptag[i] = tlb_lsu_io.spaddr[i][`PADDR_SIZE-1: `TLB_OFFSET];
        always_ff @(posedge clk)begin
            store_en[i] <= store_io.en[i] & ~store_redirect_clear_req[i];
            store_issue_data[i] <= store_io.storeIssueData[i];
            storeAddrNext[i] <= storeVAddr[i];
            smisalign_s2[i] <= smisalign[i];
            stlb_exception[i] <= store_io.exception[i];
            sissue_idx_s2[i] <= sissue_idx[i];
        end
        getMask get_mask(storeAddrNext[i][1: 0], store_issue_data[i].size, smask[i]);
        MisalignDetect misalign_detect (store_io.storeIssueData[i].size, storeVAddr[i][`DCACHE_BYTE_WIDTH-1: 0], smisalign[i]);
        assign spaddr[i] = {sptag[i], storeAddrNext[i][11: 0]};
    end

    assign stlb_exception_s2 = stlb_exception | tlb_lsu_io.sexception;
    assign suncache_s2 = tlb_lsu_io.suncache;

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic older;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, store_issue_data[i].robIdx, older);
        assign store_redirect_s2[i] = backendCtrl.redirect & older;
    end
endgenerate

    assign sissue_idx = store_io.issue_idx;
    assign tlb_lsu_io.sreq = store_io.en & ~store_io.exception;
    assign tlb_lsu_io.sreq_s2 = store_en & ~smisalign_s2;
    assign tlb_lsu_io.sidx = sissue_idx;
    assign tlb_lsu_io.saddr = storeVAddr;

    //store enqueue
    assign stlb_miss = tlb_lsu_io.smiss;
    assign store_queue_io.en = store_en & ~store_redirect_s2 & ~stlb_miss;
    assign store_queue_io.data = store_issue_data;
    assign store_queue_io.paddr = spaddr;
    assign store_queue_io.mask = smask;
    assign store_queue_io.uncache = suncache_s2 & ~stlb_exception_s2 & ~smisalign_s2;
    assign store_queue_io.wb_valid = ~(store_en_s4_unexc[`STORE_PIPELINE-1] & ~store_redirect_s4[`STORE_PIPELINE-1]);

    // store wb
    // delay two cycle for violation detect
    logic `N(`STORE_PIPELINE) store_en_s3;
    RobIdx `N(`STORE_PIPELINE) store_robIdx_s3;
    logic `ARRAY(`STORE_PIPELINE, `EXC_WIDTH) exccode_s3;
    logic `N(`STORE_PIPELINE) store_exc_s3;
    logic `N(`STORE_PIPELINE) store_redirect_s3;
    logic `N(`STORE_PIPELINE) stlb_miss_s3;
    logic `N(`STORE_PIPELINE) suncache_s3;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) svaddr_s3;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sissue_idx_s3;
    RobIdx `N(`STORE_PIPELINE) store_robIdx_s4;
    logic `ARRAY(`STORE_PIPELINE, `EXC_WIDTH) exccode_s4;
    logic `N(`STORE_PIPELINE) stlb_miss_s4;
    logic `N(`STORE_PIPELINE) suncache_s4;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) svaddr_s4;
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
            exccode_s3[i] <= stlb_exception_s2[i] ? `EXC_SPF: 
                             smisalign_s2[i] ? `EXC_SAM : `EXC_NONE;
            store_exc_s3[i] <= stlb_exception_s2[i] | smisalign_s2[i];
            suncache_s3[i] <= suncache_s2[i];
            stlb_miss_s3[i] <= stlb_miss[i];
            svaddr_s3[i] <= storeAddrNext[i];
            sissue_idx_s3[i] <= sissue_idx_s2[i];
            store_en_s4[i] <= store_en_s3[i] & ~store_redirect_s3[i] & ~store_exc_s3[i];
            store_en_s4_unexc[i] <= store_en_s3[i] & ~store_redirect_s3[i] & ~stlb_miss_s3[i];
            store_robIdx_s4[i] <= store_robIdx_s3[i];
            exccode_s4[i] <= exccode_s3[i];
            stlb_miss_s4[i] <= stlb_miss_s3[i];
            suncache_s4[i] <= ((~store_exc_s3[i]) & suncache_s3[i]);
            svaddr_s4[i] <= svaddr_s3[i];
            sissue_idx_s4[i] <= sissue_idx_s3[i];

            if(i == `STORE_PIPELINE - 1)begin
                storeWBData[i].en <= store_en_s4_unexc[i] & ~store_redirect_s4[i] & ~suncache_s4[i] | store_queue_io.wb_req;
                storeWBData[i].robIdx <= store_en_s4_unexc[i] & ~store_redirect_s4[i] & ~suncache_s4[i] ? store_robIdx_s4[i] : store_queue_io.wb_robIdx;
                storeWBData[i].exccode <= store_en_s4_unexc[i] & ~store_redirect_s4[i] & ~suncache_s4[i] ? exccode_s4[i]  : `EXC_NONE;
            end
            else begin
                storeWBData[i].en <= store_en_s4_unexc[i] & ~store_redirect_s4[i] & ~suncache_s4[i];
                storeWBData[i].robIdx <= store_robIdx_s4[i];
                storeWBData[i].exccode <= exccode_s4[i];
            end
        end
    end
endgenerate
    assign store_io.success = store_en_s4_unexc & ~store_redirect_s4 & ~tlb_lsu_io.scancel;
    assign store_io.success_idx = sissue_idx_s4;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign store_io.reply[i].en = store_en_s4[i] & (stlb_miss_s4[i] | tlb_lsu_io.scancel[i]);
        assign store_io.reply[i].issue_idx = sissue_idx_s4[i];
        assign store_io.reply[i].reason = tlb_lsu_io.scancel[i] ? 2'b00 : 2'b11;
    end
endgenerate

// store load detect
    assign violation_io.lq_data = load_queue_io.lq_violation;
    assign load_queue_io.write_violation = violation_io.wdata;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign violation_io.wdata[i].en = store_en[i] & ~tlb_lsu_io.smiss[i];
        assign violation_io.wdata[i].addr = spaddr[i];
        assign violation_io.wdata[i].mask = smask[i];
        assign violation_io.wdata[i].lqIdx = store_issue_data[i].lqIdx;
        assign violation_io.wdata[i].robIdx = store_issue_data[i].robIdx;
        assign violation_io.wdata[i].fsqInfo = store_issue_data[i].fsqInfo;
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign violation_io.s1_data[i].en = load_en[i] & ~tlb_lsu_io.lmiss[i];
        assign violation_io.s1_data[i].addr = lpaddr[i];
        assign violation_io.s1_data[i].mask = lmask[i];
        assign violation_io.s1_data[i].lqIdx = load_issue_data[i].lqIdx;
        assign violation_io.s1_data[i].robIdx = load_issue_data[i].robIdx;
        assign violation_io.s1_data[i].fsqInfo = load_issue_data[i].fsqInfo;

        assign violation_io.s2_data[i].en = leq_en[i];
        assign violation_io.s2_data[i].addr = lpaddrNext[i];
        assign violation_io.s2_data[i].mask = lmaskNext[i];
        assign violation_io.s2_data[i].lqIdx = leq_data[i].lqIdx;
        assign violation_io.s2_data[i].robIdx = leq_data[i].robIdx;
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

// exception
    RobIdx exc_idx;
    logic exc_valid;
    logic `N(`LOAD_PIPELINE) lexc_valid;
    logic `N(`STORE_PIPELINE) sexc_valid;
    RobIdx `N(`LOAD_PIPELINE) lexc_robIdx;
    RobIdx `N(`STORE_PIPELINE) sexc_robIdx;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lexc_vaddr;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) sexc_vaddr;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        always_ff @(posedge clk)begin
            lexc_valid[i] <= wb_pipeline_en[i] & (tlb_exception_s3[i] | lmisalign_s3[i]);
            lexc_robIdx[i] <= leq_data[i].robIdx;
            lexc_vaddr[i] <= lvaddr_s3[i];
        end
    end
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        always_ff @(posedge clk)begin
            sexc_valid[i] <= store_en_s4_unexc[i] & ~store_redirect_s4[i] & (exccode_s4[i] != `EXC_NONE);
            sexc_robIdx[i] <= store_robIdx_s4[i];
            sexc_vaddr[i] <= svaddr_s4[i];
        end
    end
endgenerate

    logic lexc_valid_o;
    RobIdx lexc_robIdx_o;
    logic `N(`VADDR_SIZE) lexc_vaddr_o;
    LoopOldestSelect #(
        .RADIX(`LOAD_PIPELINE),
        .WIDTH(`ROB_WIDTH),
        .DATA_WIDTH(`VADDR_SIZE)
    ) select_lexc_oldest(
        .en(lexc_valid & ~redirect_clear_s4),
        .cmp(lexc_robIdx),
        .data_i(lexc_vaddr),
        .en_o(lexc_valid_o),
        .cmp_o(lexc_robIdx_o),
        .data_o(lexc_vaddr_o)
    );
    logic sexc_valid_o;
    RobIdx sexc_robIdx_o;
    logic `N(`VADDR_SIZE) sexc_vaddr_o;
    LoopOldestSelect #(
        .RADIX(`STORE_PIPELINE),
        .WIDTH(`ROB_WIDTH),
        .DATA_WIDTH(`VADDR_SIZE)
    ) select_sexc_oldest(
        .en(sexc_valid & ~store_redirect_s4),
        .cmp(sexc_robIdx),
        .data_i(sexc_vaddr),
        .en_o(sexc_valid_o),
        .cmp_o(sexc_robIdx_o),
        .data_o(sexc_vaddr_o)
    );
    logic exc_valid_o;
    RobIdx exc_robIdx_o;
    logic `N(`VADDR_SIZE) exc_vaddr_o;

    logic ls_exc_older;
    LoopCompare #(`ROB_WIDTH) cmp_ls_exc_older (lexc_robIdx_o, sexc_robIdx_o, ls_exc_older);
    assign exc_valid_o = lexc_valid_o | sexc_valid_o;
    assign exc_robIdx_o = lexc_valid_o & ls_exc_older | lexc_valid_o & ~sexc_valid_o ? lexc_robIdx_o : sexc_robIdx_o;
    assign exc_vaddr_o = lexc_valid_o & ls_exc_older | lexc_valid_o & ~sexc_valid_o ? lexc_vaddr_o : sexc_vaddr_o;

    logic exc_redirect_older, exc_pipline_older, exc_redirect_equal, exc_redirect;
    LoopCompare #(`ROB_WIDTH) cmp_exc_older (backendCtrl.redirectIdx, exc_idx, exc_redirect_older);
    assign exc_redirect_equal = exc_idx == backendCtrl.redirectIdx;
    assign exc_redirect = exc_redirect_older | exc_redirect_equal;
    LoopCompare #(`ROB_WIDTH) cmp_exc_pipe_older (exc_robIdx_o, exc_idx, exc_pipline_older);

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            exc_valid <= 0;
            exc_idx <= 0;
            exc_vaddr <= 0;
        end
        else if(backendCtrl.redirect & exc_redirect)begin
            exc_valid <= 1'b0;
        end
        else if(exc_valid_o)begin
            if(~exc_valid | exc_pipline_older)begin
                exc_valid <= 1'b1;
                exc_idx <= exc_robIdx_o;
                exc_vaddr <= exc_vaddr_o;
            end
        end
    end

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
    input LoadIdx tail,
    ViolationIO.violation io,
    BackendRedirectIO.mem redirect_io,
    input BackendCtrl backendCtrl,
    FenceBus.lsu fenceBus
);
    ViolationData `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) s1_cmp;
    ViolationData `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) s2_cmp;
    ViolationData `N(`STORE_PIPELINE) s1_result, s1_result_o;
    ViolationData `N(`STORE_PIPELINE) s2_result, s2_result_o;
    logic redirect_s1, redirect_s2, redirect_s2_o, redirect_s3;
    RobIdx redirectIdx_s1, redirectIdx_s2, redirectIdx_s2_o, redirectIdx_s3;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            ViolationCompare cmp_s1(tail, io.wdata[i], io.s1_data[j], s1_cmp[i][j]);
            ViolationCompare cmp_s2(tail, io.wdata[i], io.s2_data[j], s2_cmp[i][j]);
        end
        ViolationOlderCompare cmp_s1_result (s1_cmp[i][0], s1_cmp[i][1], s1_result[i]);
        ViolationOlderCompare cmp_s2_result (s2_cmp[i][0], s2_cmp[i][1], s2_result[i]);
    end
endgenerate

    always_ff @(posedge clk)begin
        s1_result_o <= s1_result;
        s2_result_o <= s2_result;
        redirect_s1 <= backendCtrl.redirect;
        redirectIdx_s1 <= backendCtrl.redirectIdx;
    end
    ViolationData s1_older, s2_older, pipeline_result, pipeline_o;
    `UNPARAM(LOAD_PIPELINE, 2, "violation compare")
    ViolationOlderCompare cmp_s1_older (s1_result_o[0], s1_result_o[1], s1_older);
    ViolationOlderCompare cmp_s2_older (s2_result_o[0], s2_result_o[1], s2_older);
    ViolationOlderCompare cmp_pipeline (s1_older, s2_older, pipeline_result);

    logic redirect_s2_older;
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s2 (backendCtrl.redirectIdx, redirectIdx_s1, redirect_s2_older);
    assign redirect_s2 = redirect_s1 | backendCtrl.redirect;
    assign redirectIdx_s2 = ~redirect_s1 | backendCtrl.redirect & redirect_s2_older ? backendCtrl.redirectIdx :  redirectIdx_s1;
    always_ff @(posedge clk)begin
        pipeline_o <= pipeline_result;
        redirect_s2_o <= redirect_s2;
        redirectIdx_s2_o <= redirectIdx_s2;
    end

    logic redirect_s3_older;
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s3 (backendCtrl.redirectIdx, redirectIdx_s2_o, redirect_s3_older);
    assign redirect_s3 = redirect_s2_o | backendCtrl.redirect;
    assign redirectIdx_s3 = ~redirect_s2_o | backendCtrl.redirect & redirect_s3_older ? backendCtrl.redirectIdx : redirectIdx_s2_o;

    ViolationData out;
    ViolationOlderCompare cmp_out (pipeline_o, io.lq_data, out);

    logic out_older;
    LoopCompare #(`ROB_WIDTH) cmp_redirect_out (out.robIdx, redirectIdx_s3, out_older);
    logic `N(`ROB_WIDTH) robIdx_p;
    assign robIdx_p = out.robIdx.idx - 1;
    assign redirect_io.memRedirect.en = out.en & (~redirect_s3 | out_older) | fenceBus.fence_end;
    assign redirect_io.memRedirect.robIdx.idx = fenceBus.fence_end ? fenceBus.preRobIdx.idx : robIdx_p;
    assign redirect_io.memRedirect.robIdx.dir = fenceBus.fence_end ? fenceBus.preRobIdx.dir : robIdx_p[`ROB_WIDTH-1] & ~out.robIdx.idx[`ROB_WIDTH-1] ? ~out.robIdx.dir : out.robIdx.dir;
    assign redirect_io.memRedirect.fsqInfo = fenceBus.fence_end ? fenceBus.fsqInfo : out.fsqInfo;
    assign redirect_io.memRedirectIdx = fenceBus.fence_end ? fenceBus.robIdx : out.robIdx;
endmodule

module ViolationCompare(
    input LoadIdx tail,
    input ViolationData cmp1,
    input ViolationData cmp2,
    output ViolationData out
);
    logic older, equal, conflict, overflow;
    LoopCompare #(`LOAD_QUEUE_WIDTH) compare_lq (cmp1.lqIdx, cmp2.lqIdx, older);
    LoopCompare #(`LOAD_QUEUE_WIDTH) compare_ov (tail, cmp1.lqIdx, overflow);
    assign equal = cmp1.lqIdx == cmp2.lqIdx;
    assign conflict = (cmp1.addr[`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH] == cmp2.addr[`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH]) &&
                      (|(cmp1.mask & cmp2.mask));
    assign out.addr = cmp2.addr;
    assign out.mask = cmp2.mask;
    assign out.lqIdx = cmp2.lqIdx;
    assign out.robIdx = cmp2.robIdx;
    assign out.fsqInfo = cmp2.fsqInfo;
    // BUG: consider load queue full
    assign out.en = cmp1.en & cmp2.en & (older | equal) & conflict & ~overflow;
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
    output logic misalign
);
    always_comb begin
        case(size)
        2'b10: misalign = |offset[1: 0];
        2'b01: misalign = offset[0];
        default: misalign = 1'b0;
        endcase
    end
endmodule