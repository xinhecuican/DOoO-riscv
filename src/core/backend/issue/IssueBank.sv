`include "../../../defines/defines.svh"

interface IssueBankIO #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH=8
);
    logic en;
    IssueStatusBundle status;
    logic `N(DATA_WIDTH) data;
    logic full;
    logic `N($clog2(DEPTH)+1) bankNum;
    logic reg_en;
    logic ready;
    logic we;
    logic `N(`PREG_WIDTH) rs1, rs2, rd;
    ExStatusBundle status_o;
    logic `N(DATA_WIDTH) data_o;
    logic `N(`FSQ_WIDTH) fsqIdx;

    modport bank(input en, status, data, ready, output full, bankNum, reg_en, rs1, rs2, we, rd, status_o, data_o, fsqIdx);
endinterface

module IssueBank #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH = 8,
    parameter RS2V = 1,
    parameter FSQV = 0,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    IssueBankIO.bank io,
    WakeupBus wakeupBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);
    logic `N(DEPTH) en;
    logic `N(DEPTH) we;
    logic `N(DEPTH) rs1v;
    logic `N(`PREG_WIDTH) rs1 `N(DEPTH);
    logic `N(`PREG_WIDTH) rd `N(DEPTH);
    RobIdx robIdx `N(DEPTH);
    logic `N(DEPTH) free_en;
    logic `N(ADDR_WIDTH) freeIdx;
    logic `N(DEPTH) ready;
    logic `N(DEPTH) select_en;
    logic `N(ADDR_WIDTH) selectIdx, selectIdxNext;
    logic `N(DATA_WIDTH) data_o;
    logic `ARRAY(DEPTH, `WB_SIZE) rs1_cmp;

    SDPRAM #(
        .WIDTH(DATA_WIDTH),
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
    if(RS2V)begin
        logic `N(DEPTH) rs2v;
        logic `N(`PREG_WIDTH) rs2 `N(DEPTH);
        logic `ARRAY(DEPTH, `WB_SIZE) rs2_cmp;
        for(genvar i=0; i<DEPTH; i++)begin
            assign ready[i] = en[i] & rs1v[i] & rs2v[i];
            for(genvar j=0; j<`WB_SIZE; j++)begin
                assign rs2_cmp[i][j] = wakeupBus.en[j] & wakeupBus.we[j] & (wakeupBus.rd[j] == rs2[i]);
            end
        end
        assign io.rs2 = rs2[selectIdx];
        always_ff @(posedge clk or posedge rst)begin
            if(rst == `RST)begin
                rs2v <= 0;
            end
            else begin
                if(io.en)begin
                    rs2v[freeIdx] <= io.status.rs2v;
                    rs2[freeIdx] <= io.status.rs2;
                end
                for(int i=0; i<DEPTH; i++)begin
                    if(io.en && free_en[i])begin
                        rs2v[i] <= io.status.rs2v;
                    end
                    else begin
                        rs2v[i] <= rs2v[i] | (|rs2_cmp[i]);
                    end
                end
            end
        end
    end
    else begin
        for(genvar i=0; i<DEPTH; i++)begin
            assign ready[i] = en[i] & rs1v[i];
        end
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
    assign io.reg_en = |ready & ~backendCtrl.redirect;
    assign io.rs1 = rs1[selectIdx];
    assign io.we = we[selectIdx];
    assign io.rd = rd[selectIdx];
generate
    if(FSQV)begin
        FsqIdxInfo fsqInfo;
        assign fsqInfo = data_o[$bits(FsqIdxInfo)-1: 0];
        assign io.fsqIdx = fsqInfo.idx;
    end
endgenerate

    PSelector #(DEPTH) selector_free_idx (~en, free_en);
    Encoder #(DEPTH) encoder_free_idx (free_en, freeIdx);
    Encoder #(DEPTH) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(DEPTH)) adder_bankNum(en, io.bankNum);
generate
    for(genvar i=0; i<DEPTH; i++)begin
        for(genvar j=0; j<`WB_SIZE; j++)begin
            assign rs1_cmp[i][j] = wakeupBus.en[j] & wakeupBus.we[j] & (wakeupBus.rd[j] == rs1[i]);
        end
    end
endgenerate

    // redirect
    logic `N(DEPTH) bigger, walk_en;
    assign walk_en = en & bigger;
generate
    for(genvar i=0; i<DEPTH; i++)begin
        assign bigger[i] = (robIdx[i].dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > robIdx[i].idx);
    end
endgenerate

    always_ff @(posedge clk)begin
        selectIdxNext <= selectIdx;
        io.status_o.we <= io.we;
        io.status_o.rd <= io.rd;
        io.status_o.robIdx <= robIdx[selectIdx];
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            rs1v <= 0;
            en <= 0;
            io.data_o <= 0;
            we <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en;
            end
            else begin
                en <= (en | ({DEPTH{io.en}} & free_en)) &
                      ~(select_en & {{DEPTH{io.ready}}});
            end
            
            if(io.en)begin
                rs1v[freeIdx] <= io.status.rs1v;
                rs1[freeIdx] <= io.status.rs1;
                robIdx[freeIdx] <= io.status.robIdx;
                we[freeIdx] <= io.status.we;
                rd[freeIdx] <= io.status.rd;
            end

            for(int i=0; i<DEPTH; i++)begin
                if(io.en && free_en[i])begin
                    rs1v[i] <= io.status.rs1v;
                end
                else begin
                    rs1v[i] <= (rs1v[i] | (|rs1_cmp[i]));
                end
            end
            io.data_o <= data_o;
        end
    end
endmodule