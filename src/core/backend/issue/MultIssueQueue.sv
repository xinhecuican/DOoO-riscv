`include "../../../defines/defines.svh"

module MultIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_mult_io,
    IssueRegIO.issue mult_reg_io,
    IssueMultIO.issue mult_exu_io,
    input WakeupBus wakeupBus,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl
);
    IssueBankIO #($bits(MultIssueBundle), 2, `MULT_ISSUE_SIZE, 2) bank_io [`MULT_SIZE-1: 0]();
    // logic `ARRAY(`MULT_SIZE, $clog2(`MULT_SIZE)) order;
    // logic `ARRAY(`MULT_SIZE, $clog2(`MULT_SIZE)) bankNum;
    logic `N(`MULT_SIZE) full;
    logic `N(`MULT_SIZE) enNext, bigger, div_s2;
    logic div_ready, div_older;
    RobIdx div_robIdx;

generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        MultIssueBundle bundle;
        IssueBank #($bits(MultIssueBundle), `MULT_ISSUE_SIZE, 2, `INT_WAKEUP_PORT, 0, 2) issue_bank(
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        // assign bankNum[i] = bank_io[i].bankNum;
        assign bundle = dis_mult_io.data[0];

        assign bank_io[i].en = dis_mult_io.en[0] & ~dis_mult_io.full;
        assign bank_io[i].type_i[0] = bundle.multop[2];
        assign bank_io[i].type_i[1] = ~bundle.multop[2];
        assign bank_io[i].status = dis_mult_io.status[0];
        assign bank_io[i].data = dis_mult_io.data[0];
        assign bank_io[i].ready = mult_reg_io.ready[i];
        assign bank_io[i].type_ready[0] = div_ready;
        assign bank_io[i].type_ready[1] = 1'b1;
        assign full[i] = bank_io[i].full;

        assign mult_reg_io.en[i] = bank_io[i].reg_en;
        assign mult_reg_io.preg[i] = bank_io[i].src[0];
        assign mult_reg_io.preg[`MULT_SIZE+i] = bank_io[i].src[1];
        
        LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_io[i].status_o.robIdx, backendCtrl.redirectIdx, bigger[i]);
    end
endgenerate
    assign dis_mult_io.full = |full;

generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        always_ff @(posedge clk)begin
            enNext[i] <= bank_io[i].reg_en & mult_reg_io.ready[i];
            div_s2[i] <= bank_io[i].type_o[0];
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

    LoopCompare #(`ROB_WIDTH) cmp_div_older(backendCtrl.redirectIdx, div_robIdx, div_older);
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            div_ready <= 1'b1;
            div_robIdx <= 0;
        end
        else begin
            if(backendCtrl.redirect & div_older & ~(enNext[0] & div_s2[0]) | 
               mult_exu_io.div_end |
               enNext[0] & div_s2[0] & backendCtrl.redirect & ~bigger)begin
                div_ready <= 1'b1;
            end
            else if(bank_io[0].reg_en & mult_reg_io.ready[0] & bank_io[0].type_o[0])begin
                div_ready <= 1'b0;
            end

            if(enNext[0] & div_s2[0])begin
                div_robIdx <= bank_io[0].status_o.robIdx;
            end
        end
    end
endmodule