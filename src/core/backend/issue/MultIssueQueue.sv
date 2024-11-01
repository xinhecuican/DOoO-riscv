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
    IssueBankIO #($bits(MultIssueBundle), `MULT_ISSUE_SIZE, 2) bank_io [`MULT_SIZE-1: 0]();
    // logic `ARRAY(`MULT_SIZE, $clog2(`MULT_SIZE)) order;
    // logic `ARRAY(`MULT_SIZE, $clog2(`MULT_SIZE)) bankNum;
    logic `N(`MULT_SIZE) full;
    logic `N(`MULT_SIZE) enNext, bigger;
    logic `N(`MULT_ISSUE_SIZE) div;
    logic select_div, select_div_n1, select_div_n2;
    logic div_ready;

generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        IssueBank #($bits(MultIssueBundle), `MULT_ISSUE_SIZE, 2, `INT_WAKEUP_PORT) issue_bank(
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        // assign bankNum[i] = bank_io[i].bankNum;

        assign bank_io[i].en = dis_mult_io.en[0] & ~dis_mult_io.full;
        assign bank_io[i].status = dis_mult_io.status[0];
        assign bank_io[i].data = dis_mult_io.data[0];
        assign bank_io[i].ready = mult_reg_io.ready[i] & ~(select_div & ~div_ready);
        assign full[i] = bank_io[i].full;

        assign mult_reg_io.en[i] = bank_io[i].reg_en & ~(select_div & ~div_ready);
        assign mult_reg_io.preg[i] = bank_io[i].src[0];
        assign mult_reg_io.preg[`MULT_SIZE+i] = bank_io[i].src[1];
        
        LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_io[i].status_o.robIdx, backendCtrl.redirectIdx, bigger[i]);
    end
endgenerate
    assign dis_mult_io.full = |full;

generate
    for(genvar i=0; i<`MULT_SIZE; i++)begin
        always_ff @(posedge clk)begin
            enNext[i] <= bank_io[i].reg_en & mult_reg_io.ready[i] & ~(select_div & ~div_ready);
            mult_exu_io.bundle[i] <= bank_io[i].data_o;
            mult_exu_io.status[i] <= bank_io[i].status_o;
        end
    end
endgenerate

    assign mult_exu_io.rs1_data = mult_reg_io.data[`MULT_SIZE-1: 0];
    assign mult_exu_io.rs2_data = mult_reg_io.data[`MULT_SIZE*2-1: `MULT_SIZE];
    always_ff @(posedge clk)begin
        select_div_n1 <= select_div;
        select_div_n2 <= select_div_n1;
        mult_exu_io.en <= enNext & ({`MULT_SIZE{~backendCtrl.redirect}} | bigger);
    end

    MultIssueBundle bundle;
    logic redirect_n;
    assign bundle = dis_mult_io.data[0];
    assign select_div = div[bank_io[0].selectIdx];
    `SIG_N(backendCtrl.redirect, redirect_n)
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            div <= 0;
            div_ready <= 1'b0;
        end
        else begin
            if(dis_mult_io.en[0] & ~dis_mult_io.full)begin
                div[bank_io[0].freeIdx] <= bundle.multop[2];
            end
            if(bank_io[0].reg_en & mult_reg_io.ready[0] & div_ready & select_div)begin
                div_ready <= 1'b0;
            end

            if(mult_exu_io.div_end |
               redirect_n & mult_exu_io.div_ready & ~(mult_exu_io.en[0] & select_div_n2))begin
                div_ready <= 1'b1;
            end
        end
    end
endmodule