`include "../../../defines/defines.svh"

interface StoreUnitIO;
    logic `N(`STORE_ISSUE_BANK_NUM) en;
    StoreIssueData `N(`STORE_ISSUE_BANK_NUM) storeIssueData;
    logic `N(`STORE_DIS_PORT) dis_en;
    logic `N(`STORE_ISSUE_BANK_NUM) data_en;
    StoreIdx `N(`STORE_ISSUE_BANK_NUM) data_sqIdx;

    modport store (output en, storeIssueData, dis_en, data_en, data_sqIdx);
    modport queue (input data_en, dis_en, data_sqIdx);
endinterface

module StoreIssueQueue(
    input logic clk,
    input logic rst,
    input StoreIdx `N(`STORE_PIPELINE) sqIdx,
    input LoadIdx `N(`STORE_PIPELINE) lqIdx,
    DisIssueIO.issue dis_store_io,
    IssueRegfileIO.issue store_reg_io,
    WriteBackBus wbBus,
    StoreUnitIO.store store_io
);
    StoreAddrBankIO addr_io [`STORE_ISSUE_BANK_NUM-1: 0]();
    StoreDataBankIO data_io [`STORE_ISSUE_BANK_NUM-1: 0]();
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_NUM)) order;
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_SIZE)) bankNum;
    logic `ARRAY(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_NUM)) originOrder, sortOrder;
    logic `N(`STORE_ISSUE_BANK_NUM) full;
    StoreIdx `N(`STORE_ISSUE_BANK_NUM) sqIdxs;
    logic `N($clog2(`STORE_DIS_PORT)+1) disNum;
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_NUM; i++)begin
        StoreAddrBank addr_bank (
            .*,
            .io(addr_io[i])
        );
        assign bankNum[i] = addr_io[i].bankNum;
        assign originOrder[i] = i;

        assign addr_io[i].en = dis_store_io.en[order[i]] & ~dis_store_io.full;
        assign addr_io[i].status = dis_store_io.status[order[i]];
        assign addr_io[i].data = dis_store_io.data[order[i]];
        assign addr_io[i].sqIdx = sqIdx[order[i]];
        assign addr_io[i].lqIdx = lqIdx[order[i]];
        assign full[i] = dis_store_io.en[order[i]] & addr_io[i].full;
        
        assign store_reg_io.en[i] = addr_io[i].reg_en & ~backendCtrl.redirect;
        assign store_reg_io.preg[i] = addr_io[i].rs1;
        assign store_io.storeIssueData[i] = addr_io[i].data_o;

        assign data_io[i].en = addr_io[i].en;
        assign data_io[i].status = addr_io[i].status;
        assign data_io[i].free_en = addr_io[i].free_en;
        assign data_io[i].freeIdx = addr_io[i].freeIdx;
        assign data_io[i].sqIdx = addr_io[i].sqIdx;
        
        assign store_reg_io.en[`STORE_ISSUE_BANK_NUM+i] = data_io[i].reg_en & ~backendCtrl.redirect;
        assign store_reg_io.preg[`STORE_ISSUE_BANK_NUM+i] = data_io[i].rs2;
        assign store_io.data_sqIdx[i] = data_io[i].sqIdx_o;
    end
endgenerate
    assign dis_store_io.full = |full;
    Sort #(`STORE_ISSUE_BANK_NUM, $clog2(`STORE_ISSUE_BANK_SIZE), $clog2(`STORE_ISSUE_BANK_NUM)) sort_order (bankNum, originOrder, sortOrder); 
    assign store_io.dis_en = full ? 0 : dis_store_io.en;
    always_ff @(posedge clk)begin
        order <= sortOrder;
        store_io.en <= store_reg_io.en[`STORE_ISSUE_BANK_NUM-1: 0];
        store_io.data_en <= store_reg_io.en[`STORE_ISSUE_BANK_NUM * 2 -1: `STORE_ISSUE_BANK_NUM];
    end
endmodule

interface StoreAddrBankIO;
    logic en;
    IssueStatusBundle status;
    MemIssueBundle data;
    logic `N(`STORE_ISSUE_BANK_SIZE) free_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) freeIdx;
    StoreIdx sqIdx;
    LoadIdx lqIdx;
    logic reg_en;
    logic `N(`PREG_WIDTH) rs1;
    logic full;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)+1) bankNum;
    StoreIssueData data_o;

    modport bank(input en, status, data, sqIdx, output full, free_en, freeIdx, reg_en, rs1, bankNum, data_o);
endinterface

module StoreAddrBank(
    input logic clk,
    input logic rst,
    StoreIssueBankIO.bank io
);
    typedef struct packed {
        logic rs1v;
        logic `N(`PREG_WIDTH) rs1;
        RobIdx robIdx;
    } StatusBundle;

    logic `N(`STORE_ISSUE_BANK_SIZE) en;
    StatusBundle `N(`STORE_ISSUE_BANK_SIZE) status_ram;
    logic `N(`STORE_ISSUE_BANK_SIZE) free_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) freeIdx;
    logic `N(`STORE_ISSUE_BANK_SIZE) ready;
    logic `N(`STORE_ISSUE_BANK_SIZE) select_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) selectIdx, selectIdxNext;
    StoreIssueData data_o;
    logic `ARRAY(`STORE_ISSUE_BANK_SIZE, `WB_SIZE) rs1_cmp;
    logic [1: 0] size;

    assign size = io.data.memop == `MEM_LW ? 2'b10 :
                  io.data.memop == `MEM_LH ? 2'b01 : 2'b00;
    SDPRAM #(
        .WIDTH($bits(StoreIssueData)),
        .DEPTH(`STORE_ISSUE_BANK_SIZE)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdx),
        .we(io.en),
        .wdata({io.data.sext, size, io.data.imm, io.sqIdx, io.lqIdx, io.data.robIdx, io.data.fsqInfo}),
        .rdata1(data_o)
    );

generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs1v;
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
    assign io.reg_en = |ready;
    assign io.rs1 = status_ram[selectIdx].rs1;
    assign io.free_en = free_en;
    assign io.freeIdx = freeIdx;
    PSelector #(`STORE_ISSUE_BANK_SIZE) selector_free_idx (~en, free_en);
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_free_idx (free_en, freeIdx);
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(`STORE_ISSUE_BANK_SIZE)) adder_bankNum(en, io.bankNum);
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        for(genvar j=0; j<`WB_SIZE; j++)begin
            assign rs1_cmp[i][j] = wbBus.en[j] & wbBus.we[j] & (wbBus.rd[j] == status_ram[i].rs1);
        end
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
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
            io.data_o <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en;
            end
            else begin
                en <= (en | ({`STORE_ISSUE_BANK_SIZE{io.en}} & free_en)) &
                      ~(select_en);
            end
            
            if(io.en)begin
                status_ram[freeIdx].rs1v <= io.status.rs1v;
                status_ram[freeIdx].rs1 <= io.status.rs1;
                status_ram[freeIdx].robIdx <= io.status.robIdx;
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
    logic `N(`STORE_ISSUE_BANK_SIZE) free_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) freeIdx;
    StoreIdx sqIdx;
    logic reg_en;
    logic `N(`PREG_WIDTH) rs2;
    StoreIdx sqIdx_o;

    modport bank(input en, status, sqIdx, free_en, freeIdx, output reg_en, rs2, sqIdx_o);
endinterface

module StoreDataBank(
    input logic clk,
    input logic rst,
    StoreIssueBankIO.bank io
);
    typedef struct packed {
        logic rs2v;
        logic `N(`PREG_WIDTH) rs2;
        RobIdx robIdx;
    } StatusBundle;

    logic `N(`STORE_ISSUE_BANK_SIZE) en;
    StoreIdx sqIdxs `N(`STORE_ISSUE_BANK_SIZE);
    StatusBundle `N(`STORE_ISSUE_BANK_SIZE) status_ram;
    logic `N(`STORE_ISSUE_BANK_SIZE) ready;
    logic `N(`STORE_ISSUE_BANK_SIZE) select_en;
    logic `N($clog2(`STORE_ISSUE_BANK_SIZE)) selectIdx, selectIdxNext;
    logic `ARRAY(`STORE_ISSUE_BANK_SIZE, `WB_SIZE) rs2_cmp;

generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs2v;
    end
endgenerate
    DirectionSelector #(`STORE_ISSUE_BANK_SIZE) selector (
        .clk(clk),
        .rst(rst),
        .en(io.en),
        .idx(io.free_en),
        .ready(ready),
        .select(select_en)
    );
    assign io.reg_en = |ready;
    assign io.rs2 = status_ram[selectIdx].rs2;
    Encoder #(`STORE_ISSUE_BANK_SIZE) encoder_select_idx (select_en, selectIdx);
generate
    for(genvar i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
        for(genvar j=0; j<`WB_SIZE; j++)begin
            assign rs2_cmp[i][j] = wbBus.en[j] & wbBus.we[j] & (wbBus.rd[j] == status_ram[i].rs2);
        end
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
            sqIdxs[io.freeIdx] <= io.sqIdx;
        end
        io.sqIdx_o <= sqIdxs[selectIdx];
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en;
            end
            else begin
                en <= (en | ({`STORE_ISSUE_BANK_SIZE{io.en}} & io.free_en)) &
                      ~(select_en);
            end
            
            if(io.en)begin
                status_ram[io.freeIdx].rs2v <= io.status.rs2v;
                status_ram[io.freeIdx].rs2 <= io.status.rs2;
                status_ram[io.freeIdx].robIdx <= io.status.robIdx;
            end

            for(int i=0; i<`STORE_ISSUE_BANK_SIZE; i++)begin
                if(io.en && io.free_en[i])begin
                    status_ram[i].rs2v <= io.status.rs2v;
                end
                else begin
                    status_ram[i].rs2v <= (status_ram[i].rs2v | (|rs2_cmp[i]));
                end
            end
            
        end
    end
endmodule