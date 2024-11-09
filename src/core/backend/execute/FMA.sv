`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"
module FMAUnit(
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    IssueFMAIO.fma issue_fma_io,
    IssueWakeupIO.issue fma_wakeup_io,
    WriteBackIO.fu fma_wb_io,
    input BackendCtrl backendCtrl
);

generate
    for(genvar i=0; i<`FMA_SIZE; i++)begin
        logic `N(`XLEN) res;
        FFlags status;
        logic en_o;
        ExStatusBundle ex_status;
        FMASlice slice (
            .clk,
            .rst,
            .round_mode(issue_fma_io.bundle[i].rm == 3'b111 ? round_mode : issue_fma_io.bundle[i].rm),
            .en(issue_fma_io.en[i]),
            .rs1_data(issue_fma_io.rs1_data[i]),
            .rs2_data(issue_fma_io.rs2_data[i]),
            .rs3_data(issue_fma_io.rs3_data[i]),
            .ex_status(issue_fma_io.status[i]),
            .fltop(issue_fma_io.bundle[i].fltop),
            .backendCtrl,
            .wakeup_en(fma_wakeup_io.en[i]),
            .wakeup_rd(fma_wakeup_io.rd[i]),
            .en_o,
            .res,
            .status,
            .ex_status_o(ex_status)
        );
        assign fma_wakeup_io.we[i] = 1'b1;
        assign fma_wb_io.datas[i].en = en_o;
        assign fma_wb_io.datas[i].we = 1'b1;
        assign fma_wb_io.datas[i].rd = ex_status.rd;
        assign fma_wb_io.datas[i].robIdx = ex_status.robIdx;
        assign fma_wb_io.datas[i].res = res;
        assign fma_wb_io.datas[i].exccode = status;
    end
endgenerate

endmodule

module FMASlice (
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    input logic en,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`XLEN) rs3_data,
    ExStatusBundle ex_status,
    input logic `N(`FLTOP_WIDTH) fltop,
    input BackendCtrl backendCtrl,
    output logic wakeup_en,
    output logic `N(`PREG_WIDTH) wakeup_rd,
    output logic en_o,
    output logic `N(`XLEN) res,
    output ExStatusBundle ex_status_o,
    output FFlags status
);
    localparam int unsigned FP32_EXP_BITS = exp_bits(FP32);
    localparam int unsigned FP32_MAN_BITS = man_bits(FP32);
    logic mul_en_s2, mul_en_s3;
    logic madd_en_s2, madd_en_s3, madd_en_s4;
    logic mul_sub_s2, mul_sub_s3, mul_sub_s4;
    logic redirect_s1, redirect_s2, redirect_s3, redirect_s4, add_redirect_s2;
    logic `N(`XLEN) rs3_data_s2, rs3_data_s3, rs3_data_s4;
    logic add_en_s2;
    ExStatusBundle ex_status_s2, ex_status_s3, ex_status_s4, add_ex_status_s2;
    FMulInfo mulInfo, info_fma;

    LoopCompare #(`ROB_WIDTH) cmp_redirect_s1 (backendCtrl.redirectIdx, ex_status.robIdx, redirect_s1);
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s2 (backendCtrl.redirectIdx, ex_status_s2.robIdx, redirect_s2);
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s3 (backendCtrl.redirectIdx, ex_status_s3.robIdx, redirect_s3);
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s4 (backendCtrl.redirectIdx, ex_status_s4.robIdx, redirect_s4);
    LoopCompare #(`ROB_WIDTH) cmp_add_redirect (backendCtrl.redirectIdx, add_ex_status_s2.robIdx, add_redirect_s2);
    always_ff @(posedge clk)begin
        ex_status_s2 <= ex_status;
        ex_status_s3 <= ex_status_s2;
        ex_status_s4 <= ex_status_s3;
        rs3_data_s2 <= rs3_data;
        rs3_data_s3 <= rs3_data_s2;
        rs3_data_s4 <= rs3_data_s3;
        mul_sub_s2 <= fltop == `FLT_NMADD || fltop == `FLT_MSUB;
        mul_sub_s3 <= mul_sub_s2;
        mul_sub_s4 <= mul_sub_s3;
        madd_en_s2 <= en & ~(backendCtrl.redirect & redirect_s1) & (fltop == `FLT_MADD) | (fltop == `FLT_MSUB) | (fltop == `FLT_NMSUB) |
                    (fltop == `FLT_NMADD);
        madd_en_s3 <= madd_en_s2 & ~(backendCtrl.redirect & redirect_s2);
        madd_en_s4 <= madd_en_s3 & ~(backendCtrl.redirect & redirect_s3);
        mul_en_s2 <= en & ~(backendCtrl.redirect & redirect_s1) & (fltop == `FLT_MUL);
        mul_en_s3 <= mul_en_s2 & ~(backendCtrl.redirect & redirect_s2);
        add_en_s2 <= madd_en_s4 & ~(backendCtrl.redirect & redirect_s4) | (en & ~mul_en_s2 & ~(backendCtrl.redirect & redirect_s1) & (fltop == `FLT_ADD) | (fltop == `FLT_SUB));
        add_ex_status_s2 <= madd_en_s4 ? ex_status_s4 : ex_status;

        info_fma <= mulInfo;
    end


    logic `N(`XLEN) mul_res;
    logic `N(FP32_EXP_BITS+FP32_MAN_BITS*2+2) toadd_res, toadd_res_n;
    FFlags mul_status;
    FMul #(FP32) fmul (
        .clk,
        .rst,
        .round_mode,
        .rs1_data,
        .rs2_data,
        .fltop,
        .mulInfo,
        .toadd_res(toadd_res),
        .res(mul_res),
        .status(mul_status)
    );

    always_ff @(posedge clk)begin
        toadd_res_n <= toadd_res;
    end

    logic `N(FP32_EXP_BITS+FP32_MAN_BITS*2+2) add_rs1, add_rs2;
    logic add_sub;
    logic add_fma;
    logic `N(`XLEN) add_res;
    FFlags add_status;

    assign add_fma = madd_en_s4;
    assign add_rs1 = madd_en_s4 ? toadd_res_n : {rs1_data, {FP32_MAN_BITS+1{1'b0}}};
    assign add_rs2 = madd_en_s4 ? {rs3_data_s4, {FP32_MAN_BITS+1{1'b0}}} : {rs2_data, {FP32_MAN_BITS+1{1'b0}}};
    assign add_sub = madd_en_s4 ? mul_sub_s4 : fltop == `FLT_SUB;
    FAdd #(FP32_EXP_BITS, FP32_MAN_BITS*2+1, FP32_MAN_BITS) fadd (
        .clk,
        .rst,
        .round_mode,
        .rs1_data(add_rs1),
        .rs2_data(add_rs2),
        .sub(add_sub),
        .fma(add_fma),
        .info_fma(info_fma),
        .res(add_res),
        .status(add_status)
    );

    assign wakeup_en = mul_en_s2 | madd_en_s4 | 
                       (en & ~mul_en_s2 & (fltop == `FLT_ADD) | (fltop == `FLT_SUB));
    assign wakeup_rd = mul_en_s2 ? ex_status_s2.rd :
                       madd_en_s4 ? ex_status_s4.rd : ex_status.rd;

    assign en_o = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) | add_en_s2 & ~(backendCtrl.redirect & add_redirect_s2);
    assign res = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) ? mul_res : add_res;
    assign ex_status_o = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) ? ex_status_s3 : add_ex_status_s2;
    assign status = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) ? mul_status : add_status;

endmodule