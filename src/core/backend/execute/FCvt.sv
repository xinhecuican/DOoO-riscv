`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"

module F2I #(
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt = 0,
    parameter logic [`INT_FORMAT_BITS-1:0] int_fmt = 0
)(
    input logic uext,
    input logic `N(`XLEN) src,
    input FTypeInfo info,
    input roundmode_e round_mode,
    output logic `N(`XLEN) dest,
    output FFlags status
);

    // ----------
    // Constants
    // ----------
    localparam int unsigned EXP_BITS = exp_bits(fp_fmt);
    localparam int unsigned MAN_BITS = man_bits(fp_fmt);
    localparam int unsigned FXL = EXP_BITS + MAN_BITS + 1;
    localparam logic [EXP_BITS-1: 0] max_shamt = ((1 << (EXP_BITS-1))-1)+MAN_BITS;
    localparam logic [EXP_BITS-1: 0] max_int_exp = ((1 << (EXP_BITS-1))-1)+int_width(int_fmt)-1;
    // ----------------
    // Type definition
    // ----------------
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [MAN_BITS-1:0] mant;
    } fp_t;

    logic exp_nz;
    logic `N(EXP_BITS) exp;
    logic `N(MAN_BITS+1) mant;
    fp_t data_i;
    logic exp_of;
    logic [$clog2(MAN_BITS)-1: 0] lpath_shamt, rpath_shamt;
    logic lpath_iv, lpath_may_of, lpath_pos_of, lpath_neg_of, lpath_of, iv_sel_max;
    logic sel_lpath;
    logic [FXL-1: 0] lpath_mant_shift, rpath_mant;
    logic rpath_exceed, rpath_sticky;
    logic [MAN_BITS+1: 0] rpath_mant_shift, rpath_sticky_mask;
    logic [MAN_BITS: 0] rpath_round_out;
    logic rpath_inexact, rpath_cout, rpath_up, rpath_iv, rpath_of;

    assign data_i = src[FXL-1: 0];
    assign exp_nz = |data_i.exp;
    assign exp = {{EXP_BITS-1{1'b0}}, ~exp_nz} | data_i.exp;
    assign mant = {exp_nz, data_i.mant};
    assign exp_of = exp > max_int_exp;
    assign lpath_shamt = exp - max_shamt;
    assign rpath_shamt = max_shamt - exp;
    assign sel_lpath = exp >= max_shamt;
    assign lpath_iv = uext & data_i.sign;
    assign lpath_may_of = ~uext & (exp == max_int_exp);
    assign lpath_pos_of = lpath_may_of & ~data_i.sign;
    assign lpath_neg_of = lpath_may_of & data_i.sign & (|data_i.mant);
    assign lpath_of = lpath_pos_of | lpath_neg_of;  
    assign iv_sel_max = info.is_nan | (~data_i.sign);

    assign lpath_mant_shift = mant << lpath_shamt;
    assign rpath_exceed = rpath_shamt > MAN_BITS + 2;

    assign rpath_mant_shift = {mant, 1'b0} >> rpath_shamt;
    assign rpath_sticky_mask = ((1 << rpath_shamt) - 1) | {MAN_BITS+2{rpath_exceed}};
    assign rpath_sticky = |({mant, 1'b0} & rpath_sticky_mask);

    fp_rounding #(MAN_BITS+1) rounding (
        rpath_mant_shift[MAN_BITS+1: 1],
        rpath_mant_shift[0],
        rpath_sticky,
        data_i.sign,
        round_mode,
        rpath_round_out,
        rpath_inexact,
        rpath_cout,
        rpath_up
    );
generate
    if(int_width(int_fmt) < MAN_BITS)begin
        assign rpath_mant = {rpath_cout, rpath_round_out};
        
        logic rpath_exp_inc, exp_eq_max, exp_eq_max_p1;
        logic rpath_pos_of, rpath_neg_of;
        assign rpath_exp_inc = rpath_up & (&rpath_mant_shift[MAN_BITS: 1]);
        assign exp_eq_max = data_i.exp == max_int_exp;
        assign exp_eq_max_p1 = data_i.exp == max_int_exp - 1;
        assign rpath_pos_of = ~data_i.sign & (~uext ? exp_eq_max | (exp_eq_max_p1 & rpath_exp_inc) :
                                                    exp_eq_max & rpath_exp_inc);
        assign rpath_neg_of = data_i.sign & exp_eq_max & (|rpath_mant_shift[MAN_BITS: 1] | rpath_up);
        assign rpath_of = rpath_pos_of | rpath_neg_of;
    end
    else begin
        assign rpath_mant = {{int_width(int_fmt)-MAN_BITS-2{1'b0}}, rpath_cout, rpath_round_out};
        assign rpath_of = 0;
    end
endgenerate
    
    assign rpath_iv = uext & data_i.sign & (|rpath_mant);

    logic of, iv, ix;
    logic `N(`XLEN) int_abs, int_res;
    assign of = exp_of | (sel_lpath & lpath_of) | (~sel_lpath & rpath_of);
    assign iv = of | (sel_lpath & lpath_iv) | (~sel_lpath & rpath_iv);
    assign ix = ~iv & ~sel_lpath & rpath_inexact;
    assign int_abs = sel_lpath ? lpath_mant_shift : rpath_mant;
    assign int_res = data_i.sign & ~uext ? -int_abs : int_abs;
    always_comb begin
        if(iv)begin
            if(iv_sel_max)begin
                dest = {uext, {int_width(int_fmt)-1{1'b1}}};
            end
            else begin
                dest = {~uext, {int_width(int_fmt)-1{1'b0}}};
            end
        end
        else begin
            dest = int_res;
        end

        status = 0;
        status.NV = iv;
        status.NX = ix;
    end
endmodule

module I2F #(
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt = 0,
    parameter logic [`INT_FORMAT_BITS-1:0] int_fmt = 0,
    parameter int INT_WIDTH = int_width(int_fmt)
)(
    input logic uext,
    input logic `N(`XLEN) src,
    input FTypeInfo info,
    input roundmode_e round_mode,
    output logic `N(`XLEN) dest,
    output FFlags status
);
    localparam int unsigned EXP_BITS = exp_bits(fp_fmt);
    localparam int unsigned MAN_BITS = man_bits(fp_fmt);
    localparam int unsigned FXL = EXP_BITS + MAN_BITS + 1;
    localparam int unsigned SFT_BITS = MAN_BITS * 2 + 5;
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [MAN_BITS-1:0] mant;
    } fp_t;

    fp_t fp;
    logic sign;
    logic `N(INT_WIDTH) int_abs;
    logic `N(INT_WIDTH) int_shift, int_shift_pre; 
    logic `N($clog2(INT_WIDTH)) lzc_cnt;
    logic `N(MAN_BITS) raw_mant, round_mant;
    logic `N(EXP_BITS+1) raw_exp;
    logic lzc_empty;
    logic sticky, round;
    logic round_ix, round_cout, round_up;

    assign sign = src[INT_WIDTH-1] & ~uext;
    assign int_abs = sign ? -src[INT_WIDTH-1: 0] : src[INT_WIDTH-1: 0];
    lzc #(INT_WIDTH, 1) lzc_inst (int_abs, lzc_cnt, lzc_empty);
    assign int_shift_pre = int_abs << (lzc_cnt);
    assign int_shift = {int_shift_pre[INT_WIDTH-2: 0], 1'b0};
    
    assign raw_exp = (INT_WIDTH - 1 - lzc_cnt) + {1'b0, {EXP_BITS-1{~lzc_empty}}};
generate
    if(INT_WIDTH < MAN_BITS)begin
        assign raw_mant[MAN_BITS-1 -: INT_WIDTH] = int_shift;
        assign raw_mant[MAN_BITS-INT_WIDTH-1: 0] = 0;
        assign round_cout = 0;
        assign round_mant = raw_mant;
        assign round_ix = 0;
    end
    else begin
        assign raw_mant = int_shift[INT_WIDTH-1: INT_WIDTH-MAN_BITS];
        assign sticky = |int_shift[INT_WIDTH-MAN_BITS-1: 0];
        assign round = int_shift[INT_WIDTH-MAN_BITS-1];

        fp_rounding #(MAN_BITS) rounding (
            raw_mant,
            round,
            sticky,
            sign,
            round_mode,
            round_mant,
            round_ix,
            round_cout,
            round_up
        );
    end
endgenerate


    assign fp.exp = raw_exp + round_cout;
    assign fp.mant = round_mant;
    assign fp.sign = ~uext & src[INT_WIDTH-1];
    assign status.NV = round_ix;
    assign dest = fp;
endmodule

module F2FUp #(
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt_i = 0,
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt_o = 0
)(
    input logic `N(`XLEN) src,
    output logic `N(`XLEN) dest,
    output FFlags status
);
    localparam int unsigned EXP_BITS_I = exp_bits(fp_fmt_i);
    localparam int unsigned MAN_BITS_I = man_bits(fp_fmt_i);
    localparam int unsigned FXL_I = EXP_BITS_I + MAN_BITS_I + 1;
    localparam int unsigned EXP_BITS_O = exp_bits(fp_fmt_o);
    localparam int unsigned MAN_BITS_O = man_bits(fp_fmt_o);
    localparam int unsigned EXP_BIAS_I = (1 << (EXP_BITS_I-1)) - 1;
    localparam int unsigned EXP_BIAS_O = (1 << (EXP_BITS_O-1)) - 1;
    localparam int unsigned DELTA = EXP_BIAS_O - EXP_BIAS_I;
    logic nan;
    logic subnormal;
    logic zero, exp_all;
    logic mant_nz;
    logic `N($clog2(MAN_BITS_I)) rs1_shamt;
    logic `N(MAN_BITS_I) shift_mant;
    typedef struct packed {
        logic sign;
        logic `N(EXP_BITS_I) exp;
        logic `N(MAN_BITS_I) mant;
    } fp_t;
    fp_t data_i;
    assign data_i = src[FXL_I-1: 0];
    assign exp_all = &data_i.exp;
    assign mant_nz = |data_i.mant;
    assign nan = exp_all & mant_nz;
    assign subnormal = ~(|data_i.exp) & mant_nz;
    assign zero = ~(|{data_i.exp, data_i.mant});
    lzc #(MAN_BITS_I, 1) lzc_mant (data_i.mant, rs1_shamt,);
    assign shift_mant = data_i.mant << rs1_shamt;

    typedef struct packed {
        logic sign;
        logic `N(EXP_BITS_O) exp;
        logic `N(MAN_BITS_O) mant;
    } fp_t_o;

    fp_t_o fp_o;
    assign fp_o.sign = data_i.sign & ~nan;
    assign fp_o.exp = exp_all ? {EXP_BITS_O{1'b1}} :
                            zero ? {EXP_BITS_O{1'b0}} :
                            subnormal ? DELTA - rs1_shamt : data_i.exp + DELTA;
    assign fp_o.mant[MAN_BITS_O-1 -: MAN_BITS_I] = exp_all ? {mant_nz, {MAN_BITS_I-1{1'b0}}} :
                                                    subnormal ? shift_mant : data_i.mant;
    assign fp_o.mant[MAN_BITS_O-MAN_BITS_I-1: 0] = 0;
    assign dest = fp_o;
    assign status = '{NV: nan, default: 0};
endmodule

module F2FDown #(
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt_i = 0,
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt_o = 0
)(
    input logic `N(`XLEN) src,
    input FTypeInfo info,
    input roundmode_e round_mode,
    output logic `N(`XLEN) dest,
    output FFlags status
);
    localparam int unsigned EXP_BITS_I = exp_bits(fp_fmt_i);
    localparam int unsigned MAN_BITS_I = man_bits(fp_fmt_i);
    localparam int unsigned FXL_I = EXP_BITS_I + MAN_BITS_I + 1;
    localparam int unsigned EXP_BITS_O = exp_bits(fp_fmt_o);
    localparam int unsigned MAN_BITS_O = man_bits(fp_fmt_o);
    localparam int unsigned EXP_BIAS_I = (1 << (EXP_BITS_I-1)) - 1;
    localparam int unsigned EXP_BIAS_O = (1 << (EXP_BITS_O-1)) - 1;
    localparam int unsigned DELTA = EXP_BIAS_I - EXP_BIAS_O;

    typedef struct packed {
        logic sign;
        logic `N(EXP_BITS_I) exp;
        logic `N(MAN_BITS_I) mant;
    } fp_t;

    fp_t data_i;
    logic exp_nz, exp_all;
    logic may_uf, of, uf;
    logic `N(EXP_BITS_I) exp_bias, round_exp;
    logic `N(MAN_BITS_O) round_mant;
    logic round_ix, round_cout, round_up;

    assign data_i = src[FXL_I-1: 0];
    assign exp_nz = |data_i.exp;
    assign exp_all = &data_i.exp;
    assign may_uf = data_i.exp <= DELTA;
    assign exp_bias = data_i.exp - DELTA;

    fp_rounding #(MAN_BITS_O) normal_rounding (
        data_i.mant[MAN_BITS_I - 1 -: MAN_BITS_O],
        data_i.mant[MAN_BITS_I - MAN_BITS_O - 1],
        |data_i.mant[MAN_BITS_I - MAN_BITS_O - 1: 0],
        data_i.sign,
        round_mode,
        round_mant,
        round_ix,
        round_cout,
        round_up
    );

    assign of = round_cout ? data_i.exp > EXP_BIAS_I + EXP_BIAS_O - 1 :
                             data_i.exp > EXP_BIAS_I + EXP_BIAS_O;
    assign round_exp = exp_bias + round_cout;

    logic `N(EXP_BITS_I) subnormal_exp;
    logic `N($clog2(MAN_BITS_O+1)) subnormal_shamt;
    logic `N(MAN_BITS_O+1) subnormal_mant_pre, subnormal_mant;
    logic `N(MAN_BITS_O+2) sticky_mask;
    logic `N(MAN_BITS_O) subnormal_round_mant;
    logic subnormal_sticky, subnormal_ix, subnormal_cout, subnormal_up;
    assign subnormal_exp = DELTA - data_i.exp;
    assign subnormal_shamt = subnormal_exp[$clog2(MAN_BITS_O)-1: 0] > MAN_BITS_O + 1 ? MAN_BITS_O + 1 :
                             subnormal_exp[$clog2(MAN_BITS_O)-1: 0];
    assign subnormal_mant_pre = {exp_nz, data_i.mant[MAN_BITS_I-1 -: MAN_BITS_O]};
    assign subnormal_mant = subnormal_mant_pre >> subnormal_shamt;

    MaskGen #(MAN_BITS_O+2) gen_sticky_mask (subnormal_shamt, sticky_mask);

    assign subnormal_sticky = (|data_i.mant[MAN_BITS_I-MAN_BITS_O-1: 0]) | 
                              (|(subnormal_mant_pre & sticky_mask[MAN_BITS_O: 0]));
    fp_rounding #(MAN_BITS_O) subnormal_rounding (
        subnormal_mant[MAN_BITS_O: 1],
        subnormal_mant[0],
        subnormal_sticky,
        data_i.sign,
        round_mode,
        subnormal_round_mant,
        subnormal_ix,
        subnormal_cout,
        subnormal_up
    );

    logic rmin;
    assign rmin = round_mode == RTZ || (round_mode == RDN && data_i.sign) ||
                    (round_mode == RUP && data_i.sign);
    assign uf = subnormal_cout ? data_i.exp < DELTA : may_uf;

    logic `N(EXP_BITS_O) of_exp, subnormal_exp_o, normal_exp;
    logic `N(MAN_BITS_O) of_mant;

    assign of_exp = rmin ? (1 << (EXP_BITS_O-1)) - 2 : (1 << (EXP_BITS_O-1)) - 1;
    assign subnormal_exp_o = subnormal_cout;
    assign normal_exp = exp_bias + round_cout;
    assign of_mant = rmin ? {MAN_BITS_O{1'b1}} : 0;

    typedef struct packed {
        logic sign;
        logic `N(EXP_BITS_O) exp;
        logic `N(MAN_BITS_O) mant;
    } fp_t_o;

    fp_t_o fp_o;
    assign fp_o.sign = ~info.is_nan & data_i.sign;
    assign fp_o.exp = exp_all ? {EXP_BITS_O{1'b1}} :
                      of ? of_exp :
                      may_uf ? subnormal_exp_o : normal_exp;
    assign fp_o.mant = exp_all ? {info.is_nan, {MAN_BITS_O-1{1'b0}}} :
                       of ? of_mant : may_uf ? subnormal_round_mant : round_mant;
    assign dest = fp_o;

    assign status.NV = info.is_nan;
    assign status.DZ = 0;
    assign status.OF = ~exp_all & of;
    assign status.UF = ~exp_all & uf & subnormal_ix;
    assign status.NX = ~exp_all & (~may_uf & round_ix | may_uf & subnormal_ix);

endmodule