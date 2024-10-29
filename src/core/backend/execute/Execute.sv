`include "../../../defines/defines.svh"

module Execute(
    input logic clk,
    input logic rst,
    IntIssueExuIO.exu int_exu_io,
    IssueCSRIO.csr issue_csr_io,
    IssueMultIO.mult mult_exu_io,
    WriteBackIO.fu alu_wb_io,
`ifdef RVM
    WriteBackIO.fu mult_wb_io,
    IssueWakeupIO.issue mult_wakeup_io,
    WriteBackIO.fu div_wb_io,
    IssueWakeupIO.issue div_wakeup_io,
`endif
`ifdef RVF
    input logic [2: 0] round_mode,
    IssueFMiscIO.fmisc issue_fmisc_io,
    WriteBackIO.fu fmisc_wb_io,
    IssueWakeupIO.issue fmisc_wakeup_io,
`endif
    input BackendCtrl backendCtrl,
    output BackendRedirectInfo backendRedirectInfo,
    output BranchRedirectInfo branchRedirectInfo
);
    AluBranchCtrlIO branch_ctrl_io();
    logic `N(`ALU_SIZE) older;
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        IssueAluIO issue_alu_io();
        assign issue_alu_io.en = int_exu_io.en[i] & (~backendCtrl.redirect | older[i]);
        assign issue_alu_io.rs1_data = int_exu_io.rs1_data[i];
        assign issue_alu_io.rs2_data = int_exu_io.rs2_data[i];
        assign issue_alu_io.status = int_exu_io.status[i];
        assign issue_alu_io.bundle = int_exu_io.bundle[i];
        assign issue_alu_io.stream = int_exu_io.streams[i];
        assign issue_alu_io.vaddr = int_exu_io.vaddrs[i];
        assign issue_alu_io.ras_type = int_exu_io.bundle[i].ras_type;
        assign issue_alu_io.br_type = int_exu_io.bundle[i].br_type;
        assign int_exu_io.valid[i] = issue_alu_io.valid;
        ALU alu(
            .clk(clk),
            .rst(rst),
            .io(issue_alu_io),
            .wbData(alu_wb_io.datas[i]),
            .branchRes(branch_ctrl_io.bundles[i].res),
            .valid(alu_wb_io.valid[i]),
            .backendCtrl(backendCtrl)
        );

        LoopCompare #(`ROB_WIDTH) compare_older (issue_alu_io.status.robIdx, backendCtrl.redirectIdx, older[i]);

        assign branch_ctrl_io.bundles[i].en = int_exu_io.en[i] & int_exu_io.bundle[i].branchv & int_exu_io.valid[i] & (~backendCtrl.redirect | older[i]);
        assign branch_ctrl_io.bundles[i].fsqInfo = int_exu_io.bundle[i].fsqInfo;
        assign branch_ctrl_io.bundles[i].robIdx = int_exu_io.status[i].robIdx;
    end
endgenerate

    assign backendRedirectInfo = branch_ctrl_io.redirectInfo;
    assign branchRedirectInfo = branch_ctrl_io.branchInfo;
    AluBranchCtrl branch_ctrl(
        .clk(clk),
        .rst(rst),
        .io(branch_ctrl_io)
    );

`ifdef RVM
generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        MultUnit mult(
            .*,
            .en(mult_exu_io.en[i]),
            .rs1_data(mult_exu_io.rs1_data[i]),
            .rs2_data(mult_exu_io.rs2_data[i]),
            .status_i(mult_exu_io.status[i]),
            .multop(mult_exu_io.bundle[i].multop),
            .wakeup_en(mult_wakeup_io.en[i]),
            .wakeup_we(mult_wakeup_io.we[i]),
            .wakeup_rd(mult_wakeup_io.rd[i]),
            .wbData(mult_wb_io.datas[i])
        );
        DivUnit div(
            .*,
            .en(mult_exu_io.en[i]),
            .rs1_data(mult_exu_io.rs1_data[i]),
            .rs2_data(mult_exu_io.rs2_data[i]),
            .status_i(mult_exu_io.status[i]),
            .multop(mult_exu_io.bundle[i].multop),
            .wakeup_en(div_wakeup_io.en[i]),
            .wakeup_we(div_wakeup_io.we[i]),
            .wakeup_rd(div_wakeup_io.rd[i]),
            .wbData(div_wb_io.datas[i]),
            .ready(mult_exu_io.div_ready),
            .div_end(mult_exu_io.div_end)
        );
    end
endgenerate
`endif

`ifdef RVF
    FMiscUnit fmisc_unit (
        .*
    );
`endif
endmodule