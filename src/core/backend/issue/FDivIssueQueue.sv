`include "../../../defines/defines.svh"

module FDivIssueQueue (
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_fdiv_io,
    IssueRegIO.issue fdiv_reg_io,
    IssueFDivIO.issue issue_fdiv_io,
    WakeupBus.in fp_wakeupBus,
    input BackendCtrl backendCtrl
);
    localparam BANK_SIZE = `FDIV_ISSUE_SIZE / `FDIV_SIZE;
    localparam BANK_NUM = `FDIV_SIZE;

    `CONSTRAINT(`FDIV_SIZE, 1, "only one fdiv unit")

    IssueBankIO #($bits(FDivIssueBundle), 2, BANK_SIZE, 1) bank_io();
    logic enNext, bigger, issue_bigger, issue;
    logic ready;
    RobIdx issue_robIdx;

    IssueBank #(
        .DATA_WIDTH($bits(FDivIssueBundle)),
        .DEPTH(BANK_SIZE),
        .SRC_NUM(2),
        .WAKEUP_PORT_NUM(`FP_WAKEUP_PORT),
        .FSQV(0),
        .TYPE_SIZE(1)
    ) issue_bank (
        .*,
        .io(bank_io),
        .wakeupBus(fp_wakeupBus)
    );

    assign bank_io.en = dis_fdiv_io.en & ~dis_fdiv_io.full;
    assign bank_io.type_i[0] = 1'b1;
    assign bank_io.status = dis_fdiv_io.status;
    assign bank_io.data = dis_fdiv_io.data;
    assign bank_io.ready = fdiv_reg_io.ready;
    assign bank_io.type_ready[0] = ready;
    assign dis_fdiv_io.full = bank_io.full;
    
    assign fdiv_reg_io.en = bank_io.reg_en;
    assign fdiv_reg_io.preg = bank_io.src;

    LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_io.status_o.robIdx, backendCtrl.redirectIdx, bigger);
    LoopCompare #(`ROB_WIDTH) cmp_issue_bigger (issue_robIdx, backendCtrl.redirectIdx, issue_bigger);

    always_ff @(posedge clk)begin
        enNext <= bank_io.reg_en & fdiv_reg_io.ready;
        issue_fdiv_io.en <= enNext & (~backendCtrl.redirect | bigger);
        issue_fdiv_io.status <= bank_io.status_o;
        issue_fdiv_io.bundle <= bank_io.data_o;
    end

    assign issue_fdiv_io.rs1_data = fdiv_reg_io.data[0];
    assign issue_fdiv_io.rs2_data = fdiv_reg_io.data[1];

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            ready <= 1'b1;
            issue_robIdx <= 1'b0;
            issue <= 1'b0;
        end
        else begin
            if(backendCtrl.redirect & ((enNext & ~bigger) | (issue & ~issue_bigger)))begin
                ready <= 1'b1;
            end
            else if(bank_io.reg_en & fdiv_reg_io.ready) begin
                ready <= 1'b0;
            end

            if(enNext & (~backendCtrl.redirect | bigger))begin
                issue <= 1'b1;
                issue_robIdx <= bank_io.status_o.robIdx;
            end

            if(issue_fdiv_io.done)begin
                issue <= 1'b0;
                ready <= 1'b1;
            end
        end
    end
endmodule