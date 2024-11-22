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
    WriteBackBus #(`WB_SIZE) int_wbBus();
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
`ifdef RVF
    IssueRegIO #(`STORE_PIPELINE * 3, `STORE_PIPELINE * 3) store_reg_io();
`else
    IssueRegIO #(`STORE_PIPELINE * 2, `STORE_PIPELINE * 2) store_reg_io();
`endif
    IssueRegIO #(1, 2) csr_reg_io();
`ifdef RVM
    IssueRegIO #(`MULT_SIZE, `MULT_SIZE * 2) mult_reg_io();
`endif
`ifdef RVA
    IssueRegIO #(1, 2) amo_reg_io();
`endif
    WakeupBus #(`INT_WAKEUP_PORT) int_wakeupBus();
`ifdef RVF
    WakeupBus #(`FP_WAKEUP_PORT) fp_wakeupBus();
    WriteBackBus #(`FP_WB_SIZE) fp_wbBus();
    DisIssueIO #(.PORT_NUM(`FMISC_DIS_PORT), .DATA_SIZE($bits(FMiscIssueBundle))) dis_fmisc_io();
    DisIssueIO #(.PORT_NUM(`FMA_DIS_PORT), .DATA_SIZE($bits(FMAIssueBundle))) dis_fma_io();
    DisIssueIO #(.PORT_NUM(`FDIV_DIS_PORT), .DATA_SIZE($bits(FDivIssueBundle))) dis_fdiv_io();
    IssueRegIO #(`FMISC_SIZE * 2, `FMISC_SIZE * 3) fmisc_reg_io();
    IssueRegIO #(`FMA_SIZE, `FMA_SIZE * 3) fma_reg_io();
    IssueRegIO #(`FDIV_SIZE, `FDIV_SIZE * 2) fdiv_reg_io();
    IssueFMAIO issue_fma_io();
    IssueFMiscIO issue_fmisc_io();
    IssueFDivIO issue_fdiv_io();
    WriteBackIO #(`FMISC_SIZE*2) fmisc_wb_io();
    IssueWakeupIO #(`FMISC_SIZE*2) fmisc_wakeup_io();
    IssueWakeupIO #(`FMA_SIZE) fma_wakeup_io();
    WriteBackIO #(`FMA_SIZE) fma_wb_io();
    WriteBackIO #(`FDIV_SIZE) fdiv_wb_io();
    IssueWakeupIO #(`FDIV_SIZE) fdiv_wakeup_io();
    RobFCsrIO rob_fcsr_io();
    logic [2: 0] round_mode;
`endif
    IssueWakeupIO #(`ALU_SIZE) int_wakeup_io();
    IssueWakeupIO #(
`ifdef RVF
        `LOAD_PIPELINE * 2
`else
        `LOAD_PIPELINE
`endif
    ) load_wakeup_io();
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
    WriteBackIO #(
`ifdef RVF
        `LSU_SIZE * 2
`else
        `LSU_SIZE
`endif
    ) lsu_wb_io();
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
    DiffRAT diff_int_rat();
`ifdef RVF
    DiffRAT diff_fp_rat();
`endif
`endif

    assign commitBus_out.en = commitBus.en;
    assign commitBus_out.we = commitBus.we;
    assign commitBus_out.fsqInfo = commitBus.fsqInfo;
    assign commitBus_out.vrd = commitBus.vrd;
    assign commitBus_out.prd = commitBus.prd;
    assign commitBus_out.num = commitBus.num;
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
        .dis_issue_io(dis_int_io),
        .issue_exu_io(int_exu_io),
        .wakeupBus(int_wakeupBus)
    );
    CsrIssueQueue csr_issue_queue(.*,
                                  .commitStreamSize(fsq_back_io.commitStreamSize));
`ifdef RVM
    MultIssueQueue mult_issue_queue(.*, .wakeupBus(int_wakeupBus));
`endif
`ifdef RVF
    FMiscIssueQueue fmisc_issue_queue(.*);
    FMAIssueQueue fma_issue_queue(.*);
    FDivIssueQueue fdiv_issue_queue(.*);
`endif
    LSU lsu(
        .*,
        .redirect_io(backendRedirect),
        .snoop_io(dcache_snoop_io)
    );
    RegfileWrapper regfile_wrapper(.*);
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