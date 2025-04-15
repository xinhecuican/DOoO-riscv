`include "../../../defines/defines.svh"

module IntIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_issue_io,
    IssueRegIO.issue int_reg_io,
    IssueWakeupIO.issue int_wakeup_io,
    IntIssueExuIO.issue issue_exu_io,
    FsqBackendIO.backend fsq_back_io,
    WakeupBus.in wakeupBus,
    input BackendCtrl backendCtrl
);

    localparam BANK_SIZE = `INT_ISSUE_SIZE / `ALU_SIZE;
    localparam BANK_NUM = `ALU_SIZE;
    IssueBankIO #($bits(IntIssueBundle), 2, BANK_SIZE) bank_io [BANK_NUM-1: 0]();
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) order;
    logic `ARRAY(BANK_NUM, $clog2(BANK_SIZE)+1) bankNum;
    logic `N(BANK_NUM) full;
    logic `N(BANK_NUM) enNext, bigger;
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        IssueBank #($bits(IntIssueBundle), BANK_SIZE, 2, `INT_WAKEUP_PORT, 1) issue_bank (
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        assign bankNum[i] = bank_io[i].bankNum;

        assign bank_io[i].en = dis_issue_io.en[order[i]] & ~dis_issue_io.full;
        assign bank_io[i].status = dis_issue_io.status[order[i]];
        assign bank_io[i].data = dis_issue_io.data[order[i]];
        assign bank_io[i].ready = int_wakeup_io.ready[i] & int_reg_io.ready[i];
        assign full[i] = bank_io[i].full;

        assign int_reg_io.en[i] = bank_io[i].reg_en;
        assign int_reg_io.preg[i] = bank_io[i].src[0];
        assign int_reg_io.preg[BANK_NUM+i] = bank_io[i].src[1];
        assign int_wakeup_io.en[i] = bank_io[i].reg_en & int_reg_io.ready[i];
        assign int_wakeup_io.we[i] = bank_io[i].we;
        assign int_wakeup_io.rd[i] = bank_io[i].rd;
        assign fsq_back_io.fsqIdx[i] = bank_io[i].fsqIdx;

        LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_io[i].status_o.robIdx, backendCtrl.redirectIdx, bigger[i]);
    end
endgenerate
    assign dis_issue_io.full = |full;
    OrderSelector #(BANK_NUM, BANK_SIZE) order_selector (.*);
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        IntIssueBundle bundle;
        assign bundle = bank_io[i].data_o;
        always_ff @(posedge clk)begin
            enNext[i] <= bank_io[i].reg_en & int_wakeup_io.ready[i] & int_reg_io.ready[i];
            issue_exu_io.status[i] <= bank_io[i].status_o;
            issue_exu_io.bundle[i] <= bank_io[i].data_o;
            issue_exu_io.vaddrs[i] <= {fsq_back_io.streams[i].start_addr[`VADDR_SIZE-1: `INST_OFFSET] + bundle.fsqInfo.offset, {`INST_OFFSET{1'b0}}};
        end
    end
endgenerate

    assign issue_exu_io.rs1_data = int_reg_io.data[BANK_NUM-1: 0];
    assign issue_exu_io.rs2_data = int_reg_io.data[BANK_NUM*2-1: BANK_NUM];
    always_ff @(posedge clk)begin
        issue_exu_io.en <= enNext & ({BANK_NUM{~backendCtrl.redirect}} | bigger);
        issue_exu_io.streams <= fsq_back_io.streams;
    end

endmodule