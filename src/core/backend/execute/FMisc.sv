`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"

module FMiscUnit (
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    IssueFMiscIO.fmisc issue_fmisc_io,
    WriteBackIO.fu fmisc_wb_io,
    IssueWakeupIO.issue fmisc_wakeup_io,
    input BackendCtrl backendCtrl
);
generate
    for(genvar i=0; i<`FMISC_SIZE; i++)begin
        logic `N(`XLEN) res;
        FFlags fstatus;
        FMisc #(FP32) fmisc (
            .rs1_data(issue_fmisc_io.rs1_data[i]),
            .rs2_data(issue_fmisc_io.rs2_data[i]),
            .fltop(issue_fmisc_io.bundle[i].fltop),
            .round_mode(issue_fmisc_io.bundle[i].rm == 3'b111 ? round_mode : issue_fmisc_io.bundle[i].rm),
            .uext(issue_fmisc_io.bundle[i].uext),
            .res(res),
            .fstatus(fstatus)
        );

        logic bigger, bigger_s2;

        LoopCompare #(`ROB_WIDTH) cmp_bigger (backendCtrl.redirectIdx, issue_fmisc_io.status[i].robIdx, bigger);
        LoopCompare #(`ROB_WIDTH) cmp_bigger_s2 (backendCtrl.redirectIdx, fmisc_wb_io.datas[i].robIdx, bigger_s2);

        always_ff @(posedge clk)begin
            if(~fmisc_wb_io.datas[i].en | fmisc_wb_io.valid[i] | 
                (backendCtrl.redirect & bigger_s2))begin
                fmisc_wb_io.datas[i].en <= issue_fmisc_io.en[i] & issue_fmisc_io.bundle[i].flt_we & ~(backendCtrl.redirect & bigger);
                fmisc_wb_io.datas[i].robIdx <= issue_fmisc_io.status[i].robIdx;
                fmisc_wb_io.datas[i].res <= res;
                fmisc_wb_io.datas[i].we <= 1'b1;
                fmisc_wb_io.datas[i].rd <= issue_fmisc_io.status[i].rd;
                fmisc_wb_io.datas[i].exccode <= fstatus;
                fmisc_wakeup_io.en[i] <= issue_fmisc_io.en[i] & issue_fmisc_io.bundle[i].flt_we;
                fmisc_wakeup_io.we[i] <= 1'b1;
                fmisc_wakeup_io.rd[i] <= issue_fmisc_io.status[i].rd;
            end
            if(~fmisc_wb_io.datas[i+`FMISC_SIZE].en | fmisc_wb_io.valid[i+`FMISC_SIZE] |
               (backendCtrl.redirect & bigger_s2))begin
                fmisc_wb_io.datas[i+`FMISC_SIZE].en <= issue_fmisc_io.en[i] & ~issue_fmisc_io.bundle[i].flt_we & ~(backendCtrl.redirect & bigger);
                fmisc_wb_io.datas[i+`FMISC_SIZE].robIdx <= issue_fmisc_io.status[i].robIdx;
                fmisc_wb_io.datas[i+`FMISC_SIZE].res <= res;
                fmisc_wb_io.datas[i+`FMISC_SIZE].we <= issue_fmisc_io.status[i].we;
                fmisc_wb_io.datas[i+`FMISC_SIZE].rd <= issue_fmisc_io.status[i].rd;
                fmisc_wb_io.datas[i+`FMISC_SIZE].exccode <= fstatus;
                fmisc_wakeup_io.en[i+`FMISC_SIZE] <= issue_fmisc_io.en[i] & ~issue_fmisc_io.bundle[i].flt_we;
                fmisc_wakeup_io.we[i+`FMISC_SIZE] <= issue_fmisc_io.status[i].we;
                fmisc_wakeup_io.rd[i+`FMISC_SIZE] <= issue_fmisc_io.status[i].rd;
            end
        end
        assign issue_fmisc_io.stall[i] = issue_fmisc_io.en[i] & 
            (issue_fmisc_io.bundle[i].flt_we & fmisc_wb_io.datas[i].en & ~fmisc_wb_io.valid[i] |
            ~issue_fmisc_io.bundle[i].flt_we & fmisc_wb_io.datas[`FMISC_SIZE+i].en & ~fmisc_wb_io.valid[`FMISC_SIZE+i]);
    end
endgenerate
endmodule

module FMisc #(
    parameter fp_format_e format = fp_format_e'(0)
)(
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`FLTOP_WIDTH) fltop,
    input roundmode_e round_mode,
    input logic uext,
    output logic `N(`XLEN) res,
    output FFlags fstatus
);
    // ----------
    // Constants
    // ----------
    localparam int unsigned EXP_BITS = exp_bits(format);
    localparam int unsigned MAN_BITS = man_bits(format);
    // ----------------
    // Type definition
    // ----------------
    typedef struct packed {
        logic                sign;
        logic [EXP_BITS-1:0] exponent;
        logic [MAN_BITS-1:0] mantissa;
    } fp_t;

    FTypeInfo `N(2) info;
    FTypeInfo info_a, info_b;
    fp_t operand_a, operand_b;
    fp_classifier #(EXP_BITS, MAN_BITS, 2) classifier (
        .operands_i ({rs2_data, rs1_data}),
        .is_boxed_i (2'b11),
        .info_o (info)
    );

    assign info_a    = info[0];
    assign info_b    = info[1];
    logic any_operand_inf;
    logic any_operand_nan;
    logic signalling_nan;

    // Reduction for special case handling
    assign any_operand_inf = (| {info_a.is_inf,        info_b.is_inf});
    assign any_operand_nan = (| {info_a.is_nan,        info_b.is_nan});
    assign signalling_nan  = (| {info_a.is_signalling, info_b.is_signalling});

    logic operands_equal, operand_a_smaller;

    // Equality checks for zeroes too
    assign operand_a = rs1_data;
    assign operand_b = rs2_data;
    assign operands_equal    = (operand_a == operand_b) || (info_a.is_zero && info_b.is_zero);
    // Invert result if non-zero signs involved (unsigned comparison)
    assign operand_a_smaller = (operand_a < operand_b) ^ (operand_a.sign || operand_b.sign);

    // ---------------
    // Sign Injection
    // ---------------
    fp_t  sgnj_result;
    FFlags sgnj_status;

    always_comb begin : sign_injections
        logic sign_a, sign_b; // internal signs
        sgnj_result = operand_a; // result based on operand a

        if (!info_a.is_boxed) sgnj_result = '{sign: 1'b0, exponent: '1, mantissa: 2**(MAN_BITS-1)};

        sign_a = operand_a.sign & info_a.is_boxed;
        sign_b = operand_b.sign & info_b.is_boxed;

        unique case (fltop)
            `FLT_SGNJ: sgnj_result.sign = sign_b;          // SGNJ
            `FLT_SGNJN: sgnj_result.sign = ~sign_b;         // SGNJN
            `FLT_SGNJX: sgnj_result.sign = sign_a ^ sign_b; // SGNJX
            default: sgnj_result = '{default: 0}; // don't care
        endcase
    end
    assign sgnj_status = '0;        // sign injections never raise exceptions

    // ------------------
    // Minimum / Maximum
    // ------------------
    fp_t minmax_result;
    FFlags minmax_status;

    always_comb begin : min_max
        minmax_status = '0;
        minmax_status.NV = signalling_nan;
        if (info_a.is_nan && info_b.is_nan)
            minmax_result = '{sign: 1'b0, exponent: '1, mantissa: 2**(MAN_BITS-1)};
        else if (info_a.is_nan) minmax_result = operand_b;
        else if (info_b.is_nan) minmax_result = operand_a;
        // Otherwise decide according to the operation
        else begin
        unique case (fltop)
            `FLT_FMIN: minmax_result = operand_a_smaller ? operand_a : operand_b; // MIN
            `FLT_FMAX: minmax_result = operand_a_smaller ? operand_b : operand_a; // MAX
            default: minmax_result = '{default: 'b1}; // don't care
        endcase
        end
    end

  // ------------
  // Comparisons
  // ------------
  fp_t                cmp_result;
  FFlags cmp_status;

  // Comparisons - operation is encoded in rnd_mode_q:
  // RNE = LE, RTZ = LT, RDN = EQ
  // op_mod_q inverts boolean outputs
  always_comb begin : comparisons
    // Default assignment
    cmp_result = '0; // false
    cmp_status = '0; // no flags

    // Signalling NaNs always compare as false (except for "not equal" compares) and are illegal
    if (signalling_nan) begin
      cmp_status.NV = 1'b1; // invalid operation
      cmp_result    = fltop == `FLT_EQ && uext;
    // Otherwise do comparisons
    end else begin
      unique case (fltop)
        `FLT_LE: begin // Less than or equal
          if (any_operand_nan) cmp_status.NV = 1'b1; // Signalling comparison: NaNs are invalid
          else cmp_result = (operand_a_smaller | operands_equal) ^ uext;
        end
        `FLT_LT: begin // Less than
          if (any_operand_nan) cmp_status.NV = 1'b1; // Signalling comparison: NaNs are invalid
          else cmp_result = (operand_a_smaller & ~operands_equal) ^ uext;
        end
        `FLT_EQ: begin // Equal
          if (any_operand_nan) cmp_result = uext; // NaN always not equal
          else cmp_result = operands_equal ^ uext;
        end
        default: cmp_result = '{default: 1}; // don't care
      endcase
    end
  end

    logic `N(`XLEN) f2i_res;
    FFlags f2i_status;
    F2I #(FP32, INT32) f2i (
        uext,
        rs1_data,
        info_a,
        round_mode,
        f2i_res,
        f2i_status
    );
    logic `N(`XLEN) i2f_res;
    FFlags i2f_status;
    I2F #(FP32, INT32) i2f (
        uext,
        rs1_data,
        info_a,
        round_mode,
        i2f_res,
        i2f_status
    );

    always_comb begin
        case(fltop)
        `FLT_MV: begin
            res = rs1_data;
            fstatus = 0;
        end
        `FLT_FMIN, `FLT_FMAX: begin
            res = minmax_result;
            fstatus = minmax_status;
        end
        `FLT_SGNJ, `FLT_SGNJN, `FLT_SGNJX: begin
            res = sgnj_result;
            fstatus = sgnj_status;
        end
        `FLT_CVT: begin
            res = f2i_res;
            fstatus = f2i_status;
        end
        `FLT_CVTS: begin
            res = i2f_res;
            fstatus = i2f_status;
        end
        `FLT_LE, `FLT_LT, `FLT_EQ:begin
            res = cmp_result;
            fstatus = cmp_status;
        end
        `FLT_CLASS: begin
            res = {
                info_a.is_quiet,
                info_a.is_signalling,
                info_a.is_inf & ~operand_a.sign,
                info_a.is_normal & ~operand_a.sign,
                info_a.is_subnormal & ~operand_a.sign,
                info_a.is_zero & ~operand_a.sign,
                info_a.is_zero & operand_a.sign,
                info_a.is_subnormal & operand_a.sign,
                info_a.is_normal & operand_a.sign,
                info_a.is_inf & operand_a.sign
            };
            fstatus = 0;
        end
        default: begin
            res = 0;
            fstatus = 0;
        end
        endcase
    end
