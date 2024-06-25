`include "../../../defines/defines.svh"

module Execute(
    input logic clk,
    input logic rst,
    IntIssueExuIO.exu int_exu_io,
    IssueCSRIO.csr issue_csr_io,
    WriteBackIO.fu alu_wb_io,
    WriteBackBus.wb wbBus,
    BackendCtrl backendCtrl,
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
        assign issue_alu_io.bundle = int_exu_io.bundle[i];
        assign issue_alu_io.stream = int_exu_io.streams[i];
        assign issue_alu_io.direction = int_exu_io.directions[i];
        assign issue_alu_io.ras_type = int_exu_io.ras_type[i];
        assign issue_alu_io.br_type = int_exu_io.br_type[i];
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

        RobIdx out;
        LoopCompare #(`ROB_WIDTH) compare_older (issue_alu_io.bundle.robIdx, backendCtrl.redirectIdx, older[i], out);

        assign branch_ctrl_io.bundles[i].en = int_exu_io.en[i] & int_exu_io.bundle[i].branchv & int_exu_io.valid[i] & (~backendCtrl.redirect | older[i]);
        assign branch_ctrl_io.bundles[i].fsqInfo = int_exu_io.bundle[i].fsqInfo;
        assign branch_ctrl_io.bundles[i].robIdx = int_exu_io.bundle[i].robIdx;
    end
endgenerate

    assign backendRedirectInfo = branch_ctrl_io.redirectInfo;
    assign branchRedirectInfo = branch_ctrl_io.branchInfo;
    AluBranchCtrl branch_ctrl(
        .clk(clk),
        .rst(rst),
        .io(branch_ctrl_io)
    );
endmodule