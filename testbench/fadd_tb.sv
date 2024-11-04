`include "../src/defines/fp_defines.svh"
`include "../src/defines/defines.svh"

// sv2v --write=build/fadd_tb.v -I=src/defines -I=build --top=fadd_tb testbench/fadd_tb.sv src/core/backend/execute/FAdd.sv src/core/backend/execute/FMisc.sv src/utils/lzc.sv
// iverilog -g2012 build/fadd_tb.v -s fadd_tb -o build/sim.out
// vvp -n build/sim.out
module fadd_tb();
    int stimulus_a[1000];
    int stimulus_b[1000];
    int corner_values[6];
    int perm_idx;
    int count = 0;
    logic clk, rst;
    roundmode_e round_mode;
    logic sub;
    FMulInfo info;
    logic [31: 0] rs1_data, rs2_data, res_dut, res_ref;
    FFlags flag_dut, flag_ref;

    always #5 clk = ~clk;

    FAdd #(FP32) fadd_dut (
        .clk,
        .rst,
        .round_mode,
        .sub(sub),
        .fma(1'b0),
        .info_fma(info),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .res(res_dut),
        .status(flag_dut)
    );

    FADD fadd_ref (
        .clock(clk),
        .reset(rst),
        .io_a(rs1_data),
        .io_b(rs2_data),
        .io_rm(round_mode),
        .io_result(res_ref),
        .io_fflags(flag_ref)
    );

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, fadd_tb);
    end

    // task to run the test and print the count
    task run_test(input int a[1000], input int b[1000], input int size);
        int count = 0;
        for (int i = 0; i < size; i++) begin
            rs1_data = a[i];
            rs2_data = b[i];
            #20;
            if(res_dut != res_ref || flag_dut != flag_ref)begin
                $display("Test with A: %h, B: %h error.\nDut: %h %h\nRef: %h %h", a[i], b[i], res_dut, flag_dut, res_ref, flag_ref);
                $finish;
            end
        end
    endtask

    initial begin
        clk = 1;
        rst = 1;
        round_mode = 0;
        sub = 0;
        info = 0;
        #10;
        // Regression Tests
        stimulus_a[7: 0] = '{32'h22cb525a, 32'h40000000, 32'h83e73d5c, 32'hbf9b1e94, 32'h34082401, 32'h05e8ef81, 32'h5c75da81, 32'h002b017};
        stimulus_b[7: 0] = '{32'hadd79efa, 32'hc0000000, 32'h1c800000, 32'hc038ed3a, 32'hb328cd45, 32'h0114f3db, 32'h2f642a39, 32'hff3807ab};
        $display("Regression Tests");
        run_test(stimulus_a, stimulus_b, 8);
        

        // Corner Cases
        corner_values = '{32'h80000000, 32'h00000000, 32'h7f800000, 32'hff800000, 32'h7fc00000, 32'hffc00000};
        perm_idx = 0;
        foreach (corner_values[i]) begin
            foreach (corner_values[j]) begin
                if (perm_idx < 1000) begin
                    stimulus_a[perm_idx] = corner_values[i];
                    stimulus_b[perm_idx] = corner_values[j];
                    perm_idx++;
                end
            end
        end
        $display("Corner Cases");
        run_test(stimulus_a, stimulus_b, perm_idx);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random & 32'h807fffff;
            stimulus_b[i] = $random & 32'h807fffff;
        end
        $display("denormal + denormal");
        run_test(stimulus_a, stimulus_b, 1000);

        // Edge Cases
        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h80000000;
            stimulus_b[i] = $random;
        end
        $display("edge cases");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h00000000;
            stimulus_b[i] = $random;
        end
        $display("+0 + any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'h80000000;
        end
        $display("-0 + any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'h00000000;
        end
        $display("any + 0");
        run_test(stimulus_a, stimulus_b, 1000);

        // Special floating point cases
        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h7f800000; // +Inf
            stimulus_b[i] = $random;
        end
        $display("+Inf + any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'hff800000; // -Inf
            stimulus_b[i] = $random;
        end
        $display("-Inf + any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'h7f800000;
        end
        $display("any + Inf");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'hff800000;
        end
        $display("any - Inf");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h7fc00000; // NaN
            stimulus_b[i] = $random;
        end
        $display("NaN + any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'hffc00000; // -NaN
            stimulus_b[i] = $random;
        end
        $display("-Nan + any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'h7fc00000;
        end
        $display("any + Nan");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'hffc00000;
        end
        $display("any - NaN");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = $random;
        end
        $display("any + any");
        run_test(stimulus_a, stimulus_b, 1000);

        $display("All tests passed.");
        $finish;
    end
endmodule

// https://github.com/OpenXiangShan/fudian
module ShiftRightJam(
  input  [25:0] io_in, // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
  input  [7:0]  io_shamt, // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
  output [25:0] io_out, // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
  output        io_sticky // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
);
  wire  exceed_max_shift = io_shamt > 8'h1a; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 17:35]
  wire [4:0] shamt = io_shamt[4:0]; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 18:23]
  wire [31:0] _sticky_mask_T = 32'h1 << shamt; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:11]
  wire [31:0] _sticky_mask_T_2 = _sticky_mask_T - 32'h1; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:28]
  wire [25:0] _sticky_mask_T_5 = exceed_max_shift ? 26'h3ffffff : 26'h0; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:53]
  wire [25:0] sticky_mask = _sticky_mask_T_2[25:0] | _sticky_mask_T_5; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:47]
  wire [25:0] _io_out_T = io_in >> io_shamt; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 21:46]
  wire [25:0] _io_sticky_T = io_in & sticky_mask; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 22:23]
  assign io_out = exceed_max_shift ? 26'h0 : _io_out_T; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 21:16]
  assign io_sticky = |_io_sticky_T; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 22:38]
endmodule
module FarPath(
  input         io_in_a_sign, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [7:0]  io_in_a_exp, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [23:0] io_in_a_sig, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [23:0] io_in_b_sig, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [7:0]  io_in_expDiff, // @[src/main/scala/fudian/FADD.scala 9:14]
  input         io_in_effSub, // @[src/main/scala/fudian/FADD.scala 9:14]
  output        io_out_result_sign, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [23:0] io_out_sig_a, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [27:0] io_out_sig_b, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [7:0]  io_out_exp_a_vec_0, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [7:0]  io_out_exp_a_vec_1, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [7:0]  io_out_exp_a_vec_2 // @[src/main/scala/fudian/FADD.scala 9:14]
);
  wire [25:0] shiftRightJam_io_in; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire [7:0] shiftRightJam_io_shamt; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire [25:0] shiftRightJam_io_out; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire  shiftRightJam_io_sticky; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire [27:0] adder_in_sig_b_raw = {1'h0,shiftRightJam_io_out,shiftRightJam_io_sticky}; // @[src/main/scala/fudian/FADD.scala 34:31]
  wire [27:0] _adder_in_sig_b_T = ~adder_in_sig_b_raw; // @[src/main/scala/fudian/FADD.scala 35:37]
  wire [27:0] _adder_in_sig_b_T_1 = io_in_effSub ? _adder_in_sig_b_T : adder_in_sig_b_raw; // @[src/main/scala/fudian/FADD.scala 35:27]
  wire [27:0] _GEN_0 = {{27'd0}, io_in_effSub}; // @[src/main/scala/fudian/FADD.scala 35:86]
  ShiftRightJam shiftRightJam ( // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
    .io_in(shiftRightJam_io_in),
    .io_shamt(shiftRightJam_io_shamt),
    .io_out(shiftRightJam_io_out),
    .io_sticky(shiftRightJam_io_sticky)
  );
  assign io_out_result_sign = io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 68:20 69:15]
  assign io_out_sig_a = io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 73:16]
  assign io_out_sig_b = _adder_in_sig_b_T_1 + _GEN_0; // @[src/main/scala/fudian/FADD.scala 35:86]
  assign io_out_exp_a_vec_0 = io_in_a_exp + 8'h1; // @[src/main/scala/fudian/FADD.scala 45:28]
  assign io_out_exp_a_vec_1 = io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 77:23]
  assign io_out_exp_a_vec_2 = io_in_a_exp - 8'h1; // @[src/main/scala/fudian/FADD.scala 46:29]
  assign shiftRightJam_io_in = {io_in_b_sig,2'h0}; // @[src/main/scala/fudian/FADD.scala 31:53]
  assign shiftRightJam_io_shamt = io_in_expDiff; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 29:28]
