`include "../../defines/defines.svh"

module Backend(
    input logic clk,
    input logic rst,
    input logic ext_irq,
    IfuBackendIO.backend ifu_backend_io,
    FsqBackendIO.backend fsq_back_io,
    CommitBus.rob commitBus_out,
    AxiIO.master axi_io,
    AxiIO.master ducache_io,
    CsrTlbIO.csr csr_itlb_io,
    CsrL2IO.csr csr_l2_io,
    TlbL2IO.tlb dtlb_io,
    NativeSnoopIO.master dcache_snoop_io,
    ClintIO.cpu clint_io,
    FenceBus.backend fenceBus_o
);
    DecodeRenameIO dec_rename_io();
    RenameDisIO rename_dis_io();
    ROBRenameIO rob_rename_io();
    WriteBackBus wbBus;
    DisIssueIO #(.PORT_NUM(`INT_DIS_PORT), .DATA_SIZE($bits(IntIssueBundle))) dis_int_io();
    DisIssueIO #(.PORT_NUM(`LOAD_DIS_PORT), .DATA_SIZE($bits(MemIssueBundle))) dis_load_io();
    DisIssueIO #(.PORT_NUM(`STORE_DIS_PORT), .DATA_SIZE($bits(MemIssueBundle))) dis_store_io();
    DisIssueIO #(.PORT_NUM(1), .DATA_SIZE($bits(CsrIssueBundle))) dis_csr_io();
`ifdef RVM
    DisIssueIO #(.PORT_NUM(`MULT_DIS_PORT), .DATA_SIZE($bits(MultIssueBundle))) dis_mult_io();
`endif
`ifdef RVA
    DisIssueIO #(.PORT_NUM(`AMO_DIS_PORT), .DATA_SIZE($bits(AmoIssueBundle))) dis_amo_io();
`endif
    IssueRegIO #(`ALU_SIZE, `ALU_SIZE * 2) int_reg_io();
    IssueRegIO #(`LOAD_PIPELINE, `LOAD_PIPELINE) load_reg_io();
    IssueRegIO #(`STORE_PIPELINE * 2, `STORE_PIPELINE * 2) store_reg_io();
    IssueRegIO #(1, 2) csr_reg_io();
`ifdef RVM
    IssueRegIO #(`MULT_SIZE, `MULT_SIZE * 2) mult_reg_io();
`endif
`ifdef RVA
    IssueRegIO #(1, 2) amo_reg_io();
`endif
    WakeupBus wakeupBus;
    IssueWakeupIO #(`ALU_SIZE) int_wakeup_io();
    IssueWakeupIO #(`LOAD_PIPELINE) load_wakeup_io();
    IssueWakeupIO #(1) csr_wakeup_io();
`ifdef RVM
    IssueWakeupIO #(`MULT_SIZE) mult_wakeup_io();
    IssueWakeupIO #(`MULT_SIZE) div_wakeup_io();
`endif
    IssueCSRIO issue_csr_io();
`ifdef RVM
    IssueMultIO mult_exu_io();
`endif
    WriteBackIO #(1) csr_wb_io();
    IntIssueExuIO int_exu_io();
    BackendCtrl backendCtrl;
    CommitBus commitBus();
    CommitWalk commitWalk;
    BackendRedirectIO backendRedirect();
    RobRedirectIO rob_redirect_io();
    WriteBackIO #(`ALU_SIZE) alu_wb_io();
    WriteBackIO #(`LSU_SIZE) lsu_wb_io();
`ifdef RVM
    WriteBackIO #(`MULT_SIZE) mult_wb_io();
    WriteBackIO #(`MULT_SIZE) div_wb_io();
