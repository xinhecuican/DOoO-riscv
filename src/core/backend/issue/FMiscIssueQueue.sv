`include "../../../defines/defines.svh"

module FMiscIssueQueue (
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_fmisc_io,
    IssueRegIO.issue fmisc_reg_io,
    IssueFMiscIO.issue issue_fmisc_io,
    WakeupBus.in int_wakeupBus,
    WakeupBus.in fp_wakeupBus,
    input BackendCtrl backendCtrl
);
    localparam BANK_SIZE = `FMISC_ISSUE_SIZE / `FMISC_SIZE;
    localparam BANK_NUM = `FMISC_SIZE;
    logic `N(BANK_NUM) full, fsel, fsel_n, fsel_n2;
    logic `ARRAY(BANK_NUM, $clog2(BANK_NUM)) order;
    logic `ARRAY(BANK_NUM, $clog2(BANK_SIZE)+1) bankNum;
    logic `N(BANK_NUM) enNext, bigger, reg_en, en_o, bigger_s2, reg_ready;
    ExStatusBundle `N(BANK_NUM) bank_status, status_o;
    FMiscIssueBundle `N(BANK_NUM) bank_bundle, bundle_o;
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        logic `N(`PREG_WIDTH) rs1, rs2, rd;

        assign reg_ready[i] = fsel[i] & fmisc_reg_io.ready[i] | ~fsel[i] & fmisc_reg_io.ready[`FMISC_SIZE+i];
        FMiscIssueBank issue_bank (
            .clk,
            .rst,
            .bank_en(dis_fmisc_io.en[order[i]] & ~dis_fmisc_io.full),
            .status(dis_fmisc_io.status[order[i]]),
            .bundle(dis_fmisc_io.data[order[i]]),
            .int_wakeupBus,
            .fp_wakeupBus,
            .fsel(fsel[i]),
            .reg_ready(reg_ready[i]),
            .stall(issue_fmisc_io.stall[i] & en_o[i]),
            .issue_end(en_o[i] & ~issue_fmisc_io.stall[i]),
            .reg_en(reg_en[i]),
            .bankNum(bankNum[i]),
            .rs1_o(rs1),
            .rs2_o(rs2),
            .rd_o(rd),
            .full(full[i]),
            .status_o(bank_status[i]),
            .bundle_o(bank_bundle[i]),
            .backendCtrl
        );
        assign fmisc_reg_io.en[i] = reg_en[i] & fsel[i];
        assign fmisc_reg_io.en[i+BANK_NUM] = reg_en[i] & ~fsel[i];
        assign fmisc_reg_io.preg[i] = rs1;
        assign fmisc_reg_io.preg[i+BANK_NUM] = rs2;
        assign fmisc_reg_io.preg[i+BANK_NUM*2] = rs1;

        LoopCompare #(`ROB_WIDTH) cmp_bigger (bank_status[i].robIdx, backendCtrl.redirectIdx, bigger[i]);
        LoopCompare #(`ROB_WIDTH) cmp_bigger_s2 (status_o[i].robIdx, backendCtrl.redirectIdx, bigger_s2[i]);
    end
endgenerate
    assign dis_fmisc_io.full = |full;
    OrderSelector #(BANK_NUM, BANK_SIZE) order_selector (.*);
generate
    for(genvar i=0; i<BANK_NUM; i++)begin
        always_ff @(posedge clk)begin
            enNext[i] <= reg_en[i] & reg_ready[i];
            en_o[i] <= enNext[i] & (~backendCtrl.redirect | bigger[i]);
            fsel_n[i] <= fsel[i];
            fsel_n2[i] <= fsel_n[i];
            status_o[i] <= bank_status[i];
            bundle_o[i] <= bank_bundle[i];
            if(~issue_fmisc_io.stall[i])begin
                issue_fmisc_io.en[i] <= en_o[i] & (~backendCtrl.redirect | bigger_s2[i]);
                issue_fmisc_io.rs1_data[i] <= fsel_n2[i] ? fmisc_reg_io.data[i] : fmisc_reg_io.data[i+`FMISC_SIZE*2];
                issue_fmisc_io.rs2_data[i] <= fmisc_reg_io.data[i+`FMISC_SIZE];
                issue_fmisc_io.status[i] <= status_o[i];
                issue_fmisc_io.bundle[i] <= bundle_o[i];
            end
        end
    end
endgenerate
endmodule

