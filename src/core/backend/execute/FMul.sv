`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"
`include "../../../defines/mult_define.svh"

module FMul #(
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt = 0,
    parameter int unsigned EXP_BITS = exp_bits(fp_fmt),
    parameter int unsigned MAN_BITS = man_bits(fp_fmt)
)(
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`FLTOP_WIDTH) fltop,
    output FMulInfo mulInfo,
    output logic `N(EXP_BITS+MAN_BITS*2+2) toadd_res,
    output logic `N(`XLEN) res,
    output FFlags status
);

    localparam int unsigned BIAS_SIZE = fp_bias(fp_fmt);
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [MAN_BITS-1:0] mant;
    } fp_t;

    FTypeInfo info_a, info_b;
    logic sub;
    fp_t fp_a, fp_b;
    assign sub = fltop == `FLT_NMADD || fltop == `FLT_NMSUB;
    assign fp_a = rs1_data;
    assign fp_b = rs2_data;
    fp_classifier #(EXP_BITS, MAN_BITS, 2) classifier (
        .operands_i ({rs2_data, rs1_data}),
        .is_boxed_i (2'b11),
        .info_o ({info_b, info_a})
    );

    logic exp_nz_a, exp_nz_b;

    assign exp_nz_a = |fp_a.exp;
    assign exp_nz_b = |fp_b.exp;

    logic `N(MAN_BITS+1) raw_mant_a, raw_mant_b, denormal_mant;
    logic `N(MAN_BITS+1) shift_mant_a, shift_mant_b;
    logic `N(EXP_BITS) raw_exp_a, raw_exp_b;
    logic `N(EXP_BITS+1) raw_exp_pre;
    logic `N($clog2(MAN_BITS+1)) lzc_cnt;
    assign raw_exp_a = fp_a.exp | {{EXP_BITS-1{1'b0}}, ~exp_nz_a};
    assign raw_exp_b = fp_b.exp | {{EXP_BITS-1{1'b0}}, ~exp_nz_b};
    assign raw_exp_pre = raw_exp_a + raw_exp_b;
    assign raw_mant_a = {exp_nz_a, fp_a.mant};
    assign raw_mant_b = {exp_nz_b, fp_b.mant};
    assign denormal_mant = ~exp_nz_a ? raw_mant_a : raw_mant_b;
    lzc #(MAN_BITS+1, 1) lzc_inst (denormal_mant, lzc_cnt, );
    assign shift_mant_a = ~exp_nz_a & exp_nz_b ? raw_mant_a << lzc_cnt : raw_mant_a;
    assign shift_mant_b = ~exp_nz_b & exp_nz_a ? raw_mant_b << lzc_cnt : raw_mant_b;

    logic `N(EXP_BITS+1) raw_exp;
    logic `N(MAN_BITS*2+2) raw_mant;
    logic sign;
    always_ff @(posedge clk)begin
        raw_exp <= raw_exp_pre > lzc_cnt ? raw_exp_pre - lzc_cnt : 0;
        sign <= fp_a.sign ^ fp_b.sign ^ sub;
    end

    logic `N(EXP_BITS) shr_cnt, shr_cnt_mod;
    logic `N(EXP_BITS+1) raw_exp_n;
    logic sign_n, need_shr, exp_z;
    always_ff @(posedge clk)begin
        shr_cnt <= BIAS_SIZE - (MAN_BITS+4) >= raw_exp ? MAN_BITS + 4 :
                   BIAS_SIZE >= raw_exp ? BIAS_SIZE + 1 - raw_exp : 0;
        need_shr <= BIAS_SIZE >= raw_exp;
        exp_z <= raw_exp == BIAS_SIZE;
        raw_exp_n <= raw_exp;
        sign_n <= sign;
    end

    FMantMul #(MAN_BITS+1) mul (clk, shift_mant_a, shift_mant_b, raw_mant);

    logic `N(EXP_BITS+1) shift_exp, shift_exp_normal;
    logic `N(MAN_BITS*2+2) shift_mant;
    assign shift_exp = raw_exp_n + raw_mant[MAN_BITS*2+1];
    assign shift_exp_normal = shift_exp < BIAS_SIZE ? 0 : shift_exp - BIAS_SIZE;
    assign shr_cnt_mod = shr_cnt + (~need_shr & raw_mant[MAN_BITS*2+1]);
    assign shift_mant = raw_mant >> shr_cnt_mod; 

    logic sticky, add_sticky;
    logic `N(MAN_BITS*2+2) sticky_mask, add_sticky_mask;
    logic `N(MAN_BITS*2+2) sticky_shift_mask;
    assign sticky_shift_mask = (1 << shr_cnt_mod) - 1;
    assign sticky_mask = {sticky_shift_mask[MAN_BITS+1: 0], {MAN_BITS{1'b1}}};
    assign sticky = |(raw_mant & sticky_mask);
    assign add_sticky_mask = sticky_shift_mask;
    assign add_sticky = |(raw_mant & add_sticky_mask);

    logic `N(MAN_BITS) round_out, round_mant;
    logic round_ix, round_cout, round_up;
    logic `N(EXP_BITS+1) round_exp;
    logic `N(EXP_BITS) round_exp_o;
    FFlags normal_status;
    roundmode_e rm_s2, rm_s3;
    always_ff @(posedge clk)begin
        rm_s2 <= round_mode;
        rm_s3 <= rm_s2;
    end
    fp_rounding #(MAN_BITS) rounding (
        shift_mant[MAN_BITS*2-1: MAN_BITS],
        shift_mant[MAN_BITS-1],
        sticky,
        sign_n,
        rm_s3,
        round_out,
        round_ix,
        round_cout,
        round_up
    );
    assign round_exp = shift_exp + round_cout;
    assign round_exp_o = round_exp < BIAS_SIZE ? 0 : 
        round_exp > BIAS_SIZE + (1 << EXP_BITS) - 2 ? {EXP_BITS{1'b1}} : round_exp - BIAS_SIZE;
    // if ov, return inf
    assign round_mant = {MAN_BITS{~(round_exp > BIAS_SIZE + (1 << EXP_BITS) - 2)}} & round_out;

    logic of, uf;
    assign normal_status.NV = 0;
    assign normal_status.DZ = 0;
    assign normal_status.OF = round_exp > BIAS_SIZE + (1 << EXP_BITS) - 2;
    assign normal_status.UF = round_ix & ((round_exp < BIAS_SIZE) |
                ((round_exp == BIAS_SIZE) & ~shift_mant[MAN_BITS*2+1] & ~shift_mant[MAN_BITS*2] & 
                ~(shift_mant[MAN_BITS*2-1] & round_cout)));
    assign normal_status.NX = round_ix;

    // ----------------------
    // Special case handling
    // ----------------------
    fp_t                special_result, special_result_n, special_result_o;
    FFlags              special_status, special_status_n, special_status_o;
    logic               result_is_special, result_special_n, result_special_o;
    logic               result_denormal, result_denormal_n, result_denormal_o;
    FMulInfo info_s2, info_s2_n;

    always_comb begin : special_cases
        special_result    = '{sign: 1'b0, exp: '1, mant: 2**(MAN_BITS-1)};
        special_status    = '0;
        result_is_special = 1'b0;
        result_denormal = 1'b0;

        if((info_a.is_inf && info_b.is_zero) || (info_a.is_zero && info_b.is_inf))begin
            result_is_special = 1'b1;
            special_status.NV = 1'b1;
        end else if (info_a.is_nan | info_b.is_nan) begin
            result_is_special = 1'b1;
            special_status.NV = info_a.is_signalling | info_b.is_signalling;
        end else if (info_a.is_inf | info_b.is_inf) begin
            result_is_special = 1'b1;
            special_result    = '{sign: fp_a.sign ^ fp_b.sign ^ sub, exp: '1, mant: '0};
        end else if(info_a.is_zero | info_b.is_zero) begin
            result_is_special = 1'b1;
            special_result = '{sign: fp_a.sign ^ fp_b.sign ^ sub, exp: 0, mant: 0};
        end else if(~exp_nz_a & ~exp_nz_b)begin
            result_is_special = 1'b1;
            result_denormal = 1'b1;
            special_result = '{sign: fp_a.sign ^ fp_b.sign ^ sub, exp: 0, mant: 0};
            special_status.NX = 1'b1;
            special_status.UF = 1'b1;
        end
    end

    always_ff @(posedge clk)begin
        special_result_n <= special_result;
        special_status_n <= special_status;
        result_special_n <= result_is_special;
        special_result_o <= special_result_n;
        special_status_o <= special_status_n;
        result_special_o <= result_special_n;
        result_denormal_n <= result_denormal;
        result_denormal_o <= result_denormal_n;
        info_s2.is_nan <= info_a.is_nan | info_b.is_nan;
        info_s2.is_signalling <= info_a.is_signalling | info_b.is_signalling;
        info_s2.is_inf <= info_a.is_inf | info_b.is_inf;
        info_s2.is_invalid <= (info_a.is_inf && info_b.is_zero) || (info_a.is_zero && info_b.is_inf);
        info_s2.sign <= fp_a.sign ^ fp_b.sign ^ sub;
        info_s2_n <= info_s2;
    end

    assign res = result_special_o ? special_result_o : {sign_n, round_exp_o, round_mant};
    assign status = result_special_o ? special_status_o : normal_status;
    assign toadd_res = result_denormal_o ? {sign_n, {EXP_BITS{1'b0}}, shift_mant[MAN_BITS*2-1: 0], add_sticky} :
            result_special_o ? {special_result_o, {MAN_BITS{1'b0}}, result_denormal_o} : 
            {sign_n, shift_exp_normal[EXP_BITS-1: 0], {shift_mant[MAN_BITS*2-1: 0], add_sticky}};
    assign mulInfo.is_nan = info_s2_n.is_nan;
    assign mulInfo.is_signalling = info_s2_n.is_signalling;
    assign mulInfo.is_inf = info_s2_n.is_inf;
    assign mulInfo.is_invalid = info_s2_n.is_invalid;
    assign mulInfo.is_ov = shift_exp > BIAS_SIZE + (1 << EXP_BITS) - 2;
    assign mulInfo.sign = info_s2_n.sign;

endmodule

module FMantMul #(
    parameter WIDTH=32
)(
    input logic clk,
    input logic `N(WIDTH) data1,
    input logic `N(WIDTH) data2,
    output logic `N(WIDTH*2) res
);
    localparam NUM = WIDTH + 2;
    localparam HNUM = (NUM / 2); // 13
    localparam HM = HNUM-1;
    logic `N(NUM) d1, d2;
    logic `N(NUM/2) n;
    logic `ARRAY(NUM*2, NUM/2) st0;

    assign d1 = {2'b0, data1};
    assign d2 = {2'b0, data2};

    booth_tree #(NUM) booth_tree_inst (.*);

    localparam S1 = HNUM / 3;
    localparam S1_REM = HNUM % 3;
    localparam S1_BASE = 0;
    localparam S1_ALL = (S1 * 2 + HNUM % 3); // 9
    `STA_NUM_DEF(1, 2) // 6
    `STA_NUM_DEF(2, 3) // 4
    `STA_NUM_DEF(3, 4) // 3
    `STA_NUM_DEF(4, 5) // 2

    logic `N(NUM/2) c0;
    assign c0 = n;
    `CSA_DEF(0, 1)
    `CSAN_DEF(1, 2)
    `CSA_DEF(2, 3)
    `CSA_DEF(3, 4)
    `CSA_DEF(4, 5)

    logic `ARRAY(2, NUM*2) transpose;
generate
    for(genvar i=0; i<2; i++)begin
        for(genvar j=0; j<NUM*2; j++)begin
`ifdef SV32
            assign transpose[i][j] = st5[j][i];
`endif
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        res <= transpose[0] + transpose[1] + c5[HNUM-2];
    end
endmodule