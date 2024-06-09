`include "../../defines/defines.svh"

module Backend(
    input logic clk,
    input logic rst,
    IfuBackendIO.backend ifu_backend_io,
    FsqBackendIO.backend fsq_back_io,
    CommitBus.rob commitBus_out,
    DCacheAxi.cache axi_io
);
    DecodeRenameIO dec_rename_io();
    RenameDisIO rename_dis_io();
    ROBRenameIO rob_rename_io();
    WriteBackBus wbBus();
    DisIssueIO #(.PORT_NUM(`INT_DIS_PORT), .DATA_SIZE($bits(IntIssueBundle))) dis_intissue_io();
    DisIssueIO #(.PORT_NUM(`LOAD_DIS_PORT), .DATA_SIZE($bits(MemIssueBundle))) dis_load_io();
    DisIssueIO #(.PORT_NUM(`STORE_DIS_PORT), .DATA_SIZE($bits(MemIssueBundle))) dis_store_io();
    IssueRegfileIO #(.PORT_SIZE(`ALU_SIZE * 2)) int_reg_io();
    IssueRegfileIO #(.PORT_SIZE(`LOAD_PIPELINE)) load_reg_io();
    IssueRegfileIO #(.PORT_SIZE(`STORE_PIPELINE * 2)) store_reg_io();
    IntIssueExuIO int_exu_io();
    BackendCtrl backendCtrl();
    CommitBus commitBus();
    CommitWalk commitWalk();
    BackendRedirectIO backendRedirect();
    WriteBackIO #(`ALU_SIZE) alu_wb_io();
    WriteBackIO #(`LSU_SIZE) lsu_wb_io();
    StoreWBData `N(`STORE_PIPELINE) storeWBData;

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
    assign backendCtrl.redirectIdx = fsq_back_io.redirect.robIdx;
    assign ifu_backend_io.stall = backendCtrl.rename_full | backendCtrl.rob_full | backendCtrl.dis_full;
    assign fsq_back_io.redirect = backendRedirect.out;
    assign fsq_back_io.redirectBr = backendRedirect.branchOut;

    Decode decode(.*,
                  .insts(ifu_backend_io.fetchBundle));
    Rename rename(.*,
                  .full(backendCtrl.rename_full));
    ROB rob(.*,
            .dis_io(rename_dis_io),
            .full(backendCtrl.rob_full),
            .backendRedirect(backendRedirect.out));
    Dispatch dispatch(.*,
                      .full(backendCtrl.dis_full));
    IntIssueQueue int_issue_queue(
        .*,
        .dis_issue_io(dis_intissue_io),
        .issue_exu_io(int_exu_io)
    );
    LSU lsu(
        .*,
        .memRedirect(backendRedirect.memRedirect)
    );
    RegfileWrapper regfile_wrapper(.*);
    Execute execute(.*,
                    .backendRedirectInfo(backendRedirect.branchRedirect),
                    .branchRedirectInfo(backendRedirect.branchInfo));
    BackendRedirectCtrl backend_redirect_ctrl(.*,.io(backendRedirect));
    WriteBack write_back(.*);
endmodule