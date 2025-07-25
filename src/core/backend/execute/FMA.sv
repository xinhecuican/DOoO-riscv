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
`ifdef RVD
            .db(issue_fma_io.bundle[i].db),
`endif
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
        assign fma_wb_io.datas[i].irq_enable = 1;
    end
endgenerate

endmodule

module FMASlice (
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    input logic en,
`ifdef RVD
    input logic db,
`endif
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
    localparam int unsigned FXL = FP32_EXP_BITS + FP32_MAN_BITS + 1;
    localparam int unsigned FP64_EXP_BITS = exp_bits(FP64);
    localparam int unsigned FP64_MAN_BITS = man_bits(FP64);
    localparam int unsigned DXL = FP64_EXP_BITS + FP64_MAN_BITS + 1;
    logic mul_en_s2, mul_en_s3;
    logic madd_en_s2, madd_en_s3, madd_en_s4;
    logic mul_sub_s2, mul_sub_s3, mul_sub_s4;
    logic redirect_s1, redirect_s2, redirect_s3, redirect_s4, add_redirect_s2;
    logic `N(`XLEN) rs3_data_s2, rs3_data_s3, rs3_data_s4;
    logic add_en_s2;
    ExStatusBundle ex_status_s2, ex_status_s3, ex_status_s4, add_ex_status_s2;
    FMulInfo mulInfo, info_fma, mulInfo_w;
`ifdef RVD
    logic db_s2, db_s3, db_s4, db_s5;
    FMulInfo mulInfo_l;
`endif

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
    end

    localparam WITH_MUL = 0;
    logic `N(FP32_MAN_BITS+1) raw_mant_a_w, raw_mant_b_w;
    assign raw_mant_a_w = {|rs1_data[FXL-2 -: FP32_EXP_BITS], rs1_data[0 +: FP32_MAN_BITS]};
    assign raw_mant_b_w = {|rs2_data[FXL-2 -: FP32_EXP_BITS], rs2_data[0 +: FP32_MAN_BITS]};
`ifdef RVD
    logic `N(FP64_MAN_BITS*2+2) mant_res;
    logic `N(FP64_MAN_BITS+1) raw_mant_a, raw_mant_b;
    assign raw_mant_a = db ? {|rs1_data[DXL-2 -: FP64_EXP_BITS], rs1_data[0 +: FP64_MAN_BITS]} : raw_mant_a_w;
    assign raw_mant_b = db ? {|rs2_data[DXL-2 -: FP64_EXP_BITS], rs2_data[0 +: FP64_MAN_BITS]} : raw_mant_b_w;
generate
    if(!WITH_MUL)begin
        FMantMul #(FP64_MAN_BITS+1) mul (clk, raw_mant_a, raw_mant_b, mant_res);
    end
endgenerate
    
`else
    logic `N(FP32_MAN_BITS*2+2) mant_res;
generate
    if(!WITH_MUL)begin
        FMantMul #(FP32_MAN_BITS+1) mul (clk, raw_mant_a_w, raw_mant_b_w, mant_res);
    end
