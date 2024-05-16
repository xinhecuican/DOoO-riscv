`include "../../../defines/defines.svh"

module IntIssueQueue(
    input logic clk,
    input logic rst,
    DisIntIssueIO.issue dis_issue_io,
    IssueRegfileIO.issue int_reg_io,
    IssueAluIO.issue issue_alu_io,
    FsqBackendIO.backend fsq_back_io
);

    localparam BANK_SIZE = `INT_ISSUE_SIZE / `ALU_SIZE;
    localparam BANK_NUM = `ALU_SIZE;
    IntBankIO #(BANK_SIZE) bank_io `N(BANK_NUM);
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) order;
    logic `ARRAY(BANK_NUM, $clog2(BANK_SIZE)) bankNum;
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) originOrder, sortOrder;
    logic `N(BANK_NUM) full;
    logic `N(BANK_NUM) enNext;
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        IntIssueBank #(BANK_SIZE) issue_bank (
            .clk(clk),
            .rst(rst),
            .io(bank_io[i])
        );
        assign bankNum[i] = bank_io[i].bankNum;
        assign originOrder[i] = i;

        assign bank_io[i].en = dis_issue_io.en[order[i]] & ~dis_issue_io.full;
        assign bank_io[i].status = dis_issue_io.status[order[i]];
        assign bank_io[i].data = dis_issue_io.data[order[i]];
        assign full[i] = dis_issue_io.en[order[i]] & bank_io[i].full;

        assign int_reg_io.en[i] = bank_io[i].reg_en;
        assign int_reg_io.rs1[i] = bank_io[i].rs1;
        assign int_reg_io.rs2[i] = bank_io[i].rs2;
        assign fsq_back_io.fsqIdx[i] = bank_io[i].fsqIdx;
    end
endgenerate
    assign dis_issue_io.full = |full;
    Sort #(BANK_NUM, $clog2(BANK_SIZE)+1, $clog2(BANK_NUM)) sort_order (bankNUm, originOrder, sortOrder); 
    always_ff @(posedge clk)begin
        order <= sortOrder;
        for(int i=0; i<BANK_NUM; i++)begin
            enNext[i] <= bank_io[i].reg_en;
        end
        issue_alu_io.en <= enNext;
        issue_alu_io.rs1_data <= int_reg_io.rs1_data;
        issue_alu_io.rs2_data <= int_reg_io.rs2_data;
        for(int i=0; i<BANK_NUM; i++)begin
            issue_alu_io.bundle[i] <= bank_io[i].data_o;
        end
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
    logic stall;
    IntIssueBundle data_o;
    logic `N(`FSQ_WIDTH) fsqIdx;

    modport bank(input en, status, data, stall, output full, bankNum, reg_en, rs1, rs2, data_o, fsqIdx);
endinterface

module IntIssueBank #(
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    IntBankIO.bank io
);
    logic `N(DEPTH) en;
    IssueStatusBundle `N(DEPTH) status_ram;
    logic `N(DEPTH) free_en;
    logic `N(ADDR_WIDTH) freeIdx;
    logic `N(DEPTH) ready;
    logic `N(DEPTH) select_en;
    logic `N(ADDR_WIDTH) selectIdx, selectIdxNext;
    IntIssueBundle data_o;

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
        assign ready[i] = en[i] & status_ram[i].rs1v & status_ram[i].sr2v;
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

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            status_ram <= 0;
            en <= 0;
            io.data_o <= 0;
        end
        else begin
            en <= (en | ({DEPTH{io.en}} & free_en));
            if(io.en)begin
                status_ram[freeIdx] <= io.status;
            end

            for(int i=0; i<DEPTH; i++)begin
                status_ram[i].rs1v <= status_ram[i].rs1v;
                status_ram[i].rs2v <= status_ram[i].rs2v;
            end
            io.data_o <= data_o;
        end
    end
endmodule