`endif
    CsrTlbIO csr_ltlb_io();
    CsrTlbIO csr_stlb_io();
    FenceBus fenceBus();
    StoreWBData `N(`STORE_PIPELINE) storeWBData;
    logic rename_full, rob_full;
    /* verilator lint_off UNOPTFLAT */
    logic `N(`VADDR_SIZE) exc_pc;
    LoadIdx lqIdx;
    StoreIdx sqIdx;
    CSRIrqInfo irqInfo;
    logic `N(32) trapInst;
    logic `N(`VADDR_SIZE) exc_vaddr;
    FenceReq fence_req;

`ifdef DIFFTEST
    DiffRAT diff_rat();
`endif

    logic decode_rst, rename_rst, dispatch_rst, intissue_rst, csr_rst, mult_rst, lsu_rst, 
    regfile_rst, wakeup_rst, exe_rst, csrissue_rst, wb_rst, rob_rst;
    SyncRst rst_decode(clk, rst, decode_rst);
    SyncRst rst_rename(clk, rst, rename_rst);
    SyncRst rst_dispatch(clk, rst, dispatch_rst);
    SyncRst rst_int(clk, rst, intissue_rst);
    SyncRst rst_csr(clk, rst, csr_rst);
    SyncRst rst_mult(clk, rst, mult_rst);
    SyncRst rst_lsu(clk, rst, lsu_rst);
    SyncRst rst_regfile(clk, rst, regfile_rst);
    SyncRst rst_wakeup(clk, rst, wakeup_rst);
    SyncRst rst_exe(clk, rst, exe_rst);
    SyncRst rst_csrissue(clk, rst, csrissue_rst);
    SyncRst rst_wb(clk, rst, wb_rst);
    SyncRst rst_rob(clk, rst, rob_rst);

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
    assign fenceBus_o.mmu_flush = fenceBus.mmu_flush;
    assign fenceBus_o.mmu_flush_all = fenceBus.mmu_flush_all;
    assign fenceBus_o.vma_vaddr = fenceBus.vma_vaddr;
    assign fenceBus_o.vma_asid = fenceBus.vma_asid;
    assign fenceBus.mmu_flush_end = fenceBus_o.mmu_flush_end;
`ifdef EXT_FENCEI
    assign fenceBus_o.inst_flush = fenceBus.inst_flush;
    assign fenceBus.inst_flush_end = fenceBus_o.inst_flush_end;
`endif

    Decode decode(.*,
                  .rst(decode_rst),
                  .insts(ifu_backend_io.fetchBundle));
    Rename rename(.*,
                  .rst(rename_rst),
                  .full(rename_full));
    ROB rob(.*,
            .rst(rob_rst),
            .dis_io(rename_dis_io),
            .full(rob_full),
            .backendRedirect(backendRedirect.out));
    Dispatch dispatch(.*,
                      .rst(dispatch_rst),
                      .full(backendCtrl.dis_full));
    IntIssueQueue int_issue_queue(
        .*,
        .rst(intissue_rst),
        .dis_issue_io(dis_int_io),
        .issue_exu_io(int_exu_io)
    );
    CsrIssueQueue csr_issue_queue(.*, .rst(csrissue_rst));
`ifdef RVM
    MultIssueQueue mult_issue_queue(.*, .rst(mult_rst));
`endif
    LSU lsu(
        .*,
        .rst(lsu_rst),
        .redirect_io(backendRedirect),
        .snoop_io(dcache_snoop_io)
    );
    RegfileWrapper regfile_wrapper(.*, .rst(regfile_rst));
    Wakeup wakeup(.*, .rst(wakeup_rst));
    Execute execute(.*,
                    .rst(exe_rst),
                    .backendRedirectInfo(backendRedirect.branchRedirect),
                    .branchRedirectInfo(backendRedirect.branchInfo));
    BackendRedirectCtrl backend_redirect_ctrl(.*,
                                              .rst(wb_rst),
                                              .io(backendRedirect),
                                              .redirectIdx(backendCtrl.redirectIdx));
    CSR csr(.*,
            .rst(csr_rst),
            .exc_pc(fsq_back_io.exc_pc),
            .redirect(backendRedirect.csrOut),
            .target_pc(exc_pc));
    WriteBack write_back(.*, .rst(wb_rst));

// perf
    `PERF(renameStall, backendCtrl.rename_full)
    `PERF(disStall, backendCtrl.dis_full)
endmodule