endgenerate
`endif

    logic `N(`XLEN) mul_res;
    logic `N(FXL) mul_wres;
    logic `N(FP32_EXP_BITS+FP32_MAN_BITS*2+2) toadd_wres;
    FFlags mul_status, mul_wstatus;
    FMul #(FP32, WITH_MUL) fmul (
        .clk,
        .rst,
        .round_mode,
        .rs1_data(rs1_data[FXL-1: 0]),
        .rs2_data(rs2_data[FXL-1: 0]),
        .mul_res(mant_res[FP32_MAN_BITS*2+1: 0]),
        .fltop,
        .mulInfo(mulInfo_w),
        .toadd_res(toadd_wres),
        .res(mul_wres),
        .status(mul_wstatus)
    );

`ifdef RVD
    logic `N(`XLEN) mul_lres;
    logic `N(FP64_EXP_BITS+FP64_MAN_BITS*2+2) toadd_lres, toadd_res_n;
    FFlags mul_lstatus;
    FMul #(FP64, WITH_MUL) fmul_l (
        .*,
        .mul_res(mant_res),
        .mulInfo(mulInfo_l),
        .toadd_res(toadd_lres),
        .res(mul_lres),
        .status(mul_lstatus)
    );

    always_ff @(posedge clk)begin
        db_s2 <= db;
        db_s3 <= db_s2;
        db_s4 <= db_s3;
        db_s5 <= madd_en_s4 ? db_s4: db;
        toadd_res_n <= db_s3 ? toadd_lres : toadd_wres;
        info_fma <= db_s3 ? mulInfo_l : mulInfo_w;
    end
    assign mul_res = db_s3 ? mul_lres : {{`XLEN-FXL{1'b1}}, mul_wres[FXL-1: 0]};
    assign mul_status = db_s3 ? mul_lstatus : mul_wstatus;
`else
    logic `N(FP32_EXP_BITS+FP32_MAN_BITS*2+2) toadd_res_n;
    always_ff @(posedge clk)begin
        info_fma <= mulInfo_w;
        toadd_res_n <= toadd_wres;
    end
    assign mul_res = {{`XLEN-FXL{1'b1}}, mul_wres[FXL-1: 0]};
    assign mul_status = mul_wstatus;
`endif

    logic `N(FP32_EXP_BITS+FP32_MAN_BITS*2+2) add_rs1, add_rs2;
    logic add_sub;
    logic add_fma;
    logic `N(`XLEN) add_res;
    logic `N(FP32_MAN_BITS*2+FP32_EXP_BITS+2) add_wres;
    FFlags add_status, add_wstatus;

    assign add_fma = madd_en_s4;
    assign add_rs1 = madd_en_s4 ? toadd_res_n[FP32_EXP_BITS+FP32_MAN_BITS*2+1: 0] : {rs1_data, {FP32_MAN_BITS+1{1'b0}}};
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
        .res(add_wres),
        .status(add_wstatus)
    );

`ifdef RVD
    logic `N(FP64_EXP_BITS+FP64_MAN_BITS*2+2) add_lrs1, add_lrs2;
    logic `N(FP64_EXP_BITS+FP64_MAN_BITS*2+2) add_lres;
    FFlags add_lstatus;
    
    assign add_lrs1 = madd_en_s4 ? toadd_res_n : {rs1_data, {FP64_MAN_BITS+1{1'b0}}};
    assign add_lrs2 = madd_en_s4 ? {rs3_data_s4, {FP64_MAN_BITS+1{1'b0}}} : {rs2_data, {FP64_MAN_BITS+1{1'b0}}}; 
    FAdd #(FP64_EXP_BITS, FP64_MAN_BITS*2+1, FP64_MAN_BITS) fadd_l (
        .*,
        .rs1_data(add_lrs1),
        .rs2_data(add_lrs2),
        .sub(add_sub),
        .fma(add_fma),
        .res(add_lres),
        .status(add_lstatus)
    );
    assign add_res = db_s5 ? add_lres[DXL-1: 0] : {{`XLEN-FXL{1'b1}}, add_wres[FXL-1: 0]};
    assign add_status = db_s5 ? add_lstatus : add_wstatus;
`else
    assign add_res = {{`XLEN-FXL{1'b1}}, add_wres[FXL-1: 0]};
    assign add_status = add_wstatus;
`endif

    assign wakeup_en = mul_en_s2 | madd_en_s4 | 
                       (en & ~mul_en_s2 & (fltop == `FLT_ADD) | (fltop == `FLT_SUB));
    assign wakeup_rd = mul_en_s2 ? ex_status_s2.rd :
                       madd_en_s4 ? ex_status_s4.rd : ex_status.rd;

    assign en_o = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) | add_en_s2 & ~(backendCtrl.redirect & add_redirect_s2);
    assign res = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) ? mul_res : add_res;
    assign ex_status_o = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) ? ex_status_s3 : add_ex_status_s2;
    assign status = mul_en_s3 & ~(backendCtrl.redirect & redirect_s3) ? mul_status : add_status;

endmodule