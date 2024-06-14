`include "../../../defines/defines.svh"

module IntIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_issue_io,
    IssueRegfileIO.issue int_reg_io,
    IntIssueExuIO.issue issue_exu_io,
    FsqBackendIO.backend fsq_back_io,
    WriteBackBus wbBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);

    localparam BANK_SIZE = `INT_ISSUE_SIZE / `ALU_SIZE;
    localparam BANK_NUM = `ALU_SIZE;
    IntBankIO #(BANK_SIZE) bank_io [BANK_NUM-1: 0]();
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) order;
    logic `ARRAY(BANK_NUM, $clog2(BANK_SIZE)) bankNum;
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) originOrder, sortOrder;
    logic `N(BANK_NUM) full;
    logic `N(BANK_NUM) enNext, redirectClear;
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        IntIssueBank #(BANK_SIZE) issue_bank (
            .clk(clk),
            .rst(rst),
            .io(bank_io[i]),
            .*
        );
        assign bankNum[i] = bank_io[i].bankNum;
        assign originOrder[i] = i;

        assign bank_io[i].en = dis_issue_io.en[order[i]] & ~dis_issue_io.full;
        assign bank_io[i].status = dis_issue_io.status[order[i]];
        assign bank_io[i].data = dis_issue_io.data[order[i]];
        assign full[i] = bank_io[i].full;

        assign int_reg_io.en[i] = bank_io[i].reg_en & ~backendCtrl.redirect;
        assign int_reg_io.en[BANK_NUM+i] = bank_io[i].reg_en & ~backendCtrl.redirect;
        assign int_reg_io.preg[i] = bank_io[i].rs1;
        assign int_reg_io.preg[BANK_NUM+i] = bank_io[i].rs2;
        assign fsq_back_io.fsqIdx[i] = bank_io[i].fsqIdx;

        assign redirectClear[i] = backendCtrl.redirect & ((bank_io[i].data_o.robIdx.dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx < bank_io[i].data_o.robIdx.dir));
    end
endgenerate
    assign dis_issue_io.full = |full;
    Sort #(BANK_NUM, $clog2(BANK_SIZE), $clog2(BANK_NUM)) sort_order (bankNum, originOrder, sortOrder); 
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        always_ff @(posedge clk)begin
            enNext[i] <= bank_io[i].reg_en & ~backendCtrl.redirect;
            issue_exu_io.bundle[i] <= bank_io[i].data_o;
            issue_exu_io.br_type[i] <= bank_io[i].br_type;
            issue_exu_io.ras_type[i] <= bank_io[i].ras_type;
        end
    end
endgenerate

    always_ff @(posedge clk)begin
        order <= sortOrder;
        issue_exu_io.en <= enNext & ~redirectClear;
        issue_exu_io.rs1_data <= int_reg_io.data[BANK_NUM-1: 0];
        issue_exu_io.rs2_data <= int_reg_io.data[BANK_NUM*2-1: BANK_NUM];
        issue_exu_io.streams <= fsq_back_io.streams;
        issue_exu_io.directions <= fsq_back_io.directions;
    end

endmodule

interface IntBankIO #(parameter DEPTH=8);
    logic en;
    IssueStatusBundle status;
    IntIssueBundle data;
    logic full;
    logic `N($clog2(DEPTH)+1) bankNum;
    logic reg_en;
    logic `N(`PREG_WIDTH) rs1, rs2;
    IntIssueBundle data_o;
    logic `N(`FSQ_WIDTH) fsqIdx;
    BranchType br_type;
    RasType ras_type;

    modport bank(input en, status, data, output full, bankNum, reg_en, rs1, rs2, data_o, fsqIdx, br_type, ras_type);
endinterface