endmodule
module LZA(
  input  [24:0] io_a, // @[src/main/scala/fudian/utils/LZA.scala 12:14]
  input  [24:0] io_b, // @[src/main/scala/fudian/utils/LZA.scala 12:14]
  output [24:0] io_f // @[src/main/scala/fudian/utils/LZA.scala 12:14]
);
  wire  k_0 = ~io_a[0] & ~io_b[0]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  p_1 = io_a[1] ^ io_b[1]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_1 = ~io_a[1] & ~io_b[1]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_1 = p_1 ^ ~k_0; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_2 = io_a[2] ^ io_b[2]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_2 = ~io_a[2] & ~io_b[2]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_2 = p_2 ^ ~k_1; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_3 = io_a[3] ^ io_b[3]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_3 = ~io_a[3] & ~io_b[3]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_3 = p_3 ^ ~k_2; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_4 = io_a[4] ^ io_b[4]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_4 = ~io_a[4] & ~io_b[4]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_4 = p_4 ^ ~k_3; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_5 = io_a[5] ^ io_b[5]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_5 = ~io_a[5] & ~io_b[5]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_5 = p_5 ^ ~k_4; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_6 = io_a[6] ^ io_b[6]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_6 = ~io_a[6] & ~io_b[6]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_6 = p_6 ^ ~k_5; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_7 = io_a[7] ^ io_b[7]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_7 = ~io_a[7] & ~io_b[7]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_7 = p_7 ^ ~k_6; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_8 = io_a[8] ^ io_b[8]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_8 = ~io_a[8] & ~io_b[8]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_8 = p_8 ^ ~k_7; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_9 = io_a[9] ^ io_b[9]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_9 = ~io_a[9] & ~io_b[9]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_9 = p_9 ^ ~k_8; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_10 = io_a[10] ^ io_b[10]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_10 = ~io_a[10] & ~io_b[10]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_10 = p_10 ^ ~k_9; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_11 = io_a[11] ^ io_b[11]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_11 = ~io_a[11] & ~io_b[11]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_11 = p_11 ^ ~k_10; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_12 = io_a[12] ^ io_b[12]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_12 = ~io_a[12] & ~io_b[12]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_12 = p_12 ^ ~k_11; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_13 = io_a[13] ^ io_b[13]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_13 = ~io_a[13] & ~io_b[13]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_13 = p_13 ^ ~k_12; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_14 = io_a[14] ^ io_b[14]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_14 = ~io_a[14] & ~io_b[14]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_14 = p_14 ^ ~k_13; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_15 = io_a[15] ^ io_b[15]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_15 = ~io_a[15] & ~io_b[15]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_15 = p_15 ^ ~k_14; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_16 = io_a[16] ^ io_b[16]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_16 = ~io_a[16] & ~io_b[16]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_16 = p_16 ^ ~k_15; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_17 = io_a[17] ^ io_b[17]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_17 = ~io_a[17] & ~io_b[17]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_17 = p_17 ^ ~k_16; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_18 = io_a[18] ^ io_b[18]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_18 = ~io_a[18] & ~io_b[18]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_18 = p_18 ^ ~k_17; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_19 = io_a[19] ^ io_b[19]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_19 = ~io_a[19] & ~io_b[19]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_19 = p_19 ^ ~k_18; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_20 = io_a[20] ^ io_b[20]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_20 = ~io_a[20] & ~io_b[20]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_20 = p_20 ^ ~k_19; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_21 = io_a[21] ^ io_b[21]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_21 = ~io_a[21] & ~io_b[21]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_21 = p_21 ^ ~k_20; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_22 = io_a[22] ^ io_b[22]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_22 = ~io_a[22] & ~io_b[22]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_22 = p_22 ^ ~k_21; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_23 = io_a[23] ^ io_b[23]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_23 = ~io_a[23] & ~io_b[23]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_23 = p_23 ^ ~k_22; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_24 = io_a[24] ^ io_b[24]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  f_24 = p_24 ^ ~k_23; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire [5:0] io_f_lo_lo = {f_5,f_4,f_3,f_2,f_1,1'h0}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [11:0] io_f_lo = {f_11,f_10,f_9,f_8,f_7,f_6,io_f_lo_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [5:0] io_f_hi_lo = {f_17,f_16,f_15,f_14,f_13,f_12}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [12:0] io_f_hi = {f_24,f_23,f_22,f_21,f_20,f_19,f_18,io_f_hi_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  assign io_f = {io_f_hi,io_f_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
endmodule
module CLZ(
  input  [24:0] io_in, // @[src/main/scala/fudian/utils/CLZ.scala 12:14]
  output [4:0]  io_out // @[src/main/scala/fudian/utils/CLZ.scala 12:14]
);
  wire [4:0] _io_out_T_25 = io_in[1] ? 5'h17 : 5'h18; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_26 = io_in[2] ? 5'h16 : _io_out_T_25; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_27 = io_in[3] ? 5'h15 : _io_out_T_26; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_28 = io_in[4] ? 5'h14 : _io_out_T_27; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_29 = io_in[5] ? 5'h13 : _io_out_T_28; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_30 = io_in[6] ? 5'h12 : _io_out_T_29; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_31 = io_in[7] ? 5'h11 : _io_out_T_30; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_32 = io_in[8] ? 5'h10 : _io_out_T_31; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_33 = io_in[9] ? 5'hf : _io_out_T_32; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_34 = io_in[10] ? 5'he : _io_out_T_33; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_35 = io_in[11] ? 5'hd : _io_out_T_34; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_36 = io_in[12] ? 5'hc : _io_out_T_35; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_37 = io_in[13] ? 5'hb : _io_out_T_36; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_38 = io_in[14] ? 5'ha : _io_out_T_37; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_39 = io_in[15] ? 5'h9 : _io_out_T_38; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_40 = io_in[16] ? 5'h8 : _io_out_T_39; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_41 = io_in[17] ? 5'h7 : _io_out_T_40; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_42 = io_in[18] ? 5'h6 : _io_out_T_41; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_43 = io_in[19] ? 5'h5 : _io_out_T_42; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_44 = io_in[20] ? 5'h4 : _io_out_T_43; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_45 = io_in[21] ? 5'h3 : _io_out_T_44; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_46 = io_in[22] ? 5'h2 : _io_out_T_45; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [4:0] _io_out_T_47 = io_in[23] ? 5'h1 : _io_out_T_46; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  assign io_out = io_in[24] ? 5'h0 : _io_out_T_47; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
endmodule
module NearPath(
  input         io_in_a_sign, // @[src/main/scala/fudian/FADD.scala 84:14]
  input  [7:0]  io_in_a_exp, // @[src/main/scala/fudian/FADD.scala 84:14]
  input  [23:0] io_in_a_sig, // @[src/main/scala/fudian/FADD.scala 84:14]
  input         io_in_b_sign, // @[src/main/scala/fudian/FADD.scala 84:14]
  input  [23:0] io_in_b_sig, // @[src/main/scala/fudian/FADD.scala 84:14]
  input         io_in_need_shift_b, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_result_sign, // @[src/main/scala/fudian/FADD.scala 84:14]
  output [7:0]  io_out_result_exp, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_sig_is_zero, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_a_lt_b, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_lza_error, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_int_bit, // @[src/main/scala/fudian/FADD.scala 84:14]
  output [24:0] io_out_sig_raw, // @[src/main/scala/fudian/FADD.scala 84:14]
  output [4:0]  io_out_lzc // @[src/main/scala/fudian/FADD.scala 84:14]
);
  wire [24:0] lza_ab_io_a; // @[src/main/scala/fudian/FADD.scala 109:22]
  wire [24:0] lza_ab_io_b; // @[src/main/scala/fudian/FADD.scala 109:22]
  wire [24:0] lza_ab_io_f; // @[src/main/scala/fudian/FADD.scala 109:22]
  wire [24:0] lzc_clz_io_in; // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
  wire [4:0] lzc_clz_io_out; // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
  wire [24:0] _b_sig_T = {io_in_b_sig,1'h0}; // @[src/main/scala/fudian/FADD.scala 103:19]
  wire [24:0] b_sig = _b_sig_T >> io_in_need_shift_b; // @[src/main/scala/fudian/FADD.scala 103:37]
  wire [24:0] b_neg = ~b_sig; // @[src/main/scala/fudian/FADD.scala 104:16]
  wire [25:0] _a_minus_b_T = {1'h0,io_in_a_sig,1'h0}; // @[src/main/scala/fudian/FADD.scala 106:22]
  wire [25:0] _a_minus_b_T_1 = {1'h1,b_neg}; // @[src/main/scala/fudian/FADD.scala 106:45]
  wire [25:0] _a_minus_b_T_3 = _a_minus_b_T + _a_minus_b_T_1; // @[src/main/scala/fudian/FADD.scala 106:40]
  wire [25:0] a_minus_b = _a_minus_b_T_3 + 26'h1; // @[src/main/scala/fudian/FADD.scala 106:63]
  wire  a_lt_b = a_minus_b[25]; // @[src/main/scala/fudian/FADD.scala 107:30]
  wire [24:0] sig_raw = a_minus_b[24:0]; // @[src/main/scala/fudian/FADD.scala 108:31]
  wire  lza_str_zero = ~(|lza_ab_io_f); // @[src/main/scala/fudian/FADD.scala 113:22]
  wire  need_shift_lim = io_in_a_exp < 8'h19; // @[src/main/scala/fudian/FADD.scala 116:30]
  wire [25:0] _shift_lim_mask_raw_T_2 = 26'h2000000 >> io_in_a_exp[4:0]; // @[src/main/scala/fudian/FADD.scala 119:41]
  wire [24:0] shift_lim_mask_raw = _shift_lim_mask_raw_T_2[24:0]; // @[src/main/scala/fudian/FADD.scala 120:14]
  wire [24:0] shift_lim_mask = need_shift_lim ? shift_lim_mask_raw : 25'h0; // @[src/main/scala/fudian/FADD.scala 121:27]
  wire [24:0] _shift_lim_bit_T = shift_lim_mask_raw & sig_raw; // @[src/main/scala/fudian/FADD.scala 122:43]
  wire  shift_lim_bit = |_shift_lim_bit_T; // @[src/main/scala/fudian/FADD.scala 122:54]
  wire [24:0] lzc_str = shift_lim_mask | lza_ab_io_f; // @[src/main/scala/fudian/FADD.scala 124:32]
  wire  _int_bit_mask_T_5 = lzc_str[23] & ~(|lzc_str[24]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_10 = lzc_str[22] & ~(|lzc_str[24:23]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_15 = lzc_str[21] & ~(|lzc_str[24:22]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_20 = lzc_str[20] & ~(|lzc_str[24:21]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_25 = lzc_str[19] & ~(|lzc_str[24:20]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_30 = lzc_str[18] & ~(|lzc_str[24:19]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_35 = lzc_str[17] & ~(|lzc_str[24:18]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_40 = lzc_str[16] & ~(|lzc_str[24:17]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_45 = lzc_str[15] & ~(|lzc_str[24:16]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_50 = lzc_str[14] & ~(|lzc_str[24:15]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_55 = lzc_str[13] & ~(|lzc_str[24:14]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_60 = lzc_str[12] & ~(|lzc_str[24:13]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_65 = lzc_str[11] & ~(|lzc_str[24:12]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_70 = lzc_str[10] & ~(|lzc_str[24:11]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_75 = lzc_str[9] & ~(|lzc_str[24:10]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_80 = lzc_str[8] & ~(|lzc_str[24:9]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_85 = lzc_str[7] & ~(|lzc_str[24:8]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_90 = lzc_str[6] & ~(|lzc_str[24:7]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_95 = lzc_str[5] & ~(|lzc_str[24:6]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_100 = lzc_str[4] & ~(|lzc_str[24:5]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_105 = lzc_str[3] & ~(|lzc_str[24:4]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_110 = lzc_str[2] & ~(|lzc_str[24:3]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_115 = lzc_str[1] & ~(|lzc_str[24:2]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_120 = lzc_str[0] & ~(|lzc_str[24:1]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire [5:0] int_bit_mask_lo_lo = {_int_bit_mask_T_95,_int_bit_mask_T_100,_int_bit_mask_T_105,_int_bit_mask_T_110,
    _int_bit_mask_T_115,_int_bit_mask_T_120}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [11:0] int_bit_mask_lo = {_int_bit_mask_T_65,_int_bit_mask_T_70,_int_bit_mask_T_75,_int_bit_mask_T_80,
    _int_bit_mask_T_85,_int_bit_mask_T_90,int_bit_mask_lo_lo}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [5:0] int_bit_mask_hi_lo = {_int_bit_mask_T_35,_int_bit_mask_T_40,_int_bit_mask_T_45,_int_bit_mask_T_50,
    _int_bit_mask_T_55,_int_bit_mask_T_60}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [24:0] int_bit_mask = {lzc_str[24],_int_bit_mask_T_5,_int_bit_mask_T_10,_int_bit_mask_T_15,_int_bit_mask_T_20,
    _int_bit_mask_T_25,_int_bit_mask_T_30,int_bit_mask_hi_lo,int_bit_mask_lo}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [24:0] _GEN_0 = {{24'd0}, lza_str_zero}; // @[src/main/scala/fudian/FADD.scala 133:20]
  wire [24:0] _int_bit_predicted_T = int_bit_mask | _GEN_0; // @[src/main/scala/fudian/FADD.scala 133:20]
  wire [24:0] _int_bit_predicted_T_1 = _int_bit_predicted_T & sig_raw; // @[src/main/scala/fudian/FADD.scala 133:36]
  wire  int_bit_predicted = |_int_bit_predicted_T_1; // @[src/main/scala/fudian/FADD.scala 133:47]
  wire [24:0] _int_bit_rshift_1_T = {{1'd0}, int_bit_mask[24:1]}; // @[src/main/scala/fudian/FADD.scala 135:20]
  wire [24:0] _int_bit_rshift_1_T_1 = _int_bit_rshift_1_T & sig_raw; // @[src/main/scala/fudian/FADD.scala 135:35]
  wire  int_bit_rshift_1 = |_int_bit_rshift_1_T_1; // @[src/main/scala/fudian/FADD.scala 135:46]
  wire  _exceed_lim_mask_T_1 = |lza_ab_io_f[24]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_3 = |lza_ab_io_f[24:23]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_5 = |lza_ab_io_f[24:22]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_7 = |lza_ab_io_f[24:21]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_9 = |lza_ab_io_f[24:20]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_11 = |lza_ab_io_f[24:19]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_13 = |lza_ab_io_f[24:18]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_15 = |lza_ab_io_f[24:17]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_17 = |lza_ab_io_f[24:16]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_19 = |lza_ab_io_f[24:15]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_21 = |lza_ab_io_f[24:14]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_23 = |lza_ab_io_f[24:13]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_25 = |lza_ab_io_f[24:12]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_27 = |lza_ab_io_f[24:11]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_29 = |lza_ab_io_f[24:10]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_31 = |lza_ab_io_f[24:9]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_33 = |lza_ab_io_f[24:8]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_35 = |lza_ab_io_f[24:7]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_37 = |lza_ab_io_f[24:6]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_39 = |lza_ab_io_f[24:5]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_41 = |lza_ab_io_f[24:4]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_43 = |lza_ab_io_f[24:3]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_45 = |lza_ab_io_f[24:2]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_47 = |lza_ab_io_f[24:1]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire [5:0] exceed_lim_mask_lo_lo = {_exceed_lim_mask_T_37,_exceed_lim_mask_T_39,_exceed_lim_mask_T_41,
    _exceed_lim_mask_T_43,_exceed_lim_mask_T_45,_exceed_lim_mask_T_47}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [11:0] exceed_lim_mask_lo = {_exceed_lim_mask_T_25,_exceed_lim_mask_T_27,_exceed_lim_mask_T_29,
    _exceed_lim_mask_T_31,_exceed_lim_mask_T_33,_exceed_lim_mask_T_35,exceed_lim_mask_lo_lo}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [5:0] exceed_lim_mask_hi_lo = {_exceed_lim_mask_T_13,_exceed_lim_mask_T_15,_exceed_lim_mask_T_17,
    _exceed_lim_mask_T_19,_exceed_lim_mask_T_21,_exceed_lim_mask_T_23}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [24:0] exceed_lim_mask = {1'h0,_exceed_lim_mask_T_1,_exceed_lim_mask_T_3,_exceed_lim_mask_T_5,
    _exceed_lim_mask_T_7,_exceed_lim_mask_T_9,_exceed_lim_mask_T_11,exceed_lim_mask_hi_lo,exceed_lim_mask_lo}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [24:0] _exceed_lim_T = exceed_lim_mask & shift_lim_mask_raw; // @[src/main/scala/fudian/FADD.scala 142:41]
  wire  exceed_lim = need_shift_lim & ~(|_exceed_lim_T); // @[src/main/scala/fudian/FADD.scala 142:20]
  LZA lza_ab ( // @[src/main/scala/fudian/FADD.scala 109:22]
    .io_a(lza_ab_io_a),
    .io_b(lza_ab_io_b),
    .io_f(lza_ab_io_f)
  );
  CLZ lzc_clz ( // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
    .io_in(lzc_clz_io_in),
    .io_out(lzc_clz_io_out)
  );
  assign io_out_result_sign = a_lt_b ? io_in_b_sign : io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 166:27]
  assign io_out_result_exp = io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 168:20 170:14]
  assign io_out_sig_is_zero = lza_str_zero & ~sig_raw[0]; // @[src/main/scala/fudian/FADD.scala 173:38]
  assign io_out_a_lt_b = a_minus_b[25]; // @[src/main/scala/fudian/FADD.scala 107:30]
  assign io_out_lza_error = ~int_bit_predicted & ~exceed_lim; // @[src/main/scala/fudian/FADD.scala 147:38]
  assign io_out_int_bit = exceed_lim ? shift_lim_bit : int_bit_rshift_1 | int_bit_predicted; // @[src/main/scala/fudian/FADD.scala 145:8]
  assign io_out_sig_raw = a_minus_b[24:0]; // @[src/main/scala/fudian/FADD.scala 108:31]
  assign io_out_lzc = lzc_clz_io_out; // @[src/main/scala/fudian/FADD.scala 177:14]
  assign lza_ab_io_a = {io_in_a_sig,1'h0}; // @[src/main/scala/fudian/FADD.scala 102:18]
  assign lza_ab_io_b = ~b_sig; // @[src/main/scala/fudian/FADD.scala 104:16]
  assign lzc_clz_io_in = shift_lim_mask | lza_ab_io_f; // @[src/main/scala/fudian/FADD.scala 124:32]
endmodule
module FCMA_ADD_s1(
  input  [31:0] io_a, // @[src/main/scala/fudian/FADD.scala 185:14]
  input  [31:0] io_b, // @[src/main/scala/fudian/FADD.scala 185:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [2:0]  io_out_rm, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_far_path_out_sign, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_out_sign, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_near_path_out_exp, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_special_case_valid, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_special_case_bits_iv, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_special_case_bits_nan, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_special_case_bits_inf_sign, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_small_add, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_far_path_mul_of, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [23:0] io_out_far_sig_a, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [27:0] io_out_far_sig_b, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_far_exp_a_vec_0, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_far_exp_a_vec_1, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_far_exp_a_vec_2, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_sig_is_zero, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_lza_error, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_int_bit, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [24:0] io_out_near_path_sig_raw, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [4:0]  io_out_near_path_lzc, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_sel_far_path // @[src/main/scala/fudian/FADD.scala 185:14]
);
  wire  far_path_mods_0_io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [23:0] far_path_mods_0_io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [23:0] far_path_mods_0_io_in_b_sig; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_in_expDiff; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire  far_path_mods_0_io_in_effSub; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire  far_path_mods_0_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [23:0] far_path_mods_0_io_out_sig_a; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [27:0] far_path_mods_0_io_out_sig_b; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_out_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_out_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_out_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire  near_path_mods_0_io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_0_io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [23:0] near_path_mods_0_io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_in_b_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [23:0] near_path_mods_0_io_in_b_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_in_need_shift_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_0_io_out_result_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_a_lt_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_lza_error; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_int_bit; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [24:0] near_path_mods_0_io_out_sig_raw; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [4:0] near_path_mods_0_io_out_lzc; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_1_io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [23:0] near_path_mods_1_io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_in_b_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [23:0] near_path_mods_1_io_in_b_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_in_need_shift_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_1_io_out_result_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_a_lt_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_lza_error; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_int_bit; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [24:0] near_path_mods_1_io_out_sig_raw; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [4:0] near_path_mods_1_io_out_lzc; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  fp_a_sign = io_a[31]; // @[src/main/scala/fudian/package.scala 59:19]
  wire [7:0] fp_a_exp = io_a[30:23]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [22:0] fp_a_sig = io_a[22:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  fp_b_sign = io_b[31]; // @[src/main/scala/fudian/package.scala 59:19]
  wire [7:0] fp_b_exp = io_b[30:23]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [22:0] fp_b_sig = io_b[22:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  decode_a_expNotZero = |fp_a_exp; // @[src/main/scala/fudian/package.scala 32:28]
  wire  decode_a_expIsOnes = &fp_a_exp; // @[src/main/scala/fudian/package.scala 33:27]
  wire  decode_a_sigNotZero = |fp_a_sig; // @[src/main/scala/fudian/package.scala 34:28]
  wire  decode_a__expIsZero = ~decode_a_expNotZero; // @[src/main/scala/fudian/package.scala 37:27]
  wire  decode_a__sigIsZero = ~decode_a_sigNotZero; // @[src/main/scala/fudian/package.scala 40:27]
  wire  decode_a__isInf = decode_a_expIsOnes & decode_a__sigIsZero; // @[src/main/scala/fudian/package.scala 42:40]
  wire  decode_a__isNaN = decode_a_expIsOnes & decode_a_sigNotZero; // @[src/main/scala/fudian/package.scala 44:40]
  wire  decode_a__isSNaN = decode_a__isNaN & ~fp_a_sig[22]; // @[src/main/scala/fudian/package.scala 45:37]
  wire  decode_b_expNotZero = |fp_b_exp; // @[src/main/scala/fudian/package.scala 32:28]
  wire  decode_b_expIsOnes = &fp_b_exp; // @[src/main/scala/fudian/package.scala 33:27]
  wire  decode_b_sigNotZero = |fp_b_sig; // @[src/main/scala/fudian/package.scala 34:28]
  wire  decode_b__expIsZero = ~decode_b_expNotZero; // @[src/main/scala/fudian/package.scala 37:27]
  wire  decode_b__sigIsZero = ~decode_b_sigNotZero; // @[src/main/scala/fudian/package.scala 40:27]
  wire  decode_b__isInf = decode_b_expIsOnes & decode_b__sigIsZero; // @[src/main/scala/fudian/package.scala 42:40]
  wire  decode_b__isNaN = decode_b_expIsOnes & decode_b_sigNotZero; // @[src/main/scala/fudian/package.scala 44:40]
  wire  decode_b__isSNaN = decode_b__isNaN & ~fp_b_sig[22]; // @[src/main/scala/fudian/package.scala 45:37]
  wire [7:0] _GEN_0 = {{7'd0}, decode_a__expIsZero}; // @[src/main/scala/fudian/package.scala 83:27]
  wire [7:0] raw_a_exp = fp_a_exp | _GEN_0; // @[src/main/scala/fudian/package.scala 83:27]
  wire [23:0] raw_a_sig = {decode_a_expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire [7:0] _GEN_1 = {{7'd0}, decode_b__expIsZero}; // @[src/main/scala/fudian/package.scala 83:27]
  wire [7:0] raw_b_exp = fp_b_exp | _GEN_1; // @[src/main/scala/fudian/package.scala 83:27]
  wire [23:0] raw_b_sig = {decode_b_expNotZero,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire  eff_sub = fp_a_sign ^ fp_b_sign; // @[src/main/scala/fudian/FADD.scala 199:28]
  wire  special_path_hasNaN = decode_a__isNaN | decode_b__isNaN; // @[src/main/scala/fudian/FADD.scala 210:44]
  wire  special_path_hasSNaN = decode_a__isSNaN | decode_b__isSNaN; // @[src/main/scala/fudian/FADD.scala 211:46]
  wire  special_path_hasInf = decode_a__isInf | decode_b__isInf; // @[src/main/scala/fudian/FADD.scala 212:44]
  wire  special_path_inf_iv = decode_a__isInf & decode_b__isInf & eff_sub; // @[src/main/scala/fudian/FADD.scala 213:55]
  wire [8:0] _exp_diff_a_b_T = {1'h0,raw_a_exp}; // @[src/main/scala/fudian/FADD.scala 218:25]
  wire [8:0] _exp_diff_a_b_T_1 = {1'h0,raw_b_exp}; // @[src/main/scala/fudian/FADD.scala 218:52]
  wire [8:0] exp_diff_a_b = _exp_diff_a_b_T - _exp_diff_a_b_T_1; // @[src/main/scala/fudian/FADD.scala 218:47]
  wire [8:0] exp_diff_b_a = _exp_diff_a_b_T_1 - _exp_diff_a_b_T; // @[src/main/scala/fudian/FADD.scala 219:47]
  wire  need_swap = exp_diff_a_b[8]; // @[src/main/scala/fudian/FADD.scala 221:36]
  wire [7:0] ea_minus_eb = need_swap ? exp_diff_b_a[7:0] : exp_diff_a_b[7:0]; // @[src/main/scala/fudian/FADD.scala 223:24]
  wire  _sel_far_path_T = ~eff_sub; // @[src/main/scala/fudian/FADD.scala 224:22]
  wire  _T = ~need_swap; // @[src/main/scala/fudian/FADD.scala 232:11]
  wire [8:0] _T_5 = _T ? exp_diff_a_b : exp_diff_b_a; // @[src/main/scala/fudian/FADD.scala 234:10]
  wire  near_path_exp_neq = raw_a_exp[1:0] != raw_b_exp[1:0]; // @[src/main/scala/fudian/FADD.scala 256:43]
  wire  _near_path_out_T_2 = need_swap | ~near_path_exp_neq & near_path_mods_0_io_out_a_lt_b; // @[src/main/scala/fudian/FADD.scala 273:15]
  FarPath far_path_mods_0 ( // @[src/main/scala/fudian/FADD.scala 239:26]
    .io_in_a_sign(far_path_mods_0_io_in_a_sign),
    .io_in_a_exp(far_path_mods_0_io_in_a_exp),
    .io_in_a_sig(far_path_mods_0_io_in_a_sig),
    .io_in_b_sig(far_path_mods_0_io_in_b_sig),
    .io_in_expDiff(far_path_mods_0_io_in_expDiff),
    .io_in_effSub(far_path_mods_0_io_in_effSub),
    .io_out_result_sign(far_path_mods_0_io_out_result_sign),
    .io_out_sig_a(far_path_mods_0_io_out_sig_a),
    .io_out_sig_b(far_path_mods_0_io_out_sig_b),
    .io_out_exp_a_vec_0(far_path_mods_0_io_out_exp_a_vec_0),
    .io_out_exp_a_vec_1(far_path_mods_0_io_out_exp_a_vec_1),
    .io_out_exp_a_vec_2(far_path_mods_0_io_out_exp_a_vec_2)
  );
  NearPath near_path_mods_0 ( // @[src/main/scala/fudian/FADD.scala 263:27]
    .io_in_a_sign(near_path_mods_0_io_in_a_sign),
    .io_in_a_exp(near_path_mods_0_io_in_a_exp),
    .io_in_a_sig(near_path_mods_0_io_in_a_sig),
    .io_in_b_sign(near_path_mods_0_io_in_b_sign),
    .io_in_b_sig(near_path_mods_0_io_in_b_sig),
    .io_in_need_shift_b(near_path_mods_0_io_in_need_shift_b),
    .io_out_result_sign(near_path_mods_0_io_out_result_sign),
    .io_out_result_exp(near_path_mods_0_io_out_result_exp),
    .io_out_sig_is_zero(near_path_mods_0_io_out_sig_is_zero),
    .io_out_a_lt_b(near_path_mods_0_io_out_a_lt_b),
    .io_out_lza_error(near_path_mods_0_io_out_lza_error),
    .io_out_int_bit(near_path_mods_0_io_out_int_bit),
    .io_out_sig_raw(near_path_mods_0_io_out_sig_raw),
    .io_out_lzc(near_path_mods_0_io_out_lzc)
  );
  NearPath near_path_mods_1 ( // @[src/main/scala/fudian/FADD.scala 263:27]
    .io_in_a_sign(near_path_mods_1_io_in_a_sign),
    .io_in_a_exp(near_path_mods_1_io_in_a_exp),
    .io_in_a_sig(near_path_mods_1_io_in_a_sig),
    .io_in_b_sign(near_path_mods_1_io_in_b_sign),
    .io_in_b_sig(near_path_mods_1_io_in_b_sig),
    .io_in_need_shift_b(near_path_mods_1_io_in_need_shift_b),
    .io_out_result_sign(near_path_mods_1_io_out_result_sign),
    .io_out_result_exp(near_path_mods_1_io_out_result_exp),
    .io_out_sig_is_zero(near_path_mods_1_io_out_sig_is_zero),
    .io_out_a_lt_b(near_path_mods_1_io_out_a_lt_b),
    .io_out_lza_error(near_path_mods_1_io_out_lza_error),
    .io_out_int_bit(near_path_mods_1_io_out_int_bit),
    .io_out_sig_raw(near_path_mods_1_io_out_sig_raw),
    .io_out_lzc(near_path_mods_1_io_out_lzc)
  );
  assign io_out_rm = io_rm; // @[src/main/scala/fudian/FADD.scala 278:13]
  assign io_out_far_path_out_sign = far_path_mods_0_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 282:23]
  assign io_out_near_path_out_sign = _near_path_out_T_2 ? near_path_mods_1_io_out_result_sign :
    near_path_mods_0_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_near_path_out_exp = _near_path_out_T_2 ? near_path_mods_1_io_out_result_exp :
    near_path_mods_0_io_out_result_exp; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_special_case_valid = special_path_hasNaN | special_path_hasInf; // @[src/main/scala/fudian/FADD.scala 215:49]
  assign io_out_special_case_bits_iv = special_path_hasSNaN | special_path_inf_iv; // @[src/main/scala/fudian/FADD.scala 216:46]
  assign io_out_special_case_bits_nan = special_path_hasNaN | special_path_inf_iv; // @[src/main/scala/fudian/FADD.scala 298:55]
  assign io_out_special_case_bits_inf_sign = decode_a__isInf ? fp_a_sign : fp_b_sign; // @[src/main/scala/fudian/FADD.scala 299:43]
  assign io_out_small_add = decode_a__expIsZero & decode_b__expIsZero; // @[src/main/scala/fudian/FADD.scala 201:38]
  assign io_out_far_path_mul_of = decode_b_expIsOnes & _sel_far_path_T; // @[src/main/scala/fudian/FADD.scala 283:69]
  assign io_out_far_sig_a = far_path_mods_0_io_out_sig_a; // @[src/main/scala/fudian/FADD.scala 284:20]
  assign io_out_far_sig_b = far_path_mods_0_io_out_sig_b; // @[src/main/scala/fudian/FADD.scala 285:20]
  assign io_out_far_exp_a_vec_0 = far_path_mods_0_io_out_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 287:24]
  assign io_out_far_exp_a_vec_1 = far_path_mods_0_io_out_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 287:24]
  assign io_out_far_exp_a_vec_2 = far_path_mods_0_io_out_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 287:24]
  assign io_out_near_path_sig_is_zero = _near_path_out_T_2 ? near_path_mods_1_io_out_sig_is_zero :
    near_path_mods_0_io_out_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_near_path_lza_error = _near_path_out_T_2 ? near_path_mods_1_io_out_lza_error :
    near_path_mods_0_io_out_lza_error; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_near_path_int_bit = _near_path_out_T_2 ? near_path_mods_1_io_out_int_bit :
    near_path_mods_0_io_out_int_bit; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_near_path_sig_raw = _near_path_out_T_2 ? near_path_mods_1_io_out_sig_raw :
    near_path_mods_0_io_out_sig_raw; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_near_path_lzc = _near_path_out_T_2 ? near_path_mods_1_io_out_lzc : near_path_mods_0_io_out_lzc; // @[src/main/scala/fudian/FADD.scala 272:26]
  assign io_out_sel_far_path = ~eff_sub | ea_minus_eb > 8'h1; // @[src/main/scala/fudian/FADD.scala 224:31]
  assign far_path_mods_0_io_in_a_sign = ~need_swap ? fp_a_sign : fp_b_sign; // @[src/main/scala/fudian/FADD.scala 232:10]
  assign far_path_mods_0_io_in_a_exp = ~need_swap ? raw_a_exp : raw_b_exp; // @[src/main/scala/fudian/FADD.scala 232:10]
  assign far_path_mods_0_io_in_a_sig = ~need_swap ? raw_a_sig : raw_b_sig; // @[src/main/scala/fudian/FADD.scala 232:10]
  assign far_path_mods_0_io_in_b_sig = _T ? raw_b_sig : raw_a_sig; // @[src/main/scala/fudian/FADD.scala 233:10]
  assign far_path_mods_0_io_in_expDiff = _T_5[7:0]; // @[src/main/scala/fudian/FADD.scala 242:28]
  assign far_path_mods_0_io_in_effSub = fp_a_sign ^ fp_b_sign; // @[src/main/scala/fudian/FADD.scala 199:28]
  assign near_path_mods_0_io_in_a_sign = io_a[31]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_0_io_in_a_exp = fp_a_exp | _GEN_0; // @[src/main/scala/fudian/package.scala 83:27]
  assign near_path_mods_0_io_in_a_sig = {decode_a_expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_0_io_in_b_sign = io_b[31]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_0_io_in_b_sig = {decode_b_expNotZero,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_0_io_in_need_shift_b = raw_a_exp[1:0] != raw_b_exp[1:0]; // @[src/main/scala/fudian/FADD.scala 256:43]
  assign near_path_mods_1_io_in_a_sign = io_b[31]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_1_io_in_a_exp = fp_b_exp | _GEN_1; // @[src/main/scala/fudian/package.scala 83:27]
  assign near_path_mods_1_io_in_a_sig = {decode_b_expNotZero,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_1_io_in_b_sign = io_a[31]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_1_io_in_b_sig = {decode_a_expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_1_io_in_need_shift_b = raw_a_exp[1:0] != raw_b_exp[1:0]; // @[src/main/scala/fudian/FADD.scala 256:43]
endmodule
module RoundingUnit(
  input  [22:0] io_in, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  input         io_roundIn, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  input         io_stickyIn, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  input         io_signIn, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  output [22:0] io_out, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  output        io_inexact, // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
  output        io_cout // @[src/main/scala/fudian/RoundingUnit.scala 7:14]
);
  wire  g = io_in[0]; // @[src/main/scala/fudian/RoundingUnit.scala 19:25]
  wire  inexact = io_roundIn | io_stickyIn; // @[src/main/scala/fudian/RoundingUnit.scala 20:19]
  wire  _r_up_T_4 = io_roundIn & io_stickyIn | io_roundIn & ~io_stickyIn & g; // @[src/main/scala/fudian/RoundingUnit.scala 25:24]
  wire  _r_up_T_6 = inexact & ~io_signIn; // @[src/main/scala/fudian/RoundingUnit.scala 27:23]
  wire  _r_up_T_7 = inexact & io_signIn; // @[src/main/scala/fudian/RoundingUnit.scala 28:23]
  wire  _r_up_T_11 = 3'h1 == io_rm ? 1'h0 : 3'h0 == io_rm & _r_up_T_4; // @[src/main/scala/fudian/RoundingUnit.scala 23:13]
  wire  _r_up_T_13 = 3'h3 == io_rm ? _r_up_T_6 : _r_up_T_11; // @[src/main/scala/fudian/RoundingUnit.scala 23:13]
  wire  _r_up_T_15 = 3'h2 == io_rm ? _r_up_T_7 : _r_up_T_13; // @[src/main/scala/fudian/RoundingUnit.scala 23:13]
  wire  r_up = 3'h4 == io_rm ? io_roundIn : _r_up_T_15; // @[src/main/scala/fudian/RoundingUnit.scala 23:13]
  wire [22:0] out_r_up = io_in + 23'h1; // @[src/main/scala/fudian/RoundingUnit.scala 32:24]
  assign io_out = r_up ? out_r_up : io_in; // @[src/main/scala/fudian/RoundingUnit.scala 33:16]
  assign io_inexact = io_roundIn | io_stickyIn; // @[src/main/scala/fudian/RoundingUnit.scala 20:19]
  assign io_cout = r_up & &io_in; // @[src/main/scala/fudian/RoundingUnit.scala 36:19]
endmodule
module TininessRounder(
  input         io_in_sign, // @[src/main/scala/fudian/RoundingUnit.scala 60:14]
  input  [26:0] io_in_sig, // @[src/main/scala/fudian/RoundingUnit.scala 60:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/RoundingUnit.scala 60:14]
  output        io_tininess // @[src/main/scala/fudian/RoundingUnit.scala 60:14]
);
  wire [22:0] rounder_io_in; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_roundIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_stickyIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_signIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [2:0] rounder_io_rm; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [22:0] rounder_io_out; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_inexact; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_cout; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  _tininess_T_5 = io_in_sig[26:25] == 2'h1 & ~rounder_io_cout; // @[src/main/scala/fudian/RoundingUnit.scala 74:41]
  RoundingUnit rounder ( // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
    .io_in(rounder_io_in),
    .io_roundIn(rounder_io_roundIn),
    .io_stickyIn(rounder_io_stickyIn),
    .io_signIn(rounder_io_signIn),
    .io_rm(rounder_io_rm),
    .io_out(rounder_io_out),
    .io_inexact(rounder_io_inexact),
    .io_cout(rounder_io_cout)
  );
  assign io_tininess = io_in_sig[26:25] == 2'h0 | _tininess_T_5; // @[src/main/scala/fudian/RoundingUnit.scala 73:53]
  assign rounder_io_in = io_in_sig[24:2]; // @[src/main/scala/fudian/RoundingUnit.scala 45:33]
  assign rounder_io_roundIn = io_in_sig[1]; // @[src/main/scala/fudian/RoundingUnit.scala 46:50]
  assign rounder_io_stickyIn = |io_in_sig[0]; // @[src/main/scala/fudian/RoundingUnit.scala 47:51]
  assign rounder_io_signIn = io_in_sign; // @[src/main/scala/fudian/RoundingUnit.scala 49:23]
  assign rounder_io_rm = io_rm; // @[src/main/scala/fudian/RoundingUnit.scala 48:19]
endmodule
module FCMA_ADD_s2(
  input  [2:0]  io_in_rm, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_far_path_out_sign, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_out_sign, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_near_path_out_exp, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_special_case_valid, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_special_case_bits_iv, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_special_case_bits_nan, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_special_case_bits_inf_sign, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_small_add, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_far_path_mul_of, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [23:0] io_in_far_sig_a, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [27:0] io_in_far_sig_b, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_far_exp_a_vec_0, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_far_exp_a_vec_1, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_far_exp_a_vec_2, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_sig_is_zero, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_lza_error, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_int_bit, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [24:0] io_in_near_path_sig_raw, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [4:0]  io_in_near_path_lzc, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_sel_far_path, // @[src/main/scala/fudian/FADD.scala 336:14]
  output [31:0] io_result, // @[src/main/scala/fudian/FADD.scala 336:14]
  output [4:0]  io_fflags // @[src/main/scala/fudian/FADD.scala 336:14]
);
  wire  far_path_tininess_rounder_io_in_sign; // @[src/main/scala/fudian/FADD.scala 386:41]
  wire [26:0] far_path_tininess_rounder_io_in_sig; // @[src/main/scala/fudian/FADD.scala 386:41]
  wire [2:0] far_path_tininess_rounder_io_rm; // @[src/main/scala/fudian/FADD.scala 386:41]
  wire  far_path_tininess_rounder_io_tininess; // @[src/main/scala/fudian/FADD.scala 386:41]
  wire [22:0] far_path_rounder_io_in; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  far_path_rounder_io_roundIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  far_path_rounder_io_stickyIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  far_path_rounder_io_signIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [2:0] far_path_rounder_io_rm; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [22:0] far_path_rounder_io_out; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  far_path_rounder_io_inexact; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  far_path_rounder_io_cout; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  near_path_tininess_rounder_io_in_sign; // @[src/main/scala/fudian/FADD.scala 445:42]
  wire [26:0] near_path_tininess_rounder_io_in_sig; // @[src/main/scala/fudian/FADD.scala 445:42]
  wire [2:0] near_path_tininess_rounder_io_rm; // @[src/main/scala/fudian/FADD.scala 445:42]
  wire  near_path_tininess_rounder_io_tininess; // @[src/main/scala/fudian/FADD.scala 445:42]
  wire [22:0] near_path_rounder_io_in; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  near_path_rounder_io_roundIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  near_path_rounder_io_stickyIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  near_path_rounder_io_signIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [2:0] near_path_rounder_io_rm; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [22:0] near_path_rounder_io_out; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  near_path_rounder_io_inexact; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  near_path_rounder_io_cout; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [31:0] _special_path_result_T_3 = {io_in_special_case_bits_inf_sign,8'hff,23'h0}; // @[src/main/scala/fudian/FADD.scala 349:8]
  wire [31:0] special_path_result = io_in_special_case_bits_nan ? 32'h7fc00000 : _special_path_result_T_3; // @[src/main/scala/fudian/FADD.scala 346:32]
  wire [4:0] special_path_fflags = {io_in_special_case_bits_iv,4'h0}; // @[src/main/scala/fudian/FADD.scala 356:32]
  wire [27:0] adder_in_sig_a = {1'h0,io_in_far_sig_a,3'h0}; // @[src/main/scala/fudian/FADD.scala 362:27]
  wire [27:0] adder_result = adder_in_sig_a + io_in_far_sig_b; // @[src/main/scala/fudian/FADD.scala 363:37]
  wire  cout = adder_result[27]; // @[src/main/scala/fudian/FADD.scala 365:31]
  wire  keep = adder_result[27:26] == 2'h1; // @[src/main/scala/fudian/FADD.scala 366:35]
  wire  cancellation = adder_result[27:26] == 2'h0; // @[src/main/scala/fudian/FADD.scala 367:43]
  wire  _far_path_res_sig_T = keep | io_in_small_add; // @[src/main/scala/fudian/FADD.scala 370:20]
  wire  _far_path_res_sig_T_2 = cancellation & ~io_in_small_add; // @[src/main/scala/fudian/FADD.scala 370:47]
  wire [26:0] _far_path_res_sig_T_6 = {adder_result[27:2],|adder_result[1:0]}; // @[src/main/scala/fudian/FADD.scala 372:36]
  wire [26:0] _far_path_res_sig_T_11 = {adder_result[26:1],|adder_result[0]}; // @[src/main/scala/fudian/FADD.scala 373:44]
  wire [26:0] _far_path_res_sig_T_16 = {adder_result[25:0],1'h0}; // @[src/main/scala/fudian/FADD.scala 374:44]
  wire [26:0] _far_path_res_sig_T_17 = cout ? _far_path_res_sig_T_6 : 27'h0; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [26:0] _far_path_res_sig_T_18 = _far_path_res_sig_T ? _far_path_res_sig_T_11 : 27'h0; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [26:0] _far_path_res_sig_T_19 = _far_path_res_sig_T_2 ? _far_path_res_sig_T_16 : 27'h0; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [26:0] _far_path_res_sig_T_20 = _far_path_res_sig_T_17 | _far_path_res_sig_T_18; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [26:0] far_path_res_sig = _far_path_res_sig_T_20 | _far_path_res_sig_T_19; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [7:0] _far_path_res_exp_T = cout ? io_in_far_exp_a_vec_0 : 8'h0; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [7:0] _far_path_res_exp_T_1 = keep ? io_in_far_exp_a_vec_1 : 8'h0; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [7:0] _far_path_res_exp_T_2 = cancellation ? io_in_far_exp_a_vec_2 : 8'h0; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [7:0] _far_path_res_exp_T_3 = _far_path_res_exp_T | _far_path_res_exp_T_1; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire [7:0] far_path_res_exp = _far_path_res_exp_T_3 | _far_path_res_exp_T_2; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  wire  far_path_tininess = io_in_small_add & far_path_tininess_rounder_io_tininess; // @[src/main/scala/fudian/FADD.scala 389:37]
  wire [7:0] _GEN_0 = {{7'd0}, far_path_rounder_io_cout}; // @[src/main/scala/fudian/FADD.scala 398:55]
  wire [7:0] far_path_exp_rounded = _GEN_0 + far_path_res_exp; // @[src/main/scala/fudian/FADD.scala 398:55]
  wire  far_path_may_uf = far_path_tininess & ~io_in_far_path_mul_of; // @[src/main/scala/fudian/FADD.scala 403:43]
  wire  far_path_of_before_round = far_path_res_exp == 8'hff; // @[src/main/scala/fudian/FADD.scala 406:18]
  wire  _far_path_of_after_round_T = far_path_res_exp == 8'hfe; // @[src/main/scala/fudian/FADD.scala 408:18]
  wire  far_path_of_after_round = far_path_rounder_io_cout & _far_path_of_after_round_T; // @[src/main/scala/fudian/FADD.scala 407:58]
  wire  far_path_of = far_path_of_before_round | far_path_of_after_round | io_in_far_path_mul_of; // @[src/main/scala/fudian/FADD.scala 411:57]
  wire  far_path_ix = far_path_rounder_io_inexact | far_path_of; // @[src/main/scala/fudian/FADD.scala 412:49]
  wire  far_path_uf = far_path_may_uf & far_path_ix; // @[src/main/scala/fudian/FADD.scala 413:37]
  wire [31:0] far_path_result = {io_in_far_path_out_sign,far_path_exp_rounded,far_path_rounder_io_out}; // @[src/main/scala/fudian/FADD.scala 416:8]
  wire [7:0] _GEN_1 = {{3'd0}, io_in_near_path_lzc}; // @[src/main/scala/fudian/FADD.scala 428:40]
  wire [7:0] exp_s1 = io_in_near_path_out_exp - _GEN_1; // @[src/main/scala/fudian/FADD.scala 428:40]
  wire [7:0] _GEN_2 = {{7'd0}, io_in_near_path_lza_error}; // @[src/main/scala/fudian/FADD.scala 429:23]
  wire [7:0] exp_s2 = exp_s1 - _GEN_2; // @[src/main/scala/fudian/FADD.scala 429:23]
  wire [7:0] near_path_res_exp = io_in_near_path_int_bit ? exp_s2 : 8'h0; // @[src/main/scala/fudian/FADD.scala 430:27]
  wire  near_path_is_zero = near_path_res_exp == 8'h0 & io_in_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 424:49]
  wire [55:0] _GEN_4 = {{31'd0}, io_in_near_path_sig_raw}; // @[src/main/scala/fudian/FADD.scala 432:41]
  wire [55:0] _sig_s1_T = _GEN_4 << io_in_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 432:41]
  wire [24:0] sig_s1 = _sig_s1_T[24:0]; // @[src/main/scala/fudian/FADD.scala 432:48]
  wire [24:0] _sig_s2_T_1 = {sig_s1[23:0],1'h0}; // @[src/main/scala/fudian/FADD.scala 433:50]
  wire [24:0] sig_s2 = io_in_near_path_lza_error ? _sig_s2_T_1 : sig_s1; // @[src/main/scala/fudian/FADD.scala 433:19]
  wire [26:0] near_path_sig_cor = {sig_s2,2'h0}; // @[src/main/scala/fudian/FADD.scala 435:8]
  wire [26:0] near_path_sig = {near_path_sig_cor[26:1],|near_path_sig_cor[0]}; // @[src/main/scala/fudian/FADD.scala 442:57]
  wire [7:0] _GEN_3 = {{7'd0}, near_path_rounder_io_cout}; // @[src/main/scala/fudian/FADD.scala 457:57]
  wire [7:0] near_path_exp_rounded = _GEN_3 + near_path_res_exp; // @[src/main/scala/fudian/FADD.scala 457:57]
  wire  near_path_zero_sign = io_in_rm == 3'h2; // @[src/main/scala/fudian/FADD.scala 459:38]
  wire  _near_path_result_T_3 = io_in_near_path_out_sign & ~near_path_is_zero | near_path_zero_sign & near_path_is_zero; // @[src/main/scala/fudian/FADD.scala 461:44]
  wire [31:0] near_path_result = {_near_path_result_T_3,near_path_exp_rounded,near_path_rounder_io_out}; // @[src/main/scala/fudian/FADD.scala 460:29]
  wire  near_path_of = near_path_exp_rounded == 8'hff; // @[src/main/scala/fudian/FADD.scala 466:44]
  wire  near_path_ix = near_path_rounder_io_inexact | near_path_of; // @[src/main/scala/fudian/FADD.scala 467:51]
  wire  near_path_uf = near_path_tininess_rounder_io_tininess & near_path_ix; // @[src/main/scala/fudian/FADD.scala 468:41]
  wire  _common_overflow_T_1 = ~io_in_sel_far_path; // @[src/main/scala/fudian/FADD.scala 472:36]
  wire  common_overflow = io_in_sel_far_path & far_path_of | ~io_in_sel_far_path & near_path_of; // @[src/main/scala/fudian/FADD.scala 472:33]
  wire  common_overflow_sign = io_in_sel_far_path ? io_in_far_path_out_sign : io_in_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 474:8]
  wire  rmin = io_in_rm == 3'h1 | near_path_zero_sign & ~io_in_far_path_out_sign | io_in_rm == 3'h3 &
    io_in_far_path_out_sign; // @[src/main/scala/fudian/RoundingUnit.scala 54:41]
  wire [7:0] common_overflow_exp = rmin ? 8'hfe : 8'hff; // @[src/main/scala/fudian/FADD.scala 476:32]
  wire [22:0] common_overflow_sig = rmin ? 23'h7fffff : 23'h0; // @[src/main/scala/fudian/FADD.scala 482:8]
  wire  common_underflow = io_in_sel_far_path & far_path_uf | _common_overflow_T_1 & near_path_uf; // @[src/main/scala/fudian/FADD.scala 484:33]
  wire  common_inexact = io_in_sel_far_path & far_path_ix | _common_overflow_T_1 & near_path_ix; // @[src/main/scala/fudian/FADD.scala 486:33]
  wire [4:0] common_fflags = {2'h0,common_overflow,common_underflow,common_inexact}; // @[src/main/scala/fudian/FADD.scala 487:26]
  wire [31:0] _io_result_T = {common_overflow_sign,common_overflow_exp,common_overflow_sig}; // @[src/main/scala/fudian/FADD.scala 500:10]
  wire [31:0] _io_result_T_1 = io_in_sel_far_path ? far_path_result : near_path_result; // @[src/main/scala/fudian/FADD.scala 501:10]
  wire [31:0] _io_result_T_2 = common_overflow ? _io_result_T : _io_result_T_1; // @[src/main/scala/fudian/FADD.scala 498:8]
  TininessRounder far_path_tininess_rounder ( // @[src/main/scala/fudian/FADD.scala 386:41]
    .io_in_sign(far_path_tininess_rounder_io_in_sign),
    .io_in_sig(far_path_tininess_rounder_io_in_sig),
    .io_rm(far_path_tininess_rounder_io_rm),
    .io_tininess(far_path_tininess_rounder_io_tininess)
  );
  RoundingUnit far_path_rounder ( // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
    .io_in(far_path_rounder_io_in),
    .io_roundIn(far_path_rounder_io_roundIn),
    .io_stickyIn(far_path_rounder_io_stickyIn),
    .io_signIn(far_path_rounder_io_signIn),
    .io_rm(far_path_rounder_io_rm),
    .io_out(far_path_rounder_io_out),
    .io_inexact(far_path_rounder_io_inexact),
    .io_cout(far_path_rounder_io_cout)
  );
  TininessRounder near_path_tininess_rounder ( // @[src/main/scala/fudian/FADD.scala 445:42]
    .io_in_sign(near_path_tininess_rounder_io_in_sign),
    .io_in_sig(near_path_tininess_rounder_io_in_sig),
    .io_rm(near_path_tininess_rounder_io_rm),
    .io_tininess(near_path_tininess_rounder_io_tininess)
  );
  RoundingUnit near_path_rounder ( // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
    .io_in(near_path_rounder_io_in),
    .io_roundIn(near_path_rounder_io_roundIn),
    .io_stickyIn(near_path_rounder_io_stickyIn),
    .io_signIn(near_path_rounder_io_signIn),
    .io_rm(near_path_rounder_io_rm),
    .io_out(near_path_rounder_io_out),
    .io_inexact(near_path_rounder_io_inexact),
    .io_cout(near_path_rounder_io_cout)
  );
  assign io_result = io_in_special_case_valid ? special_path_result : _io_result_T_2; // @[src/main/scala/fudian/FADD.scala 495:19]
  assign io_fflags = io_in_special_case_valid ? special_path_fflags : common_fflags; // @[src/main/scala/fudian/FADD.scala 504:19]
  assign far_path_tininess_rounder_io_in_sign = io_in_far_path_out_sign; // @[src/main/scala/fudian/FADD.scala 359:{30,30}]
  assign far_path_tininess_rounder_io_in_sig = _far_path_res_sig_T_20 | _far_path_res_sig_T_19; // @[src/main/scala/chisel3/util/Mux.scala 30:73]
  assign far_path_tininess_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/FADD.scala 388:35]
  assign far_path_rounder_io_in = far_path_res_sig[25:3]; // @[src/main/scala/fudian/RoundingUnit.scala 45:33]
  assign far_path_rounder_io_roundIn = far_path_res_sig[2]; // @[src/main/scala/fudian/RoundingUnit.scala 46:50]
  assign far_path_rounder_io_stickyIn = |far_path_res_sig[1:0]; // @[src/main/scala/fudian/RoundingUnit.scala 47:51]
  assign far_path_rounder_io_signIn = io_in_far_path_out_sign; // @[src/main/scala/fudian/FADD.scala 359:{30,30}]
  assign far_path_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/RoundingUnit.scala 48:19]
  assign near_path_tininess_rounder_io_in_sign = io_in_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 419:{31,31}]
  assign near_path_tininess_rounder_io_in_sig = {near_path_sig_cor[26:1],|near_path_sig_cor[0]}; // @[src/main/scala/fudian/FADD.scala 442:57]
  assign near_path_tininess_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/FADD.scala 447:36]
  assign near_path_rounder_io_in = near_path_sig[25:3]; // @[src/main/scala/fudian/RoundingUnit.scala 45:33]
  assign near_path_rounder_io_roundIn = near_path_sig[2]; // @[src/main/scala/fudian/RoundingUnit.scala 46:50]
  assign near_path_rounder_io_stickyIn = |near_path_sig[1:0]; // @[src/main/scala/fudian/RoundingUnit.scala 47:51]
  assign near_path_rounder_io_signIn = io_in_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 419:{31,31}]
  assign near_path_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/RoundingUnit.scala 48:19]
endmodule
module FCMA_ADD(
  input  [31:0] io_a, // @[src/main/scala/fudian/FADD.scala 725:14]
  input  [31:0] io_b, // @[src/main/scala/fudian/FADD.scala 725:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FADD.scala 725:14]
  output [31:0] io_result, // @[src/main/scala/fudian/FADD.scala 725:14]
  output [4:0]  io_fflags // @[src/main/scala/fudian/FADD.scala 725:14]
);
  wire [31:0] fadd_s1_io_a; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [31:0] fadd_s1_io_b; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [2:0] fadd_s1_io_rm; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [2:0] fadd_s1_io_out_rm; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_far_path_out_sign; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_near_path_out_exp; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_special_case_valid; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_special_case_bits_iv; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_special_case_bits_nan; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_special_case_bits_inf_sign; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_small_add; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_far_path_mul_of; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [23:0] fadd_s1_io_out_far_sig_a; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [27:0] fadd_s1_io_out_far_sig_b; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_far_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_far_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_far_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_lza_error; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_int_bit; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [24:0] fadd_s1_io_out_near_path_sig_raw; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [4:0] fadd_s1_io_out_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_sel_far_path; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [2:0] fadd_s2_io_in_rm; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_far_path_out_sign; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_near_path_out_exp; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_special_case_valid; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_special_case_bits_iv; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_special_case_bits_nan; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_special_case_bits_inf_sign; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_small_add; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_far_path_mul_of; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [23:0] fadd_s2_io_in_far_sig_a; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [27:0] fadd_s2_io_in_far_sig_b; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_far_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_far_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_far_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_lza_error; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_int_bit; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [24:0] fadd_s2_io_in_near_path_sig_raw; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [4:0] fadd_s2_io_in_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_sel_far_path; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [31:0] fadd_s2_io_result; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [4:0] fadd_s2_io_fflags; // @[src/main/scala/fudian/FADD.scala 735:23]
  FCMA_ADD_s1 fadd_s1 ( // @[src/main/scala/fudian/FADD.scala 734:23]
    .io_a(fadd_s1_io_a),
    .io_b(fadd_s1_io_b),
    .io_rm(fadd_s1_io_rm),
    .io_out_rm(fadd_s1_io_out_rm),
    .io_out_far_path_out_sign(fadd_s1_io_out_far_path_out_sign),
    .io_out_near_path_out_sign(fadd_s1_io_out_near_path_out_sign),
    .io_out_near_path_out_exp(fadd_s1_io_out_near_path_out_exp),
    .io_out_special_case_valid(fadd_s1_io_out_special_case_valid),
    .io_out_special_case_bits_iv(fadd_s1_io_out_special_case_bits_iv),
    .io_out_special_case_bits_nan(fadd_s1_io_out_special_case_bits_nan),
    .io_out_special_case_bits_inf_sign(fadd_s1_io_out_special_case_bits_inf_sign),
    .io_out_small_add(fadd_s1_io_out_small_add),
    .io_out_far_path_mul_of(fadd_s1_io_out_far_path_mul_of),
    .io_out_far_sig_a(fadd_s1_io_out_far_sig_a),
    .io_out_far_sig_b(fadd_s1_io_out_far_sig_b),
    .io_out_far_exp_a_vec_0(fadd_s1_io_out_far_exp_a_vec_0),
    .io_out_far_exp_a_vec_1(fadd_s1_io_out_far_exp_a_vec_1),
    .io_out_far_exp_a_vec_2(fadd_s1_io_out_far_exp_a_vec_2),
    .io_out_near_path_sig_is_zero(fadd_s1_io_out_near_path_sig_is_zero),
    .io_out_near_path_lza_error(fadd_s1_io_out_near_path_lza_error),
    .io_out_near_path_int_bit(fadd_s1_io_out_near_path_int_bit),
    .io_out_near_path_sig_raw(fadd_s1_io_out_near_path_sig_raw),
    .io_out_near_path_lzc(fadd_s1_io_out_near_path_lzc),
    .io_out_sel_far_path(fadd_s1_io_out_sel_far_path)
  );
  FCMA_ADD_s2 fadd_s2 ( // @[src/main/scala/fudian/FADD.scala 735:23]
    .io_in_rm(fadd_s2_io_in_rm),
    .io_in_far_path_out_sign(fadd_s2_io_in_far_path_out_sign),
    .io_in_near_path_out_sign(fadd_s2_io_in_near_path_out_sign),
    .io_in_near_path_out_exp(fadd_s2_io_in_near_path_out_exp),
    .io_in_special_case_valid(fadd_s2_io_in_special_case_valid),
    .io_in_special_case_bits_iv(fadd_s2_io_in_special_case_bits_iv),
    .io_in_special_case_bits_nan(fadd_s2_io_in_special_case_bits_nan),
    .io_in_special_case_bits_inf_sign(fadd_s2_io_in_special_case_bits_inf_sign),
    .io_in_small_add(fadd_s2_io_in_small_add),
    .io_in_far_path_mul_of(fadd_s2_io_in_far_path_mul_of),
    .io_in_far_sig_a(fadd_s2_io_in_far_sig_a),
    .io_in_far_sig_b(fadd_s2_io_in_far_sig_b),
    .io_in_far_exp_a_vec_0(fadd_s2_io_in_far_exp_a_vec_0),
    .io_in_far_exp_a_vec_1(fadd_s2_io_in_far_exp_a_vec_1),
    .io_in_far_exp_a_vec_2(fadd_s2_io_in_far_exp_a_vec_2),
    .io_in_near_path_sig_is_zero(fadd_s2_io_in_near_path_sig_is_zero),
    .io_in_near_path_lza_error(fadd_s2_io_in_near_path_lza_error),
    .io_in_near_path_int_bit(fadd_s2_io_in_near_path_int_bit),
    .io_in_near_path_sig_raw(fadd_s2_io_in_near_path_sig_raw),
    .io_in_near_path_lzc(fadd_s2_io_in_near_path_lzc),
    .io_in_sel_far_path(fadd_s2_io_in_sel_far_path),
    .io_result(fadd_s2_io_result),
    .io_fflags(fadd_s2_io_fflags)
  );
  assign io_result = fadd_s2_io_result; // @[src/main/scala/fudian/FADD.scala 745:13]
  assign io_fflags = fadd_s2_io_fflags; // @[src/main/scala/fudian/FADD.scala 746:13]
  assign fadd_s1_io_a = io_a; // @[src/main/scala/fudian/FADD.scala 737:16]
  assign fadd_s1_io_b = io_b; // @[src/main/scala/fudian/FADD.scala 738:16]
  assign fadd_s1_io_rm = io_rm; // @[src/main/scala/fudian/FADD.scala 741:17]
  assign fadd_s2_io_in_rm = fadd_s1_io_out_rm; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_path_out_sign = fadd_s1_io_out_far_path_out_sign; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_out_sign = fadd_s1_io_out_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_out_exp = fadd_s1_io_out_near_path_out_exp; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_special_case_valid = fadd_s1_io_out_special_case_valid; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_special_case_bits_iv = fadd_s1_io_out_special_case_bits_iv; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_special_case_bits_nan = fadd_s1_io_out_special_case_bits_nan; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_special_case_bits_inf_sign = fadd_s1_io_out_special_case_bits_inf_sign; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_small_add = fadd_s1_io_out_small_add; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_path_mul_of = fadd_s1_io_out_far_path_mul_of; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_sig_a = fadd_s1_io_out_far_sig_a; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_sig_b = fadd_s1_io_out_far_sig_b; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_exp_a_vec_0 = fadd_s1_io_out_far_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_exp_a_vec_1 = fadd_s1_io_out_far_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_far_exp_a_vec_2 = fadd_s1_io_out_far_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_sig_is_zero = fadd_s1_io_out_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_lza_error = fadd_s1_io_out_near_path_lza_error; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_int_bit = fadd_s1_io_out_near_path_int_bit; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_sig_raw = fadd_s1_io_out_near_path_sig_raw; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_near_path_lzc = fadd_s1_io_out_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 743:17]
  assign fadd_s2_io_in_sel_far_path = fadd_s1_io_out_sel_far_path; // @[src/main/scala/fudian/FADD.scala 743:17]
endmodule
module FADD(
  input         clock,
  input         reset,
  input  [31:0] io_a, // @[src/main/scala/fudian/FADD.scala 751:14]
  input  [31:0] io_b, // @[src/main/scala/fudian/FADD.scala 751:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FADD.scala 751:14]
  output [31:0] io_result, // @[src/main/scala/fudian/FADD.scala 751:14]
  output [4:0]  io_fflags // @[src/main/scala/fudian/FADD.scala 751:14]
);
  wire [31:0] module__io_a; // @[src/main/scala/fudian/FADD.scala 758:22]
  wire [31:0] module__io_b; // @[src/main/scala/fudian/FADD.scala 758:22]
  wire [2:0] module__io_rm; // @[src/main/scala/fudian/FADD.scala 758:22]
  wire [31:0] module__io_result; // @[src/main/scala/fudian/FADD.scala 758:22]
  wire [4:0] module__io_fflags; // @[src/main/scala/fudian/FADD.scala 758:22]
  FCMA_ADD module_ ( // @[src/main/scala/fudian/FADD.scala 758:22]
    .io_a(module__io_a),
    .io_b(module__io_b),
    .io_rm(module__io_rm),
    .io_result(module__io_result),
    .io_fflags(module__io_fflags)
  );
  assign io_result = module__io_result; // @[src/main/scala/fudian/FADD.scala 765:13]
  assign io_fflags = module__io_fflags; // @[src/main/scala/fudian/FADD.scala 766:13]
  assign module__io_a = io_a; // @[src/main/scala/fudian/FADD.scala 760:15]
  assign module__io_b = io_b; // @[src/main/scala/fudian/FADD.scala 761:15]
  assign module__io_rm = io_rm; // @[src/main/scala/fudian/FADD.scala 762:16]
endmodule
