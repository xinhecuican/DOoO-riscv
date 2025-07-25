`include "../../../defines/defines.svh"

interface LoadUnitIO;
    logic `N(`LOAD_ISSUE_BANK_NUM) en;
    LoadIssueData `N(`LOAD_ISSUE_BANK_NUM) loadIssueData;
    logic `N($clog2(`LOAD_DIS_PORT)+1) eqNum;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx;
    logic `N(`LOAD_DIS_PORT) dis_en;
    RobIdx `N(`LOAD_DIS_PORT) dis_rob_idx;
    LoadIdx `N(`LOAD_DIS_PORT) dis_lq_idx;
    logic full;
    logic dis_stall;

    ReplyRequest `N(`LOAD_PIPELINE) reply_fast;
    ReplyRequest `N(`LOAD_PIPELINE) reply_slow;
    logic `N(`LOAD_PIPELINE) success;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) success_idx;

    modport load (output en, loadIssueData, eqNum, issue_idx, dis_en, dis_rob_idx, dis_lq_idx, dis_stall,
                  input reply_fast, reply_slow, success, success_idx, full);
    modport queue (input dis_en, eqNum, dis_rob_idx, dis_lq_idx, dis_stall, output full);
endinterface

module LoadIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_load_io,
    IssueRegIO.issue load_reg_io,
    WakeupBus.in wakeupBus,
    LoadUnitIO.load load_io,
    DTLBLsuIO.lq tlb_lsu_io,
`ifdef FEAT_MEMPRED
    input logic `N(`LOAD_PIPELINE) lfst_en,
    input RobIdx `N(`LOAD_PIPELINE) lfst_idx,
    input logic `N(`STORE_PIPELINE) lfst_finish,
    input RobIdx `N(`STORE_PIPELINE) lfst_finish_idx,
`endif
    input BackendCtrl backendCtrl
);

    LoadIssueBankIO bank_io [`LOAD_ISSUE_BANK_NUM-1: 0]();
    MemIssueBundle `N(`LOAD_ISSUE_BANK_NUM) mem_issue_bundle;
    logic `ARRAY(`LOAD_ISSUE_BANK_NUM, $clog2(`LOAD_ISSUE_BANK_NUM)) order;
    logic `ARRAY(`LOAD_ISSUE_BANK_NUM, $clog2(`LOAD_ISSUE_BANK_SIZE)) bankNum;
    logic `N(`LOAD_ISSUE_BANK_NUM) full, enNext, bigger;
    logic `N($clog2(`LOAD_DIS_PORT)+1) disNum;

    `UNPARAM(LOAD_ISSUE_BANK_NUM, 2, "order for load queue bank")
    assign order[0] = ~(mem_issue_bundle[0].lqIdx.idx[0] == 0);
    assign order[1] = mem_issue_bundle[0].lqIdx.idx[0] == 0;
generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_NUM; i++)begin
        LoadIssueBank issue_bank (
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        assign mem_issue_bundle[i] = dis_load_io.data[i];
        assign bankNum[i] = bank_io[i].bankNum;

        assign bank_io[i].en = dis_load_io.en[order[i]] & ~dis_load_io.full;
        assign bank_io[i].status = dis_load_io.status[order[i]];
        assign bank_io[i].data = dis_load_io.data[order[i]];
`ifdef FEAT_MEMPRED
        assign bank_io[i].lfst_en = lfst_en[order[i]];
        assign bank_io[i].lfst_idx = lfst_idx[order[i]];
        assign bank_io[i].lfst_finish = lfst_finish;
        assign bank_io[i].lfst_finish_idx = lfst_finish_idx;
`endif
        assign bank_io[i].reply_fast = load_io.reply_fast[i];
        assign bank_io[i].reply_slow = load_io.reply_slow[i];
        assign bank_io[i].success = load_io.success[i];
        assign bank_io[i].success_idx = load_io.success_idx[i];
        assign bank_io[i].tlb_en = tlb_lsu_io.lwb[i];
        assign bank_io[i].tlb_exception = tlb_lsu_io.lwb_exception[i];
        assign bank_io[i].tlb_error = tlb_lsu_io.lwb_error[i];
        assign bank_io[i].tlb_bank_idx = tlb_lsu_io.lwb_idx[i];
        assign full[i] = bank_io[i].full;

        assign load_io.dis_en[i] = dis_load_io.en[order[i]];

        assign load_reg_io.en[i] = bank_io[i].reg_en;
        assign load_reg_io.preg[i] = bank_io[i].rs1;
        assign load_io.loadIssueData[i] = bank_io[i].data_o;
        assign load_io.issue_idx[i] = bank_io[i].issue_idx;
        assign load_io.dis_rob_idx[i] = dis_load_io.status[order[i]].robIdx;
        assign load_io.dis_lq_idx[i] = mem_issue_bundle[order[i]].lqIdx;

        LoopCompare #(`ROB_WIDTH) cmp_bigger(bank_io[i].robIdx_o, backendCtrl.redirectIdx, bigger[i]);
    end