module IntIssueBank #(
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    IntBankIO.bank io,
    WriteBackBus wbBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);
    logic `N(DEPTH) en;
    IssueStatusBundle `N(DEPTH) status_ram;
    logic `N(DEPTH) free_en;
    logic `N(ADDR_WIDTH) freeIdx;
    logic `N(DEPTH) ready;
    logic `N(DEPTH) select_en;
    logic `N(ADDR_WIDTH) selectIdx, selectIdxNext;
    IntIssueBundle data_o;
    logic `ARRAY(DEPTH, `WB_SIZE) rs1_cmp, rs2_cmp;

    SDPRAM #(
        .WIDTH($bits(IntIssueBundle)),
        .DEPTH(DEPTH)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdx),
        .we(io.en),
        .wdata(io.data),
        .rdata1(data_o)
    );

generate
    for(genvar i=0; i<DEPTH; i++)begin
        assign ready[i] = en[i] & status_ram[i].rs1v & status_ram[i].rs2v;
    end
endgenerate
    DirectionSelector #(DEPTH) selector (
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
    assign io.rs2 = status_ram[selectIdx].rs2;
    assign io.fsqIdx = data_o.fsqInfo.idx;
    PSelector #(DEPTH) selector_free_idx (~en, free_en);
    Encoder #(DEPTH) encoder_free_idx (free_en, freeIdx);
    Encoder #(DEPTH) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(DEPTH)) adder_bankNum(en, io.bankNum);
generate
    for(genvar i=0; i<DEPTH; i++)begin
        for(genvar j=0; j<`WB_SIZE; j++)begin
            assign rs1_cmp[i][j] = wbBus.en[j] & wbBus.we[j] & (wbBus.rd[j] == status_ram[i].rs1);
            assign rs2_cmp[i][j] = wbBus.en[j] & wbBus.we[j] & (wbBus.rd[j] == status_ram[i].rs2);
        end
    end
endgenerate

    // redirect
    logic `N(DEPTH) bigger, walk_en;
    assign walk_en = en & bigger;
generate
    for(genvar i=0; i<DEPTH; i++)begin
        assign bigger[i] = (status_ram[i].robIdx.dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > status_ram[i].robIdx.idx);
    end
endgenerate

    always_ff @(posedge clk)begin
        selectIdxNext <= selectIdx;
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
                en <= (en | ({DEPTH{io.en}} & free_en)) &
                      ~(select_en);
            end
            
            if(io.en)begin
                status_ram[freeIdx].rs1v <= io.status.rs1v;
                status_ram[freeIdx].rs2v <= io.status.rs2v;
                status_ram[freeIdx].rs1 <= io.status.rs1;
                status_ram[freeIdx].rs2 <= io.status.rs2;
                status_ram[freeIdx].robIdx <= io.status.robIdx;
            end

            for(int i=0; i<DEPTH; i++)begin
                if(io.en && free_en[i])begin
                    status_ram[i].rs1v <= io.status.rs1v;
                    status_ram[i].rs2v <= io.status.rs2v;
                end
                else begin
                    status_ram[i].rs1v <= (status_ram[i].rs1v | (|rs1_cmp[i]));
                    status_ram[i].rs2v <= status_ram[i].rs2v | (|rs2_cmp[i]);
                end
            end
            io.data_o <= data_o;
        end
    end

    // br type & ras type
    logic push, pop;
    logic `N(`PREG_WIDTH) rd, rs;
    logic `N(`BRANCHOP_WIDTH) op;
    assign rd = io.data_o.rd;
    assign rs = status_ram[selectIdxNext].rs1;
    assign op = io.data_o.branchop;
    assign push = rd == 5'h1 || rd == 5'h5;
    assign pop = rs == 5'h1 || rs == 5'h5;
    always_comb begin
        case({push, pop})
        2'b00: io.ras_type = NONE;
        2'b01: io.ras_type = POP;
        2'b10: io.ras_type = PUSH;
        2'b11: io.ras_type = POP_PUSH;
        endcase
        if(op == `BRANCH_JAL)begin
            io.br_type = DIRECT;
        end
        else if(op == `BRANCH_JALR)begin
            if(push | pop)begin
                io.br_type = CALL;
            end
            else begin
                io.br_type = INDIRECT;
            end
        end
        else begin
            io.br_type = CONDITION;
        end
    end
endmodule