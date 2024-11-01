`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"

module F2I #(
    parameter fp_format_e fp_fmt = 0,
    parameter int_format_e int_fmt = 0
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
    logic [`XLEN-1: 0] lpath_mant_shift, rpath_mant;
    logic rpath_exceed, rpath_sticky;
    logic [MAN_BITS+1: 0] rpath_mant_shift, rpath_sticky_mask;
    logic [MAN_BITS: 0] rpath_round_out;
    logic rpath_inexact, rpath_cout, rpath_up, rpath_iv;

    assign data_i = src;
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
    assign rpath_mant = {{int_width(int_fmt)-MAN_BITS-2{1'b0}}, rpath_cout, rpath_round_out};
    assign rpath_iv = uext & data_i.sign & (|rpath_mant);

    logic of, iv, ix;
    logic `N(`XLEN) int_abs, int_res;
    assign of = exp_of | (sel_lpath & lpath_of);
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
    parameter fp_format_e fp_fmt = 0,
    parameter int_format_e int_fmt = 0,
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
    localparam int unsigned SFT_BITS = MAN_BITS * 2 + 5;
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exp;
        logic [MAN_BITS-1:0] mant;
    } fp_t;

    fp_t fp;
    logic sign;
    logic `N(`XLEN) int_abs;
    logic `N(`XLEN) int_shift, int_shift_pre; 
    logic `N($clog2(INT_WIDTH)) lzc_cnt;
    logic `N(MAN_BITS) raw_mant, round_mant;
    logic `N(EXP_BITS+1) raw_exp;
    logic lzc_empty;
    logic sticky, round;
    logic round_ix, round_cout, round_up;

    assign sign = src[INT_WIDTH-1] & ~uext;
    assign int_abs = sign ? -src : src;
    lzc #(INT_WIDTH, 1) lzc_inst (int_abs, lzc_cnt, lzc_empty);
    assign int_shift_pre = int_abs << (lzc_cnt);
    assign int_shift = {int_shift_pre[`XLEN-2: 0], 1'b0};
    
    assign raw_exp = (INT_WIDTH - 1 - lzc_cnt) + {1'b0, {EXP_BITS-1{~lzc_empty}}};
    assign raw_mant = int_shift[INT_WIDTH-1: INT_WIDTH-MAN_BITS];
    assign sticky = |int_shift[0 +: MAN_BITS+1];
    assign round = int_shift[MAN_BITS-1];

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

    assign fp.exp = raw_exp + round_cout;
    assign fp.mant = round_mant;
    assign fp.sign = ~uext & src[INT_WIDTH-1];
    assign status.NV = round_ix;
    assign dest = fp;
endmodule

module fp_rounding #(
    parameter MAN_BITS=1
)(
    input logic `N(MAN_BITS) in,
    input logic round,
    input logic sticky,
    input logic sign,
    input roundmode_e round_mode,
    output logic `N(MAN_BITS) out,
    output logic inexact,
    output logic cout,
    output logic r_up
);
    assign inexact = sticky | round;
    always_comb begin
        case(round_mode)
        RNE: r_up = round & sticky | (round & ~sticky & in[0]);
        RUP: r_up = inexact & ~sign;
        RDN: r_up = inexact & sign;
        RMM: r_up = round;
        default: r_up = 0;
        endcase
    end

    assign out = r_up ? in + 1 : in;
    assign cout = r_up & (&(in));
endmodule