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
    IssueRegfileIO.issue load_reg_io,
    IssueRegfileIO.issue store_reg_io,
    WriteBackIO.fu lsu_wb_io,
    WriteBackBus wbBus,
    CommitBus.mem commitBus,
    BackendCtrl backendCtrl,
    DCacheAxi.cache axi_io,
    output BackendRedirectInfo memRedirect,
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

    LoadIssueQueue load_issue_queue(
        .*, 
        .lqIdx(lqIdxs),
        .sqIdx(l_sqIdxs)
    );
    DCache dcache(.*);
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
        .store_data(store_reg_io.data[`STORE_PIPELINE*2-1: `STORE_PIPELINE])
    );
    StoreCommitBuffer store_commit_buffer (
        .*,
        .io(store_commit_io),
        .loadFwd(commit_queue_fwd)
    );
    ViolationDetect violation_detect(.*, .io(violation_io));

// load
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) lmask_pre;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_PIPELINE) dis_ls_older;
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
            RobIdx rob_out;
            assign storeBundle = dis_store_io.data[j];
            LoopCompare #(`ROB_WIDTH) compare_older (loadBundle.robIdx, storeBundle.robIdx, older, rob_out);
            assign dis_ls_older[i][j] = older & dis_store_io.en[j];
        end
        logic `N($clog2(`LOAD_PIPELINE)) store_idx;
        PEncoder #(`STORE_PIPELINE) pencoder_store_idx (dis_ls_older[i], store_idx);
        assign l_sqIdxs[i] = |dis_ls_older[i] ? sqIdxs[store_idx] : store_queue_io.sqIdx;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : load_addr
        AGU agu(
            .imm(load_io.loadIssueData[i].imm),
            .data(load_reg_io.data[i]),
            .addr(loadVAddr[i])
        );
        always_comb begin
            getMask(loadVAddr[i][1: 0], load_io.loadIssueData[i].size, lmask_pre[i]);
        end
    end
