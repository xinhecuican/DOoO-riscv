`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"
module FAdd #(
    parameter fp_format_e fp_fmt = 0
)(
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    input logic sub,
    input logic fma,
    input FMulInfo info_fma,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    output logic `N(`XLEN) res,
    output FFlags status
);
    localparam int unsigned EXP_BITS = exp_bits(fp_fmt);
    localparam int unsigned MAN_BITS = man_bits(fp_fmt);
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [MAN_BITS-1:0] mant;
    } fp_t;

    FTypeInfo info_a, info_b;
    fp_t fp_a, fp_b_pre, fp_b;
    assign fp_a = rs1_data;
    assign fp_b_pre = rs2_data;
    assign fp_b.sign = fp_b_pre.sign ^ sub;
    assign fp_b.exp = fp_b_pre.exp;
    assign fp_b.mant = fp_b_pre.mant;
    fp_classifier #(fp_fmt, 2) classifier (
        .operands_i ({rs2_data, rs1_data}),
        .is_boxed_i (2'b11),
        .info_o ({info_b, info_a})
    );

    logic exp_nz_a, exp_nz_b;

    assign exp_nz_a = |fp_a.exp;
    assign exp_nz_b = |fp_b.exp;

    logic `N(MAN_BITS+2) raw_mant_a, raw_mant_b;
    logic `N(EXP_BITS) raw_exp_a, raw_exp_b;
    assign raw_exp_a = fp_a.exp | {{EXP_BITS-1{1'b0}}, ~exp_nz_a};
    assign raw_exp_b = fp_b.exp | {{EXP_BITS-1{1'b0}}, ~exp_nz_b};
    assign raw_mant_a = {exp_nz_a, fp_a.mant, 1'b0};
    assign raw_mant_b = {exp_nz_b, fp_b.mant, 1'b0};

// align
    logic `N(EXP_BITS) shift_cnt, sub_ab, sub_ba, exp_diff;
    logic `N(MAN_BITS+2) shift_mant_a, shift_mant_b, sticky_mask;
    logic sticky_pre, exp_gt;
    assign sub_ab = raw_exp_a - raw_exp_b;
    assign sub_ba = raw_exp_b - raw_exp_a;
    assign exp_gt = raw_exp_a > raw_exp_b;
    assign exp_diff = exp_gt ? sub_ab : sub_ba;
    assign shift_mant_a = exp_gt ? raw_mant_a : raw_mant_a >> sub_ba;
    assign shift_mant_b = exp_gt ? raw_mant_b >> sub_ab : raw_mant_b;
    assign sticky_mask = ((1 << exp_diff) - 1);

// mant cal
    logic `N(MAN_BITS+3) mant_sum;
    logic `N(EXP_BITS) shift_exp;
    logic sign;
    always_ff @(posedge clk) begin
        shift_exp <= exp_gt ? raw_exp_a : raw_exp_b;
        sticky_pre <= |((exp_gt ? raw_mant_b : raw_mant_a) & sticky_mask);
        if(fp_a.sign ^ fp_b.sign)begin
            if(shift_mant_a > shift_mant_b)begin
                mant_sum <= shift_mant_a - shift_mant_b;
                sign <= fp_a.sign;
            end
            else begin
                mant_sum <= shift_mant_b - shift_mant_a;
                sign <= fp_b.sign;
            end
        end
        else begin
            mant_sum <= shift_mant_a + shift_mant_b;
            sign <= fp_a.sign;
        end
    end

// normalization
    logic `N(MAN_BITS+2) align_mant;
    logic `N($clog2(MAN_BITS+1)) lpath_shamt;
    logic `N(EXP_BITS+1) align_exp;
    logic lzc_empty;

    lzc #(MAN_BITS+1, 1) lzc_inst (mant_sum[MAN_BITS+1: 1], lpath_shamt, lzc_empty);
    always_comb begin 
        if(mant_sum[MAN_BITS+2])begin
            align_exp = shift_exp + 1;
            align_mant = {1'b0, mant_sum[MAN_BITS+1: 1]};
        end
        else if(!lzc_empty) begin
            align_exp = shift_exp - lpath_shamt;
            align_mant = mant_sum << lpath_shamt;
        end
        else begin
          align_exp = shift_exp;
          align_mant = mant_sum;
        end
    end

// rounding
    logic `N(MAN_BITS) round_mant;
    logic `N(EXP_BITS+1) round_exp;
    logic round_ix, round_cout, round_up;
    fp_rounding #(MAN_BITS) rounding (
        align_mant[MAN_BITS: 1],
        align_mant[0],
        sticky_pre | (mant_sum[MAN_BITS+2] & mant_sum[0]),
        sign,
        round_mode,
        round_mant,
        round_ix,
        round_cout,
        round_up
    );
    assign round_exp = align_exp + round_cout;

    FFlags normal_status;
    always_comb begin
        normal_status = 0;
        normal_status.OF = round_exp[EXP_BITS] > 127;
        normal_status.UF = shift_exp < lpath_shamt;
        normal_status.NX = round_ix;
    end


    // ----------------------
    // Special case handling
    // ----------------------
    fp_t                special_result, special_result_n;
    FFlags              special_status, special_status_n;
    logic               result_is_special, result_special_n;

    always_comb begin : special_cases
        // Default assignments
        special_result    = '{sign: 1'b0, exp: '1, mant: 2**(MAN_BITS-1)}; // canonical qNaN
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
        end else if (info_a.is_nan | info_b.is_nan | fma & info_fma.is_nan) begin
        result_is_special = 1'b1;           // bypass FMA, output is the canonical qNaN
        special_status.NV = info_a.is_signalling | info_b.is_signalling | fma & info_fma.is_signalling; // raise the invalid operation flag if signalling
        // Special cases involving infinity
        end else if (info_a.is_inf | info_b.is_inf | fma & info_fma.is_inf) begin
        result_is_special = 1'b1; // bypass FMA
        // Effective addition of opposite infinities (±inf - ±inf) is invalid!
        if(~fma & info_a.is_inf & info_b.is_inf & (fp_a.sign ^ fp_b.sign) |
            fma & info_b.is_inf & info_fma.is_inf & (info_fma.sign ^ fp_b.sign))
            special_status.NV = 1'b1; // invalid operation
        // Handle cases where output will be inf because of inf product input
        else if (fma & info_fma.is_inf) begin
            // Result is infinity with the sign of the product
            special_result    = '{sign: info_fma.sign, exp: '1, mant: '0};
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

    assign res = result_special_n ? special_result_n : {sign, round_exp[EXP_BITS-1: 0], round_mant};
    assign status = result_special_n ? special_status_n : normal_status;

endmodule