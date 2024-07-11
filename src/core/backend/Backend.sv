`include "../../defines/defines.svh"

module Backend(
    input logic clk,
    input logic rst,
    IfuBackendIO.backend ifu_backend_io,
    FsqBackendIO.backend fsq_back_io,
    CommitBus.rob commitBus_out,
    DCacheAxi.cache axi_io,
    CsrTlbIO.csr csr_itlb_io,
    CsrL2IO.csr csr_l2_io,
    TlbL2IO.tlb dtlb_io,
    PTWRequest.cache ptw_request
);
    DecodeRenameIO dec_rename_io();
    RenameDisIO rename_dis_io();
    ROBRenameIO rob_rename_io();
    WriteBackBus wbBus();
    DisIssueIO #(.PORT_NUM(`INT_DIS_PORT), .DATA_SIZE($bits(IntIssueBundle))) dis_intissue_io();
    DisIssueIO #(.PORT_NUM(`LOAD_DIS_PORT), .DATA_SIZE($bits(MemIssueBundle))) dis_load_io();
    DisIssueIO #(.PORT_NUM(`STORE_DIS_PORT), .DATA_SIZE($bits(MemIssueBundle))) dis_store_io();
    WakeupBus wakeupBus();
    IssueWakeupIO #(`ALU_SIZE, `ALU_SIZE * 2) int_wakeup_io();
    IssueWakeupIO #(`LOAD_PIPELINE, `LOAD_PIPELINE) load_wakeup_io();
    IssueWakeupIO #(`STORE_PIPELINE * 2, `STORE_PIPELINE * 2) store_wakeup_io();
    DisIssueIO #(.PORT_NUM(1), .DATA_SIZE($bits(CsrIssueBundle))) dis_csr_io();
    IssueWakeupIO #(1, 1) csr_wakeup_io();
    IssueCSRIO issue_csr_io();
    WriteBackIO #(1) csr_wb_io();
    IntIssueExuIO int_exu_io();
    BackendCtrl backendCtrl();
    CommitBus commitBus();
    CommitWalk commitWalk();
    BackendRedirectIO backendRedirect();
    RobRedirectIO rob_redirect_io();
    WriteBackIO #(`ALU_SIZE) alu_wb_io();
    WriteBackIO #(`LSU_SIZE) lsu_wb_io();
    CsrTlbIO csr_ltlb_io();
    CsrTlbIO csr_stlb_io();
    StoreWBData `N(`STORE_PIPELINE) storeWBData;
    logic rename_full, rob_full;
    logic `N(`VADDR_SIZE) exc_pc;

`ifdef DIFFTEST
    DiffRAT diff_rat();
`endif

    assign commitBus_out.en = commitBus.en;
    assign commitBus_out.we = commitBus.we;
    assign commitBus_out.fsqInfo = commitBus.fsqInfo;
    assign commitBus_out.vrd = commitBus.vrd;
    assign commitBus_out.prd = commitBus.prd;
    assign commitBus_out.num = commitBus.num;
    assign commitBus_out.wenum = commitBus.wenum;
    assign backendCtrl.redirect = fsq_back_io.redirect.en;
    // assign backendCtrl.redirectIdx = fsq_back_io.redirect.robIdx;
    assign backendCtrl.rename_full = rename_full | rob_full;
    assign ifu_backend_io.stall = backendCtrl.rename_full | backendCtrl.dis_full | commitWalk.walk;
    assign fsq_back_io.redirect = backendRedirect.out;
    assign fsq_back_io.redirectBr = backendRedirect.branchOut;
    assign fsq_back_io.redirectCsr = backendRedirect.csrOut;

    Decode decode(.*,
                  .insts(ifu_backend_io.fetchBundle));
    Rename rename(.*,
                  .full(rename_full));
    ROB rob(.*,
            .dis_io(rename_dis_io),
            .full(rob_full),
            .backendRedirect(backendRedirect.out));
    Dispatch dispatch(.*,
                      .full(backendCtrl.dis_full));
    IntIssueQueue int_issue_queue(
        .*,
        .dis_issue_io(dis_intissue_io),
        .issue_exu_io(int_exu_io)
    );
    CsrIssueQueue csr_issue_queue(.*);
    LSU lsu(
        .*,
        .redirect_io(backendRedirect)
    );
    Wakeup wakeup(.*);
    Execute execute(.*,
                    .backendRedirectInfo(backendRedirect.branchRedirect),
                    .branchRedirectInfo(backendRedirect.branchInfo));
    BackendRedirectCtrl backend_redirect_ctrl(.*,
                                              .io(backendRedirect),
                                              .redirectIdx(backendCtrl.redirectIdx));
    CSR csr(.*,
            .exc_pc(fsq_back_io.exc_pc),
            .redirect(backendRedirect.csrOut),
            .target_pc(exc_pc));
    WriteBack write_back(.*);

// perf
    `PERF(renameStall, backendCtrl.rename_full)
    `PERF(disStall, backendCtrl.dis_full)
endmodule