endgenerate
    // load request
    assign rio.req = load_io.en;
    assign rio.vaddr = loadVAddr;

    // tlb
    logic `ARRAY(`LOAD_PIPELINE, `TLB_TAG) lptag;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lpaddr, loadAddrNext;
    logic `ARRAY(`LOAD_PIPELINE, 4) lmask, lmaskNext;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) load_issue_idx;
    logic `N(`LOAD_PIPELINE) redirect_clear_req;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        RobIdx rob_out;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, load_io.loadIssueData[i].robIdx, older, rob_out);
        assign redirect_clear_req[i] = backendCtrl.redirect & older;
    end
endgenerate
    assign rio.req_cancel = redirect_clear_req;

    always_ff @(posedge clk)begin
        loadAddrNext <= loadVAddr;
        load_issue_data <= load_io.loadIssueData;
        lmask <= lmask_pre;
        load_en <= load_io.en & ~redirect_clear_req;
        load_issue_idx <= load_io.issue_idx;
        for(int i=0; i<`LOAD_PIPELINE; i++)begin
            lptag[i] <= loadVAddr[i]`TLB_TAG_BUS;
        end
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
        assign load_io.reply_fast[i].en = load_en[i] & rio.conflict[i];
        assign load_io.reply_fast[i].issue_idx = load_issue_idx[i];
        assign load_io.reply_fast[i].reason = 2'b00;
    end
endgenerate

    // load data
    logic `ARRAY(`LOAD_PIPELINE, 32) rdata;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic `N(32) combine_queue_data;
        logic `N(32) expand_mask, expand_commit_mask;
        MaskExpand #(4) mask_expand(store_queue_fwd.mask[i], expand_mask);
        MaskExpand #(4) mask_expand_commit(commit_queue_fwd.mask[i], expand_commit_mask);
        assign combine_queue_data = (rio.rdata[i] & ~expand_mask) | (store_queue_fwd.data[i] & expand_mask);
        assign rdata[i] = (combine_queue_data & ~expand_commit_mask) | (commit_queue_fwd.data[i] & expand_commit_mask);
    end
endgenerate

    // load enqueue
    LoadIssueData `N(`LOAD_PIPELINE) leq_data;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lpaddrNext;
    logic `N(`LOAD_PIPELINE) leq_en, leq_valid;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx_next;

    logic `N(`LOAD_PIPELINE) redirect_clear_s2, redirect_clear_s3;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        RobIdx rob_out;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, load_issue_data[i].robIdx, older, rob_out);
        assign redirect_clear_s2[i] = backendCtrl.redirect & older;
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic older;
        RobIdx rob_out;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, leq_data[i].robIdx, older, rob_out);
        assign redirect_clear_s3[i] = backendCtrl.redirect & older;
    end
endgenerate
    assign rio.req_cancel_s2 = redirect_clear_s2;

    always_ff @(posedge clk)begin
        lpaddrNext <= lpaddr;
        leq_data <= load_issue_data;
        leq_en <= load_en & ~rio.conflict & ~redirect_clear_s2;
        lmaskNext <= lmask;
        issue_idx_next <= load_issue_idx;
    end
    assign leq_valid = leq_en & ~fwd_data_invalid & ~rio.full & ~redirect_clear_s3;
    assign load_queue_io.disNum = load_io.eqNum;
    assign load_queue_io.en = leq_valid;
    assign load_queue_io.data = leq_data;
    assign load_queue_io.paddr = lpaddrNext;
    assign load_queue_io.mask = lmaskNext;
    assign load_queue_io.rdata = rio.rdata;
    assign load_queue_io.miss = ~rio.hit;
    
    assign load_io.success = leq_valid;
    assign load_io.success_idx = issue_idx_next;

    // reply slow
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign load_io.reply_slow[i].en = leq_en[i] & (fwd_data_invalid[i] | rio.full);
        assign load_io.reply_slow[i].issue_idx = issue_idx_next[i];
        assign load_io.reply_slow[i].reason = rio.full ? 2'b10 : 2'b01;
    end
endgenerate
    
    // wb
    logic `N(`LOAD_PIPELINE) from_issue;
    logic `ARRAY(`LOAD_PIPELINE, `ROB_WIDTH) lrobIdx_n;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) lrd_n;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) ldata_n;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic wb_data_en;
        always_ff @(posedge clk)begin
            wb_data_en <= leq_valid[i] |
                                     load_queue_io.wbData[i].en;
            from_issue[i] <= leq_valid[i];
            lrobIdx_n[i] <= leq_data[i].robIdx;
            lrd_n[i] <= leq_data[i].rd;
            ldata_n[i] <= rdata[i];
        end
        assign lsu_wb_io.datas[i].en = wb_data_en;
        assign lsu_wb_io.datas[i].robIdx = from_issue[i] ? lrobIdx_n[i] : load_queue_io.wbData[i].robIdx;
        assign lsu_wb_io.datas[i].rd = from_issue[i] ? lrd_n[i] : load_queue_io.wbData[i].rd;
        assign lsu_wb_io.datas[i].res = from_issue[i] ? ldata_n[i] : load_queue_io.wbData[i].res;
    end
endgenerate

// store
    logic `ARRAY(`STORE_PIPELINE, `TLB_TAG) sptag;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) spaddr, storeAddrNext;
    logic `ARRAY(`STORE_PIPELINE, 4) smask;
    logic `ARRAY(`STORE_PIPELINE, `LOAD_PIPELINE) dis_sl_older;
    logic `N(`STORE_PIPELINE) store_en;
    StoreIssueData `N(`STORE_PIPELINE) store_issue_data;

    logic `N(`STORE_PIPELINE) store_redirect_clear_req;
    logic `N(`STORE_PIPELINE) store_redirect_s2;

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic older;
        RobIdx rob_out;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, store_io.storeIssueData[i].robIdx, older, rob_out);
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
            RobIdx rob_out;
            assign loadBundle = dis_load_io.data[j];
            LoopCompare #(`ROB_WIDTH) compare_older (storeBundle.robIdx, loadBundle.robIdx, older, rob_out);
            assign dis_sl_older[i][j] = older & dis_load_io.en[j];
        end
        logic `N($clog2(`LOAD_PIPELINE)) load_idx;
        PEncoder #(`LOAD_PIPELINE) pencoder_load_idx (dis_sl_older[i], load_idx);
        assign s_lqIdxs[i] = |dis_sl_older[i] ? lqIdxs[load_idx] : load_queue_io.lqIdx;
    end
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin : store_addr
        AGU agu(
            .imm(store_io.storeIssueData[i].imm),
            .data(store_reg_io.data[i]),
            .addr(storeVAddr[i])
        );
        always_ff @(posedge clk)begin
            store_en[i] <= store_io.en[i] & ~store_redirect_clear_req;
            store_issue_data[i] <= store_io.storeIssueData[i];
            sptag[i] <= storeVAddr[i]`TLB_TAG_BUS;
            storeAddrNext[i] <= storeVAddr[i];
        end
        always_comb begin
            getMask(storeAddrNext[i][1: 0], store_issue_data[i].size, smask[i]);
        end
        assign spaddr[i] = {sptag[i], storeAddrNext[i][11: 0]};
    end

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic older;
        RobIdx rob_out;
        LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, store_issue_data[i].robIdx, older, rob_out);
        assign store_redirect_s2[i] = backendCtrl.redirect & older;
    end
endgenerate

    //store enqueue
    assign store_queue_io.en = store_en & ~store_redirect_s2;
    assign store_queue_io.data = store_issue_data;
    assign store_queue_io.paddr = spaddr;
    assign store_queue_io.mask = smask;

    // store wb
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        always_ff @(posedge clk)begin
            storeWBData[i].en <= store_en[i] & ~store_redirect_s2[i];
            storeWBData[i].robIdx <= store_issue_data[i].robIdx;
        end
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
    assign memRedirect = violation_io.memInfo;
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

    BackendRedirectInfo memInfo;
    modport violation(input wdata, s1_data, s2_data, lq_data, output memInfo);
endinterface

module ViolationDetect(
    input logic clk,
    input logic rst,
    ViolationIO.violation io
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
    assign io.memInfo.en = out.en;
    assign io.memInfo.robIdx = out.robIdx;
    assign io.memInfo.fsqInfo =out.fsqInfo;
endmodule

module ViolationCompare(
    input ViolationData cmp1,
    input ViolationData cmp2,
    output ViolationData out
);
    logic older, conflict;
    RobIdx rob_out;
    LoopCompare #(`LOAD_QUEUE_WIDTH) compare_lq (cmp1.lqIdx, cmp2.lqIdx, older, rob_out);
    assign conflict = (cmp1.addr[`VADDR_SIZE-1: 2] == cmp2.addr[`VADDR_SIZE-1: 2]) &&
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
    RobIdx rob_out;
    LoopCompare #(`LOAD_QUEUE_WIDTH) compare_lq (cmp1.lqIdx, cmp2.lqIdx, older, rob_out);
    assign out = cmp1.en & older | cmp1.en & ~cmp2.en ? cmp1 : cmp2;
endmodule