endgenerate
    assign dis_load_io.full = (|full) | load_io.full;
    assign load_io.dis_stall = dis_load_io.full;
    ParallelAdder #(1, `LOAD_ISSUE_BANK_NUM) adder_dis_num (dis_load_io.en, disNum);
    assign load_io.eqNum = disNum;
    always_ff @(posedge clk)begin
        enNext <= load_reg_io.en;
        for(int i=0; i<`LOAD_ISSUE_BANK_NUM; i++)begin
            load_io.en[i] <= enNext[i] & (~backendCtrl.redirect | bigger[i]);
        end
    end
endmodule

interface LoadIssueBankIO;
    logic en;
    IssueStatusBundle status;
    MemIssueBundle data;
    logic reg_en;
    logic `N(`PREG_WIDTH) rs1;
    logic full;
    logic `N($clog2(`LOAD_ISSUE_BANK_SIZE)+1) bankNum;
    LoadIssueData data_o;
    logic `N(`LOAD_ISSUE_BANK_WIDTH) issue_idx;
    RobIdx robIdx_o;
    ReplyRequest reply_fast;
    ReplyRequest reply_slow;
    logic success;
    logic `N(`LOAD_ISSUE_BANK_WIDTH) success_idx;
    logic tlb_en;
    logic tlb_exception;
    logic tlb_error;
    logic `N(`LOAD_ISSUE_BANK_WIDTH) tlb_bank_idx;
`ifdef FEAT_MEMPRED
    logic lfst_en;
    RobIdx  lfst_idx;
    logic `N(`STORE_PIPELINE) lfst_finish;
    RobIdx `N(`STORE_PIPELINE) lfst_finish_idx;
`endif

    modport bank(input en, status, data, reply_fast, reply_slow, success, success_idx,
                 tlb_en, tlb_exception, tlb_error, tlb_bank_idx,
`ifdef FEAT_MEMPRED
                input lfst_en, lfst_idx, lfst_finish, lfst_finish_idx,
`endif
                 output full, reg_en, rs1, bankNum, data_o, issue_idx, robIdx_o);
endinterface

module LoadIssueBank(
    input logic clk,
    input logic rst,
    LoadIssueBankIO.bank io,
    WakeupBus.in wakeupBus,
    input BackendCtrl backendCtrl
);
    typedef struct packed {
        logic rs1v;
        logic `N(`PREG_WIDTH) rs1;
        RobIdx robIdx;
    } StatusBundle;

    logic `N(`LOAD_ISSUE_BANK_SIZE) en;
    StatusBundle `N(`LOAD_ISSUE_BANK_SIZE) status_ram;
    logic `N(`LOAD_ISSUE_BANK_SIZE) free_en;
    logic `N($clog2(`LOAD_ISSUE_BANK_SIZE)) freeIdx;
    // exception: tlb miss exception
    logic `N(`LOAD_ISSUE_BANK_SIZE) ready, issue, tlbmiss;
    logic `N(`LOAD_ISSUE_BANK_SIZE) select_en, tlbmiss_valid;
    logic `N($clog2(`LOAD_ISSUE_BANK_SIZE)) selectIdx, selectIdxNext;
    LoadIssueData data_o;
    logic `ARRAY(`LOAD_ISSUE_BANK_SIZE, `INT_WAKEUP_PORT) rs1_cmp;
    logic [1: 0] size;
    logic reg_en;
    RobIdx select_robIdx;
    logic `N(`LOAD_ISSUE_BANK_SIZE) selectIdx_decode, replyfast_decode, replyslow_decode, tlbbank_decode;
`ifdef FEAT_MEMPRED
    logic `N(`LOAD_ISSUE_BANK_SIZE) lfst_en;
    RobIdx `N(`LOAD_ISSUE_BANK_SIZE) lfst_idx;
`endif

    assign size = io.data.memop[1: 0];
    SDPRAM #(
        .WIDTH($bits(LoadIssueData)),
        .DEPTH(`LOAD_ISSUE_BANK_SIZE)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(1'b0),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdxNext),
        .we(io.en),
        .wdata({io.status.we, io.data.uext, 
`ifdef RVF
        io.data.fp_en,
`endif
        size, io.data.imm, io.status.rd, io.data.lqIdx, io.data.sqIdx, io.status.robIdx, io.data.fsqInfo}),
        .rdata1(data_o),
        .ready()
    );

generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs1v & ~issue[i]
`ifdef FEAT_MEMPRED
                        & ~lfst_en[i]
`endif
        ;
    end
endgenerate
    DirectionSelector #(`LOAD_ISSUE_BANK_SIZE) selector (
        .clk(clk),
        .rst(rst),
        .en(io.en),
        .idx(free_en),
        .ready(ready),
        .select(select_en)
    );
    assign io.full = &en;
    assign io.reg_en = |ready & ~backendCtrl.redirect;
    assign io.rs1 = status_ram[selectIdx].rs1;
    always_ff @(posedge clk)begin
        select_robIdx <= status_ram[selectIdx].robIdx;
    end
    assign io.robIdx_o = select_robIdx;
    PSelector #(`LOAD_ISSUE_BANK_SIZE) selector_free_idx (~en, free_en);
    Encoder #(`LOAD_ISSUE_BANK_SIZE) encoder_free_idx (free_en, freeIdx);
    Encoder #(`LOAD_ISSUE_BANK_SIZE) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(`LOAD_ISSUE_BANK_SIZE)) adder_bankNum(en, io.bankNum);
generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
        for(genvar j=0; j<`INT_WAKEUP_PORT; j++)begin
            assign rs1_cmp[i][j] = wakeupBus.en[j] & wakeupBus.we[j] & (wakeupBus.rd[j] == status_ram[i].rs1);
        end
    end
endgenerate
    // redirect
    logic `N(`LOAD_ISSUE_BANK_SIZE) bigger, walk_en;
    assign walk_en = en & bigger;
generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
        assign bigger[i] = (status_ram[i].robIdx.dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > status_ram[i].robIdx.idx);
        assign tlbmiss_valid[i] = io.reply_slow.en && (io.reply_slow.reason == 2'b11) & replyslow_decode[i];
    end
endgenerate

    logic `N(`LOAD_ISSUE_BANK_SIZE) success_idx_decode;
    Decoder #(`LOAD_ISSUE_BANK_SIZE) decoder_success_idx (io.success_idx, success_idx_decode);
    Decoder #(`LOAD_ISSUE_BANK_SIZE) decoder_select_idx (selectIdx, selectIdx_decode);
    Decoder #(`LOAD_ISSUE_BANK_SIZE) decoder_replyfast (io.reply_fast.issue_idx, replyfast_decode);
    Decoder #(`LOAD_ISSUE_BANK_SIZE) decoder_replyslow (io.reply_slow.issue_idx, replyslow_decode);
    Decoder #(`LOAD_ISSUE_BANK_SIZE) decoder_tlbbank (io.tlb_bank_idx, tlbbank_decode);

    always_ff @(posedge clk)begin
        selectIdxNext <= selectIdx;
        io.issue_idx <= selectIdxNext;
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
            io.data_o <= 0;
            issue <= 0;
            tlbmiss <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en &
                      ~({`LOAD_ISSUE_BANK_SIZE{io.success}} & success_idx_decode);
            end
            else begin
                en <= (en | ({`LOAD_ISSUE_BANK_SIZE{io.en}} & free_en)) &
                      ~({`LOAD_ISSUE_BANK_SIZE{io.success}} & success_idx_decode);
            end
            
            if(io.en)begin
                status_ram[freeIdx].rs1v <= io.status.rs1v;
                status_ram[freeIdx].rs1 <= io.status.rs1;
                status_ram[freeIdx].robIdx <= io.status.robIdx;
            end

            for(int i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
                issue[i] <= (issue[i] | (((ready[i]) & ~backendCtrl.redirect) & selectIdx_decode[i])) &
                            ~(io.reply_fast.en & replyfast_decode[i]) &
                            ~(io.reply_slow.en & (io.reply_slow.reason != 2'b11) & replyslow_decode[i]) &
                            ~(io.tlb_en & en[i] & tlbmiss[i] & (~io.tlb_error | tlbbank_decode[i])) &
                            ~(io.en & free_en[i]);
                tlbmiss[i] <= ((tlbmiss[i] & ~(io.tlb_en & (~io.tlb_error | tlbbank_decode[i]))) |
                                tlbmiss_valid[i]) &
                              ~(io.en & free_en[i]);
            end

            for(int i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
                if(io.en && free_en[i])begin
                    status_ram[i].rs1v <= io.status.rs1v;
                end
                else begin
                    status_ram[i].rs1v <= (status_ram[i].rs1v | (|rs1_cmp[i]));
                end
            end
            io.data_o <= data_o;
        end
    end

`ifdef FEAT_MEMPRED
    logic `ARRAY(`STORE_PIPELINE, `LOAD_ISSUE_BANK_SIZE) lfst_eq;
    logic `N(`LOAD_ISSUE_BANK_SIZE) lfst_eq_all;
    logic lfst_older;
    logic `N(`LOAD_ISSUE_BANK_SIZE) lfst_redirect_older;

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`LOAD_ISSUE_BANK_SIZE; j++)begin
            assign lfst_eq[i][j] = lfst_en[j] & io.lfst_finish[i] & (io.lfst_finish_idx[i] == lfst_idx[j]);
        end
    end
    for(genvar i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
        LoopCompare #(`ROB_WIDTH) cmp_lfst_redirect(
            backendCtrl.redirectIdx, lfst_idx[i], lfst_redirect_older[i]);
    end
endgenerate
    ParallelOR #(`LOAD_ISSUE_BANK_SIZE, `STORE_PIPELINE) or_lfst_eq (lfst_eq, lfst_eq_all);
    LoopCompare #(`ROB_WIDTH) cmp_lfst (io.lfst_idx, io.status.robIdx, lfst_older);
    always_ff @(posedge clk)begin
        if(io.en & io.lfst_en)begin
            lfst_idx[freeIdx] <= io.lfst_idx;
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            lfst_en <= 0;
        end
        else begin
            for(int i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
                lfst_en[i] <= (lfst_en[i] | io.en & free_en[i] & io.lfst_en & lfst_older) &
                            ~lfst_eq_all[i] & ~(backendCtrl.redirect & lfst_redirect_older[i]);
            end
        end
    end
`endif

endmodule