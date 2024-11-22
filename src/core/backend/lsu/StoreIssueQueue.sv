`include "../../../defines/defines.svh"

interface StoreUnitIO;
    logic `N(`STORE_ISSUE_BANK_NUM) en;
    StoreIssueData `N(`STORE_ISSUE_BANK_NUM) storeIssueData;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) issue_idx;
    logic `N(`STORE_ISSUE_BANK_NUM) exception;
    logic `N(`STORE_DIS_PORT) dis_en;
    RobIdx `N(`STORE_DIS_PORT) dis_rob_idx;
    StoreIdx `N(`STORE_DIS_PORT) dis_sq_idx;
    logic `N(`STORE_ISSUE_BANK_NUM) data_en;
    StoreIdx `N(`STORE_ISSUE_BANK_NUM) data_sqIdx;
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, 2) data_size;
`ifdef RVF
    logic `N(`STORE_ISSUE_BANK_NUM) data_fp_sel;
`endif
    logic `N(`STORE_PIPELINE) success;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) success_idx;
    ReplyRequest `N(`STORE_PIPELINE) reply;

    logic full;
    logic dis_stall;

    modport store (output en, storeIssueData, dis_en, dis_rob_idx, dis_sq_idx, data_en, data_sqIdx, data_size, issue_idx, exception, dis_stall, input reply, success, success_idx, full
`ifdef RVF
    ,output data_fp_sel
`endif
    );
    modport queue (input data_en, dis_en, dis_rob_idx, dis_sq_idx, data_sqIdx, data_size, dis_stall, output full
`ifdef RVF
    ,input data_fp_sel
`endif
    );
endinterface

module StoreIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_store_io,
    IssueRegIO.issue store_reg_io,
    input WakeupBus int_wakeupBus,
`ifdef RVF
    input WakeupBus fp_wakeupBus,
`endif
    input BackendCtrl backendCtrl,
    StoreUnitIO.store store_io,
    DTLBLsuIO.sq tlb_lsu_io
);
    StoreAddrBankIO addr_io [`STORE_ISSUE_BANK_NUM-1: 0]();
    StoreDataBankIO data_io [`STORE_ISSUE_BANK_NUM-1: 0]();
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_NUM)) order;
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_SIZE)) bankNum;
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_NUM)) originOrder, sortOrder;
    logic `N(`STORE_ISSUE_BANK_NUM) full, addr_bigger, data_bigger;
    logic `N(`STORE_ISSUE_BANK_NUM) addr_en_next, data_en_next;
    logic `N($clog2(`STORE_DIS_PORT)+1) disNum;
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_NUM; i++)begin
        StoreAddrBank addr_bank (
            .*,
            .io(addr_io[i]),
            .wakeupBus(int_wakeupBus)
        );
        StoreDataBank data_bank (
            .*,
            .io(data_io[i])
        );
        MemIssueBundle mem_issue_bundle;
        assign mem_issue_bundle = dis_store_io.data[i];
        assign bankNum[i] = addr_io[i].bankNum;
        assign originOrder[i] = i;

        assign addr_io[i].en = dis_store_io.en[order[i]] & ~dis_store_io.full;
        assign addr_io[i].status = dis_store_io.status[order[i]];
        assign addr_io[i].data = dis_store_io.data[order[i]];
        assign addr_io[i].success = store_io.success[i];
        assign addr_io[i].success_idx = store_io.success_idx[i];
        assign addr_io[i].reply = store_io.reply[i];
        assign addr_io[i].tlb_en = tlb_lsu_io.swb[i];
        assign addr_io[i].tlb_exception = tlb_lsu_io.swb_exception[i];
        assign addr_io[i].tlb_error = tlb_lsu_io.swb_error[i];
        assign addr_io[i].tlb_bank_idx = tlb_lsu_io.swb_idx[i];
        assign full[i] = addr_io[i].full | data_io[i].full;
        
        assign store_reg_io.en[i] = addr_io[i].reg_en;
        assign store_reg_io.preg[i] = addr_io[i].rs1;
        assign store_io.storeIssueData[i] = addr_io[i].data_o;
        assign store_io.exception[i] = addr_io[i].exception_o;
        assign store_io.issue_idx[i] = addr_io[i].issue_idx;

        assign data_io[i].en = addr_io[i].en;
        assign data_io[i].status = addr_io[i].status;
        assign data_io[i].data = addr_io[i].data;
        assign data_io[i].reg_ready = store_reg_io.ready[i];
        
        assign store_reg_io.en[`STORE_ISSUE_BANK_NUM+i] = data_io[i].reg_en
`ifdef RVF
                                                          & ~data_io[i].fp_reg_en
`endif
        ;
        assign store_reg_io.preg[`STORE_ISSUE_BANK_NUM+i] = data_io[i].rs2;
`ifdef RVF
        assign store_reg_io.en[`STORE_ISSUE_BANK_NUM*2+i] = data_io[i].reg_en & data_io[i].fp_reg_en;
        assign store_reg_io.preg[`STORE_ISSUE_BANK_NUM*2+i] = data_io[i].rs2;
        assign store_io.data_fp_sel[i] = data_io[i].fp_sel_o;
`endif
        assign store_io.data_sqIdx[i] = data_io[i].sqIdx_o;
        assign store_io.dis_rob_idx[i] = dis_store_io.status[i].robIdx;
        assign store_io.dis_sq_idx[i] = mem_issue_bundle.sqIdx;
        assign store_io.data_size[i] = data_io[i].size_o;

        LoopCompare #(`ROB_WIDTH) cmp_addr_bigger (addr_io[i].robIdx_o, backendCtrl.redirectIdx, addr_bigger[i]);
        LoopCompare #(`ROB_WIDTH) cmp_data_bigger (data_io[i].robIdx_o, backendCtrl.redirectIdx, data_bigger[i]);
    end
endgenerate
    assign dis_store_io.full = (|full) | store_io.full;
    Sort #(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_SIZE), $clog2(`STORE_ISSUE_BANK_NUM)) sort_order (bankNum, originOrder, sortOrder); 
    assign store_io.dis_en = dis_store_io.en;
    assign store_io.dis_stall = dis_store_io.full;
    always_ff @(posedge clk)begin
        order <= sortOrder;
    end
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_NUM; i++)begin
        always_ff @(posedge clk)begin
            addr_en_next[i] <= addr_io[i].reg_en;
            data_en_next[i] <= data_io[i].reg_en;
            store_io.en[i] <= addr_en_next[i] & (~backendCtrl.redirect | addr_bigger[i]) & store_reg_io.ready[i];
            store_io.data_en[i] <= data_en_next[i] & (~backendCtrl.redirect | data_bigger[i]) & store_reg_io.ready[`STORE_ISSUE_BANK_NUM+i];
        end
    end
endgenerate
endmodule

interface StoreAddrBankIO;
    logic en;
    IssueStatusBundle status;
    MemIssueBundle data;
    logic reg_en;
    logic `N(`PREG_WIDTH) rs1;
    logic full;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)+1) bankNum;
    logic `N(`STORE_ISSUE_BANK_WIDTH) issue_idx;
    StoreIssueData data_o;
    RobIdx robIdx_o;
    logic exception_o;
    ReplyRequest reply;
    logic success;
    logic `N(`STORE_ISSUE_BANK_WIDTH) success_idx;
    logic tlb_en;
    logic tlb_exception;
    logic tlb_error;
    logic `N(`STORE_ISSUE_BANK_WIDTH) tlb_bank_idx;

    modport bank(input en, status, data, reply, success, success_idx, tlb_en, tlb_exception, tlb_error, tlb_bank_idx, output full, reg_en, rs1, bankNum, data_o, robIdx_o, exception_o, issue_idx);
endinterface

module StoreAddrBank(
    input logic clk,
    input logic rst,
    StoreAddrBankIO.bank io,
    input WakeupBus wakeupBus,
    input BackendCtrl backendCtrl
);
    typedef struct packed {
        logic rs1v;
        logic `N(`PREG_WIDTH) rs1;
        RobIdx robIdx;
    } StatusBundle;

    logic `N(`STORE_ISSUE_BANK_SIZE) en, issue, exception, tlbmiss;
    StatusBundle `N(`STORE_ISSUE_BANK_SIZE) status_ram;
    logic `N(`STORE_ISSUE_BANK_SIZE) free_en, tlbmiss_valid;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) freeIdx;
    logic `N(`STORE_ISSUE_BANK_SIZE) ready;
    logic `N(`STORE_ISSUE_BANK_SIZE) select_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) selectIdx, selectIdxNext;
    StoreIssueData data_o;
    logic `ARRAY(`STORE_ISSUE_BANK_SIZE, `INT_WAKEUP_PORT) rs1_cmp;
    logic [1: 0] size;
    RobIdx select_robIdx;

    assign size = io.data.memop == `MEM_SW ? 2'b10 :
                  io.data.memop == `MEM_SH ? 2'b01 : 2'b00;
    SDPRAM #(
        .WIDTH($bits(StoreIssueData)),
        .DEPTH(`STORE_ISSUE_BANK_SIZE)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdxNext),
        .we(io.en),
        .wdata({io.data.uext, size, io.data.imm, io.data.sqIdx, io.data.lqIdx, io.status.robIdx, io.data.fsqInfo}),
        .rdata1(data_o),
        .ready()
    );

generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs1v & ~issue[i];
    end
endgenerate
    DirectionSelector #(`STORE_ISSUE_BANK_SIZE) selector (
        .clk(clk),
        .rst(rst),
        .en(io.en),
        .idx(free_en),
        .ready(ready),
        .select(select_en)
    );
    assign io.full = &en;
    assign io.reg_en = (|ready) & ~backendCtrl.redirect;
    assign io.rs1 = status_ram[selectIdx].rs1;
    always_ff @(posedge clk)begin
        select_robIdx <= status_ram[selectIdx].robIdx;
    end
    assign io.robIdx_o = select_robIdx;
    PSelector #(`STORE_ISSUE_BANK_SIZE) selector_free_idx (~en, free_en);
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_free_idx (free_en, freeIdx);
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(`STORE_ISSUE_BANK_SIZE)) adder_bankNum(en, io.bankNum);
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        for(genvar j=0; j<`INT_WAKEUP_PORT; j++)begin
            assign rs1_cmp[i][j] = wakeupBus.en[j] & wakeupBus.we[j] & (wakeupBus.rd[j] == status_ram[i].rs1);
        end
    end
endgenerate
    // walk
    logic `N(`STORE_ISSUE_BANK_SIZE) bigger, walk_en;
    assign walk_en = en & bigger;
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        assign bigger[i] = (status_ram[i].robIdx.dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > status_ram[i].robIdx.idx);
        assign tlbmiss_valid[i] = io.reply.en && (io.reply.reason == 2'b11) & reply_decode[i];
    end
endgenerate

    logic `N(`STORE_ISSUE_BANK_SIZE) success_idx_decode;
    Decoder #(`STORE_ISSUE_BANK_SIZE) decoder_success_idx (io.success_idx, success_idx_decode);

    logic `N(`STORE_ISSUE_BANK_SIZE) selectIdx_decode, reply_decode, replyslow_decode, tlbbank_decode;
    Decoder #(`STORE_ISSUE_BANK_SIZE) decoder_select_idx (selectIdx, selectIdx_decode);
    Decoder #(`STORE_ISSUE_BANK_SIZE) decoder_reply (io.reply.issue_idx, reply_decode);
    Decoder #(`STORE_ISSUE_BANK_SIZE) decoder_tlbbank (io.tlb_bank_idx, tlbbank_decode);

    always_ff @(posedge clk)begin
        selectIdxNext <= selectIdx;
        io.issue_idx <= selectIdxNext;
        io.exception_o <= exception[selectIdxNext];
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
            io.data_o <= 0;
            issue <= 0;
            exception <= 0;
            tlbmiss <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en &
                      ~({`STORE_ISSUE_BANK_SIZE{io.success}} & success_idx_decode);
            end
            else begin
                en <= (en | ({`STORE_ISSUE_BANK_SIZE{io.en}} & free_en)) &
                      ~({`STORE_ISSUE_BANK_SIZE{io.success}} & success_idx_decode);
            end
            
            if(io.en)begin
                status_ram[freeIdx].rs1v <= io.status.rs1v;
                status_ram[freeIdx].rs1 <= io.status.rs1;
                status_ram[freeIdx].robIdx <= io.status.robIdx;
                exception[freeIdx] <= 1'b0;
            end

            for(int i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
                issue[i] <= ((issue[i] & ~(backendCtrl.redirect & (tlbmiss[i] | tlbmiss_valid[i]))) |
                            (((|ready) & ~backendCtrl.redirect) & selectIdx_decode[i])) &
                            ~(io.reply.en & (io.reply.reason != 2'b11) & reply_decode[i]) &
                            ~(io.tlb_en & tlbbank_decode[i]) &
                            ~(io.en & free_en[i]);
                tlbmiss[i] <= (tlbmiss[i] | tlbmiss_valid[i]) &
                              ~(io.tlb_en & tlbbank_decode[i]) & ~backendCtrl.redirect;
                              
            end

            if((|ready) & ~backendCtrl.redirect)begin
                issue[selectIdx] <= 1'b1;
            end

            if(io.reply.en && (io.reply.reason != 2'b11))begin
                issue[io.reply.issue_idx] <= 1'b0;
            end

            if(io.tlb_en)begin
                issue[io.tlb_bank_idx] <= 1'b0;
            end

            if(io.tlb_en & io.tlb_exception)begin
                exception[io.tlb_bank_idx] <= 1'b1;
            end

            for(int i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
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

interface StoreDataBankIO;
    logic en;
    IssueStatusBundle status;
    MemIssueBundle data;
    logic reg_en;
`ifdef RVF
    logic fp_reg_en;
    logic fp_sel_o;
`endif
    logic reg_ready;
    logic `N(`PREG_WIDTH) rs2;
    StoreIdx sqIdx_o;
    logic full;
    RobIdx robIdx_o;
    logic [1: 0] size_o;

    modport bank(input en, status, data, output reg_en, reg_ready, rs2, sqIdx_o, full, robIdx_o, size_o
`ifdef RVF
    ,output fp_reg_en, fp_sel_o
`endif
    );
endinterface

module StoreDataBank(
    input logic clk,
    input logic rst,
    StoreDataBankIO.bank io,
    input WakeupBus int_wakeupBus,
`ifdef RVF
    input WakeupBus fp_wakeupBus,
`endif
    input BackendCtrl backendCtrl
);
    typedef struct packed {
`ifdef RVF
        logic frs2_sel;
`endif
        logic rs2v;
        logic `N(`PREG_WIDTH) rs2;
        RobIdx robIdx;
    } StatusBundle;

    logic `N(`STORE_ISSUE_BANK_SIZE) en;
    StoreIdx sqIdxs `N(`STORE_ISSUE_BANK_SIZE);
    logic [1: 0] sqSize `N(`STORE_ISSUE_BANK_SIZE);
    StatusBundle `N(`STORE_ISSUE_BANK_SIZE) status_ram;
    logic `N(`STORE_ISSUE_BANK_SIZE) free_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) freeIdx;
    logic `N(`STORE_ISSUE_BANK_SIZE) ready;
    logic `N(`STORE_ISSUE_BANK_SIZE) select_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) selectIdx, selectIdxNext;
    logic `ARRAY(`STORE_ISSUE_BANK_SIZE, `INT_WAKEUP_PORT) int_rs2_cmp;
`ifdef RVF
    logic `ARRAY(`STORE_ISSUE_BANK_SIZE, `FP_WAKEUP_PORT) fp_rs2_cmp;
    logic fp_sel;
`endif
    logic `N(`STORE_ISSUE_BANK_SIZE) rs2_cmp;
    logic [1: 0] size;
    RobIdx select_robIdx;

    assign size = io.data.memop == `MEM_SW ? 2'b10 :
                  io.data.memop == `MEM_SH ? 2'b01 : 2'b00;
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs2v;
    end
endgenerate
    DirectionSelector #(`STORE_ISSUE_BANK_SIZE) selector (
        .clk(clk),
        .rst(rst),
        .en(io.en),
        .idx(free_en),
        .ready(ready),
        .select(select_en)
    );
    assign io.full = &en;
`ifdef RVF
    assign io.reg_en = (|(ready)) & ~backendCtrl.redirect;
    assign io.fp_reg_en = status_ram[selectIdx].frs2_sel;
`else
    assign io.reg_en = (|ready) & ~backendCtrl.redirect;
`endif
    assign io.rs2 = status_ram[selectIdx].rs2;
    always_ff @(posedge clk)begin
        select_robIdx <= status_ram[selectIdx].robIdx;
    end
    assign io.robIdx_o = select_robIdx;
    PSelector #(`STORE_ISSUE_BANK_SIZE) selector_free_idx (~en, free_en);
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_free_idx (free_en, freeIdx);
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_select_idx (select_en, selectIdx);
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        for(genvar j=0; j<`INT_WAKEUP_PORT; j++)begin
            assign int_rs2_cmp[i][j] = int_wakeupBus.en[j] & int_wakeupBus.we[j] & (int_wakeupBus.rd[j] == status_ram[i].rs2);
        end
`ifdef RVF
        for(genvar j=0; j<`FP_WAKEUP_PORT; j++)begin
            assign fp_rs2_cmp[i][j] = fp_wakeupBus.en[j] & fp_wakeupBus.we[j] & (fp_wakeupBus.rd[j] == status_ram[i].rs2);
        end
        assign rs2_cmp[i] = status_ram[i].frs2_sel ? |fp_rs2_cmp[i] : |int_rs2_cmp[i];
`else
        assign rs2_cmp[i] = |int_rs2_cmp[i];
`endif
    end
endgenerate

    // walk
    logic `N(`STORE_ISSUE_BANK_SIZE) bigger, walk_en;
    assign walk_en = en & bigger;
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        assign bigger[i] = (status_ram[i].robIdx.dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > status_ram[i].robIdx.idx);
    end
endgenerate

    always_ff @(posedge clk)begin
        if(io.en)begin
            sqIdxs[freeIdx] <= io.data.sqIdx;
            sqSize[freeIdx] <= size;
        end
        selectIdxNext <= selectIdx;
        io.sqIdx_o <= sqIdxs[selectIdxNext];
        io.size_o <= sqSize[selectIdxNext];
`ifdef RVF
        fp_sel <= io.fp_reg_en;
        io.fp_sel_o <= fp_sel;
`endif
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en;
            end
            else begin
                en <= (en | ({`STORE_ISSUE_BANK_SIZE{io.en}} & free_en)) &
                      ~(select_en & {`STORE_ISSUE_BANK_SIZE{io.reg_ready}});
            end
            
            if(io.en)begin
`ifdef RVF
                status_ram[freeIdx].frs2_sel <= io.status.frs2_sel;
`endif
                status_ram[freeIdx].rs2v <= io.status.rs2v;
                status_ram[freeIdx].rs2 <= io.status.rs2;
                status_ram[freeIdx].robIdx <= io.status.robIdx;
            end

            for(int i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
                if(io.en && free_en[i])begin
                    status_ram[i].rs2v <= io.status.rs2v;
                end
                else begin
                    status_ram[i].rs2v <= (status_ram[i].rs2v | (rs2_cmp[i]));
                end
            end
            
        end
    end
endmodule