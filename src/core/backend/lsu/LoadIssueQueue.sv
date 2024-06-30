`include "../../../defines/defines.svh"

interface LoadUnitIO;
    logic `N(`LOAD_ISSUE_BANK_NUM) en;
    LoadIssueData `N(`LOAD_ISSUE_BANK_NUM) loadIssueData;
    logic `N($clog2(`LOAD_DIS_PORT)+1) eqNum;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) issue_idx;

    logic `N(`LOAD_DIS_PORT) dis_en;
    RobIdx `N(`LOAD_DIS_PORT) dis_rob_idx;
    LoadIdx `N(`LOAD_DIS_PORT) dis_lq_idx;

    LoadReplyRequest `N(`LOAD_PIPELINE) reply_fast;
    LoadReplyRequest `N(`LOAD_PIPELINE) reply_slow;
    logic `N(`LOAD_PIPELINE) success;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) success_idx;

    modport load (output en, loadIssueData, eqNum, issue_idx, dis_en, dis_rob_idx, dis_lq_idx,
                  input reply_fast, reply_slow, success, success_idx);
    modport queue (input dis_en, dis_rob_idx, dis_lq_idx);
endinterface

module LoadIssueQueue(
    input logic clk,
    input logic rst,
    input LoadIdx `N(`LOAD_PIPELINE) lqIdx,
    input StoreIdx `N(`LOAD_PIPELINE) sqIdx,
    DisIssueIO.issue dis_load_io,
    IssueWakeupIO.regfile load_wakeup_io,
    WakeupBus wakeupBus,
    LoadUnitIO.load load_io,
    BackendCtrl backendCtrl
);

    LoadIssueBankIO bank_io [`LOAD_ISSUE_BANK_NUM-1: 0]();
    logic `ARRAY(`LOAD_ISSUE_BANK_NUM, $clog2(`LOAD_ISSUE_BANK_NUM)) order;
    logic `ARRAY(`LOAD_ISSUE_BANK_NUM, $clog2(`LOAD_ISSUE_BANK_SIZE)) bankNum;
    logic `ARRAY(`LOAD_ISSUE_BANK_NUM, $clog2(`LOAD_ISSUE_BANK_NUM)) originOrder, sortOrder;
    logic `N(`LOAD_ISSUE_BANK_NUM) full;
    logic `N($clog2(`LOAD_DIS_PORT)+1) disNum;
generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_NUM; i++)begin
        LoadIssueBank issue_bank (
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        MemIssueBundle mem_issue_bundle;
        assign mem_issue_bundle = dis_load_io.data[i];
        assign bankNum[i] = bank_io[i].bankNum;
        assign originOrder[i] = i;

        assign bank_io[i].en = dis_load_io.en[order[i]] & ~dis_load_io.full;
        assign bank_io[i].status = dis_load_io.status[order[i]];
        assign bank_io[i].data = dis_load_io.data[order[i]];
        assign bank_io[i].lqIdx = lqIdx[order[i]];
        assign bank_io[i].sqIdx = sqIdx[order[i]];
        assign bank_io[i].reply_fast = load_io.reply_fast[i];
        assign bank_io[i].reply_slow = load_io.reply_slow[i];
        assign bank_io[i].success = load_io.success[i];
        assign bank_io[i].success_idx = load_io.success_idx[i];
        assign full[i] = bank_io[i].full;

        assign load_wakeup_io.en[i] = bank_io[i].reg_en & ~backendCtrl.redirect;
        assign load_wakeup_io.preg[i] = bank_io[i].rs1;
        assign load_io.loadIssueData[i] = bank_io[i].data_o;
        assign load_io.issue_idx[i] = bank_io[i].issue_idx;
        assign load_io.dis_rob_idx[i] = mem_issue_bundle.robIdx;
        assign load_io.dis_lq_idx[i] = lqIdx[i];
    end
endgenerate
    assign dis_load_io.full = |full;
    Sort #(`LOAD_ISSUE_BANK_NUM, $clog2(`LOAD_ISSUE_BANK_SIZE), $clog2(`LOAD_ISSUE_BANK_NUM)) sort_order (bankNum, originOrder, sortOrder); 
    assign load_io.dis_en = full ? 0 : dis_load_io.en;
    ParallelAdder #(1, `LOAD_ISSUE_BANK_NUM) adder_dis_num (dis_load_io.en, disNum);
    assign load_io.eqNum = full ? 0 : disNum;
    always_ff @(posedge clk)begin
        order <= sortOrder;
        load_io.en <= load_wakeup_io.en & load_wakeup_io.ready;
    end
endmodule

interface LoadIssueBankIO;
    logic en;
    IssueStatusBundle status;
    MemIssueBundle data;
    LoadIdx lqIdx;
    StoreIdx sqIdx;
    logic reg_en;
    logic `N(`PREG_WIDTH) rs1;
    logic full;
    logic `N($clog2(`LOAD_ISSUE_BANK_SIZE)+1) bankNum;
    LoadIssueData data_o;
    logic `N(`LOAD_ISSUE_BANK_WIDTH) issue_idx;
    LoadReplyRequest reply_fast;
    LoadReplyRequest reply_slow;
    logic success;
    logic `N(`LOAD_ISSUE_BANK_WIDTH) success_idx;

    modport bank(input en, status, data, lqIdx, sqIdx, reply_fast, reply_slow, success, success_idx,
                 output full, reg_en, rs1, bankNum, data_o, issue_idx);
endinterface

module LoadIssueBank(
    input logic clk,
    input logic rst,
    LoadIssueBankIO.bank io,
    WakeupBus wakeupBus,
    BackendCtrl backendCtrl
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
    logic `N(`LOAD_ISSUE_BANK_SIZE) ready, issue;
    logic `N(`LOAD_ISSUE_BANK_SIZE) select_en;
    logic `N($clog2(`LOAD_ISSUE_BANK_SIZE)) selectIdx, selectIdxNext;
    LoadIssueData data_o;
    logic `ARRAY(`LOAD_ISSUE_BANK_SIZE, `WB_SIZE) rs1_cmp;
    logic [1: 0] size;

    assign size = io.data.memop == `MEM_LW ? 2'b10 :
                  io.data.memop == `MEM_LH ? 2'b01 : 2'b00;
    SDPRAM #(
        .WIDTH($bits(LoadIssueData)),
        .DEPTH(`LOAD_ISSUE_BANK_SIZE)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdxNext),
        .we(io.en),
        .wdata({io.data.uext, size, io.data.imm, io.data.rd, io.lqIdx, io.sqIdx, io.data.robIdx, io.data.fsqInfo}),
        .rdata1(data_o)
    );

generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs1v & ~issue;
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
    always_ff @(posedge clk)begin
        io.reg_en <= |ready;
        io.rs1 <= status_ram[selectIdx].rs1;
    end
    // assign io.reg_en = |ready;
    // assign io.rs1 = status_ram[selectIdx].rs1;
    PSelector #(`LOAD_ISSUE_BANK_SIZE) selector_free_idx (~en, free_en);
    Encoder #(`LOAD_ISSUE_BANK_SIZE) encoder_free_idx (free_en, freeIdx);
    Encoder #(`LOAD_ISSUE_BANK_SIZE) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(`LOAD_ISSUE_BANK_SIZE)) adder_bankNum(en, io.bankNum);
generate
    for(genvar i=0; i<`LOAD_ISSUE_BANK_SIZE; i++)begin
        for(genvar j=0; j<`WB_SIZE; j++)begin
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
    end
endgenerate

    logic `N(`LOAD_ISSUE_BANK_SIZE) success_idx_decode;
    Decoder #(`LOAD_ISSUE_BANK_SIZE) decoder_success_idx (io.success_idx, success_idx_decode);
    always_ff @(posedge clk or posedge rst)begin
        selectIdxNext <= selectIdx;
        io.issue_idx <= selectIdxNext;
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
            io.data_o <= 0;
            issue <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en;
            end
            else begin
                en <= (en | ({`LOAD_ISSUE_BANK_SIZE{io.en}} & free_en)) &
                      ~({`LOAD_ISSUE_BANK_SIZE{io.success}} & success_idx_decode);
            end
            
            if(io.en)begin
                status_ram[freeIdx].rs1v <= io.status.rs1v;
                status_ram[freeIdx].rs1 <= io.status.rs1;
                status_ram[freeIdx].robIdx <= io.status.robIdx;
                issue[freeIdx] <= 1'b0;
            end

            if(|ready)begin
                issue[selectIdx] <= 1'b1;
            end

            if(io.reply_fast.en)begin
                issue[io.reply_fast.issue_idx] <= 1'b0;
            end

            if(io.reply_slow.en)begin
                issue[io.reply_slow.issue_idx] <= 1'b0;
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
endmodule