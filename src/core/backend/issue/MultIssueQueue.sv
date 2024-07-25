`include "../../../defines/defines.svh"

module MultIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_mult_io,
    IssueRegIO.issue mult_reg_io,
    IssueMultIO.issue mult_exu_io,
    WakeupBus wakeupBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);
    IssueBankIO #($bits(MultIssueBundle), `MULT_ISSUE_SIZE) bank_io [`MULT_SIZE-1: 0]();
    // logic `ARRAY(`MULT_SIZE, $clog2(`MULT_SIZE)) order;
    // logic `ARRAY(`MULT_SIZE, $clog2(`MULT_SIZE)) bankNum;
    logic `N(`MULT_SIZE) full;
    logic `N(`MULT_SIZE) enNext, bigger;

generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        IssueBank #($bits(MultIssueBundle), `MULT_ISSUE_SIZE) issue_bank(
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        // assign bankNum[i] = bank_io[i].bankNum;

        assign bank_io[i].en = dis_mult_io.en[0] &~dis_mult_io.full;
        assign bank_io[i].status = dis_mult_io.status[0];
        assign bank_io[i].data = dis_mult_io.data[0];
        assign bank_io[i].ready = mult_reg_io.ready[i];
        assign full[i] = bank_io[i].full;

        assign mult_reg_io.en[i] = bank_io[i].reg_en;
        assign mult_reg_io.preg[i] = bank_io[i].rs1;
        assign mult_reg_io.preg[`MULT_SIZE+i] = bank_io[i].rs2;
        
        LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_io[i].status_o.robIdx, backendCtrl.redirectIdx, bigger[i]);
    end
endgenerate
    assign dis_mult_io.full = |full;

generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        always_ff @(posedge clk)begin
            enNext[i] <= bank_io[i].reg_en & mult_reg_io.ready[i];
            mult_exu_io.bundle[i] <= bank_io[i].data_o;
            mult_exu_io.status[i] <= bank_io[i].status_o;
        end
    end
endgenerate

    assign mult_exu_io.rs1_data = mult_reg_io.data[`MULT_SIZE-1: 0];
    assign mult_exu_io.rs2_data = mult_reg_io.data[`MULT_SIZE*2-1: `MULT_SIZE];
    always_ff @(posedge clk)begin
        mult_exu_io.en <= enNext & ({`MULT_SIZE{~backendCtrl.redirect}} | bigger);
    end
endmodule