`include "../../../defines/defines.svh"

module FMAIssueQueue (
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_fma_io,
    IssueRegIO.issue fma_reg_io,
    IssueFMAIO.issue issue_fma_io,
    input WakeupBus fp_wakeupBus,
    input BackendCtrl backendCtrl
);
    localparam BANK_SIZE = `FMA_ISSUE_SIZE / `FMA_SIZE;
    localparam BANK_NUM = `FMA_SIZE;
    logic `N(BANK_NUM) full, enNext, reg_en;
    logic `ARRAY(BANK_NUM, 3) type_o;
    logic `N(BANK_NUM) bigger;
    IssueBankIO #($bits(FMAIssueBundle), 3, BANK_SIZE, 3) bank_io[BANK_NUM-1: 0]();
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) order;
    logic `ARRAY(BANK_NUM, $clog2(BANK_SIZE)) bankNum;
    logic `N(BANK_NUM) bank_en_s4, madd_s3, madd_s4;
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        FMAIssueBundle bundle;
        IssueBank #(
            .DATA_WIDTH($bits(FMAIssueBundle)), 
            .DEPTH(BANK_SIZE), 
            .SRC_NUM(3), 
            .WAKEUP_PORT_NUM(`FP_WAKEUP_PORT), 
            .FSQV(0), 
            .TYPE_SIZE(3)
        ) issue_bank(
            .*,
            .io(bank_io[i]),
            .wakeupBus(fp_wakeupBus)
        );

        assign bankNum[i] = bank_io[i].bankNum;
        assign bundle = dis_fma_io.data[order[i]];

        assign bank_io[i].en = dis_fma_io.en[order[i]] & ~dis_fma_io.full;
        assign bank_io[i].type_i[0] = bundle.fltop == `FLT_ADD || bundle.fltop == `FLT_SUB;
        assign bank_io[i].type_i[1] = bundle.fltop == `FLT_MUL;
        assign bank_io[i].type_i[2] = bundle.fltop != `FLT_ADD && bundle.fltop != `FLT_SUB &&
                                      bundle.fltop != `FLT_MUL;
        assign bank_io[i].status = dis_fma_io.status[order[i]];
        assign bank_io[i].data = dis_fma_io.data[order[i]];
        assign bank_io[i].ready = ~fma_reg_io.ready[i];
        assign bank_io[i].type_ready[0] = ~(enNext[i] & type_o[i][1] | 
                                          bank_en_s4[i] & madd_s4[i]);
        assign bank_io[i].type_ready[1] = ~(issue_fma_io.en[i] & madd_s3[i]);
        assign bank_io[i].type_ready[2] = 1'b1;
        assign full[i] = bank_io[i].full;
        assign reg_en[i] = bank_io[i].reg_en;
        assign bank_io[i].ready = fma_reg_io.ready[i];

        assign fma_reg_io.en[i] = bank_io[i].reg_en;
        assign fma_reg_io.preg[i] = bank_io[i].src[0];
        assign fma_reg_io.preg[BANK_NUM+i] = bank_io[i].src[1];
        assign fma_reg_io.preg[BANK_NUM*2+i] = bank_io[i].src[2];

        LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_io[i].status_o.robIdx, backendCtrl.redirectIdx, bigger[i]);
    end
endgenerate
    assign dis_fma_io.full = |full;
    OrderSelector #(BANK_NUM, BANK_SIZE) order_selector (.*);
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        always_ff @(posedge clk)begin
            enNext[i] <= bank_io[i].reg_en & fma_reg_io.ready[i];
            issue_fma_io.en[i] <= enNext[i] & (~backendCtrl.redirect | bigger[i]);
            issue_fma_io.status[i] <= bank_io[i].status_o;
            issue_fma_io.bundle[i] <= bank_io[i].data_o;
            madd_s3[i] <= type_o[i][2];
            madd_s4[i] <= madd_s3[i];
            bank_en_s4[i] <= issue_fma_io.en[i];
            type_o[i] <= bank_io[i].type_o;
        end
    end
endgenerate

    assign issue_fma_io.rs1_data = fma_reg_io.data[BANK_NUM-1: 0];
    assign issue_fma_io.rs2_data = fma_reg_io.data[BANK_NUM +: BANK_NUM];
    assign issue_fma_io.rs3_data = fma_reg_io.data[BANK_NUM*2 +: BANK_NUM];
endmodule