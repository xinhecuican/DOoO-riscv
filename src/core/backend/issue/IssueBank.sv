`include "../../../defines/defines.svh"

interface IssueBankIO #(
    parameter DATA_WIDTH = 1,
    parameter SRC_NUM = 2,
    parameter DEPTH=8,
    parameter TYPE_SIZE=0,
    parameter TYPE_WIDTH=TYPE_SIZE==0?1:TYPE_SIZE
);
    logic en;
    logic `N(TYPE_WIDTH) type_i;
    IssueStatusBundle status;
    logic `N(DATA_WIDTH) data;
    logic full;
    logic `N($clog2(DEPTH)+1) bankNum;
    logic reg_en;
    logic ready;
    logic `N($clog2(DEPTH)) freeIdx;
    logic `N($clog2(DEPTH)) selectIdx;
    logic we;
    logic `ARRAY(SRC_NUM, `PREG_WIDTH) src;
    logic `N(`PREG_WIDTH) rd;
    ExStatusBundle status_o;
    logic `N(DATA_WIDTH) data_o;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(TYPE_WIDTH) type_ready;
    logic `N(TYPE_WIDTH) type_o;

    modport bank(input en, status, data, ready, type_i, type_ready, output full, bankNum, reg_en, freeIdx, selectIdx, src, we, rd, status_o, data_o, fsqIdx, type_o);
endinterface

module IssueBank #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH = 8,
    parameter SRC_NUM=2,
    parameter WAKEUP_PORT_NUM=8,
    parameter FSQV = 0,
    parameter TYPE_SIZE=0,
    parameter TYPE_WIDTH=TYPE_SIZE==0?1:TYPE_SIZE,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    IssueBankIO.bank io,
    WakeupBus.in wakeupBus,
    input BackendCtrl backendCtrl
);
    logic `N(DEPTH) en;
    logic `N(DEPTH) we;
    logic `ARRAY(SRC_NUM, DEPTH) srcv;
    logic `TENSOR(SRC_NUM, DEPTH, `PREG_WIDTH) src;
    logic `ARRAY(TYPE_WIDTH, DEPTH) src_type;
    logic `N(`PREG_WIDTH) rd `N(DEPTH);
    RobIdx robIdx `N(DEPTH);
    logic `N(DEPTH) free_en;
    logic `N(ADDR_WIDTH) freeIdx;
    logic `N(DEPTH) ready;
    logic `N(DEPTH) type_ready, src_ready;
    logic `N(DEPTH) select_en;
    logic `N(ADDR_WIDTH) selectIdx, selectIdxNext;
    logic `N(DATA_WIDTH) data_o;
    logic `TENSOR(SRC_NUM, DEPTH, WAKEUP_PORT_NUM) src_cmp;

    SDPRAM #(
        .WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdx),
        .we(io.en),
        .wdata(io.data),
        .rdata1(data_o),
        .ready()
    );

    DirectionSelector #(DEPTH) selector (
        .clk(clk),
        .rst(rst),
        .en(io.en),
        .idx(free_en),
        .ready(ready),
        .select(select_en)
    );

    assign ready = en & src_ready & type_ready;
    assign io.full = &en;
    assign io.reg_en = |ready & ~backendCtrl.redirect;
    assign io.we = we[selectIdx];
    assign io.rd = rd[selectIdx];
    assign io.selectIdx = selectIdx;
    assign io.freeIdx = freeIdx;
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
    ParallelAND #(DEPTH, SRC_NUM) and_src (srcv, src_ready);
generate
    for(genvar i=0; i<SRC_NUM; i++)begin
        for(genvar j=0; j<DEPTH; j++)begin
            for(genvar k=0; k<WAKEUP_PORT_NUM; k++)begin
                assign src_cmp[i][j][k] = wakeupBus.en[k] & wakeupBus.we[k] & (wakeupBus.rd[k] == src[i][j]);
            end
        end
    end
endgenerate

generate
    if(TYPE_SIZE <= 0)begin
        assign type_ready = {DEPTH{1'b1}};
    end
    else begin
        logic `ARRAY(TYPE_SIZE, DEPTH) type_readys;
        for(genvar i=0; i<TYPE_SIZE; i++)begin
            assign type_readys[i] = {DEPTH{io.type_ready[i]}} & src_type[i];
            assign io.type_o[i] = src_type[i][selectIdx];
        end
        ParallelOR #(DEPTH, TYPE_SIZE) or_type_ready (type_readys, type_ready);

        always_ff @(posedge clk)begin
            if(io.en)begin
                for(int i=0; i<TYPE_SIZE; i++)begin
                    src_type[i][freeIdx] <= io.type_i[i];
                end
            end
        end
    end
endgenerate

    // redirect
    logic `N(DEPTH) bigger, walk_en;
    assign walk_en = en & bigger;

`define ISSUE_BANK_SRC_DEF(id) \
    always_ff @(posedge clk)begin \
        if(io.en)begin \
            src[``id``-1][freeIdx] <= io.status.rs``id``; \
        end \
    end \
    assign io.src[``id``-1] = src[``id``-1][selectIdx]; \
    always_ff @(posedge clk, negedge rst)begin \
        if(rst == `RST)begin \
            srcv[``id``-1] <= 0; \
        end \
        else begin \
            for(int i=0; i<DEPTH; i++)begin \
                if(io.en & free_en[i])begin \
                    srcv[``id``-1][i] <= io.status.rs``id``v; \
                end else begin \
                    srcv[``id``-1][i] <= (srcv[``id``-1][i] | (|src_cmp[``id``-1][i])); \
                end \
            end \
        end \
    end

generate
    for(genvar i=0; i<DEPTH; i++)begin
        assign bigger[i] = (robIdx[i].dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > robIdx[i].idx);
    end
    if(SRC_NUM > 0)begin
        `ISSUE_BANK_SRC_DEF(1)
    end
    if(SRC_NUM > 1)begin
        `ISSUE_BANK_SRC_DEF(2)
    end
    if(SRC_NUM > 2)begin
        `ISSUE_BANK_SRC_DEF(3)
    end
endgenerate

    always_ff @(posedge clk)begin
        selectIdxNext <= selectIdx;
        io.status_o.we <= io.we;
        io.status_o.rd <= io.rd;
        io.status_o.robIdx <= robIdx[selectIdx];
        if(io.en)begin
            robIdx[freeIdx] <= io.status.robIdx;
            rd[freeIdx] <= io.status.rd;
        end
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
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
                we[freeIdx] <= io.status.we;
            end
            io.data_o <= data_o;
        end
    end
endmodule