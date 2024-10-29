`ifndef __FP__DEFINES__SVH__
`define __FP__DEFINES__SVH__

typedef struct packed {
    logic NV;
    logic DZ;
    logic OF;
    logic UF;
    logic NX;
} FFlags;

typedef enum logic [2:0] {
    RNE = 3'b000,
    RTZ = 3'b001,
    RDN = 3'b010,
    RUP = 3'b011,
    RMM = 3'b100,
    ROD = 3'b101,  // This mode is not defined in RISC-V FP-SPEC
    DYN = 3'b111
} roundmode_e;

typedef struct packed {
    logic is_normal;      // is the value normal
    logic is_subnormal;   // is the value subnormal
    logic is_zero;        // is the value zero
    logic is_inf;         // is the value infinity
    logic is_nan;         // is the value NaN
    logic is_signalling;  // is the value a signalling NaN
    logic is_quiet;       // is the value a quiet NaN
    logic is_boxed;       // is the value properly NaN-boxed (RISC-V specific)
} FTypeInfo;

`define NUM_INT_FORMATS 4
`define NUM_FP_FORMATS 5
`define INT_FORMAT_BITS $clog2(`NUM_INT_FORMATS)
`define FP_FORMAT_BITS $clog2(`NUM_FP_FORMATS)
typedef logic [`NUM_FP_FORMATS-1: 0]       fmt_logic_t; 
typedef logic [`NUM_INT_FORMATS-1: 0]      ifmt_logic_t;

  // Encoding for a format
  typedef struct packed {
    int unsigned exp_bits;
    int unsigned man_bits;
  } fp_encoding_t;

// FP formats
typedef enum logic [`FP_FORMAT_BITS-1:0] {
    FP32    = 'd0,
    FP64    = 'd1,
    FP16    = 'd2,
    FP8     = 'd3,
    FP16ALT = 'd4
    // add new formats here
} fp_format_e;

typedef enum logic [`INT_FORMAT_BITS-1:0] {
    INT8,
    INT16,
    INT32,
    INT64
    // add new formats here
} int_format_e;
// Encodings for supported FP formats
localparam fp_encoding_t [`NUM_FP_FORMATS-1: 0] FP_ENCODINGS = '{
    '{8, 7},  // custom binary16alt
    '{5, 2},  // custom binary8
    '{5, 10},  // IEEE binary16 (half)
    '{11, 52},  // IEEE binary64 (double)
    '{8, 23}  // IEEE binary32 (single)
// add new formats here
};

  // Returns the bias value for a given format (as per IEEE 754-2008)
  function automatic int unsigned fp_bias(fp_format_e fmt);
    return unsigned'(2**(FP_ENCODINGS[fmt].exp_bits-1)-1); // symmetrical bias
  endfunction

// Returns the number of expoent bits for a format
function automatic int unsigned exp_bits(fp_format_e fmt);
    return FP_ENCODINGS[fmt].exp_bits;
endfunction

// Returns the number of mantissa bits for a format
function automatic int unsigned man_bits(fp_format_e fmt);
    return FP_ENCODINGS[fmt].man_bits;
endfunction

// Returns the width of an INT format by index
function automatic int unsigned int_width(int_format_e ifmt);
    unique case (ifmt)
        INT8:  return 8;
        INT16: return 16;
        INT32: return 32;
        INT64: return 64;
        default: begin
            // pragma translate_off
            $fatal(1, "Invalid INT format supplied");
            // pragma translate_on
            // just return any integer to avoid any latches
            // hopefully this error is caught by simulation
            return INT8;
        end
    endcase
endfunction

function automatic int maximum(int a, int b);
    return (a > b) ? a : b;
endfunction

// -------------------------------------------
// Helper functions for INT formats and values
// -------------------------------------------
// Returns the widest INT format present
function automatic int unsigned max_int_width(ifmt_logic_t cfg);
    automatic int unsigned res = 0;
    for (int ifmt = 0; ifmt < `NUM_INT_FORMATS; ifmt++) begin
        if (cfg[ifmt]) res = maximum(res, int_width(int_format_e'(ifmt)));
    end
    return res;
endfunction

  function automatic fp_encoding_t super_format(fmt_logic_t cfg);
    automatic fp_encoding_t res;
    res = '0;
    for (int unsigned fmt = 0; fmt < `NUM_FP_FORMATS; fmt++)
      if (cfg[fmt]) begin // only active format
        res.exp_bits = unsigned'(maximum(res.exp_bits, exp_bits(fp_format_e'(fmt))));
        res.man_bits = unsigned'(maximum(res.man_bits, man_bits(fp_format_e'(fmt))));
      end
    return res;
  endfunction

  function automatic int unsigned fp_width(fp_format_e fmt);
    return FP_ENCODINGS[fmt].exp_bits + FP_ENCODINGS[fmt].man_bits + 1;
  endfunction

  function automatic int unsigned max_fp_width(fmt_logic_t cfg);
    automatic int unsigned res = 0;
    for (int unsigned i = 0; i < `NUM_FP_FORMATS; i++)
      if (cfg[i])
        res = unsigned'(maximum(res, fp_width(fp_format_e'(i))));
    return res;
  endfunction
`endif
