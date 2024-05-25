`include "../../defines/defines.svh"

module Backend(
    input logic clk,
    input logic rst,
    IfuBackendIO.backend ifu_backend_io,
    FsqBackendIO.backend fsq_back_io,
    CommitBus.rob commitBus
);
    DecodeRenameIO dec_rename_io();
    RenameDisIO rename_dis_io();
    ROBRenameIO rob_rename_io();
    WriteBackBus wbBus();
    DisIntIssueIO dis_intissue_io();
    IssueRegfileIO #(.PORT_SIZE(`ALU_SIZE)) int_reg_io();
    IntIssueExuIO int_exu_io();
    BackendCtrl backendCtrl();
    CommitWalk commitWalk();


    assign backendCtrl.redirect = fsq_back_io.redirect.en;
    assign backendCtrl.redirectIdx = fsq_back_io.redirect.robIdx;
    assign ifu_backend_io.stall = backendCtrl.rename_full | backendCtrl.rob_full | backendCtrl.dis_full;

    Decode decode(.*,
                  .insts(ifu_backend_io.fetchBundle));
    Rename rename(.*,
                  .full(backendCtrl.rename_full));
    ROB rob(.*,
            .dis_io(rename_dis_io),
            .full(backendCtrl.rob_full),
            .backendRedirect(fsq_back_io.redirect));
    Dispatch dispatch(.*,
                      .full(backendCtrl.dis_full));
    IntIssueQueue int_issue_queue(
        .*,
        .dis_issue_io(dis_intissue_io),
        .issue_exu_io(int_exu_io)
    );
    RegfileWrapper regfile_wrapper(.*);
    Execute execute(.*,
                    .backendRedirectInfo(fsq_back_io.redirect));
endmodule