module FMiscIssueBank #(
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    input logic bank_en,
    input IssueStatusBundle status,
    input FMiscIssueBundle bundle,
    WakeupBus.in int_wakeupBus,
    WakeupBus.in fp_wakeupBus,
    input logic reg_ready,
    input logic issue_end,
    input logic stall,
    input BackendCtrl backendCtrl,

    output logic reg_en,
    output logic fsel,
    output logic `N($clog2(DEPTH)+1) bankNum,
    output logic `N(`PREG_WIDTH) rs1_o,
    output logic `N(`PREG_WIDTH) rs2_o,
    output logic `N(`PREG_WIDTH) rd_o,
    output FMiscIssueBundle bundle_o,
    output ExStatusBundle status_o,
    output logic full
);

    logic `N(DEPTH) en;
    logic `N(DEPTH) we;
    logic `N(DEPTH) rs1v, rs2v, frs1_sel;
    logic `N(`PREG_WIDTH) rs1 `N(DEPTH);
    logic `N(`PREG_WIDTH) rs2 `N(DEPTH);
    logic `N(`PREG_WIDTH) rd `N(DEPTH);
    RobIdx robIdx `N(DEPTH);
    logic `N(DEPTH) free_en, ready, issue, select_en, select_en_n, select_en_n2;
    logic `N(ADDR_WIDTH) freeIdx;
    logic `ARRAY(DEPTH, `INT_WAKEUP_PORT) rs1_int_cmp;
    logic `ARRAY(DEPTH, `FP_WAKEUP_PORT) rs1_fp_cmp, rs2_fp_cmp;
    logic `N(DEPTH) rs1_cmp, rs2_cmp;
    logic `N(ADDR_WIDTH) selectIdx, selectIdxNext, selectIdxN3;

    SDPRAM #(
        .WIDTH($bits(FMiscIssueBundle)),
        .DEPTH(DEPTH),
        .READ_LATENCY(1)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(1'b0),
        .en(1'b1),
        .addr0(freeIdx),
        .addr1(selectIdx),
        .we(bank_en),
        .wdata(bundle),
        .rdata1(bundle_o),
        .ready()
    );

generate
    for(genvar i=0; i<DEPTH; i++)begin
        for(genvar j=0; j<`INT_WAKEUP_PORT; j++)begin
            assign rs1_int_cmp[i][j] = int_wakeupBus.en[j] & int_wakeupBus.we[j] & (int_wakeupBus.rd[j] == rs1[i]);
        end
    end
    for(genvar i=0; i<DEPTH; i++)begin
        for(genvar j=0; j<`FP_WAKEUP_PORT; j++)begin
            assign rs1_fp_cmp[i][j] = fp_wakeupBus.en[j] & fp_wakeupBus.we[j] & (fp_wakeupBus.rd[j] == rs1[i]);
            assign rs2_fp_cmp[i][j] = fp_wakeupBus.en[j] & fp_wakeupBus.we[j] & (fp_wakeupBus.rd[j] == rs2[i]);
        end
        assign rs1_cmp[i] = frs1_sel[i] ? |rs1_fp_cmp[i] : |rs1_int_cmp[i];
        assign rs2_cmp[i] = |rs2_fp_cmp[i];
        assign ready[i] = en[i] & rs1v[i] & rs2v[i] & ~issue[i];
    end
endgenerate
    DirectionSelector #(DEPTH) selector (
        .clk(clk),
        .rst(rst),
        .en(bank_en),
        .idx(free_en),
        .ready(ready),
        .select(select_en)
    );
    PSelector #(DEPTH) selector_free_idx (~en, free_en);
    Encoder #(DEPTH) encoder_free_idx (free_en, freeIdx);
    Encoder #(DEPTH) encoder_select_idx (select_en, selectIdx);
    ParallelAdder #(.DEPTH(DEPTH)) adder_bankNum(en, bankNum);
    assign full = &en;
    assign reg_en = |ready & ~backendCtrl.redirect;
    assign rs1_o = rs1[selectIdx];
    assign rs2_o = rs2[selectIdx];
    assign fsel = frs1_sel[selectIdx];

    // redirect
    logic `N(DEPTH) bigger, walk_en;
    assign walk_en = en & bigger;
generate
    for(genvar i=0; i<DEPTH; i++)begin
        assign bigger[i] = (robIdx[i].dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > robIdx[i].idx);
    end
endgenerate

    always_ff @(posedge clk)begin
        status_o.we <= we[selectIdx];
        status_o.rd <= rd[selectIdx];
        status_o.robIdx <= robIdx[selectIdx];
        select_en_n <= select_en;
        select_en_n2 <= select_en_n;
        selectIdxNext <= selectIdx;
        selectIdxN3 <= selectIdxNext;
        if(bank_en)begin
            rs1[freeIdx] <= status.rs1;
            rs2[freeIdx] <= status.rs2;
            rd[freeIdx] <= status.rd;
            robIdx[freeIdx] <= status.robIdx;
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            we <= 0;
            rs1v <= 0;
            rs2v <= 0;
            issue <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                en <= walk_en & ~(select_en_n & {{DEPTH{issue_end}}});
            end
            else begin
                en <= (en | ({DEPTH{bank_en}} & free_en)) &
                      ~(select_en_n2 & {{DEPTH{issue_end}}});
            end

            if(bank_en)begin
                we[freeIdx] <= status.we;
                frs1_sel[freeIdx] <= status.frs1_sel;
                issue[freeIdx] <= 1'b0;
            end

            if(reg_en & reg_ready)begin
                issue[selectIdx] <= 1'b1;
            end
            if(stall)begin
                issue[selectIdxN3] <= 1'b0;
            end

            for(int i=0; i<DEPTH; i++)begin
                if(bank_en & free_en[i])begin
                    rs1v[i] <= status.rs1v;
                    rs2v[i] <= status.rs2v | ~status.frs2_sel;
                end
                else begin
                    rs1v[i] <= (rs1v[i] | (rs1_cmp[i]));
                    rs2v[i] <= (rs2v[i] | (rs2_cmp[i]));
                end
            end
        end
    end

endmodule