endmodule

module fp_classifier #(
    parameter int unsigned EXP_BITS = 8,
    parameter int unsigned MAN_BITS = 23,
    parameter int unsigned             NumOperands = 1,
    localparam int unsigned WIDTH = EXP_BITS + MAN_BITS + 1
)(
  input  logic                [NumOperands-1:0][WIDTH-1:0] operands_i,
  input  logic                [NumOperands-1:0]            is_boxed_i,
  output FTypeInfo [NumOperands-1:0]            info_o
);


  // Type definition
  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;

  // Iterate through all operands
  for (genvar op = 0; op < int'(NumOperands); op++) begin : gen_num_values

    fp_t value;
    logic is_boxed;
    logic is_normal;
    logic is_inf;
    logic is_nan;
    logic is_signalling;
    logic is_quiet;
    logic is_zero;
    logic is_subnormal;

    // ---------------
    // Classify Input
    // ---------------
    always_comb begin : classify_input
      value         = operands_i[op];
      is_boxed      = is_boxed_i[op];
      is_normal     = is_boxed && (value.exponent != '0) && (value.exponent != '1);
      is_zero       = is_boxed && (value.exponent == '0) && (value.mantissa == '0);
      is_subnormal  = is_boxed && (value.exponent == '0) && !is_zero;
      is_inf        = is_boxed && ((value.exponent == '1) && (value.mantissa == '0));
      is_nan        = !is_boxed || ((value.exponent == '1) && (value.mantissa != '0));
      is_signalling = is_boxed && is_nan && (value.mantissa[MAN_BITS-1] == 1'b0);
      is_quiet      = is_nan && !is_signalling;
      // Assign output for current input
      info_o[op].is_normal     = is_normal;
      info_o[op].is_subnormal  = is_subnormal;
      info_o[op].is_zero       = is_zero;
      info_o[op].is_inf        = is_inf;
      info_o[op].is_nan        = is_nan;
      info_o[op].is_signalling = is_signalling;
      info_o[op].is_quiet      = is_quiet;
      info_o[op].is_boxed      = is_boxed;
    end
  end
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