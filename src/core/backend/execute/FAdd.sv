`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"
module FAdd #(
    parameter int unsigned EXP_BITS = 1,
    parameter int unsigned MAN_BITS = 1,
    parameter int unsigned OUT_MAN_BITS = 1,
    parameter int unsigned FP_BITS = EXP_BITS + MAN_BITS + 1
)(
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    input logic sub,
    input logic fma,
    input FMulInfo info_fma,
    input logic `N(FP_BITS) rs1_data,
    input logic `N(FP_BITS) rs2_data,
    output logic `N(`XLEN) res,
    output FFlags status
);
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [MAN_BITS-1:0] mant;
    } fp_t;

    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [OUT_MAN_BITS-1:0] mant;
    } fpo_t;

    FTypeInfo info_a, info_b;
    fp_t fp_a, fp_b_pre, fp_b;
    logic exp_mant_equal;
    assign fp_a = rs1_data;
    assign fp_b_pre = rs2_data;
    assign fp_b.sign = fp_b_pre.sign ^ sub;
    assign fp_b.exp = fp_b_pre.exp;
    assign fp_b.mant = fp_b_pre.mant;
    assign exp_mant_equal = fp_a.exp == fp_b.exp && fp_a.mant == fp_b.mant;
    fp_classifier #(EXP_BITS, MAN_BITS, 2) classifier (
        .operands_i ({rs2_data, rs1_data}),
        .is_boxed_i (2'b11),
        .info_o ({info_b, info_a})
    );

    logic exp_nz_a, exp_nz_b;

    assign exp_nz_a = |fp_a.exp;
    assign exp_nz_b = |fp_b.exp;

    logic `N(MAN_BITS+4) raw_mant_a, raw_mant_b;
    logic `N(EXP_BITS) raw_exp_a, raw_exp_b, nor_exp_a, nor_exp_b;
    assign raw_exp_a = fp_a.exp;
    assign raw_exp_b = fp_b.exp;
    assign nor_exp_a = fp_a.exp | {{EXP_BITS-1{1'b0}}, ~exp_nz_a};
    assign nor_exp_b = fp_b.exp | {{EXP_BITS-1{1'b0}}, ~exp_nz_b};
    assign raw_mant_a = {exp_nz_a, fp_a.mant, 3'b0};
    assign raw_mant_b = {exp_nz_b, fp_b.mant, 3'b0};

// align
    logic `N(EXP_BITS) shift_cnt, sub_ab, sub_ba, exp_diff;
    logic `N(MAN_BITS+4) shift_mant_a, shift_mant_b, sticky_mask;
    logic sticky_pre, exp_gt;
    assign sub_ab = nor_exp_a - nor_exp_b;
    assign sub_ba = nor_exp_b - nor_exp_a;
    assign exp_gt = raw_exp_a > raw_exp_b;
    assign exp_diff = exp_gt | fma & info_fma.is_ov ? sub_ab : sub_ba;
    assign sticky_mask = ((1 << exp_diff) - 1);
    assign sticky_pre = |((exp_gt ? raw_mant_b : raw_mant_a) & sticky_mask);
    assign shift_mant_a = exp_gt ? raw_mant_a : (raw_mant_a >> sub_ba) | {{MAN_BITS+3{1'b0}}, sticky_pre};
    assign shift_mant_b = exp_gt ? (raw_mant_b >> sub_ab) | {{MAN_BITS+3{1'b0}}, sticky_pre} : raw_mant_b;

// mant cal
    logic `N(MAN_BITS+5) mant_sum;
    logic `N(EXP_BITS) shift_exp;
    logic sign, shift_exp_z;
    FMulInfo info_fma_n;
    roundmode_e rm;
    always_ff @(posedge clk) begin
        shift_exp <= exp_gt | fma & info_fma.is_ov ? raw_exp_a : raw_exp_b;
        shift_exp_z <= raw_exp_a == 0 && raw_exp_b == 0;
        info_fma_n <= info_fma;
        rm <= round_mode;
        if(fp_a.sign ^ fp_b.sign)begin
            if(shift_mant_a > shift_mant_b | fma & info_fma.is_ov)begin
                mant_sum <= shift_mant_a - shift_mant_b;
                sign <= fp_a.sign;
            end
            else begin
                mant_sum <= shift_mant_b - shift_mant_a;
                // -a + a = +0
                // -0 + -0 = -0
                sign <= fp_b.sign & (~exp_mant_equal | fp_a.sign & fp_b.sign);
            end
        end
        else begin
            mant_sum <= shift_mant_a + shift_mant_b;
            sign <= fp_a.sign;
        end
    end

// normalization
    logic `N(OUT_MAN_BITS+2) align_mant;
    logic `N(OUT_MAN_BITS+5) mant_sum_c;
    logic `N(MAN_BITS+5) shift_mant;
    logic `N($clog2(OUT_MAN_BITS+1)) lpath_shamt, lpath_shamt_pre;
    logic `N(EXP_BITS+1) align_exp;
    logic lzc_empty;
    logic sticky_bit;

    assign mant_sum_c = mant_sum[MAN_BITS+4 : MAN_BITS-OUT_MAN_BITS];
    lzc #(OUT_MAN_BITS+1, 1) lzc_inst (mant_sum_c[OUT_MAN_BITS+3: 3], lpath_shamt_pre, lzc_empty);
    assign lpath_shamt = shift_exp < lpath_shamt_pre ? shift_exp : lpath_shamt_pre;
    assign shift_mant = mant_sum << lpath_shamt;
    assign sticky_bit = mant_sum_c[0] | (mant_sum_c[OUT_MAN_BITS+4] & mant_sum_c[2]) | 
                        ((lzc_empty | mant_sum_c[OUT_MAN_BITS+3] | mant_sum_c[OUT_MAN_BITS+4]) & mant_sum_c[1]) | (|mant_sum[MAN_BITS-OUT_MAN_BITS-1: 0]);
    always_comb begin 
        if(mant_sum_c[OUT_MAN_BITS+4])begin
            align_exp = shift_exp + 1;
            align_mant = {1'b1, mant_sum_c[OUT_MAN_BITS+3: 3]};
        end
        else if(shift_exp_z & mant_sum_c[OUT_MAN_BITS+3])begin
            align_exp = 1;
            align_mant = mant_sum_c[OUT_MAN_BITS+3: 2];
        end
        else if(!lzc_empty) begin
            align_exp = shift_exp < lpath_shamt ? 0 : shift_exp - lpath_shamt;
            align_mant = shift_mant[MAN_BITS+3: MAN_BITS-OUT_MAN_BITS+2];
        end
        else begin
          align_exp = 0;
          align_mant = mant_sum_c;
        end
    end

// rounding
    logic `N(OUT_MAN_BITS) round_mant;
    logic `N(EXP_BITS+1) round_exp;
    logic round_ix, round_cout, round_up;
    logic ov;
    fp_rounding #(OUT_MAN_BITS) rounding (
        align_mant[OUT_MAN_BITS: 1],
        align_mant[0],
        sticky_bit,
        sign,
        rm,
        round_mant,
        round_ix,
        round_cout,
        round_up
    );
    assign round_exp = align_exp + round_cout;
    assign ov = (shift_exp == ((1<<EXP_BITS)-2)) & (mant_sum_c[OUT_MAN_BITS+4] | round_cout) |
                fma & info_fma_n.is_ov;
    FFlags normal_status;
    always_comb begin
        normal_status = 0;
        normal_status.OF = ov;
        normal_status.UF = round_ix && (shift_exp_z & ((mant_sum_c[OUT_MAN_BITS+4: OUT_MAN_BITS+3] == 2'b00) & ~(mant_sum_c[OUT_MAN_BITS+2] & round_cout)));
        normal_status.NX = round_ix;
    end


    // ----------------------
    // Special case handling
    // ----------------------
    fpo_t                special_result, special_result_n;
    FFlags              special_status, special_status_n;
    logic               result_is_special, result_special_n;

    always_comb begin : special_cases
        // Default assignments
        special_result    = '{sign: 1'b0, exp: '1, mant: 2**(OUT_MAN_BITS-1)}; // canonical qNaN
        special_status    = '0;
        result_is_special = 1'b0;

        // Handle potentially mixed nan & infinity input => important for the case where infinity and
        // zero are multiplied and added to a qnan.
        // RISC-V mandates raising the NV exception in these cases:
        // (inf * 0) + c or (0 * inf) + c INVALID, no matter c (even quiet NaNs)
        if (fma && info_fma.is_invalid) begin
            result_is_special = 1'b1; // bypass FMA, output is the canonical qNaN
            special_status.NV = 1'b1; // invalid operation
        // NaN Inputs cause canonical quiet NaN at the output and maybe invalid OP
        end else if (~fma & info_a.is_nan | info_b.is_nan | fma & info_fma.is_nan) begin
            result_is_special = 1'b1;           // bypass FMA, output is the canonical qNaN
            special_status.NV = info_a.is_signalling | info_b.is_signalling | fma & info_fma.is_signalling; // raise the invalid operation flag if signalling
        // Special cases involving infinity
        end else if (~fma & info_a.is_inf | info_b.is_inf | fma & info_fma.is_inf) begin
            result_is_special = 1'b1; // bypass FMA
            // Effective addition of opposite infinities (±inf - ±inf) is invalid!
            if(~fma & info_a.is_inf & info_b.is_inf & (fp_a.sign ^ fp_b.sign) |
                fma & info_b.is_inf & info_fma.is_inf & (info_fma.sign ^ fp_b.sign))
                special_status.NV = 1'b1; // invalid operation
            // Handle cases where output will be inf because of inf product input
            else if (fma & info_fma.is_inf | ~fma & info_a.is_inf) begin
                // Result is infinity with the sign of the product
                special_result    = '{sign: fma ? info_fma.sign : fp_a.sign, exp: '1, mant: '0};
            // Handle cases where the addend is inf
            end else if (info_b.is_inf) begin
                // Result is inifinity with sign of the addend (= operand_c)
                special_result    = '{sign: fp_b.sign, exp: '1, mant: '0};
            end
        end
    end
    always_ff @(posedge clk)begin
        result_special_n <= result_is_special;
        special_status_n <= special_status;
        special_result_n <= special_result;
    end
    logic rmin;
    logic `N(EXP_BITS) ov_exp;
    logic `N(OUT_MAN_BITS) ov_mant;
    assign rmin = rm == RTZ || rm == RDN && !sign || rm == RUP && sign;
    assign ov_exp = rmin ? ((1<<EXP_BITS)-2) : ((1<<EXP_BITS)-1);
    assign ov_mant = rmin ? {OUT_MAN_BITS{1'b1}} : 0;

    assign res = result_special_n ? special_result_n : 
                 ov ? {sign, ov_exp, ov_mant} :
                 {sign, round_exp[EXP_BITS-1: 0], round_mant};
    assign status = result_special_n ? special_status_n : normal_status;

endmodule