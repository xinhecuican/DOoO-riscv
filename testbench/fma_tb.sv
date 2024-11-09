`include "../src/defines/fp_defines.svh"
`include "../src/defines/defines.svh"


// sv2v --write=build/fma_tb.v -I=src/defines -I=build --top=fma_tb testbench/fma_tb.sv src/core/backend/execute/FAdd.sv src/core/backend/execute/FMisc.sv src/core/backend/execute/Mult.sv src/core/backend/execute/FMul.sv src/utils/lzc.sv
// iverilog -g2012 build/fma_tb.v -s fma_tb -o build/sim.out
// vvp -n build/sim.out
module fma_tb();
    int stimulus_a[1000];
    int stimulus_b[1000];
    int stimulus_c[1000];
    int corner_values[6];
    int perm_idx;
    int count = 0;
    logic clk, rst;
    roundmode_e round_mode;
    logic [31: 0] rs1_data, rs2_data, rs3_data, res_dut, res_ref;
    logic [55: 0] toadd_res, toadd_res_n;
    FMulInfo mulInfo, mulInfo_n;
    FFlags flag_dut, flag_ref;

    always #5 clk = ~clk;

    FMul #(FP32) fmul_dut (
        .clk,
        .rst,
        .round_mode,
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .fltop(5'b0),
        .mulInfo(mulInfo),
        .toadd_res(toadd_res),
        .res(),
        .status()
    );

    always_ff @(posedge clk)begin
        toadd_res_n <= toadd_res;
        mulInfo_n <= mulInfo;
    end
    localparam int unsigned FP32_EXP_BITS = exp_bits(FP32);
    localparam int unsigned FP32_MAN_BITS = man_bits(FP32);
    FAdd #(FP32_EXP_BITS, FP32_MAN_BITS*2+1, FP32_MAN_BITS) fadd_dut (
        .clk,
        .rst,
        .round_mode,
        .sub(1'b0),
        .fma(1'b1),
        .info_fma(mulInfo_n),
        .rs1_data(toadd_res_n),
        .rs2_data({rs3_data, {FP32_MAN_BITS+1{1'b0}}}),
        .res(res_dut),
        .status(flag_dut)
    );

    FCMA fma_ref (
        clk,
        rst,
        rs1_data,
        rs2_data,
        rs3_data,
        round_mode,
        res_ref,
        flag_ref
    );

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, fma_tb);
    end

    // task to run the test and print the count
    task run_test(input int a[1000], input int b[1000], input int c[1000], input int size);
        int count = 0;
        for (int i = 0; i < size; i++) begin
            rs1_data = a[i];
            rs2_data = b[i];
            rs3_data = c[i];
            #50;
            if(res_dut != res_ref || flag_dut != flag_ref)begin
                $display("Test with A: %h, B: %h C: %h error.\nDut: %h %h\nRef: %h %h", a[i], b[i], c[i], res_dut, flag_dut, res_ref, flag_ref);
                $finish;
            end
            count = count + 1;
            if(count % 100 == 0)begin
                $display("pass count %d", count);
            end
        end
    endtask

    initial begin
        clk = 1;
        rst = 1;
        round_mode = 0;
        #10;
        // Regression Tests
        stimulus_a[9: 0] = '{32'h22cb525a, 32'h40000000, 32'h83e73d5c, 32'hbf9b1e94, 32'h34082401, 32'h05e8ef81, 32'h5c75da81, 32'h002b017, 32'h4adeb000, 32'h40000000};
        stimulus_b[9: 0] = '{32'hadd79efa, 32'hc0000000, 32'h1c800000, 32'hc038ed3a, 32'hb328cd45, 32'h0114f3db, 32'h2f642a39, 32'hff3807ab, 32'h45000000, 32'hc0a00000};
        stimulus_c[9: 0] = '{32'hadd79efa, 32'hc0000000, 32'h1c800000, 32'hc038ed3a, 32'hb328cd45, 32'h0114f3db, 32'h2f642a39, 32'hff3807ab, 32'h5defb8b6, 32'hc0000000};
        $display("Regression Tests");
        run_test(stimulus_a, stimulus_b, stimulus_c, 10);
        

        // Corner Cases
        corner_values = '{32'h80000000, 32'h00000000, 32'h7f800000, 32'hff800000, 32'h7fc00000, 32'hffc00000};
        perm_idx = 0;
        foreach (corner_values[i]) begin
            foreach (corner_values[j]) begin
                foreach (corner_values[k])begin
                    if (perm_idx < 1000) begin
                        stimulus_a[perm_idx] = corner_values[i];
                        stimulus_b[perm_idx] = corner_values[j];
                        stimulus_c[perm_idx] = corner_values[k];
                        perm_idx++;
                    end
                end
            end
        end
        $display("Corner Cases");
        run_test(stimulus_a, stimulus_b, stimulus_c, perm_idx);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = $random;
            stimulus_c[i] = $random;
        end
        $display("any * any + any");
        run_test(stimulus_a, stimulus_b, stimulus_c, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random & 32'h807fffff;
            stimulus_b[i] = $random & 32'h807fffff;
            stimulus_c[i] = $random;
        end
        $display("denormal * denormal + any");
        run_test(stimulus_a, stimulus_b, stimulus_c, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random | 32'h7f800000;
            stimulus_b[i] = $random;
            stimulus_c[i] = $random;
        end
        $display("ov * any + any");
        run_test(stimulus_a, stimulus_b, stimulus_c, 1000);

        // Edge Cases
        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h80000000;
            stimulus_b[i] = $random;
            stimulus_c[i] = $random;
        end
        $display("edge cases");
        run_test(stimulus_a, stimulus_b, stimulus_c, 1000);

        $display("All tests passed.");
        $finish;
    end
endmodule

module C22(
  input   io_in_0, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_1, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_0, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_1 // @[src/main/scala/fudian/utils/CSA.scala 7:14]
);
  wire  sum = io_in_0 ^ io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 17:17]
  wire  cout = io_in_0 & io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 18:18]
  wire [1:0] temp_0 = {cout,sum}; // @[src/main/scala/fudian/utils/CSA.scala 19:13]
  assign io_out_0 = temp_0[0]; // @[src/main/scala/fudian/utils/CSA.scala 21:73]
  assign io_out_1 = temp_0[1]; // @[src/main/scala/fudian/utils/CSA.scala 21:73]
endmodule
module C32(
  input   io_in_0, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_1, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_2, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_0, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_1 // @[src/main/scala/fudian/utils/CSA.scala 7:14]
);
  wire  a_xor_b = io_in_0 ^ io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 28:21]
  wire  a_and_b = io_in_0 & io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 29:21]
  wire  sum = a_xor_b ^ io_in_2; // @[src/main/scala/fudian/utils/CSA.scala 30:23]
  wire  cout = a_and_b | a_xor_b & io_in_2; // @[src/main/scala/fudian/utils/CSA.scala 31:24]
  wire [1:0] temp_0 = {cout,sum}; // @[src/main/scala/fudian/utils/CSA.scala 32:13]
  assign io_out_0 = temp_0[0]; // @[src/main/scala/fudian/utils/CSA.scala 34:73]
  assign io_out_1 = temp_0[1]; // @[src/main/scala/fudian/utils/CSA.scala 34:73]
endmodule
module C53(
  input   io_in_0, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_1, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_2, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_3, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  input   io_in_4, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_0, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_1, // @[src/main/scala/fudian/utils/CSA.scala 7:14]
  output  io_out_2 // @[src/main/scala/fudian/utils/CSA.scala 7:14]
);
  wire  CSA3_2_io_in_0; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_io_in_2; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_io_out_0; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_io_out_1; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_1_io_in_0; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_1_io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_1_io_in_2; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_1_io_out_0; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  wire  CSA3_2_1_io_out_1; // @[src/main/scala/fudian/utils/CSA.scala 38:33]
  C32 CSA3_2 ( // @[src/main/scala/fudian/utils/CSA.scala 38:33]
    .io_in_0(CSA3_2_io_in_0),
    .io_in_1(CSA3_2_io_in_1),
    .io_in_2(CSA3_2_io_in_2),
    .io_out_0(CSA3_2_io_out_0),
    .io_out_1(CSA3_2_io_out_1)
  );
  C32 CSA3_2_1 ( // @[src/main/scala/fudian/utils/CSA.scala 38:33]
    .io_in_0(CSA3_2_1_io_in_0),
    .io_in_1(CSA3_2_1_io_in_1),
    .io_in_2(CSA3_2_1_io_in_2),
    .io_out_0(CSA3_2_1_io_out_0),
    .io_out_1(CSA3_2_1_io_out_1)
  );
  assign io_out_0 = CSA3_2_1_io_out_0; // @[src/main/scala/fudian/utils/CSA.scala 41:{20,20}]
  assign io_out_1 = CSA3_2_io_out_1; // @[src/main/scala/fudian/utils/CSA.scala 41:{20,20}]
  assign io_out_2 = CSA3_2_1_io_out_1; // @[src/main/scala/fudian/utils/CSA.scala 41:{20,20}]
  assign CSA3_2_io_in_0 = io_in_0; // @[src/main/scala/fudian/utils/CSA.scala 39:16]
  assign CSA3_2_io_in_1 = io_in_1; // @[src/main/scala/fudian/utils/CSA.scala 39:16]
  assign CSA3_2_io_in_2 = io_in_2; // @[src/main/scala/fudian/utils/CSA.scala 39:16]
  assign CSA3_2_1_io_in_0 = CSA3_2_io_out_0; // @[src/main/scala/fudian/utils/CSA.scala 40:{26,26}]
  assign CSA3_2_1_io_in_1 = io_in_3; // @[src/main/scala/fudian/utils/CSA.scala 40:{26,26}]
  assign CSA3_2_1_io_in_2 = io_in_4; // @[src/main/scala/fudian/utils/CSA.scala 40:{26,26}]
endmodule
module Multiplier(
  input  [24:0] io_a, // @[src/main/scala/fudian/utils/Multiplier.scala 15:14]
  input  [24:0] io_b, // @[src/main/scala/fudian/utils/Multiplier.scala 15:14]
  output [49:0] io_result // @[src/main/scala/fudian/utils/Multiplier.scala 15:14]
);
  wire  c22_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_1_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_1_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_1_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_1_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_1_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_1_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_1_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_1_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_1_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_1_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_2_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_3_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_4_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_2_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_2_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_2_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_2_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_5_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_5_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_3_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_3_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_3_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_3_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_6_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_6_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_2_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_2_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_2_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_2_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_2_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_7_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_7_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_3_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_3_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_3_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_3_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_3_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_8_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_8_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_9_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_10_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_11_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_12_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_13_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_14_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_15_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_16_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_17_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_4_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_4_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_4_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_4_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_18_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_18_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_19_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_5_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_5_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_5_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_5_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_20_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_20_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_21_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_4_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_4_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_4_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_4_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_4_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_22_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_22_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_23_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_5_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_5_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_5_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_5_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_5_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_24_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_24_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_25_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_26_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_27_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_28_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_29_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_30_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_31_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_32_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_33_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_34_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_35_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_36_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_37_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_38_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_39_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_40_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_41_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_42_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_43_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_44_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_45_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_46_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_47_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_48_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_49_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_50_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_51_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_52_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_53_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_54_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_55_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_6_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_6_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_6_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_6_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_6_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_56_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_56_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_57_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_7_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_7_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_7_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_7_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_7_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_58_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_58_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_59_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_6_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_6_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_6_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_6_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_60_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_60_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_61_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_7_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_7_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_7_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_7_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_62_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_62_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_63_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_64_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_65_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_66_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_67_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_68_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_69_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_70_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_8_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_8_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_8_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_8_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_8_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_71_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_71_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_9_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_9_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_9_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_9_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_9_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_72_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_72_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_8_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_8_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_8_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_8_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_73_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_73_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_9_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_9_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_9_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_9_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_74_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_74_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_75_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_76_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_77_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_10_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_10_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_10_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_10_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_10_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_11_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_11_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_11_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_11_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_11_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c22_10_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_10_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_10_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_10_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_11_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_11_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_11_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_11_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_12_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_12_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_12_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_12_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_13_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_13_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_13_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_13_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_14_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_14_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_14_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_14_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_15_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_15_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_15_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_15_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_16_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_16_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_16_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_16_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_12_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_12_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_12_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_12_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_12_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_13_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_13_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_13_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_13_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_13_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_14_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_14_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_14_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_14_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_14_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_78_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_78_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_79_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_80_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_81_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_82_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_83_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_84_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_85_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_86_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_17_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_17_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_17_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_17_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_87_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_87_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_18_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_18_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_18_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_18_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_88_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_88_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_19_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_19_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_19_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_19_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_89_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_89_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_20_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_20_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_20_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_20_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_90_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_90_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_21_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_21_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_21_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_21_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_91_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_91_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_15_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_15_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_15_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_15_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_15_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_92_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_92_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_16_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_16_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_16_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_16_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_16_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_93_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_93_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_17_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_17_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_17_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_17_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_17_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_94_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_94_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_18_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_18_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_18_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_18_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_18_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_95_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_95_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_19_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_19_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_19_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_19_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_19_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_96_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_96_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_20_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_20_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_20_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_20_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_20_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_97_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_97_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_21_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_21_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_21_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_21_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_21_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_98_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_98_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_22_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_22_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_99_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_99_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_22_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_22_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_22_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_100_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_100_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_23_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_23_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_23_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_23_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_101_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_101_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_24_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_24_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_24_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_24_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_102_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_102_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_25_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_25_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_25_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_25_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_103_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_103_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_26_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_26_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_26_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_26_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c53_104_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_104_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_105_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_106_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_107_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_108_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_109_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_110_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_111_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c32_23_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_23_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_23_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_23_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_23_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c22_27_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_27_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_27_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_27_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_28_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_28_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_28_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_28_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_24_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_24_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_24_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_24_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_24_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c22_29_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_29_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_29_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_29_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_30_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_30_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_30_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_30_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_31_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_31_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_31_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_31_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_32_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_32_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_32_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_32_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_33_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_33_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_33_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_33_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_34_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_34_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_34_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_34_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_35_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_35_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_35_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_35_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_36_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_36_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_36_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_36_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_37_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_37_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_37_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_37_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_38_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_38_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_38_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_38_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_39_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_39_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_39_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_39_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_40_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_40_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_40_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_40_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_41_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_41_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_41_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_41_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_42_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_42_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_42_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_42_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_43_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_43_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_43_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_43_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_25_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_25_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_25_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_25_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_25_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_26_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_26_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_26_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_26_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_26_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_27_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_27_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_27_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_27_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_27_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_28_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_28_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_28_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_28_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_28_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c53_112_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_112_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_113_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_114_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_115_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_116_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_117_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_118_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_119_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_120_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_121_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_122_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_123_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_124_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_125_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_126_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_127_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_128_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_in_3; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_in_4; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c53_129_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
  wire  c22_44_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_44_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_44_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_44_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_45_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_45_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_45_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_45_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_29_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_29_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_29_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_29_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_29_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c22_46_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_46_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_46_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_46_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_47_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_47_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_47_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_47_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_48_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_48_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_48_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_48_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_49_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_49_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_49_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_49_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_30_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_30_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_30_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_30_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_30_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c22_50_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_50_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_50_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_50_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_51_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_51_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_51_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_51_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_52_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_52_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_52_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_52_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_53_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_53_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_53_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_53_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_54_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_54_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_54_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_54_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_55_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_55_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_55_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_55_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_56_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_56_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_56_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_56_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_57_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_57_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_57_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_57_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_58_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_58_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_58_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_58_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_59_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_59_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_59_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_59_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_60_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_60_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_60_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_60_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_61_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_61_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_61_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_61_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_62_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_62_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_62_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_62_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_63_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_63_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_63_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_63_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_64_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_64_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_64_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_64_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_65_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_65_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_65_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_65_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_66_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_66_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_66_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_66_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_67_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_67_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_67_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_67_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_68_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_68_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_68_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_68_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_69_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_69_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_69_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_69_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_70_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_70_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_70_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_70_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_71_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_71_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_71_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_71_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_72_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_72_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_72_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_72_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_73_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_73_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_73_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_73_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_74_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_74_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_74_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_74_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_75_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_75_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_75_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_75_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_76_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_76_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_76_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_76_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_77_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_77_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_77_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_77_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_78_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_78_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_78_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_78_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_79_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_79_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_79_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_79_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_80_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_80_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_80_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_80_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_81_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_81_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_81_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_81_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_82_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_82_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_82_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_82_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_83_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_83_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_83_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_83_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_84_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_84_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_84_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_84_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_85_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_85_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_85_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_85_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_86_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_86_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_86_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_86_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_87_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_87_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_87_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_87_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_88_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_88_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_88_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_88_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c32_31_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_31_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_31_io_in_2; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_31_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c32_31_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
  wire  c22_89_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_89_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_89_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_89_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_90_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_90_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_90_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_90_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_91_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_91_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_91_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_91_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_92_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_92_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_92_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_92_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_93_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_93_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_93_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_93_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_94_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_94_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_94_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_94_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_95_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_95_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_95_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_95_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_96_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_96_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_96_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_96_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_97_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_97_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_97_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_97_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_98_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_98_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_98_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_98_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_99_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_99_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_99_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_99_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_100_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_100_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_100_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_100_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_101_io_in_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_101_io_in_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_101_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  c22_101_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
  wire  b_sext_signBit = io_b[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 9:20]
  wire [25:0] b_sext = {b_sext_signBit,io_b}; // @[src/main/scala/fudian/utils/Multiplier.scala 10:41]
  wire [26:0] _bx2_T = {b_sext, 1'h0}; // @[src/main/scala/fudian/utils/Multiplier.scala 26:17]
  wire [25:0] neg_b = ~b_sext; // @[src/main/scala/fudian/utils/Multiplier.scala 27:13]
  wire [26:0] _neg_bx2_T = {neg_b, 1'h0}; // @[src/main/scala/fudian/utils/Multiplier.scala 28:20]
  wire [2:0] x = {io_a[1:0],1'h0}; // @[src/main/scala/fudian/utils/Multiplier.scala 34:25]
  wire [25:0] _pp_temp_T_1 = 3'h1 == x ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_3 = 3'h2 == x ? b_sext : _pp_temp_T_1; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] bx2 = _bx2_T[25:0]; // @[src/main/scala/fudian/utils/Multiplier.scala 24:41 26:7]
  wire [25:0] _pp_temp_T_5 = 3'h3 == x ? bx2 : _pp_temp_T_3; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_6 = 3'h4 == x; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] neg_bx2 = _neg_bx2_T[25:0]; // @[src/main/scala/fudian/utils/Multiplier.scala 24:41 28:11]
  wire [25:0] _pp_temp_T_7 = 3'h4 == x ? neg_bx2 : _pp_temp_T_5; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_8 = 3'h5 == x; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_9 = 3'h5 == x ? neg_b : _pp_temp_T_7; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_10 = 3'h6 == x; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp = 3'h6 == x ? neg_b : _pp_temp_T_9; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s = pp_temp[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire  _T = ~s; // @[src/main/scala/fudian/utils/Multiplier.scala 52:14]
  wire [28:0] pp = {_T,s,s,pp_temp}; // @[src/main/scala/fudian/utils/Multiplier.scala 52:13]
  wire [2:0] x_1 = io_a[3:1]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_12 = 3'h1 == x_1 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_14 = 3'h2 == x_1 ? b_sext : _pp_temp_T_12; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_16 = 3'h3 == x_1 ? bx2 : _pp_temp_T_14; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_17 = 3'h4 == x_1; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_18 = 3'h4 == x_1 ? neg_bx2 : _pp_temp_T_16; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_19 = 3'h5 == x_1; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_20 = 3'h5 == x_1 ? neg_b : _pp_temp_T_18; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_21 = 3'h6 == x_1; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_1 = 3'h6 == x_1 ? neg_b : _pp_temp_T_20; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_1 = pp_temp_1[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_6 = _pp_temp_T_6 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_8 = _pp_temp_T_8 ? 2'h1 : _t_T_6; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_1 = _pp_temp_T_10 ? 2'h1 : _t_T_8; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_30 = ~s_1; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_1 = {1'h1,_T_30,pp_temp_1,t_1}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_2 = io_a[5:3]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_23 = 3'h1 == x_2 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_25 = 3'h2 == x_2 ? b_sext : _pp_temp_T_23; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_27 = 3'h3 == x_2 ? bx2 : _pp_temp_T_25; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_28 = 3'h4 == x_2; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_29 = 3'h4 == x_2 ? neg_bx2 : _pp_temp_T_27; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_30 = 3'h5 == x_2; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_31 = 3'h5 == x_2 ? neg_b : _pp_temp_T_29; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_32 = 3'h6 == x_2; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_2 = 3'h6 == x_2 ? neg_b : _pp_temp_T_31; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_2 = pp_temp_2[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_11 = _pp_temp_T_17 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_13 = _pp_temp_T_19 ? 2'h1 : _t_T_11; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_2 = _pp_temp_T_21 ? 2'h1 : _t_T_13; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_61 = ~s_2; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_2 = {1'h1,_T_61,pp_temp_2,t_2}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_3 = io_a[7:5]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_34 = 3'h1 == x_3 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_36 = 3'h2 == x_3 ? b_sext : _pp_temp_T_34; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_38 = 3'h3 == x_3 ? bx2 : _pp_temp_T_36; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_39 = 3'h4 == x_3; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_40 = 3'h4 == x_3 ? neg_bx2 : _pp_temp_T_38; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_41 = 3'h5 == x_3; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_42 = 3'h5 == x_3 ? neg_b : _pp_temp_T_40; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_43 = 3'h6 == x_3; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_3 = 3'h6 == x_3 ? neg_b : _pp_temp_T_42; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_3 = pp_temp_3[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_16 = _pp_temp_T_28 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_18 = _pp_temp_T_30 ? 2'h1 : _t_T_16; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_3 = _pp_temp_T_32 ? 2'h1 : _t_T_18; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_92 = ~s_3; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_3 = {1'h1,_T_92,pp_temp_3,t_3}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_4 = io_a[9:7]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_45 = 3'h1 == x_4 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_47 = 3'h2 == x_4 ? b_sext : _pp_temp_T_45; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_49 = 3'h3 == x_4 ? bx2 : _pp_temp_T_47; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_50 = 3'h4 == x_4; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_51 = 3'h4 == x_4 ? neg_bx2 : _pp_temp_T_49; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_52 = 3'h5 == x_4; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_53 = 3'h5 == x_4 ? neg_b : _pp_temp_T_51; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_54 = 3'h6 == x_4; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_4 = 3'h6 == x_4 ? neg_b : _pp_temp_T_53; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_4 = pp_temp_4[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_21 = _pp_temp_T_39 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_23 = _pp_temp_T_41 ? 2'h1 : _t_T_21; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_4 = _pp_temp_T_43 ? 2'h1 : _t_T_23; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_123 = ~s_4; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_4 = {1'h1,_T_123,pp_temp_4,t_4}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_5 = io_a[11:9]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_56 = 3'h1 == x_5 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_58 = 3'h2 == x_5 ? b_sext : _pp_temp_T_56; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_60 = 3'h3 == x_5 ? bx2 : _pp_temp_T_58; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_61 = 3'h4 == x_5; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_62 = 3'h4 == x_5 ? neg_bx2 : _pp_temp_T_60; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_63 = 3'h5 == x_5; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_64 = 3'h5 == x_5 ? neg_b : _pp_temp_T_62; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_65 = 3'h6 == x_5; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_5 = 3'h6 == x_5 ? neg_b : _pp_temp_T_64; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_5 = pp_temp_5[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_26 = _pp_temp_T_50 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_28 = _pp_temp_T_52 ? 2'h1 : _t_T_26; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_5 = _pp_temp_T_54 ? 2'h1 : _t_T_28; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_154 = ~s_5; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_5 = {1'h1,_T_154,pp_temp_5,t_5}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_6 = io_a[13:11]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_67 = 3'h1 == x_6 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_69 = 3'h2 == x_6 ? b_sext : _pp_temp_T_67; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_71 = 3'h3 == x_6 ? bx2 : _pp_temp_T_69; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_72 = 3'h4 == x_6; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_73 = 3'h4 == x_6 ? neg_bx2 : _pp_temp_T_71; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_74 = 3'h5 == x_6; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_75 = 3'h5 == x_6 ? neg_b : _pp_temp_T_73; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_76 = 3'h6 == x_6; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_6 = 3'h6 == x_6 ? neg_b : _pp_temp_T_75; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_6 = pp_temp_6[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_31 = _pp_temp_T_61 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_33 = _pp_temp_T_63 ? 2'h1 : _t_T_31; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_6 = _pp_temp_T_65 ? 2'h1 : _t_T_33; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_185 = ~s_6; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_6 = {1'h1,_T_185,pp_temp_6,t_6}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_7 = io_a[15:13]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_78 = 3'h1 == x_7 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_80 = 3'h2 == x_7 ? b_sext : _pp_temp_T_78; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_82 = 3'h3 == x_7 ? bx2 : _pp_temp_T_80; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_83 = 3'h4 == x_7; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_84 = 3'h4 == x_7 ? neg_bx2 : _pp_temp_T_82; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_85 = 3'h5 == x_7; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_86 = 3'h5 == x_7 ? neg_b : _pp_temp_T_84; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_87 = 3'h6 == x_7; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_7 = 3'h6 == x_7 ? neg_b : _pp_temp_T_86; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_7 = pp_temp_7[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_36 = _pp_temp_T_72 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_38 = _pp_temp_T_74 ? 2'h1 : _t_T_36; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_7 = _pp_temp_T_76 ? 2'h1 : _t_T_38; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_216 = ~s_7; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_7 = {1'h1,_T_216,pp_temp_7,t_7}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_8 = io_a[17:15]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_89 = 3'h1 == x_8 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_91 = 3'h2 == x_8 ? b_sext : _pp_temp_T_89; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_93 = 3'h3 == x_8 ? bx2 : _pp_temp_T_91; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_94 = 3'h4 == x_8; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_95 = 3'h4 == x_8 ? neg_bx2 : _pp_temp_T_93; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_96 = 3'h5 == x_8; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_97 = 3'h5 == x_8 ? neg_b : _pp_temp_T_95; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_98 = 3'h6 == x_8; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_8 = 3'h6 == x_8 ? neg_b : _pp_temp_T_97; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_8 = pp_temp_8[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_41 = _pp_temp_T_83 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_43 = _pp_temp_T_85 ? 2'h1 : _t_T_41; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_8 = _pp_temp_T_87 ? 2'h1 : _t_T_43; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_247 = ~s_8; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_8 = {1'h1,_T_247,pp_temp_8,t_8}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_9 = io_a[19:17]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_100 = 3'h1 == x_9 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_102 = 3'h2 == x_9 ? b_sext : _pp_temp_T_100; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_104 = 3'h3 == x_9 ? bx2 : _pp_temp_T_102; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_105 = 3'h4 == x_9; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_106 = 3'h4 == x_9 ? neg_bx2 : _pp_temp_T_104; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_107 = 3'h5 == x_9; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_108 = 3'h5 == x_9 ? neg_b : _pp_temp_T_106; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_109 = 3'h6 == x_9; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_9 = 3'h6 == x_9 ? neg_b : _pp_temp_T_108; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_9 = pp_temp_9[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_46 = _pp_temp_T_94 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_48 = _pp_temp_T_96 ? 2'h1 : _t_T_46; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_9 = _pp_temp_T_98 ? 2'h1 : _t_T_48; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_278 = ~s_9; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_9 = {1'h1,_T_278,pp_temp_9,t_9}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_10 = io_a[21:19]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_111 = 3'h1 == x_10 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_113 = 3'h2 == x_10 ? b_sext : _pp_temp_T_111; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_115 = 3'h3 == x_10 ? bx2 : _pp_temp_T_113; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_116 = 3'h4 == x_10; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_117 = 3'h4 == x_10 ? neg_bx2 : _pp_temp_T_115; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_118 = 3'h5 == x_10; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_119 = 3'h5 == x_10 ? neg_b : _pp_temp_T_117; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_120 = 3'h6 == x_10; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_10 = 3'h6 == x_10 ? neg_b : _pp_temp_T_119; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_10 = pp_temp_10[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_51 = _pp_temp_T_105 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_53 = _pp_temp_T_107 ? 2'h1 : _t_T_51; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_10 = _pp_temp_T_109 ? 2'h1 : _t_T_53; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_309 = ~s_10; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_10 = {1'h1,_T_309,pp_temp_10,t_10}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire [2:0] x_11 = io_a[23:21]; // @[src/main/scala/fudian/utils/Multiplier.scala 34:90]
  wire [25:0] _pp_temp_T_122 = 3'h1 == x_11 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_124 = 3'h2 == x_11 ? b_sext : _pp_temp_T_122; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_126 = 3'h3 == x_11 ? bx2 : _pp_temp_T_124; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_127 = 3'h4 == x_11; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_128 = 3'h4 == x_11 ? neg_bx2 : _pp_temp_T_126; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_129 = 3'h5 == x_11; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_130 = 3'h5 == x_11 ? neg_b : _pp_temp_T_128; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  _pp_temp_T_131 = 3'h6 == x_11; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_11 = 3'h6 == x_11 ? neg_b : _pp_temp_T_130; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_11 = pp_temp_11[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_56 = _pp_temp_T_116 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_58 = _pp_temp_T_118 ? 2'h1 : _t_T_56; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_11 = _pp_temp_T_120 ? 2'h1 : _t_T_58; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_340 = ~s_11; // @[src/main/scala/fudian/utils/Multiplier.scala 56:24]
  wire [29:0] pp_11 = {1'h1,_T_340,pp_temp_11,t_11}; // @[src/main/scala/fudian/utils/Multiplier.scala 56:13]
  wire  x_signBit = io_a[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 9:20]
  wire [2:0] x_12 = {x_signBit,io_a[24:23]}; // @[src/main/scala/fudian/utils/Multiplier.scala 10:41]
  wire [25:0] _pp_temp_T_133 = 3'h1 == x_12 ? b_sext : 26'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_135 = 3'h2 == x_12 ? b_sext : _pp_temp_T_133; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_137 = 3'h3 == x_12 ? bx2 : _pp_temp_T_135; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_139 = 3'h4 == x_12 ? neg_bx2 : _pp_temp_T_137; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] _pp_temp_T_141 = 3'h5 == x_12 ? neg_b : _pp_temp_T_139; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire [25:0] pp_temp_12 = 3'h6 == x_12 ? neg_b : _pp_temp_T_141; // @[src/main/scala/fudian/utils/Multiplier.scala 35:36]
  wire  s_12 = pp_temp_12[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 43:20]
  wire [1:0] _t_T_61 = _pp_temp_T_127 ? 2'h2 : 2'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] _t_T_63 = _pp_temp_T_129 ? 2'h1 : _t_T_61; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire [1:0] t_12 = _pp_temp_T_131 ? 2'h1 : _t_T_63; // @[src/main/scala/fudian/utils/Multiplier.scala 44:40]
  wire  _T_371 = ~s_12; // @[src/main/scala/fudian/utils/Multiplier.scala 54:14]
  wire [28:0] pp_12 = {_T_371,pp_temp_12,t_12}; // @[src/main/scala/fudian/utils/Multiplier.scala 54:13]
  wire  s_0 = c22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  s_0_50 = c22_12_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  s_0_99 = c22_32_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  s_0_147 = c22_56_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_147 = c22_56_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_148 = c22_57_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_148 = c22_57_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_149 = c22_58_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_149 = c22_58_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_150 = c22_59_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_150 = c22_59_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_151 = c22_60_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_151 = c22_60_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_152 = c22_61_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_152 = c22_61_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_153 = c22_62_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_153 = c22_62_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_154 = c22_63_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_154 = c22_63_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_155 = c22_64_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_155 = c22_64_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_156 = c22_65_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_156 = c22_65_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_157 = c22_66_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_157 = c22_66_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_158 = c22_67_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_158 = c22_67_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_159 = c22_68_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_159 = c22_68_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_160 = c22_69_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_160 = c22_69_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_161 = c22_70_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_161 = c22_70_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_162 = c22_71_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_162 = c22_71_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_163 = c22_72_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_163 = c22_72_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_164 = c22_73_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_164 = c22_73_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_165 = c22_74_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_165 = c22_74_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_166 = c22_75_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_166 = c22_75_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_167 = c22_76_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_167 = c22_76_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_168 = c22_77_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_168 = c22_77_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_169 = c22_78_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_169 = c22_78_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_170 = c22_79_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_170 = c22_79_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_171 = c22_80_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_171 = c22_80_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_172 = c22_81_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_172 = c22_81_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_173 = c22_82_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_173 = c22_82_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_174 = c22_83_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_174 = c22_83_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_175 = c22_84_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_175 = c22_84_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_176 = c22_85_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_176 = c22_85_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_177 = c22_86_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_177 = c22_86_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_178 = c22_87_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_178 = c22_87_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_179 = c22_88_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_179 = c22_88_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_180 = c32_31_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  wire  c2_0_180 = c32_31_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  wire  s_0_181 = c22_89_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_181 = c22_89_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_182 = c22_90_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_182 = c22_90_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_183 = c22_91_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_183 = c22_91_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_184 = c22_92_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_184 = c22_92_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_185 = c22_93_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_185 = c22_93_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_186 = c22_94_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_186 = c22_94_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_187 = c22_95_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_187 = c22_95_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_188 = c22_96_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_188 = c22_96_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_189 = c22_97_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_189 = c22_97_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_190 = c22_98_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_190 = c22_98_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_191 = c22_99_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_191 = c22_99_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_192 = c22_100_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire  c2_0_192 = c22_100_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  wire  s_0_193 = c22_101_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  wire [5:0] sum_lo_lo_lo = {s_0_149,s_0_148,s_0_147,s_0_99,s_0_50,s_0}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [11:0] sum_lo_lo = {s_0_155,s_0_154,s_0_153,s_0_152,s_0_151,s_0_150,sum_lo_lo_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [5:0] sum_lo_hi_lo = {s_0_161,s_0_160,s_0_159,s_0_158,s_0_157,s_0_156}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [24:0] sum_lo = {s_0_168,s_0_167,s_0_166,s_0_165,s_0_164,s_0_163,s_0_162,sum_lo_hi_lo,sum_lo_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [5:0] sum_hi_lo_lo = {s_0_174,s_0_173,s_0_172,s_0_171,s_0_170,s_0_169}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [11:0] sum_hi_lo = {s_0_180,s_0_179,s_0_178,s_0_177,s_0_176,s_0_175,sum_hi_lo_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [5:0] sum_hi_hi_lo = {s_0_186,s_0_185,s_0_184,s_0_183,s_0_182,s_0_181}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [49:0] sum = {s_0_193,s_0_192,s_0_191,s_0_190,s_0_189,s_0_188,s_0_187,sum_hi_hi_lo,sum_hi_lo,sum_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 106:20]
  wire [4:0] carry_lo_lo_lo = {c2_0_151,c2_0_150,c2_0_149,c2_0_148,c2_0_147}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [10:0] carry_lo_lo = {c2_0_157,c2_0_156,c2_0_155,c2_0_154,c2_0_153,c2_0_152,carry_lo_lo_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [5:0] carry_lo_hi_lo = {c2_0_163,c2_0_162,c2_0_161,c2_0_160,c2_0_159,c2_0_158}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [22:0] carry_lo = {c2_0_169,c2_0_168,c2_0_167,c2_0_166,c2_0_165,c2_0_164,carry_lo_hi_lo,carry_lo_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [4:0] carry_hi_lo_lo = {c2_0_174,c2_0_173,c2_0_172,c2_0_171,c2_0_170}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [10:0] carry_hi_lo = {c2_0_180,c2_0_179,c2_0_178,c2_0_177,c2_0_176,c2_0_175,carry_hi_lo_lo}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [5:0] carry_hi_hi_lo = {c2_0_186,c2_0_185,c2_0_184,c2_0_183,c2_0_182,c2_0_181}; // @[src/main/scala/fudian/utils/Multiplier.scala 109:22]
  wire [49:0] carry_1 = {c2_0_192,c2_0_191,c2_0_190,c2_0_189,c2_0_188,c2_0_187,carry_hi_hi_lo,carry_hi_lo,carry_lo,4'h0}
    ; // @[src/main/scala/fudian/utils/Multiplier.scala 110:16]
  C22 c22 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_io_in_0),
    .io_in_1(c22_io_in_1),
    .io_out_0(c22_io_out_0),
    .io_out_1(c22_io_out_1)
  );
  C22 c22_1 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_1_io_in_0),
    .io_in_1(c22_1_io_in_1),
    .io_out_0(c22_1_io_out_0),
    .io_out_1(c22_1_io_out_1)
  );
  C32 c32 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_io_in_0),
    .io_in_1(c32_io_in_1),
    .io_in_2(c32_io_in_2),
    .io_out_0(c32_io_out_0),
    .io_out_1(c32_io_out_1)
  );
  C32 c32_1 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_1_io_in_0),
    .io_in_1(c32_1_io_in_1),
    .io_in_2(c32_1_io_in_2),
    .io_out_0(c32_1_io_out_0),
    .io_out_1(c32_1_io_out_1)
  );
  C53 c53 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_io_in_0),
    .io_in_1(c53_io_in_1),
    .io_in_2(c53_io_in_2),
    .io_in_3(c53_io_in_3),
    .io_in_4(c53_io_in_4),
    .io_out_0(c53_io_out_0),
    .io_out_1(c53_io_out_1),
    .io_out_2(c53_io_out_2)
  );
  C53 c53_1 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_1_io_in_0),
    .io_in_1(c53_1_io_in_1),
    .io_in_2(c53_1_io_in_2),
    .io_in_3(c53_1_io_in_3),
    .io_in_4(c53_1_io_in_4),
    .io_out_0(c53_1_io_out_0),
    .io_out_1(c53_1_io_out_1),
    .io_out_2(c53_1_io_out_2)
  );
  C53 c53_2 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_2_io_in_0),
    .io_in_1(c53_2_io_in_1),
    .io_in_2(c53_2_io_in_2),
    .io_in_3(c53_2_io_in_3),
    .io_in_4(c53_2_io_in_4),
    .io_out_0(c53_2_io_out_0),
    .io_out_1(c53_2_io_out_1),
    .io_out_2(c53_2_io_out_2)
  );
  C53 c53_3 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_3_io_in_0),
    .io_in_1(c53_3_io_in_1),
    .io_in_2(c53_3_io_in_2),
    .io_in_3(c53_3_io_in_3),
    .io_in_4(c53_3_io_in_4),
    .io_out_0(c53_3_io_out_0),
    .io_out_1(c53_3_io_out_1),
    .io_out_2(c53_3_io_out_2)
  );
  C53 c53_4 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_4_io_in_0),
    .io_in_1(c53_4_io_in_1),
    .io_in_2(c53_4_io_in_2),
    .io_in_3(c53_4_io_in_3),
    .io_in_4(c53_4_io_in_4),
    .io_out_0(c53_4_io_out_0),
    .io_out_1(c53_4_io_out_1),
    .io_out_2(c53_4_io_out_2)
  );
  C22 c22_2 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_2_io_in_0),
    .io_in_1(c22_2_io_in_1),
    .io_out_0(c22_2_io_out_0),
    .io_out_1(c22_2_io_out_1)
  );
  C53 c53_5 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_5_io_in_0),
    .io_in_1(c53_5_io_in_1),
    .io_in_2(c53_5_io_in_2),
    .io_in_3(c53_5_io_in_3),
    .io_in_4(c53_5_io_in_4),
    .io_out_0(c53_5_io_out_0),
    .io_out_1(c53_5_io_out_1),
    .io_out_2(c53_5_io_out_2)
  );
  C22 c22_3 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_3_io_in_0),
    .io_in_1(c22_3_io_in_1),
    .io_out_0(c22_3_io_out_0),
    .io_out_1(c22_3_io_out_1)
  );
  C53 c53_6 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_6_io_in_0),
    .io_in_1(c53_6_io_in_1),
    .io_in_2(c53_6_io_in_2),
    .io_in_3(c53_6_io_in_3),
    .io_in_4(c53_6_io_in_4),
    .io_out_0(c53_6_io_out_0),
    .io_out_1(c53_6_io_out_1),
    .io_out_2(c53_6_io_out_2)
  );
  C32 c32_2 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_2_io_in_0),
    .io_in_1(c32_2_io_in_1),
    .io_in_2(c32_2_io_in_2),
    .io_out_0(c32_2_io_out_0),
    .io_out_1(c32_2_io_out_1)
  );
  C53 c53_7 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_7_io_in_0),
    .io_in_1(c53_7_io_in_1),
    .io_in_2(c53_7_io_in_2),
    .io_in_3(c53_7_io_in_3),
    .io_in_4(c53_7_io_in_4),
    .io_out_0(c53_7_io_out_0),
    .io_out_1(c53_7_io_out_1),
    .io_out_2(c53_7_io_out_2)
  );
  C32 c32_3 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_3_io_in_0),
    .io_in_1(c32_3_io_in_1),
    .io_in_2(c32_3_io_in_2),
    .io_out_0(c32_3_io_out_0),
    .io_out_1(c32_3_io_out_1)
  );
  C53 c53_8 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_8_io_in_0),
    .io_in_1(c53_8_io_in_1),
    .io_in_2(c53_8_io_in_2),
    .io_in_3(c53_8_io_in_3),
    .io_in_4(c53_8_io_in_4),
    .io_out_0(c53_8_io_out_0),
    .io_out_1(c53_8_io_out_1),
    .io_out_2(c53_8_io_out_2)
  );
  C53 c53_9 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_9_io_in_0),
    .io_in_1(c53_9_io_in_1),
    .io_in_2(c53_9_io_in_2),
    .io_in_3(c53_9_io_in_3),
    .io_in_4(c53_9_io_in_4),
    .io_out_0(c53_9_io_out_0),
    .io_out_1(c53_9_io_out_1),
    .io_out_2(c53_9_io_out_2)
  );
  C53 c53_10 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_10_io_in_0),
    .io_in_1(c53_10_io_in_1),
    .io_in_2(c53_10_io_in_2),
    .io_in_3(c53_10_io_in_3),
    .io_in_4(c53_10_io_in_4),
    .io_out_0(c53_10_io_out_0),
    .io_out_1(c53_10_io_out_1),
    .io_out_2(c53_10_io_out_2)
  );
  C53 c53_11 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_11_io_in_0),
    .io_in_1(c53_11_io_in_1),
    .io_in_2(c53_11_io_in_2),
    .io_in_3(c53_11_io_in_3),
    .io_in_4(c53_11_io_in_4),
    .io_out_0(c53_11_io_out_0),
    .io_out_1(c53_11_io_out_1),
    .io_out_2(c53_11_io_out_2)
  );
  C53 c53_12 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_12_io_in_0),
    .io_in_1(c53_12_io_in_1),
    .io_in_2(c53_12_io_in_2),
    .io_in_3(c53_12_io_in_3),
    .io_in_4(c53_12_io_in_4),
    .io_out_0(c53_12_io_out_0),
    .io_out_1(c53_12_io_out_1),
    .io_out_2(c53_12_io_out_2)
  );
  C53 c53_13 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_13_io_in_0),
    .io_in_1(c53_13_io_in_1),
    .io_in_2(c53_13_io_in_2),
    .io_in_3(c53_13_io_in_3),
    .io_in_4(c53_13_io_in_4),
    .io_out_0(c53_13_io_out_0),
    .io_out_1(c53_13_io_out_1),
    .io_out_2(c53_13_io_out_2)
  );
  C53 c53_14 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_14_io_in_0),
    .io_in_1(c53_14_io_in_1),
    .io_in_2(c53_14_io_in_2),
    .io_in_3(c53_14_io_in_3),
    .io_in_4(c53_14_io_in_4),
    .io_out_0(c53_14_io_out_0),
    .io_out_1(c53_14_io_out_1),
    .io_out_2(c53_14_io_out_2)
  );
  C53 c53_15 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_15_io_in_0),
    .io_in_1(c53_15_io_in_1),
    .io_in_2(c53_15_io_in_2),
    .io_in_3(c53_15_io_in_3),
    .io_in_4(c53_15_io_in_4),
    .io_out_0(c53_15_io_out_0),
    .io_out_1(c53_15_io_out_1),
    .io_out_2(c53_15_io_out_2)
  );
  C53 c53_16 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_16_io_in_0),
    .io_in_1(c53_16_io_in_1),
    .io_in_2(c53_16_io_in_2),
    .io_in_3(c53_16_io_in_3),
    .io_in_4(c53_16_io_in_4),
    .io_out_0(c53_16_io_out_0),
    .io_out_1(c53_16_io_out_1),
    .io_out_2(c53_16_io_out_2)
  );
  C53 c53_17 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_17_io_in_0),
    .io_in_1(c53_17_io_in_1),
    .io_in_2(c53_17_io_in_2),
    .io_in_3(c53_17_io_in_3),
    .io_in_4(c53_17_io_in_4),
    .io_out_0(c53_17_io_out_0),
    .io_out_1(c53_17_io_out_1),
    .io_out_2(c53_17_io_out_2)
  );
  C22 c22_4 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_4_io_in_0),
    .io_in_1(c22_4_io_in_1),
    .io_out_0(c22_4_io_out_0),
    .io_out_1(c22_4_io_out_1)
  );
  C53 c53_18 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_18_io_in_0),
    .io_in_1(c53_18_io_in_1),
    .io_in_2(c53_18_io_in_2),
    .io_in_3(c53_18_io_in_3),
    .io_in_4(c53_18_io_in_4),
    .io_out_0(c53_18_io_out_0),
    .io_out_1(c53_18_io_out_1),
    .io_out_2(c53_18_io_out_2)
  );
  C53 c53_19 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_19_io_in_0),
    .io_in_1(c53_19_io_in_1),
    .io_in_2(c53_19_io_in_2),
    .io_in_3(c53_19_io_in_3),
    .io_in_4(c53_19_io_in_4),
    .io_out_0(c53_19_io_out_0),
    .io_out_1(c53_19_io_out_1),
    .io_out_2(c53_19_io_out_2)
  );
  C22 c22_5 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_5_io_in_0),
    .io_in_1(c22_5_io_in_1),
    .io_out_0(c22_5_io_out_0),
    .io_out_1(c22_5_io_out_1)
  );
  C53 c53_20 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_20_io_in_0),
    .io_in_1(c53_20_io_in_1),
    .io_in_2(c53_20_io_in_2),
    .io_in_3(c53_20_io_in_3),
    .io_in_4(c53_20_io_in_4),
    .io_out_0(c53_20_io_out_0),
    .io_out_1(c53_20_io_out_1),
    .io_out_2(c53_20_io_out_2)
  );
  C53 c53_21 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_21_io_in_0),
    .io_in_1(c53_21_io_in_1),
    .io_in_2(c53_21_io_in_2),
    .io_in_3(c53_21_io_in_3),
    .io_in_4(c53_21_io_in_4),
    .io_out_0(c53_21_io_out_0),
    .io_out_1(c53_21_io_out_1),
    .io_out_2(c53_21_io_out_2)
  );
  C32 c32_4 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_4_io_in_0),
    .io_in_1(c32_4_io_in_1),
    .io_in_2(c32_4_io_in_2),
    .io_out_0(c32_4_io_out_0),
    .io_out_1(c32_4_io_out_1)
  );
  C53 c53_22 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_22_io_in_0),
    .io_in_1(c53_22_io_in_1),
    .io_in_2(c53_22_io_in_2),
    .io_in_3(c53_22_io_in_3),
    .io_in_4(c53_22_io_in_4),
    .io_out_0(c53_22_io_out_0),
    .io_out_1(c53_22_io_out_1),
    .io_out_2(c53_22_io_out_2)
  );
  C53 c53_23 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_23_io_in_0),
    .io_in_1(c53_23_io_in_1),
    .io_in_2(c53_23_io_in_2),
    .io_in_3(c53_23_io_in_3),
    .io_in_4(c53_23_io_in_4),
    .io_out_0(c53_23_io_out_0),
    .io_out_1(c53_23_io_out_1),
    .io_out_2(c53_23_io_out_2)
  );
  C32 c32_5 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_5_io_in_0),
    .io_in_1(c32_5_io_in_1),
    .io_in_2(c32_5_io_in_2),
    .io_out_0(c32_5_io_out_0),
    .io_out_1(c32_5_io_out_1)
  );
  C53 c53_24 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_24_io_in_0),
    .io_in_1(c53_24_io_in_1),
    .io_in_2(c53_24_io_in_2),
    .io_in_3(c53_24_io_in_3),
    .io_in_4(c53_24_io_in_4),
    .io_out_0(c53_24_io_out_0),
    .io_out_1(c53_24_io_out_1),
    .io_out_2(c53_24_io_out_2)
  );
  C53 c53_25 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_25_io_in_0),
    .io_in_1(c53_25_io_in_1),
    .io_in_2(c53_25_io_in_2),
    .io_in_3(c53_25_io_in_3),
    .io_in_4(c53_25_io_in_4),
    .io_out_0(c53_25_io_out_0),
    .io_out_1(c53_25_io_out_1),
    .io_out_2(c53_25_io_out_2)
  );
  C53 c53_26 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_26_io_in_0),
    .io_in_1(c53_26_io_in_1),
    .io_in_2(c53_26_io_in_2),
    .io_in_3(c53_26_io_in_3),
    .io_in_4(c53_26_io_in_4),
    .io_out_0(c53_26_io_out_0),
    .io_out_1(c53_26_io_out_1),
    .io_out_2(c53_26_io_out_2)
  );
  C53 c53_27 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_27_io_in_0),
    .io_in_1(c53_27_io_in_1),
    .io_in_2(c53_27_io_in_2),
    .io_in_3(c53_27_io_in_3),
    .io_in_4(c53_27_io_in_4),
    .io_out_0(c53_27_io_out_0),
    .io_out_1(c53_27_io_out_1),
    .io_out_2(c53_27_io_out_2)
  );
  C53 c53_28 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_28_io_in_0),
    .io_in_1(c53_28_io_in_1),
    .io_in_2(c53_28_io_in_2),
    .io_in_3(c53_28_io_in_3),
    .io_in_4(c53_28_io_in_4),
    .io_out_0(c53_28_io_out_0),
    .io_out_1(c53_28_io_out_1),
    .io_out_2(c53_28_io_out_2)
  );
  C53 c53_29 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_29_io_in_0),
    .io_in_1(c53_29_io_in_1),
    .io_in_2(c53_29_io_in_2),
    .io_in_3(c53_29_io_in_3),
    .io_in_4(c53_29_io_in_4),
    .io_out_0(c53_29_io_out_0),
    .io_out_1(c53_29_io_out_1),
    .io_out_2(c53_29_io_out_2)
  );
  C53 c53_30 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_30_io_in_0),
    .io_in_1(c53_30_io_in_1),
    .io_in_2(c53_30_io_in_2),
    .io_in_3(c53_30_io_in_3),
    .io_in_4(c53_30_io_in_4),
    .io_out_0(c53_30_io_out_0),
    .io_out_1(c53_30_io_out_1),
    .io_out_2(c53_30_io_out_2)
  );
  C53 c53_31 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_31_io_in_0),
    .io_in_1(c53_31_io_in_1),
    .io_in_2(c53_31_io_in_2),
    .io_in_3(c53_31_io_in_3),
    .io_in_4(c53_31_io_in_4),
    .io_out_0(c53_31_io_out_0),
    .io_out_1(c53_31_io_out_1),
    .io_out_2(c53_31_io_out_2)
  );
  C53 c53_32 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_32_io_in_0),
    .io_in_1(c53_32_io_in_1),
    .io_in_2(c53_32_io_in_2),
    .io_in_3(c53_32_io_in_3),
    .io_in_4(c53_32_io_in_4),
    .io_out_0(c53_32_io_out_0),
    .io_out_1(c53_32_io_out_1),
    .io_out_2(c53_32_io_out_2)
  );
  C53 c53_33 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_33_io_in_0),
    .io_in_1(c53_33_io_in_1),
    .io_in_2(c53_33_io_in_2),
    .io_in_3(c53_33_io_in_3),
    .io_in_4(c53_33_io_in_4),
    .io_out_0(c53_33_io_out_0),
    .io_out_1(c53_33_io_out_1),
    .io_out_2(c53_33_io_out_2)
  );
  C53 c53_34 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_34_io_in_0),
    .io_in_1(c53_34_io_in_1),
    .io_in_2(c53_34_io_in_2),
    .io_in_3(c53_34_io_in_3),
    .io_in_4(c53_34_io_in_4),
    .io_out_0(c53_34_io_out_0),
    .io_out_1(c53_34_io_out_1),
    .io_out_2(c53_34_io_out_2)
  );
  C53 c53_35 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_35_io_in_0),
    .io_in_1(c53_35_io_in_1),
    .io_in_2(c53_35_io_in_2),
    .io_in_3(c53_35_io_in_3),
    .io_in_4(c53_35_io_in_4),
    .io_out_0(c53_35_io_out_0),
    .io_out_1(c53_35_io_out_1),
    .io_out_2(c53_35_io_out_2)
  );
  C53 c53_36 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_36_io_in_0),
    .io_in_1(c53_36_io_in_1),
    .io_in_2(c53_36_io_in_2),
    .io_in_3(c53_36_io_in_3),
    .io_in_4(c53_36_io_in_4),
    .io_out_0(c53_36_io_out_0),
    .io_out_1(c53_36_io_out_1),
    .io_out_2(c53_36_io_out_2)
  );
  C53 c53_37 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_37_io_in_0),
    .io_in_1(c53_37_io_in_1),
    .io_in_2(c53_37_io_in_2),
    .io_in_3(c53_37_io_in_3),
    .io_in_4(c53_37_io_in_4),
    .io_out_0(c53_37_io_out_0),
    .io_out_1(c53_37_io_out_1),
    .io_out_2(c53_37_io_out_2)
  );
  C53 c53_38 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_38_io_in_0),
    .io_in_1(c53_38_io_in_1),
    .io_in_2(c53_38_io_in_2),
    .io_in_3(c53_38_io_in_3),
    .io_in_4(c53_38_io_in_4),
    .io_out_0(c53_38_io_out_0),
    .io_out_1(c53_38_io_out_1),
    .io_out_2(c53_38_io_out_2)
  );
  C53 c53_39 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_39_io_in_0),
    .io_in_1(c53_39_io_in_1),
    .io_in_2(c53_39_io_in_2),
    .io_in_3(c53_39_io_in_3),
    .io_in_4(c53_39_io_in_4),
    .io_out_0(c53_39_io_out_0),
    .io_out_1(c53_39_io_out_1),
    .io_out_2(c53_39_io_out_2)
  );
  C53 c53_40 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_40_io_in_0),
    .io_in_1(c53_40_io_in_1),
    .io_in_2(c53_40_io_in_2),
    .io_in_3(c53_40_io_in_3),
    .io_in_4(c53_40_io_in_4),
    .io_out_0(c53_40_io_out_0),
    .io_out_1(c53_40_io_out_1),
    .io_out_2(c53_40_io_out_2)
  );
  C53 c53_41 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_41_io_in_0),
    .io_in_1(c53_41_io_in_1),
    .io_in_2(c53_41_io_in_2),
    .io_in_3(c53_41_io_in_3),
    .io_in_4(c53_41_io_in_4),
    .io_out_0(c53_41_io_out_0),
    .io_out_1(c53_41_io_out_1),
    .io_out_2(c53_41_io_out_2)
  );
  C53 c53_42 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_42_io_in_0),
    .io_in_1(c53_42_io_in_1),
    .io_in_2(c53_42_io_in_2),
    .io_in_3(c53_42_io_in_3),
    .io_in_4(c53_42_io_in_4),
    .io_out_0(c53_42_io_out_0),
    .io_out_1(c53_42_io_out_1),
    .io_out_2(c53_42_io_out_2)
  );
  C53 c53_43 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_43_io_in_0),
    .io_in_1(c53_43_io_in_1),
    .io_in_2(c53_43_io_in_2),
    .io_in_3(c53_43_io_in_3),
    .io_in_4(c53_43_io_in_4),
    .io_out_0(c53_43_io_out_0),
    .io_out_1(c53_43_io_out_1),
    .io_out_2(c53_43_io_out_2)
  );
  C53 c53_44 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_44_io_in_0),
    .io_in_1(c53_44_io_in_1),
    .io_in_2(c53_44_io_in_2),
    .io_in_3(c53_44_io_in_3),
    .io_in_4(c53_44_io_in_4),
    .io_out_0(c53_44_io_out_0),
    .io_out_1(c53_44_io_out_1),
    .io_out_2(c53_44_io_out_2)
  );
  C53 c53_45 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_45_io_in_0),
    .io_in_1(c53_45_io_in_1),
    .io_in_2(c53_45_io_in_2),
    .io_in_3(c53_45_io_in_3),
    .io_in_4(c53_45_io_in_4),
    .io_out_0(c53_45_io_out_0),
    .io_out_1(c53_45_io_out_1),
    .io_out_2(c53_45_io_out_2)
  );
  C53 c53_46 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_46_io_in_0),
    .io_in_1(c53_46_io_in_1),
    .io_in_2(c53_46_io_in_2),
    .io_in_3(c53_46_io_in_3),
    .io_in_4(c53_46_io_in_4),
    .io_out_0(c53_46_io_out_0),
    .io_out_1(c53_46_io_out_1),
    .io_out_2(c53_46_io_out_2)
  );
  C53 c53_47 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_47_io_in_0),
    .io_in_1(c53_47_io_in_1),
    .io_in_2(c53_47_io_in_2),
    .io_in_3(c53_47_io_in_3),
    .io_in_4(c53_47_io_in_4),
    .io_out_0(c53_47_io_out_0),
    .io_out_1(c53_47_io_out_1),
    .io_out_2(c53_47_io_out_2)
  );
  C53 c53_48 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_48_io_in_0),
    .io_in_1(c53_48_io_in_1),
    .io_in_2(c53_48_io_in_2),
    .io_in_3(c53_48_io_in_3),
    .io_in_4(c53_48_io_in_4),
    .io_out_0(c53_48_io_out_0),
    .io_out_1(c53_48_io_out_1),
    .io_out_2(c53_48_io_out_2)
  );
  C53 c53_49 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_49_io_in_0),
    .io_in_1(c53_49_io_in_1),
    .io_in_2(c53_49_io_in_2),
    .io_in_3(c53_49_io_in_3),
    .io_in_4(c53_49_io_in_4),
    .io_out_0(c53_49_io_out_0),
    .io_out_1(c53_49_io_out_1),
    .io_out_2(c53_49_io_out_2)
  );
  C53 c53_50 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_50_io_in_0),
    .io_in_1(c53_50_io_in_1),
    .io_in_2(c53_50_io_in_2),
    .io_in_3(c53_50_io_in_3),
    .io_in_4(c53_50_io_in_4),
    .io_out_0(c53_50_io_out_0),
    .io_out_1(c53_50_io_out_1),
    .io_out_2(c53_50_io_out_2)
  );
  C53 c53_51 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_51_io_in_0),
    .io_in_1(c53_51_io_in_1),
    .io_in_2(c53_51_io_in_2),
    .io_in_3(c53_51_io_in_3),
    .io_in_4(c53_51_io_in_4),
    .io_out_0(c53_51_io_out_0),
    .io_out_1(c53_51_io_out_1),
    .io_out_2(c53_51_io_out_2)
  );
  C53 c53_52 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_52_io_in_0),
    .io_in_1(c53_52_io_in_1),
    .io_in_2(c53_52_io_in_2),
    .io_in_3(c53_52_io_in_3),
    .io_in_4(c53_52_io_in_4),
    .io_out_0(c53_52_io_out_0),
    .io_out_1(c53_52_io_out_1),
    .io_out_2(c53_52_io_out_2)
  );
  C53 c53_53 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_53_io_in_0),
    .io_in_1(c53_53_io_in_1),
    .io_in_2(c53_53_io_in_2),
    .io_in_3(c53_53_io_in_3),
    .io_in_4(c53_53_io_in_4),
    .io_out_0(c53_53_io_out_0),
    .io_out_1(c53_53_io_out_1),
    .io_out_2(c53_53_io_out_2)
  );
  C53 c53_54 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_54_io_in_0),
    .io_in_1(c53_54_io_in_1),
    .io_in_2(c53_54_io_in_2),
    .io_in_3(c53_54_io_in_3),
    .io_in_4(c53_54_io_in_4),
    .io_out_0(c53_54_io_out_0),
    .io_out_1(c53_54_io_out_1),
    .io_out_2(c53_54_io_out_2)
  );
  C53 c53_55 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_55_io_in_0),
    .io_in_1(c53_55_io_in_1),
    .io_in_2(c53_55_io_in_2),
    .io_in_3(c53_55_io_in_3),
    .io_in_4(c53_55_io_in_4),
    .io_out_0(c53_55_io_out_0),
    .io_out_1(c53_55_io_out_1),
    .io_out_2(c53_55_io_out_2)
  );
  C32 c32_6 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_6_io_in_0),
    .io_in_1(c32_6_io_in_1),
    .io_in_2(c32_6_io_in_2),
    .io_out_0(c32_6_io_out_0),
    .io_out_1(c32_6_io_out_1)
  );
  C53 c53_56 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_56_io_in_0),
    .io_in_1(c53_56_io_in_1),
    .io_in_2(c53_56_io_in_2),
    .io_in_3(c53_56_io_in_3),
    .io_in_4(c53_56_io_in_4),
    .io_out_0(c53_56_io_out_0),
    .io_out_1(c53_56_io_out_1),
    .io_out_2(c53_56_io_out_2)
  );
  C53 c53_57 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_57_io_in_0),
    .io_in_1(c53_57_io_in_1),
    .io_in_2(c53_57_io_in_2),
    .io_in_3(c53_57_io_in_3),
    .io_in_4(c53_57_io_in_4),
    .io_out_0(c53_57_io_out_0),
    .io_out_1(c53_57_io_out_1),
    .io_out_2(c53_57_io_out_2)
  );
  C32 c32_7 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_7_io_in_0),
    .io_in_1(c32_7_io_in_1),
    .io_in_2(c32_7_io_in_2),
    .io_out_0(c32_7_io_out_0),
    .io_out_1(c32_7_io_out_1)
  );
  C53 c53_58 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_58_io_in_0),
    .io_in_1(c53_58_io_in_1),
    .io_in_2(c53_58_io_in_2),
    .io_in_3(c53_58_io_in_3),
    .io_in_4(c53_58_io_in_4),
    .io_out_0(c53_58_io_out_0),
    .io_out_1(c53_58_io_out_1),
    .io_out_2(c53_58_io_out_2)
  );
  C53 c53_59 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_59_io_in_0),
    .io_in_1(c53_59_io_in_1),
    .io_in_2(c53_59_io_in_2),
    .io_in_3(c53_59_io_in_3),
    .io_in_4(c53_59_io_in_4),
    .io_out_0(c53_59_io_out_0),
    .io_out_1(c53_59_io_out_1),
    .io_out_2(c53_59_io_out_2)
  );
  C22 c22_6 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_6_io_in_0),
    .io_in_1(c22_6_io_in_1),
    .io_out_0(c22_6_io_out_0),
    .io_out_1(c22_6_io_out_1)
  );
  C53 c53_60 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_60_io_in_0),
    .io_in_1(c53_60_io_in_1),
    .io_in_2(c53_60_io_in_2),
    .io_in_3(c53_60_io_in_3),
    .io_in_4(c53_60_io_in_4),
    .io_out_0(c53_60_io_out_0),
    .io_out_1(c53_60_io_out_1),
    .io_out_2(c53_60_io_out_2)
  );
  C53 c53_61 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_61_io_in_0),
    .io_in_1(c53_61_io_in_1),
    .io_in_2(c53_61_io_in_2),
    .io_in_3(c53_61_io_in_3),
    .io_in_4(c53_61_io_in_4),
    .io_out_0(c53_61_io_out_0),
    .io_out_1(c53_61_io_out_1),
    .io_out_2(c53_61_io_out_2)
  );
  C22 c22_7 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_7_io_in_0),
    .io_in_1(c22_7_io_in_1),
    .io_out_0(c22_7_io_out_0),
    .io_out_1(c22_7_io_out_1)
  );
  C53 c53_62 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_62_io_in_0),
    .io_in_1(c53_62_io_in_1),
    .io_in_2(c53_62_io_in_2),
    .io_in_3(c53_62_io_in_3),
    .io_in_4(c53_62_io_in_4),
    .io_out_0(c53_62_io_out_0),
    .io_out_1(c53_62_io_out_1),
    .io_out_2(c53_62_io_out_2)
  );
  C53 c53_63 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_63_io_in_0),
    .io_in_1(c53_63_io_in_1),
    .io_in_2(c53_63_io_in_2),
    .io_in_3(c53_63_io_in_3),
    .io_in_4(c53_63_io_in_4),
    .io_out_0(c53_63_io_out_0),
    .io_out_1(c53_63_io_out_1),
    .io_out_2(c53_63_io_out_2)
  );
  C53 c53_64 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_64_io_in_0),
    .io_in_1(c53_64_io_in_1),
    .io_in_2(c53_64_io_in_2),
    .io_in_3(c53_64_io_in_3),
    .io_in_4(c53_64_io_in_4),
    .io_out_0(c53_64_io_out_0),
    .io_out_1(c53_64_io_out_1),
    .io_out_2(c53_64_io_out_2)
  );
  C53 c53_65 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_65_io_in_0),
    .io_in_1(c53_65_io_in_1),
    .io_in_2(c53_65_io_in_2),
    .io_in_3(c53_65_io_in_3),
    .io_in_4(c53_65_io_in_4),
    .io_out_0(c53_65_io_out_0),
    .io_out_1(c53_65_io_out_1),
    .io_out_2(c53_65_io_out_2)
  );
  C53 c53_66 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_66_io_in_0),
    .io_in_1(c53_66_io_in_1),
    .io_in_2(c53_66_io_in_2),
    .io_in_3(c53_66_io_in_3),
    .io_in_4(c53_66_io_in_4),
    .io_out_0(c53_66_io_out_0),
    .io_out_1(c53_66_io_out_1),
    .io_out_2(c53_66_io_out_2)
  );
  C53 c53_67 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_67_io_in_0),
    .io_in_1(c53_67_io_in_1),
    .io_in_2(c53_67_io_in_2),
    .io_in_3(c53_67_io_in_3),
    .io_in_4(c53_67_io_in_4),
    .io_out_0(c53_67_io_out_0),
    .io_out_1(c53_67_io_out_1),
    .io_out_2(c53_67_io_out_2)
  );
  C53 c53_68 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_68_io_in_0),
    .io_in_1(c53_68_io_in_1),
    .io_in_2(c53_68_io_in_2),
    .io_in_3(c53_68_io_in_3),
    .io_in_4(c53_68_io_in_4),
    .io_out_0(c53_68_io_out_0),
    .io_out_1(c53_68_io_out_1),
    .io_out_2(c53_68_io_out_2)
  );
  C53 c53_69 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_69_io_in_0),
    .io_in_1(c53_69_io_in_1),
    .io_in_2(c53_69_io_in_2),
    .io_in_3(c53_69_io_in_3),
    .io_in_4(c53_69_io_in_4),
    .io_out_0(c53_69_io_out_0),
    .io_out_1(c53_69_io_out_1),
    .io_out_2(c53_69_io_out_2)
  );
  C53 c53_70 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_70_io_in_0),
    .io_in_1(c53_70_io_in_1),
    .io_in_2(c53_70_io_in_2),
    .io_in_3(c53_70_io_in_3),
    .io_in_4(c53_70_io_in_4),
    .io_out_0(c53_70_io_out_0),
    .io_out_1(c53_70_io_out_1),
    .io_out_2(c53_70_io_out_2)
  );
  C32 c32_8 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_8_io_in_0),
    .io_in_1(c32_8_io_in_1),
    .io_in_2(c32_8_io_in_2),
    .io_out_0(c32_8_io_out_0),
    .io_out_1(c32_8_io_out_1)
  );
  C53 c53_71 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_71_io_in_0),
    .io_in_1(c53_71_io_in_1),
    .io_in_2(c53_71_io_in_2),
    .io_in_3(c53_71_io_in_3),
    .io_in_4(c53_71_io_in_4),
    .io_out_0(c53_71_io_out_0),
    .io_out_1(c53_71_io_out_1),
    .io_out_2(c53_71_io_out_2)
  );
  C32 c32_9 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_9_io_in_0),
    .io_in_1(c32_9_io_in_1),
    .io_in_2(c32_9_io_in_2),
    .io_out_0(c32_9_io_out_0),
    .io_out_1(c32_9_io_out_1)
  );
  C53 c53_72 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_72_io_in_0),
    .io_in_1(c53_72_io_in_1),
    .io_in_2(c53_72_io_in_2),
    .io_in_3(c53_72_io_in_3),
    .io_in_4(c53_72_io_in_4),
    .io_out_0(c53_72_io_out_0),
    .io_out_1(c53_72_io_out_1),
    .io_out_2(c53_72_io_out_2)
  );
  C22 c22_8 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_8_io_in_0),
    .io_in_1(c22_8_io_in_1),
    .io_out_0(c22_8_io_out_0),
    .io_out_1(c22_8_io_out_1)
  );
  C53 c53_73 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_73_io_in_0),
    .io_in_1(c53_73_io_in_1),
    .io_in_2(c53_73_io_in_2),
    .io_in_3(c53_73_io_in_3),
    .io_in_4(c53_73_io_in_4),
    .io_out_0(c53_73_io_out_0),
    .io_out_1(c53_73_io_out_1),
    .io_out_2(c53_73_io_out_2)
  );
  C22 c22_9 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_9_io_in_0),
    .io_in_1(c22_9_io_in_1),
    .io_out_0(c22_9_io_out_0),
    .io_out_1(c22_9_io_out_1)
  );
  C53 c53_74 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_74_io_in_0),
    .io_in_1(c53_74_io_in_1),
    .io_in_2(c53_74_io_in_2),
    .io_in_3(c53_74_io_in_3),
    .io_in_4(c53_74_io_in_4),
    .io_out_0(c53_74_io_out_0),
    .io_out_1(c53_74_io_out_1),
    .io_out_2(c53_74_io_out_2)
  );
  C53 c53_75 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_75_io_in_0),
    .io_in_1(c53_75_io_in_1),
    .io_in_2(c53_75_io_in_2),
    .io_in_3(c53_75_io_in_3),
    .io_in_4(c53_75_io_in_4),
    .io_out_0(c53_75_io_out_0),
    .io_out_1(c53_75_io_out_1),
    .io_out_2(c53_75_io_out_2)
  );
  C53 c53_76 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_76_io_in_0),
    .io_in_1(c53_76_io_in_1),
    .io_in_2(c53_76_io_in_2),
    .io_in_3(c53_76_io_in_3),
    .io_in_4(c53_76_io_in_4),
    .io_out_0(c53_76_io_out_0),
    .io_out_1(c53_76_io_out_1),
    .io_out_2(c53_76_io_out_2)
  );
  C53 c53_77 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_77_io_in_0),
    .io_in_1(c53_77_io_in_1),
    .io_in_2(c53_77_io_in_2),
    .io_in_3(c53_77_io_in_3),
    .io_in_4(c53_77_io_in_4),
    .io_out_0(c53_77_io_out_0),
    .io_out_1(c53_77_io_out_1),
    .io_out_2(c53_77_io_out_2)
  );
  C32 c32_10 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_10_io_in_0),
    .io_in_1(c32_10_io_in_1),
    .io_in_2(c32_10_io_in_2),
    .io_out_0(c32_10_io_out_0),
    .io_out_1(c32_10_io_out_1)
  );
  C32 c32_11 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_11_io_in_0),
    .io_in_1(c32_11_io_in_1),
    .io_in_2(c32_11_io_in_2),
    .io_out_0(c32_11_io_out_0),
    .io_out_1(c32_11_io_out_1)
  );
  C22 c22_10 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_10_io_in_0),
    .io_in_1(c22_10_io_in_1),
    .io_out_0(c22_10_io_out_0),
    .io_out_1(c22_10_io_out_1)
  );
  C22 c22_11 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_11_io_in_0),
    .io_in_1(c22_11_io_in_1),
    .io_out_0(c22_11_io_out_0),
    .io_out_1(c22_11_io_out_1)
  );
  C22 c22_12 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_12_io_in_0),
    .io_in_1(c22_12_io_in_1),
    .io_out_0(c22_12_io_out_0),
    .io_out_1(c22_12_io_out_1)
  );
  C22 c22_13 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_13_io_in_0),
    .io_in_1(c22_13_io_in_1),
    .io_out_0(c22_13_io_out_0),
    .io_out_1(c22_13_io_out_1)
  );
  C22 c22_14 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_14_io_in_0),
    .io_in_1(c22_14_io_in_1),
    .io_out_0(c22_14_io_out_0),
    .io_out_1(c22_14_io_out_1)
  );
  C22 c22_15 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_15_io_in_0),
    .io_in_1(c22_15_io_in_1),
    .io_out_0(c22_15_io_out_0),
    .io_out_1(c22_15_io_out_1)
  );
  C22 c22_16 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_16_io_in_0),
    .io_in_1(c22_16_io_in_1),
    .io_out_0(c22_16_io_out_0),
    .io_out_1(c22_16_io_out_1)
  );
  C32 c32_12 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_12_io_in_0),
    .io_in_1(c32_12_io_in_1),
    .io_in_2(c32_12_io_in_2),
    .io_out_0(c32_12_io_out_0),
    .io_out_1(c32_12_io_out_1)
  );
  C32 c32_13 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_13_io_in_0),
    .io_in_1(c32_13_io_in_1),
    .io_in_2(c32_13_io_in_2),
    .io_out_0(c32_13_io_out_0),
    .io_out_1(c32_13_io_out_1)
  );
  C32 c32_14 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_14_io_in_0),
    .io_in_1(c32_14_io_in_1),
    .io_in_2(c32_14_io_in_2),
    .io_out_0(c32_14_io_out_0),
    .io_out_1(c32_14_io_out_1)
  );
  C53 c53_78 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_78_io_in_0),
    .io_in_1(c53_78_io_in_1),
    .io_in_2(c53_78_io_in_2),
    .io_in_3(c53_78_io_in_3),
    .io_in_4(c53_78_io_in_4),
    .io_out_0(c53_78_io_out_0),
    .io_out_1(c53_78_io_out_1),
    .io_out_2(c53_78_io_out_2)
  );
  C53 c53_79 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_79_io_in_0),
    .io_in_1(c53_79_io_in_1),
    .io_in_2(c53_79_io_in_2),
    .io_in_3(c53_79_io_in_3),
    .io_in_4(c53_79_io_in_4),
    .io_out_0(c53_79_io_out_0),
    .io_out_1(c53_79_io_out_1),
    .io_out_2(c53_79_io_out_2)
  );
  C53 c53_80 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_80_io_in_0),
    .io_in_1(c53_80_io_in_1),
    .io_in_2(c53_80_io_in_2),
    .io_in_3(c53_80_io_in_3),
    .io_in_4(c53_80_io_in_4),
    .io_out_0(c53_80_io_out_0),
    .io_out_1(c53_80_io_out_1),
    .io_out_2(c53_80_io_out_2)
  );
  C53 c53_81 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_81_io_in_0),
    .io_in_1(c53_81_io_in_1),
    .io_in_2(c53_81_io_in_2),
    .io_in_3(c53_81_io_in_3),
    .io_in_4(c53_81_io_in_4),
    .io_out_0(c53_81_io_out_0),
    .io_out_1(c53_81_io_out_1),
    .io_out_2(c53_81_io_out_2)
  );
  C53 c53_82 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_82_io_in_0),
    .io_in_1(c53_82_io_in_1),
    .io_in_2(c53_82_io_in_2),
    .io_in_3(c53_82_io_in_3),
    .io_in_4(c53_82_io_in_4),
    .io_out_0(c53_82_io_out_0),
    .io_out_1(c53_82_io_out_1),
    .io_out_2(c53_82_io_out_2)
  );
  C53 c53_83 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_83_io_in_0),
    .io_in_1(c53_83_io_in_1),
    .io_in_2(c53_83_io_in_2),
    .io_in_3(c53_83_io_in_3),
    .io_in_4(c53_83_io_in_4),
    .io_out_0(c53_83_io_out_0),
    .io_out_1(c53_83_io_out_1),
    .io_out_2(c53_83_io_out_2)
  );
  C53 c53_84 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_84_io_in_0),
    .io_in_1(c53_84_io_in_1),
    .io_in_2(c53_84_io_in_2),
    .io_in_3(c53_84_io_in_3),
    .io_in_4(c53_84_io_in_4),
    .io_out_0(c53_84_io_out_0),
    .io_out_1(c53_84_io_out_1),
    .io_out_2(c53_84_io_out_2)
  );
  C53 c53_85 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_85_io_in_0),
    .io_in_1(c53_85_io_in_1),
    .io_in_2(c53_85_io_in_2),
    .io_in_3(c53_85_io_in_3),
    .io_in_4(c53_85_io_in_4),
    .io_out_0(c53_85_io_out_0),
    .io_out_1(c53_85_io_out_1),
    .io_out_2(c53_85_io_out_2)
  );
  C53 c53_86 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_86_io_in_0),
    .io_in_1(c53_86_io_in_1),
    .io_in_2(c53_86_io_in_2),
    .io_in_3(c53_86_io_in_3),
    .io_in_4(c53_86_io_in_4),
    .io_out_0(c53_86_io_out_0),
    .io_out_1(c53_86_io_out_1),
    .io_out_2(c53_86_io_out_2)
  );
  C22 c22_17 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_17_io_in_0),
    .io_in_1(c22_17_io_in_1),
    .io_out_0(c22_17_io_out_0),
    .io_out_1(c22_17_io_out_1)
  );
  C53 c53_87 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_87_io_in_0),
    .io_in_1(c53_87_io_in_1),
    .io_in_2(c53_87_io_in_2),
    .io_in_3(c53_87_io_in_3),
    .io_in_4(c53_87_io_in_4),
    .io_out_0(c53_87_io_out_0),
    .io_out_1(c53_87_io_out_1),
    .io_out_2(c53_87_io_out_2)
  );
  C22 c22_18 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_18_io_in_0),
    .io_in_1(c22_18_io_in_1),
    .io_out_0(c22_18_io_out_0),
    .io_out_1(c22_18_io_out_1)
  );
  C53 c53_88 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_88_io_in_0),
    .io_in_1(c53_88_io_in_1),
    .io_in_2(c53_88_io_in_2),
    .io_in_3(c53_88_io_in_3),
    .io_in_4(c53_88_io_in_4),
    .io_out_0(c53_88_io_out_0),
    .io_out_1(c53_88_io_out_1),
    .io_out_2(c53_88_io_out_2)
  );
  C22 c22_19 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_19_io_in_0),
    .io_in_1(c22_19_io_in_1),
    .io_out_0(c22_19_io_out_0),
    .io_out_1(c22_19_io_out_1)
  );
  C53 c53_89 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_89_io_in_0),
    .io_in_1(c53_89_io_in_1),
    .io_in_2(c53_89_io_in_2),
    .io_in_3(c53_89_io_in_3),
    .io_in_4(c53_89_io_in_4),
    .io_out_0(c53_89_io_out_0),
    .io_out_1(c53_89_io_out_1),
    .io_out_2(c53_89_io_out_2)
  );
  C22 c22_20 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_20_io_in_0),
    .io_in_1(c22_20_io_in_1),
    .io_out_0(c22_20_io_out_0),
    .io_out_1(c22_20_io_out_1)
  );
  C53 c53_90 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_90_io_in_0),
    .io_in_1(c53_90_io_in_1),
    .io_in_2(c53_90_io_in_2),
    .io_in_3(c53_90_io_in_3),
    .io_in_4(c53_90_io_in_4),
    .io_out_0(c53_90_io_out_0),
    .io_out_1(c53_90_io_out_1),
    .io_out_2(c53_90_io_out_2)
  );
  C22 c22_21 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_21_io_in_0),
    .io_in_1(c22_21_io_in_1),
    .io_out_0(c22_21_io_out_0),
    .io_out_1(c22_21_io_out_1)
  );
  C53 c53_91 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_91_io_in_0),
    .io_in_1(c53_91_io_in_1),
    .io_in_2(c53_91_io_in_2),
    .io_in_3(c53_91_io_in_3),
    .io_in_4(c53_91_io_in_4),
    .io_out_0(c53_91_io_out_0),
    .io_out_1(c53_91_io_out_1),
    .io_out_2(c53_91_io_out_2)
  );
  C32 c32_15 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_15_io_in_0),
    .io_in_1(c32_15_io_in_1),
    .io_in_2(c32_15_io_in_2),
    .io_out_0(c32_15_io_out_0),
    .io_out_1(c32_15_io_out_1)
  );
  C53 c53_92 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_92_io_in_0),
    .io_in_1(c53_92_io_in_1),
    .io_in_2(c53_92_io_in_2),
    .io_in_3(c53_92_io_in_3),
    .io_in_4(c53_92_io_in_4),
    .io_out_0(c53_92_io_out_0),
    .io_out_1(c53_92_io_out_1),
    .io_out_2(c53_92_io_out_2)
  );
  C32 c32_16 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_16_io_in_0),
    .io_in_1(c32_16_io_in_1),
    .io_in_2(c32_16_io_in_2),
    .io_out_0(c32_16_io_out_0),
    .io_out_1(c32_16_io_out_1)
  );
  C53 c53_93 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_93_io_in_0),
    .io_in_1(c53_93_io_in_1),
    .io_in_2(c53_93_io_in_2),
    .io_in_3(c53_93_io_in_3),
    .io_in_4(c53_93_io_in_4),
    .io_out_0(c53_93_io_out_0),
    .io_out_1(c53_93_io_out_1),
    .io_out_2(c53_93_io_out_2)
  );
  C32 c32_17 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_17_io_in_0),
    .io_in_1(c32_17_io_in_1),
    .io_in_2(c32_17_io_in_2),
    .io_out_0(c32_17_io_out_0),
    .io_out_1(c32_17_io_out_1)
  );
  C53 c53_94 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_94_io_in_0),
    .io_in_1(c53_94_io_in_1),
    .io_in_2(c53_94_io_in_2),
    .io_in_3(c53_94_io_in_3),
    .io_in_4(c53_94_io_in_4),
    .io_out_0(c53_94_io_out_0),
    .io_out_1(c53_94_io_out_1),
    .io_out_2(c53_94_io_out_2)
  );
  C32 c32_18 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_18_io_in_0),
    .io_in_1(c32_18_io_in_1),
    .io_in_2(c32_18_io_in_2),
    .io_out_0(c32_18_io_out_0),
    .io_out_1(c32_18_io_out_1)
  );
  C53 c53_95 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_95_io_in_0),
    .io_in_1(c53_95_io_in_1),
    .io_in_2(c53_95_io_in_2),
    .io_in_3(c53_95_io_in_3),
    .io_in_4(c53_95_io_in_4),
    .io_out_0(c53_95_io_out_0),
    .io_out_1(c53_95_io_out_1),
    .io_out_2(c53_95_io_out_2)
  );
  C32 c32_19 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_19_io_in_0),
    .io_in_1(c32_19_io_in_1),
    .io_in_2(c32_19_io_in_2),
    .io_out_0(c32_19_io_out_0),
    .io_out_1(c32_19_io_out_1)
  );
  C53 c53_96 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_96_io_in_0),
    .io_in_1(c53_96_io_in_1),
    .io_in_2(c53_96_io_in_2),
    .io_in_3(c53_96_io_in_3),
    .io_in_4(c53_96_io_in_4),
    .io_out_0(c53_96_io_out_0),
    .io_out_1(c53_96_io_out_1),
    .io_out_2(c53_96_io_out_2)
  );
  C32 c32_20 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_20_io_in_0),
    .io_in_1(c32_20_io_in_1),
    .io_in_2(c32_20_io_in_2),
    .io_out_0(c32_20_io_out_0),
    .io_out_1(c32_20_io_out_1)
  );
  C53 c53_97 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_97_io_in_0),
    .io_in_1(c53_97_io_in_1),
    .io_in_2(c53_97_io_in_2),
    .io_in_3(c53_97_io_in_3),
    .io_in_4(c53_97_io_in_4),
    .io_out_0(c53_97_io_out_0),
    .io_out_1(c53_97_io_out_1),
    .io_out_2(c53_97_io_out_2)
  );
  C32 c32_21 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_21_io_in_0),
    .io_in_1(c32_21_io_in_1),
    .io_in_2(c32_21_io_in_2),
    .io_out_0(c32_21_io_out_0),
    .io_out_1(c32_21_io_out_1)
  );
  C53 c53_98 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_98_io_in_0),
    .io_in_1(c53_98_io_in_1),
    .io_in_2(c53_98_io_in_2),
    .io_in_3(c53_98_io_in_3),
    .io_in_4(c53_98_io_in_4),
    .io_out_0(c53_98_io_out_0),
    .io_out_1(c53_98_io_out_1),
    .io_out_2(c53_98_io_out_2)
  );
  C22 c22_22 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_22_io_in_0),
    .io_in_1(c22_22_io_in_1),
    .io_out_0(c22_22_io_out_0),
    .io_out_1(c22_22_io_out_1)
  );
  C53 c53_99 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_99_io_in_0),
    .io_in_1(c53_99_io_in_1),
    .io_in_2(c53_99_io_in_2),
    .io_in_3(c53_99_io_in_3),
    .io_in_4(c53_99_io_in_4),
    .io_out_0(c53_99_io_out_0),
    .io_out_1(c53_99_io_out_1),
    .io_out_2(c53_99_io_out_2)
  );
  C32 c32_22 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_22_io_in_0),
    .io_in_1(c32_22_io_in_1),
    .io_in_2(c32_22_io_in_2),
    .io_out_0(c32_22_io_out_0),
    .io_out_1(c32_22_io_out_1)
  );
  C53 c53_100 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_100_io_in_0),
    .io_in_1(c53_100_io_in_1),
    .io_in_2(c53_100_io_in_2),
    .io_in_3(c53_100_io_in_3),
    .io_in_4(c53_100_io_in_4),
    .io_out_0(c53_100_io_out_0),
    .io_out_1(c53_100_io_out_1),
    .io_out_2(c53_100_io_out_2)
  );
  C22 c22_23 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_23_io_in_0),
    .io_in_1(c22_23_io_in_1),
    .io_out_0(c22_23_io_out_0),
    .io_out_1(c22_23_io_out_1)
  );
  C53 c53_101 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_101_io_in_0),
    .io_in_1(c53_101_io_in_1),
    .io_in_2(c53_101_io_in_2),
    .io_in_3(c53_101_io_in_3),
    .io_in_4(c53_101_io_in_4),
    .io_out_0(c53_101_io_out_0),
    .io_out_1(c53_101_io_out_1),
    .io_out_2(c53_101_io_out_2)
  );
  C22 c22_24 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_24_io_in_0),
    .io_in_1(c22_24_io_in_1),
    .io_out_0(c22_24_io_out_0),
    .io_out_1(c22_24_io_out_1)
  );
  C53 c53_102 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_102_io_in_0),
    .io_in_1(c53_102_io_in_1),
    .io_in_2(c53_102_io_in_2),
    .io_in_3(c53_102_io_in_3),
    .io_in_4(c53_102_io_in_4),
    .io_out_0(c53_102_io_out_0),
    .io_out_1(c53_102_io_out_1),
    .io_out_2(c53_102_io_out_2)
  );
  C22 c22_25 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_25_io_in_0),
    .io_in_1(c22_25_io_in_1),
    .io_out_0(c22_25_io_out_0),
    .io_out_1(c22_25_io_out_1)
  );
  C53 c53_103 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_103_io_in_0),
    .io_in_1(c53_103_io_in_1),
    .io_in_2(c53_103_io_in_2),
    .io_in_3(c53_103_io_in_3),
    .io_in_4(c53_103_io_in_4),
    .io_out_0(c53_103_io_out_0),
    .io_out_1(c53_103_io_out_1),
    .io_out_2(c53_103_io_out_2)
  );
  C22 c22_26 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_26_io_in_0),
    .io_in_1(c22_26_io_in_1),
    .io_out_0(c22_26_io_out_0),
    .io_out_1(c22_26_io_out_1)
  );
  C53 c53_104 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_104_io_in_0),
    .io_in_1(c53_104_io_in_1),
    .io_in_2(c53_104_io_in_2),
    .io_in_3(c53_104_io_in_3),
    .io_in_4(c53_104_io_in_4),
    .io_out_0(c53_104_io_out_0),
    .io_out_1(c53_104_io_out_1),
    .io_out_2(c53_104_io_out_2)
  );
  C53 c53_105 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_105_io_in_0),
    .io_in_1(c53_105_io_in_1),
    .io_in_2(c53_105_io_in_2),
    .io_in_3(c53_105_io_in_3),
    .io_in_4(c53_105_io_in_4),
    .io_out_0(c53_105_io_out_0),
    .io_out_1(c53_105_io_out_1),
    .io_out_2(c53_105_io_out_2)
  );
  C53 c53_106 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_106_io_in_0),
    .io_in_1(c53_106_io_in_1),
    .io_in_2(c53_106_io_in_2),
    .io_in_3(c53_106_io_in_3),
    .io_in_4(c53_106_io_in_4),
    .io_out_0(c53_106_io_out_0),
    .io_out_1(c53_106_io_out_1),
    .io_out_2(c53_106_io_out_2)
  );
  C53 c53_107 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_107_io_in_0),
    .io_in_1(c53_107_io_in_1),
    .io_in_2(c53_107_io_in_2),
    .io_in_3(c53_107_io_in_3),
    .io_in_4(c53_107_io_in_4),
    .io_out_0(c53_107_io_out_0),
    .io_out_1(c53_107_io_out_1),
    .io_out_2(c53_107_io_out_2)
  );
  C53 c53_108 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_108_io_in_0),
    .io_in_1(c53_108_io_in_1),
    .io_in_2(c53_108_io_in_2),
    .io_in_3(c53_108_io_in_3),
    .io_in_4(c53_108_io_in_4),
    .io_out_0(c53_108_io_out_0),
    .io_out_1(c53_108_io_out_1),
    .io_out_2(c53_108_io_out_2)
  );
  C53 c53_109 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_109_io_in_0),
    .io_in_1(c53_109_io_in_1),
    .io_in_2(c53_109_io_in_2),
    .io_in_3(c53_109_io_in_3),
    .io_in_4(c53_109_io_in_4),
    .io_out_0(c53_109_io_out_0),
    .io_out_1(c53_109_io_out_1),
    .io_out_2(c53_109_io_out_2)
  );
  C53 c53_110 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_110_io_in_0),
    .io_in_1(c53_110_io_in_1),
    .io_in_2(c53_110_io_in_2),
    .io_in_3(c53_110_io_in_3),
    .io_in_4(c53_110_io_in_4),
    .io_out_0(c53_110_io_out_0),
    .io_out_1(c53_110_io_out_1),
    .io_out_2(c53_110_io_out_2)
  );
  C53 c53_111 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_111_io_in_0),
    .io_in_1(c53_111_io_in_1),
    .io_in_2(c53_111_io_in_2),
    .io_in_3(c53_111_io_in_3),
    .io_in_4(c53_111_io_in_4),
    .io_out_0(c53_111_io_out_0),
    .io_out_1(c53_111_io_out_1),
    .io_out_2(c53_111_io_out_2)
  );
  C32 c32_23 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_23_io_in_0),
    .io_in_1(c32_23_io_in_1),
    .io_in_2(c32_23_io_in_2),
    .io_out_0(c32_23_io_out_0),
    .io_out_1(c32_23_io_out_1)
  );
  C22 c22_27 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_27_io_in_0),
    .io_in_1(c22_27_io_in_1),
    .io_out_0(c22_27_io_out_0),
    .io_out_1(c22_27_io_out_1)
  );
  C22 c22_28 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_28_io_in_0),
    .io_in_1(c22_28_io_in_1),
    .io_out_0(c22_28_io_out_0),
    .io_out_1(c22_28_io_out_1)
  );
  C32 c32_24 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_24_io_in_0),
    .io_in_1(c32_24_io_in_1),
    .io_in_2(c32_24_io_in_2),
    .io_out_0(c32_24_io_out_0),
    .io_out_1(c32_24_io_out_1)
  );
  C22 c22_29 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_29_io_in_0),
    .io_in_1(c22_29_io_in_1),
    .io_out_0(c22_29_io_out_0),
    .io_out_1(c22_29_io_out_1)
  );
  C22 c22_30 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_30_io_in_0),
    .io_in_1(c22_30_io_in_1),
    .io_out_0(c22_30_io_out_0),
    .io_out_1(c22_30_io_out_1)
  );
  C22 c22_31 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_31_io_in_0),
    .io_in_1(c22_31_io_in_1),
    .io_out_0(c22_31_io_out_0),
    .io_out_1(c22_31_io_out_1)
  );
  C22 c22_32 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_32_io_in_0),
    .io_in_1(c22_32_io_in_1),
    .io_out_0(c22_32_io_out_0),
    .io_out_1(c22_32_io_out_1)
  );
  C22 c22_33 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_33_io_in_0),
    .io_in_1(c22_33_io_in_1),
    .io_out_0(c22_33_io_out_0),
    .io_out_1(c22_33_io_out_1)
  );
  C22 c22_34 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_34_io_in_0),
    .io_in_1(c22_34_io_in_1),
    .io_out_0(c22_34_io_out_0),
    .io_out_1(c22_34_io_out_1)
  );
  C22 c22_35 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_35_io_in_0),
    .io_in_1(c22_35_io_in_1),
    .io_out_0(c22_35_io_out_0),
    .io_out_1(c22_35_io_out_1)
  );
  C22 c22_36 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_36_io_in_0),
    .io_in_1(c22_36_io_in_1),
    .io_out_0(c22_36_io_out_0),
    .io_out_1(c22_36_io_out_1)
  );
  C22 c22_37 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_37_io_in_0),
    .io_in_1(c22_37_io_in_1),
    .io_out_0(c22_37_io_out_0),
    .io_out_1(c22_37_io_out_1)
  );
  C22 c22_38 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_38_io_in_0),
    .io_in_1(c22_38_io_in_1),
    .io_out_0(c22_38_io_out_0),
    .io_out_1(c22_38_io_out_1)
  );
  C22 c22_39 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_39_io_in_0),
    .io_in_1(c22_39_io_in_1),
    .io_out_0(c22_39_io_out_0),
    .io_out_1(c22_39_io_out_1)
  );
  C22 c22_40 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_40_io_in_0),
    .io_in_1(c22_40_io_in_1),
    .io_out_0(c22_40_io_out_0),
    .io_out_1(c22_40_io_out_1)
  );
  C22 c22_41 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_41_io_in_0),
    .io_in_1(c22_41_io_in_1),
    .io_out_0(c22_41_io_out_0),
    .io_out_1(c22_41_io_out_1)
  );
  C22 c22_42 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_42_io_in_0),
    .io_in_1(c22_42_io_in_1),
    .io_out_0(c22_42_io_out_0),
    .io_out_1(c22_42_io_out_1)
  );
  C22 c22_43 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_43_io_in_0),
    .io_in_1(c22_43_io_in_1),
    .io_out_0(c22_43_io_out_0),
    .io_out_1(c22_43_io_out_1)
  );
  C32 c32_25 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_25_io_in_0),
    .io_in_1(c32_25_io_in_1),
    .io_in_2(c32_25_io_in_2),
    .io_out_0(c32_25_io_out_0),
    .io_out_1(c32_25_io_out_1)
  );
  C32 c32_26 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_26_io_in_0),
    .io_in_1(c32_26_io_in_1),
    .io_in_2(c32_26_io_in_2),
    .io_out_0(c32_26_io_out_0),
    .io_out_1(c32_26_io_out_1)
  );
  C32 c32_27 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_27_io_in_0),
    .io_in_1(c32_27_io_in_1),
    .io_in_2(c32_27_io_in_2),
    .io_out_0(c32_27_io_out_0),
    .io_out_1(c32_27_io_out_1)
  );
  C32 c32_28 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_28_io_in_0),
    .io_in_1(c32_28_io_in_1),
    .io_in_2(c32_28_io_in_2),
    .io_out_0(c32_28_io_out_0),
    .io_out_1(c32_28_io_out_1)
  );
  C53 c53_112 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_112_io_in_0),
    .io_in_1(c53_112_io_in_1),
    .io_in_2(c53_112_io_in_2),
    .io_in_3(c53_112_io_in_3),
    .io_in_4(c53_112_io_in_4),
    .io_out_0(c53_112_io_out_0),
    .io_out_1(c53_112_io_out_1),
    .io_out_2(c53_112_io_out_2)
  );
  C53 c53_113 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_113_io_in_0),
    .io_in_1(c53_113_io_in_1),
    .io_in_2(c53_113_io_in_2),
    .io_in_3(c53_113_io_in_3),
    .io_in_4(c53_113_io_in_4),
    .io_out_0(c53_113_io_out_0),
    .io_out_1(c53_113_io_out_1),
    .io_out_2(c53_113_io_out_2)
  );
  C53 c53_114 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_114_io_in_0),
    .io_in_1(c53_114_io_in_1),
    .io_in_2(c53_114_io_in_2),
    .io_in_3(c53_114_io_in_3),
    .io_in_4(c53_114_io_in_4),
    .io_out_0(c53_114_io_out_0),
    .io_out_1(c53_114_io_out_1),
    .io_out_2(c53_114_io_out_2)
  );
  C53 c53_115 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_115_io_in_0),
    .io_in_1(c53_115_io_in_1),
    .io_in_2(c53_115_io_in_2),
    .io_in_3(c53_115_io_in_3),
    .io_in_4(c53_115_io_in_4),
    .io_out_0(c53_115_io_out_0),
    .io_out_1(c53_115_io_out_1),
    .io_out_2(c53_115_io_out_2)
  );
  C53 c53_116 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_116_io_in_0),
    .io_in_1(c53_116_io_in_1),
    .io_in_2(c53_116_io_in_2),
    .io_in_3(c53_116_io_in_3),
    .io_in_4(c53_116_io_in_4),
    .io_out_0(c53_116_io_out_0),
    .io_out_1(c53_116_io_out_1),
    .io_out_2(c53_116_io_out_2)
  );
  C53 c53_117 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_117_io_in_0),
    .io_in_1(c53_117_io_in_1),
    .io_in_2(c53_117_io_in_2),
    .io_in_3(c53_117_io_in_3),
    .io_in_4(c53_117_io_in_4),
    .io_out_0(c53_117_io_out_0),
    .io_out_1(c53_117_io_out_1),
    .io_out_2(c53_117_io_out_2)
  );
  C53 c53_118 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_118_io_in_0),
    .io_in_1(c53_118_io_in_1),
    .io_in_2(c53_118_io_in_2),
    .io_in_3(c53_118_io_in_3),
    .io_in_4(c53_118_io_in_4),
    .io_out_0(c53_118_io_out_0),
    .io_out_1(c53_118_io_out_1),
    .io_out_2(c53_118_io_out_2)
  );
  C53 c53_119 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_119_io_in_0),
    .io_in_1(c53_119_io_in_1),
    .io_in_2(c53_119_io_in_2),
    .io_in_3(c53_119_io_in_3),
    .io_in_4(c53_119_io_in_4),
    .io_out_0(c53_119_io_out_0),
    .io_out_1(c53_119_io_out_1),
    .io_out_2(c53_119_io_out_2)
  );
  C53 c53_120 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_120_io_in_0),
    .io_in_1(c53_120_io_in_1),
    .io_in_2(c53_120_io_in_2),
    .io_in_3(c53_120_io_in_3),
    .io_in_4(c53_120_io_in_4),
    .io_out_0(c53_120_io_out_0),
    .io_out_1(c53_120_io_out_1),
    .io_out_2(c53_120_io_out_2)
  );
  C53 c53_121 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_121_io_in_0),
    .io_in_1(c53_121_io_in_1),
    .io_in_2(c53_121_io_in_2),
    .io_in_3(c53_121_io_in_3),
    .io_in_4(c53_121_io_in_4),
    .io_out_0(c53_121_io_out_0),
    .io_out_1(c53_121_io_out_1),
    .io_out_2(c53_121_io_out_2)
  );
  C53 c53_122 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_122_io_in_0),
    .io_in_1(c53_122_io_in_1),
    .io_in_2(c53_122_io_in_2),
    .io_in_3(c53_122_io_in_3),
    .io_in_4(c53_122_io_in_4),
    .io_out_0(c53_122_io_out_0),
    .io_out_1(c53_122_io_out_1),
    .io_out_2(c53_122_io_out_2)
  );
  C53 c53_123 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_123_io_in_0),
    .io_in_1(c53_123_io_in_1),
    .io_in_2(c53_123_io_in_2),
    .io_in_3(c53_123_io_in_3),
    .io_in_4(c53_123_io_in_4),
    .io_out_0(c53_123_io_out_0),
    .io_out_1(c53_123_io_out_1),
    .io_out_2(c53_123_io_out_2)
  );
  C53 c53_124 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_124_io_in_0),
    .io_in_1(c53_124_io_in_1),
    .io_in_2(c53_124_io_in_2),
    .io_in_3(c53_124_io_in_3),
    .io_in_4(c53_124_io_in_4),
    .io_out_0(c53_124_io_out_0),
    .io_out_1(c53_124_io_out_1),
    .io_out_2(c53_124_io_out_2)
  );
  C53 c53_125 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_125_io_in_0),
    .io_in_1(c53_125_io_in_1),
    .io_in_2(c53_125_io_in_2),
    .io_in_3(c53_125_io_in_3),
    .io_in_4(c53_125_io_in_4),
    .io_out_0(c53_125_io_out_0),
    .io_out_1(c53_125_io_out_1),
    .io_out_2(c53_125_io_out_2)
  );
  C53 c53_126 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_126_io_in_0),
    .io_in_1(c53_126_io_in_1),
    .io_in_2(c53_126_io_in_2),
    .io_in_3(c53_126_io_in_3),
    .io_in_4(c53_126_io_in_4),
    .io_out_0(c53_126_io_out_0),
    .io_out_1(c53_126_io_out_1),
    .io_out_2(c53_126_io_out_2)
  );
  C53 c53_127 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_127_io_in_0),
    .io_in_1(c53_127_io_in_1),
    .io_in_2(c53_127_io_in_2),
    .io_in_3(c53_127_io_in_3),
    .io_in_4(c53_127_io_in_4),
    .io_out_0(c53_127_io_out_0),
    .io_out_1(c53_127_io_out_1),
    .io_out_2(c53_127_io_out_2)
  );
  C53 c53_128 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_128_io_in_0),
    .io_in_1(c53_128_io_in_1),
    .io_in_2(c53_128_io_in_2),
    .io_in_3(c53_128_io_in_3),
    .io_in_4(c53_128_io_in_4),
    .io_out_0(c53_128_io_out_0),
    .io_out_1(c53_128_io_out_1),
    .io_out_2(c53_128_io_out_2)
  );
  C53 c53_129 ( // @[src/main/scala/fudian/utils/Multiplier.scala 83:25]
    .io_in_0(c53_129_io_in_0),
    .io_in_1(c53_129_io_in_1),
    .io_in_2(c53_129_io_in_2),
    .io_in_3(c53_129_io_in_3),
    .io_in_4(c53_129_io_in_4),
    .io_out_0(c53_129_io_out_0),
    .io_out_1(c53_129_io_out_1),
    .io_out_2(c53_129_io_out_2)
  );
  C22 c22_44 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_44_io_in_0),
    .io_in_1(c22_44_io_in_1),
    .io_out_0(c22_44_io_out_0),
    .io_out_1(c22_44_io_out_1)
  );
  C22 c22_45 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_45_io_in_0),
    .io_in_1(c22_45_io_in_1),
    .io_out_0(c22_45_io_out_0),
    .io_out_1(c22_45_io_out_1)
  );
  C32 c32_29 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_29_io_in_0),
    .io_in_1(c32_29_io_in_1),
    .io_in_2(c32_29_io_in_2),
    .io_out_0(c32_29_io_out_0),
    .io_out_1(c32_29_io_out_1)
  );
  C22 c22_46 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_46_io_in_0),
    .io_in_1(c22_46_io_in_1),
    .io_out_0(c22_46_io_out_0),
    .io_out_1(c22_46_io_out_1)
  );
  C22 c22_47 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_47_io_in_0),
    .io_in_1(c22_47_io_in_1),
    .io_out_0(c22_47_io_out_0),
    .io_out_1(c22_47_io_out_1)
  );
  C22 c22_48 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_48_io_in_0),
    .io_in_1(c22_48_io_in_1),
    .io_out_0(c22_48_io_out_0),
    .io_out_1(c22_48_io_out_1)
  );
  C22 c22_49 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_49_io_in_0),
    .io_in_1(c22_49_io_in_1),
    .io_out_0(c22_49_io_out_0),
    .io_out_1(c22_49_io_out_1)
  );
  C32 c32_30 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_30_io_in_0),
    .io_in_1(c32_30_io_in_1),
    .io_in_2(c32_30_io_in_2),
    .io_out_0(c32_30_io_out_0),
    .io_out_1(c32_30_io_out_1)
  );
  C22 c22_50 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_50_io_in_0),
    .io_in_1(c22_50_io_in_1),
    .io_out_0(c22_50_io_out_0),
    .io_out_1(c22_50_io_out_1)
  );
  C22 c22_51 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_51_io_in_0),
    .io_in_1(c22_51_io_in_1),
    .io_out_0(c22_51_io_out_0),
    .io_out_1(c22_51_io_out_1)
  );
  C22 c22_52 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_52_io_in_0),
    .io_in_1(c22_52_io_in_1),
    .io_out_0(c22_52_io_out_0),
    .io_out_1(c22_52_io_out_1)
  );
  C22 c22_53 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_53_io_in_0),
    .io_in_1(c22_53_io_in_1),
    .io_out_0(c22_53_io_out_0),
    .io_out_1(c22_53_io_out_1)
  );
  C22 c22_54 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_54_io_in_0),
    .io_in_1(c22_54_io_in_1),
    .io_out_0(c22_54_io_out_0),
    .io_out_1(c22_54_io_out_1)
  );
  C22 c22_55 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_55_io_in_0),
    .io_in_1(c22_55_io_in_1),
    .io_out_0(c22_55_io_out_0),
    .io_out_1(c22_55_io_out_1)
  );
  C22 c22_56 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_56_io_in_0),
    .io_in_1(c22_56_io_in_1),
    .io_out_0(c22_56_io_out_0),
    .io_out_1(c22_56_io_out_1)
  );
  C22 c22_57 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_57_io_in_0),
    .io_in_1(c22_57_io_in_1),
    .io_out_0(c22_57_io_out_0),
    .io_out_1(c22_57_io_out_1)
  );
  C22 c22_58 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_58_io_in_0),
    .io_in_1(c22_58_io_in_1),
    .io_out_0(c22_58_io_out_0),
    .io_out_1(c22_58_io_out_1)
  );
  C22 c22_59 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_59_io_in_0),
    .io_in_1(c22_59_io_in_1),
    .io_out_0(c22_59_io_out_0),
    .io_out_1(c22_59_io_out_1)
  );
  C22 c22_60 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_60_io_in_0),
    .io_in_1(c22_60_io_in_1),
    .io_out_0(c22_60_io_out_0),
    .io_out_1(c22_60_io_out_1)
  );
  C22 c22_61 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_61_io_in_0),
    .io_in_1(c22_61_io_in_1),
    .io_out_0(c22_61_io_out_0),
    .io_out_1(c22_61_io_out_1)
  );
  C22 c22_62 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_62_io_in_0),
    .io_in_1(c22_62_io_in_1),
    .io_out_0(c22_62_io_out_0),
    .io_out_1(c22_62_io_out_1)
  );
  C22 c22_63 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_63_io_in_0),
    .io_in_1(c22_63_io_in_1),
    .io_out_0(c22_63_io_out_0),
    .io_out_1(c22_63_io_out_1)
  );
  C22 c22_64 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_64_io_in_0),
    .io_in_1(c22_64_io_in_1),
    .io_out_0(c22_64_io_out_0),
    .io_out_1(c22_64_io_out_1)
  );
  C22 c22_65 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_65_io_in_0),
    .io_in_1(c22_65_io_in_1),
    .io_out_0(c22_65_io_out_0),
    .io_out_1(c22_65_io_out_1)
  );
  C22 c22_66 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_66_io_in_0),
    .io_in_1(c22_66_io_in_1),
    .io_out_0(c22_66_io_out_0),
    .io_out_1(c22_66_io_out_1)
  );
  C22 c22_67 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_67_io_in_0),
    .io_in_1(c22_67_io_in_1),
    .io_out_0(c22_67_io_out_0),
    .io_out_1(c22_67_io_out_1)
  );
  C22 c22_68 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_68_io_in_0),
    .io_in_1(c22_68_io_in_1),
    .io_out_0(c22_68_io_out_0),
    .io_out_1(c22_68_io_out_1)
  );
  C22 c22_69 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_69_io_in_0),
    .io_in_1(c22_69_io_in_1),
    .io_out_0(c22_69_io_out_0),
    .io_out_1(c22_69_io_out_1)
  );
  C22 c22_70 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_70_io_in_0),
    .io_in_1(c22_70_io_in_1),
    .io_out_0(c22_70_io_out_0),
    .io_out_1(c22_70_io_out_1)
  );
  C22 c22_71 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_71_io_in_0),
    .io_in_1(c22_71_io_in_1),
    .io_out_0(c22_71_io_out_0),
    .io_out_1(c22_71_io_out_1)
  );
  C22 c22_72 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_72_io_in_0),
    .io_in_1(c22_72_io_in_1),
    .io_out_0(c22_72_io_out_0),
    .io_out_1(c22_72_io_out_1)
  );
  C22 c22_73 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_73_io_in_0),
    .io_in_1(c22_73_io_in_1),
    .io_out_0(c22_73_io_out_0),
    .io_out_1(c22_73_io_out_1)
  );
  C22 c22_74 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_74_io_in_0),
    .io_in_1(c22_74_io_in_1),
    .io_out_0(c22_74_io_out_0),
    .io_out_1(c22_74_io_out_1)
  );
  C22 c22_75 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_75_io_in_0),
    .io_in_1(c22_75_io_in_1),
    .io_out_0(c22_75_io_out_0),
    .io_out_1(c22_75_io_out_1)
  );
  C22 c22_76 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_76_io_in_0),
    .io_in_1(c22_76_io_in_1),
    .io_out_0(c22_76_io_out_0),
    .io_out_1(c22_76_io_out_1)
  );
  C22 c22_77 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_77_io_in_0),
    .io_in_1(c22_77_io_in_1),
    .io_out_0(c22_77_io_out_0),
    .io_out_1(c22_77_io_out_1)
  );
  C22 c22_78 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_78_io_in_0),
    .io_in_1(c22_78_io_in_1),
    .io_out_0(c22_78_io_out_0),
    .io_out_1(c22_78_io_out_1)
  );
  C22 c22_79 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_79_io_in_0),
    .io_in_1(c22_79_io_in_1),
    .io_out_0(c22_79_io_out_0),
    .io_out_1(c22_79_io_out_1)
  );
  C22 c22_80 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_80_io_in_0),
    .io_in_1(c22_80_io_in_1),
    .io_out_0(c22_80_io_out_0),
    .io_out_1(c22_80_io_out_1)
  );
  C22 c22_81 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_81_io_in_0),
    .io_in_1(c22_81_io_in_1),
    .io_out_0(c22_81_io_out_0),
    .io_out_1(c22_81_io_out_1)
  );
  C22 c22_82 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_82_io_in_0),
    .io_in_1(c22_82_io_in_1),
    .io_out_0(c22_82_io_out_0),
    .io_out_1(c22_82_io_out_1)
  );
  C22 c22_83 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_83_io_in_0),
    .io_in_1(c22_83_io_in_1),
    .io_out_0(c22_83_io_out_0),
    .io_out_1(c22_83_io_out_1)
  );
  C22 c22_84 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_84_io_in_0),
    .io_in_1(c22_84_io_in_1),
    .io_out_0(c22_84_io_out_0),
    .io_out_1(c22_84_io_out_1)
  );
  C22 c22_85 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_85_io_in_0),
    .io_in_1(c22_85_io_in_1),
    .io_out_0(c22_85_io_out_0),
    .io_out_1(c22_85_io_out_1)
  );
  C22 c22_86 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_86_io_in_0),
    .io_in_1(c22_86_io_in_1),
    .io_out_0(c22_86_io_out_0),
    .io_out_1(c22_86_io_out_1)
  );
  C22 c22_87 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_87_io_in_0),
    .io_in_1(c22_87_io_in_1),
    .io_out_0(c22_87_io_out_0),
    .io_out_1(c22_87_io_out_1)
  );
  C22 c22_88 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_88_io_in_0),
    .io_in_1(c22_88_io_in_1),
    .io_out_0(c22_88_io_out_0),
    .io_out_1(c22_88_io_out_1)
  );
  C32 c32_31 ( // @[src/main/scala/fudian/utils/Multiplier.scala 78:25]
    .io_in_0(c32_31_io_in_0),
    .io_in_1(c32_31_io_in_1),
    .io_in_2(c32_31_io_in_2),
    .io_out_0(c32_31_io_out_0),
    .io_out_1(c32_31_io_out_1)
  );
  C22 c22_89 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_89_io_in_0),
    .io_in_1(c22_89_io_in_1),
    .io_out_0(c22_89_io_out_0),
    .io_out_1(c22_89_io_out_1)
  );
  C22 c22_90 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_90_io_in_0),
    .io_in_1(c22_90_io_in_1),
    .io_out_0(c22_90_io_out_0),
    .io_out_1(c22_90_io_out_1)
  );
  C22 c22_91 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_91_io_in_0),
    .io_in_1(c22_91_io_in_1),
    .io_out_0(c22_91_io_out_0),
    .io_out_1(c22_91_io_out_1)
  );
  C22 c22_92 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_92_io_in_0),
    .io_in_1(c22_92_io_in_1),
    .io_out_0(c22_92_io_out_0),
    .io_out_1(c22_92_io_out_1)
  );
  C22 c22_93 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_93_io_in_0),
    .io_in_1(c22_93_io_in_1),
    .io_out_0(c22_93_io_out_0),
    .io_out_1(c22_93_io_out_1)
  );
  C22 c22_94 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_94_io_in_0),
    .io_in_1(c22_94_io_in_1),
    .io_out_0(c22_94_io_out_0),
    .io_out_1(c22_94_io_out_1)
  );
  C22 c22_95 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_95_io_in_0),
    .io_in_1(c22_95_io_in_1),
    .io_out_0(c22_95_io_out_0),
    .io_out_1(c22_95_io_out_1)
  );
  C22 c22_96 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_96_io_in_0),
    .io_in_1(c22_96_io_in_1),
    .io_out_0(c22_96_io_out_0),
    .io_out_1(c22_96_io_out_1)
  );
  C22 c22_97 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_97_io_in_0),
    .io_in_1(c22_97_io_in_1),
    .io_out_0(c22_97_io_out_0),
    .io_out_1(c22_97_io_out_1)
  );
  C22 c22_98 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_98_io_in_0),
    .io_in_1(c22_98_io_in_1),
    .io_out_0(c22_98_io_out_0),
    .io_out_1(c22_98_io_out_1)
  );
  C22 c22_99 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_99_io_in_0),
    .io_in_1(c22_99_io_in_1),
    .io_out_0(c22_99_io_out_0),
    .io_out_1(c22_99_io_out_1)
  );
  C22 c22_100 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_100_io_in_0),
    .io_in_1(c22_100_io_in_1),
    .io_out_0(c22_100_io_out_0),
    .io_out_1(c22_100_io_out_1)
  );
  C22 c22_101 ( // @[src/main/scala/fudian/utils/Multiplier.scala 73:25]
    .io_in_0(c22_101_io_in_0),
    .io_in_1(c22_101_io_in_1),
    .io_out_0(c22_101_io_out_0),
    .io_out_1(c22_101_io_out_1)
  );
  assign io_result = sum + carry_1; // @[src/main/scala/fudian/utils/Multiplier.scala 135:20]
  assign c22_io_in_0 = pp[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_io_in_1 = pp_1[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_1_io_in_0 = pp[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_1_io_in_1 = pp_1[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_io_in_0 = pp[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_io_in_1 = pp_1[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_io_in_2 = pp_2[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_1_io_in_0 = pp[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_1_io_in_1 = pp_1[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_1_io_in_2 = pp_2[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_io_in_0 = pp[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_io_in_1 = pp_1[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_io_in_2 = pp_2[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_io_in_3 = pp_3[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_io_in_4 = 1'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 87:24]
  assign c53_1_io_in_0 = pp[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_1_io_in_1 = pp_1[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_1_io_in_2 = pp_2[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_1_io_in_3 = pp_3[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_1_io_in_4 = c53_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_2_io_in_0 = pp[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_2_io_in_1 = pp_1[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_2_io_in_2 = pp_2[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_2_io_in_3 = pp_3[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_2_io_in_4 = c53_1_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_3_io_in_0 = pp[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_3_io_in_1 = pp_1[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_3_io_in_2 = pp_2[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_3_io_in_3 = pp_3[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_3_io_in_4 = c53_2_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_4_io_in_0 = pp[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_4_io_in_1 = pp_1[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_4_io_in_2 = pp_2[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_4_io_in_3 = pp_3[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_4_io_in_4 = c53_3_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_2_io_in_0 = pp_4[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_2_io_in_1 = pp_5[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_5_io_in_0 = pp[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_5_io_in_1 = pp_1[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_5_io_in_2 = pp_2[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_5_io_in_3 = pp_3[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_5_io_in_4 = c53_4_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_3_io_in_0 = pp_4[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_3_io_in_1 = pp_5[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_6_io_in_0 = pp[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_6_io_in_1 = pp_1[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_6_io_in_2 = pp_2[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_6_io_in_3 = pp_3[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_6_io_in_4 = c53_5_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_2_io_in_0 = pp_4[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_2_io_in_1 = pp_5[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_2_io_in_2 = pp_6[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_7_io_in_0 = pp[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_7_io_in_1 = pp_1[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_7_io_in_2 = pp_2[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_7_io_in_3 = pp_3[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_7_io_in_4 = c53_6_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_3_io_in_0 = pp_4[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_3_io_in_1 = pp_5[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_3_io_in_2 = pp_6[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_8_io_in_0 = pp[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_8_io_in_1 = pp_1[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_8_io_in_2 = pp_2[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_8_io_in_3 = pp_3[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_8_io_in_4 = c53_7_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_9_io_in_0 = pp_4[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_9_io_in_1 = pp_5[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_9_io_in_2 = pp_6[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_9_io_in_3 = pp_7[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_9_io_in_4 = 1'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 87:24]
  assign c53_10_io_in_0 = pp[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_10_io_in_1 = pp_1[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_10_io_in_2 = pp_2[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_10_io_in_3 = pp_3[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_10_io_in_4 = c53_8_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_11_io_in_0 = pp_4[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_11_io_in_1 = pp_5[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_11_io_in_2 = pp_6[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_11_io_in_3 = pp_7[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_11_io_in_4 = c53_9_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_12_io_in_0 = pp[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_12_io_in_1 = pp_1[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_12_io_in_2 = pp_2[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_12_io_in_3 = pp_3[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_12_io_in_4 = c53_10_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_13_io_in_0 = pp_4[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_13_io_in_1 = pp_5[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_13_io_in_2 = pp_6[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_13_io_in_3 = pp_7[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_13_io_in_4 = c53_11_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_14_io_in_0 = pp[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_14_io_in_1 = pp_1[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_14_io_in_2 = pp_2[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_14_io_in_3 = pp_3[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_14_io_in_4 = c53_12_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_15_io_in_0 = pp_4[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_15_io_in_1 = pp_5[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_15_io_in_2 = pp_6[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_15_io_in_3 = pp_7[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_15_io_in_4 = c53_13_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_16_io_in_0 = pp[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_16_io_in_1 = pp_1[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_16_io_in_2 = pp_2[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_16_io_in_3 = pp_3[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_16_io_in_4 = c53_14_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_17_io_in_0 = pp_4[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_17_io_in_1 = pp_5[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_17_io_in_2 = pp_6[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_17_io_in_3 = pp_7[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_17_io_in_4 = c53_15_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_4_io_in_0 = pp_8[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_4_io_in_1 = pp_9[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_18_io_in_0 = pp[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_18_io_in_1 = pp_1[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_18_io_in_2 = pp_2[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_18_io_in_3 = pp_3[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_18_io_in_4 = c53_16_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_19_io_in_0 = pp_4[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_19_io_in_1 = pp_5[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_19_io_in_2 = pp_6[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_19_io_in_3 = pp_7[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_19_io_in_4 = c53_17_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_5_io_in_0 = pp_8[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_5_io_in_1 = pp_9[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_20_io_in_0 = pp[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_20_io_in_1 = pp_1[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_20_io_in_2 = pp_2[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_20_io_in_3 = pp_3[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_20_io_in_4 = c53_18_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_21_io_in_0 = pp_4[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_21_io_in_1 = pp_5[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_21_io_in_2 = pp_6[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_21_io_in_3 = pp_7[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_21_io_in_4 = c53_19_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_4_io_in_0 = pp_8[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_4_io_in_1 = pp_9[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_4_io_in_2 = pp_10[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_22_io_in_0 = pp[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_22_io_in_1 = pp_1[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_22_io_in_2 = pp_2[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_22_io_in_3 = pp_3[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_22_io_in_4 = c53_20_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_23_io_in_0 = pp_4[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_23_io_in_1 = pp_5[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_23_io_in_2 = pp_6[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_23_io_in_3 = pp_7[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_23_io_in_4 = c53_21_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_5_io_in_0 = pp_8[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_5_io_in_1 = pp_9[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_5_io_in_2 = pp_10[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_24_io_in_0 = pp[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_24_io_in_1 = pp_1[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_24_io_in_2 = pp_2[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_24_io_in_3 = pp_3[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_24_io_in_4 = c53_22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_25_io_in_0 = pp_4[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_25_io_in_1 = pp_5[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_25_io_in_2 = pp_6[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_25_io_in_3 = pp_7[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_25_io_in_4 = c53_23_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_26_io_in_0 = pp_8[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_26_io_in_1 = pp_9[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_26_io_in_2 = pp_10[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_26_io_in_3 = pp_11[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_26_io_in_4 = 1'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 87:24]
  assign c53_27_io_in_0 = pp[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_27_io_in_1 = pp_1[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_27_io_in_2 = pp_2[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_27_io_in_3 = pp_3[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_27_io_in_4 = c53_24_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_28_io_in_0 = pp_4[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_28_io_in_1 = pp_5[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_28_io_in_2 = pp_6[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_28_io_in_3 = pp_7[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_28_io_in_4 = c53_25_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_29_io_in_0 = pp_8[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_29_io_in_1 = pp_9[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_29_io_in_2 = pp_10[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_29_io_in_3 = pp_11[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_29_io_in_4 = c53_26_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_30_io_in_0 = pp[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_30_io_in_1 = pp_1[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_30_io_in_2 = pp_2[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_30_io_in_3 = pp_3[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_30_io_in_4 = c53_27_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_31_io_in_0 = pp_4[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_31_io_in_1 = pp_5[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_31_io_in_2 = pp_6[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_31_io_in_3 = pp_7[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_31_io_in_4 = c53_28_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_32_io_in_0 = pp_8[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_32_io_in_1 = pp_9[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_32_io_in_2 = pp_10[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_32_io_in_3 = pp_11[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_32_io_in_4 = c53_29_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_33_io_in_0 = pp[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_33_io_in_1 = pp_1[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_33_io_in_2 = pp_2[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_33_io_in_3 = pp_3[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_33_io_in_4 = c53_30_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_34_io_in_0 = pp_4[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_34_io_in_1 = pp_5[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_34_io_in_2 = pp_6[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_34_io_in_3 = pp_7[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_34_io_in_4 = c53_31_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_35_io_in_0 = pp_8[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_35_io_in_1 = pp_9[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_35_io_in_2 = pp_10[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_35_io_in_3 = pp_11[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_35_io_in_4 = c53_32_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_36_io_in_0 = pp[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_36_io_in_1 = pp_1[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_36_io_in_2 = pp_2[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_36_io_in_3 = pp_3[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_36_io_in_4 = c53_33_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_37_io_in_0 = pp_4[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_37_io_in_1 = pp_5[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_37_io_in_2 = pp_6[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_37_io_in_3 = pp_7[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_37_io_in_4 = c53_34_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_38_io_in_0 = pp_8[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_38_io_in_1 = pp_9[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_38_io_in_2 = pp_10[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_38_io_in_3 = pp_11[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_38_io_in_4 = c53_35_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_39_io_in_0 = pp[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_39_io_in_1 = pp_1[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_39_io_in_2 = pp_2[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_39_io_in_3 = pp_3[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_39_io_in_4 = c53_36_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_40_io_in_0 = pp_4[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_40_io_in_1 = pp_5[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_40_io_in_2 = pp_6[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_40_io_in_3 = pp_7[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_40_io_in_4 = c53_37_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_41_io_in_0 = pp_8[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_41_io_in_1 = pp_9[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_41_io_in_2 = pp_10[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_41_io_in_3 = pp_11[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_41_io_in_4 = c53_38_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_42_io_in_0 = pp[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_42_io_in_1 = pp_1[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_42_io_in_2 = pp_2[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_42_io_in_3 = pp_3[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_42_io_in_4 = c53_39_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_43_io_in_0 = pp_4[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_43_io_in_1 = pp_5[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_43_io_in_2 = pp_6[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_43_io_in_3 = pp_7[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_43_io_in_4 = c53_40_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_44_io_in_0 = pp_8[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_44_io_in_1 = pp_9[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_44_io_in_2 = pp_10[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_44_io_in_3 = pp_11[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_44_io_in_4 = c53_41_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_45_io_in_0 = pp[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_45_io_in_1 = pp_1[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_45_io_in_2 = pp_2[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_45_io_in_3 = pp_3[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_45_io_in_4 = c53_42_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_46_io_in_0 = pp_4[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_46_io_in_1 = pp_5[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_46_io_in_2 = pp_6[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_46_io_in_3 = pp_7[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_46_io_in_4 = c53_43_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_47_io_in_0 = pp_8[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_47_io_in_1 = pp_9[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_47_io_in_2 = pp_10[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_47_io_in_3 = pp_11[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_47_io_in_4 = c53_44_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_48_io_in_0 = pp[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_48_io_in_1 = pp_1[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_48_io_in_2 = pp_2[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_48_io_in_3 = pp_3[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_48_io_in_4 = c53_45_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_49_io_in_0 = pp_4[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_49_io_in_1 = pp_5[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_49_io_in_2 = pp_6[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_49_io_in_3 = pp_7[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_49_io_in_4 = c53_46_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_50_io_in_0 = pp_8[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_50_io_in_1 = pp_9[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_50_io_in_2 = pp_10[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_50_io_in_3 = pp_11[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_50_io_in_4 = c53_47_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_51_io_in_0 = pp_1[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_51_io_in_1 = pp_2[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_51_io_in_2 = pp_3[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_51_io_in_3 = pp_4[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_51_io_in_4 = c53_48_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_52_io_in_0 = pp_5[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_52_io_in_1 = pp_6[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_52_io_in_2 = pp_7[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_52_io_in_3 = pp_8[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_52_io_in_4 = c53_49_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_53_io_in_0 = pp_9[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_53_io_in_1 = pp_10[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_53_io_in_2 = pp_11[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_53_io_in_3 = pp_12[7]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_53_io_in_4 = c53_50_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_54_io_in_0 = pp_2[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_54_io_in_1 = pp_3[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_54_io_in_2 = pp_4[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_54_io_in_3 = pp_5[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_54_io_in_4 = c53_51_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_55_io_in_0 = pp_6[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_55_io_in_1 = pp_7[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_55_io_in_2 = pp_8[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_55_io_in_3 = pp_9[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_55_io_in_4 = c53_52_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_6_io_in_0 = pp_10[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_6_io_in_1 = pp_11[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_6_io_in_2 = pp_12[8]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_56_io_in_0 = pp_2[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_56_io_in_1 = pp_3[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_56_io_in_2 = pp_4[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_56_io_in_3 = pp_5[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_56_io_in_4 = c53_54_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_57_io_in_0 = pp_6[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_57_io_in_1 = pp_7[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_57_io_in_2 = pp_8[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_57_io_in_3 = pp_9[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_57_io_in_4 = c53_55_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_7_io_in_0 = pp_10[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_7_io_in_1 = pp_11[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_7_io_in_2 = pp_12[9]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_58_io_in_0 = pp_3[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_58_io_in_1 = pp_4[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_58_io_in_2 = pp_5[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_58_io_in_3 = pp_6[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_58_io_in_4 = c53_56_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_59_io_in_0 = pp_7[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_59_io_in_1 = pp_8[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_59_io_in_2 = pp_9[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_59_io_in_3 = pp_10[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_59_io_in_4 = c53_57_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_6_io_in_0 = pp_11[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_6_io_in_1 = pp_12[10]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_60_io_in_0 = pp_3[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_60_io_in_1 = pp_4[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_60_io_in_2 = pp_5[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_60_io_in_3 = pp_6[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_60_io_in_4 = c53_58_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_61_io_in_0 = pp_7[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_61_io_in_1 = pp_8[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_61_io_in_2 = pp_9[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_61_io_in_3 = pp_10[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_61_io_in_4 = c53_59_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_7_io_in_0 = pp_11[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_7_io_in_1 = pp_12[11]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_62_io_in_0 = pp_4[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_62_io_in_1 = pp_5[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_62_io_in_2 = pp_6[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_62_io_in_3 = pp_7[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_62_io_in_4 = c53_60_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_63_io_in_0 = pp_8[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_63_io_in_1 = pp_9[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_63_io_in_2 = pp_10[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_63_io_in_3 = pp_11[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_63_io_in_4 = c53_61_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_64_io_in_0 = pp_4[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_64_io_in_1 = pp_5[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_64_io_in_2 = pp_6[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_64_io_in_3 = pp_7[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_64_io_in_4 = c53_62_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_65_io_in_0 = pp_8[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_65_io_in_1 = pp_9[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_65_io_in_2 = pp_10[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_65_io_in_3 = pp_11[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_65_io_in_4 = c53_63_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_66_io_in_0 = pp_5[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_66_io_in_1 = pp_6[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_66_io_in_2 = pp_7[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_66_io_in_3 = pp_8[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_66_io_in_4 = c53_64_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_67_io_in_0 = pp_9[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_67_io_in_1 = pp_10[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_67_io_in_2 = pp_11[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_67_io_in_3 = pp_12[14]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_67_io_in_4 = c53_65_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_68_io_in_0 = pp_5[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_68_io_in_1 = pp_6[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_68_io_in_2 = pp_7[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_68_io_in_3 = pp_8[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_68_io_in_4 = c53_66_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_69_io_in_0 = pp_9[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_69_io_in_1 = pp_10[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_69_io_in_2 = pp_11[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_69_io_in_3 = pp_12[15]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_69_io_in_4 = c53_67_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_70_io_in_0 = pp_6[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_70_io_in_1 = pp_7[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_70_io_in_2 = pp_8[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_70_io_in_3 = pp_9[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_70_io_in_4 = c53_68_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_8_io_in_0 = pp_10[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_8_io_in_1 = pp_11[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_8_io_in_2 = pp_12[16]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_71_io_in_0 = pp_6[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_71_io_in_1 = pp_7[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_71_io_in_2 = pp_8[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_71_io_in_3 = pp_9[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_71_io_in_4 = c53_70_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_9_io_in_0 = pp_10[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_9_io_in_1 = pp_11[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_9_io_in_2 = pp_12[17]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_72_io_in_0 = pp_7[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_72_io_in_1 = pp_8[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_72_io_in_2 = pp_9[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_72_io_in_3 = pp_10[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_72_io_in_4 = c53_71_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_8_io_in_0 = pp_11[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_8_io_in_1 = pp_12[18]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_73_io_in_0 = pp_7[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_73_io_in_1 = pp_8[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_73_io_in_2 = pp_9[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_73_io_in_3 = pp_10[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_73_io_in_4 = c53_72_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_9_io_in_0 = pp_11[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_9_io_in_1 = pp_12[19]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_74_io_in_0 = pp_8[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_74_io_in_1 = pp_9[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_74_io_in_2 = pp_10[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_74_io_in_3 = pp_11[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_74_io_in_4 = c53_73_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_75_io_in_0 = pp_8[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_75_io_in_1 = pp_9[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_75_io_in_2 = pp_10[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_75_io_in_3 = pp_11[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_75_io_in_4 = c53_74_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_76_io_in_0 = pp_9[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_76_io_in_1 = pp_10[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_76_io_in_2 = pp_11[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_76_io_in_3 = pp_12[22]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_76_io_in_4 = c53_75_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_77_io_in_0 = pp_9[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_77_io_in_1 = pp_10[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_77_io_in_2 = pp_11[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_77_io_in_3 = pp_12[23]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_77_io_in_4 = c53_76_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_10_io_in_0 = pp_10[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_10_io_in_1 = pp_11[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_10_io_in_2 = pp_12[24]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_11_io_in_0 = pp_10[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_11_io_in_1 = pp_11[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_11_io_in_2 = pp_12[25]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_10_io_in_0 = pp_11[28]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_10_io_in_1 = pp_12[26]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_11_io_in_0 = pp_11[29]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_11_io_in_1 = pp_12[27]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c22_12_io_in_0 = c22_1_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_12_io_in_1 = c22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_13_io_in_0 = c32_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_13_io_in_1 = c22_1_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_14_io_in_0 = c32_1_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_14_io_in_1 = c32_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_15_io_in_0 = c53_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_15_io_in_1 = c32_1_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_16_io_in_0 = c53_1_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_16_io_in_1 = c53_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_12_io_in_0 = c53_2_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_12_io_in_1 = pp_4[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_12_io_in_2 = c53_1_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_13_io_in_0 = c53_3_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_13_io_in_1 = pp_4[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_13_io_in_2 = c53_2_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_14_io_in_0 = c53_4_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_14_io_in_1 = c22_2_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c32_14_io_in_2 = c53_3_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_78_io_in_0 = c53_5_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_78_io_in_1 = c22_3_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_78_io_in_2 = c53_4_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_78_io_in_3 = c22_2_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_78_io_in_4 = 1'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 87:24]
  assign c53_79_io_in_0 = c53_6_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_79_io_in_1 = c32_2_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_79_io_in_2 = c53_5_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_79_io_in_3 = c22_3_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_79_io_in_4 = c53_78_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_80_io_in_0 = c53_7_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_80_io_in_1 = c32_3_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_80_io_in_2 = c53_6_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_80_io_in_3 = c32_2_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_80_io_in_4 = c53_79_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_81_io_in_0 = c53_8_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_81_io_in_1 = c53_9_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_81_io_in_2 = c53_7_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_81_io_in_3 = c32_3_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_81_io_in_4 = c53_80_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_82_io_in_0 = c53_10_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_82_io_in_1 = c53_11_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_82_io_in_2 = c53_8_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_82_io_in_3 = c53_9_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_82_io_in_4 = c53_81_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_83_io_in_0 = c53_12_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_83_io_in_1 = c53_13_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_83_io_in_2 = pp_8[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_83_io_in_3 = c53_10_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_83_io_in_4 = c53_82_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_84_io_in_0 = c53_14_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_84_io_in_1 = c53_15_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_84_io_in_2 = pp_8[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_84_io_in_3 = c53_12_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_84_io_in_4 = c53_83_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_85_io_in_0 = c53_16_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_85_io_in_1 = c53_17_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_85_io_in_2 = c22_4_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_85_io_in_3 = c53_14_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_85_io_in_4 = c53_84_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_86_io_in_0 = c53_18_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_86_io_in_1 = c53_19_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_86_io_in_2 = c22_5_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_86_io_in_3 = c53_16_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_86_io_in_4 = c53_85_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_17_io_in_0 = c53_17_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_17_io_in_1 = c22_4_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_87_io_in_0 = c53_20_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_87_io_in_1 = c53_21_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_87_io_in_2 = c32_4_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_87_io_in_3 = c53_18_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_87_io_in_4 = c53_86_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_18_io_in_0 = c53_19_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_18_io_in_1 = c22_5_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_88_io_in_0 = c53_22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_88_io_in_1 = c53_23_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_88_io_in_2 = c32_5_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_88_io_in_3 = c53_20_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_88_io_in_4 = c53_87_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_19_io_in_0 = c53_21_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_19_io_in_1 = c32_4_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_89_io_in_0 = c53_24_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_89_io_in_1 = c53_25_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_89_io_in_2 = c53_26_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_89_io_in_3 = c53_22_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_89_io_in_4 = c53_88_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_20_io_in_0 = c53_23_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_20_io_in_1 = c32_5_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_90_io_in_0 = c53_27_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_90_io_in_1 = c53_28_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_90_io_in_2 = c53_29_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_90_io_in_3 = c53_24_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_90_io_in_4 = c53_89_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_21_io_in_0 = c53_25_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_21_io_in_1 = c53_26_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_91_io_in_0 = c53_30_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_91_io_in_1 = c53_31_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_91_io_in_2 = c53_32_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_91_io_in_3 = pp_12[0]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_91_io_in_4 = c53_90_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_15_io_in_0 = c53_27_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_15_io_in_1 = c53_28_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_15_io_in_2 = c53_29_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_92_io_in_0 = c53_33_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_92_io_in_1 = c53_34_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_92_io_in_2 = c53_35_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_92_io_in_3 = pp_12[1]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_92_io_in_4 = c53_91_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_16_io_in_0 = c53_30_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_16_io_in_1 = c53_31_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_16_io_in_2 = c53_32_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_93_io_in_0 = c53_36_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_93_io_in_1 = c53_37_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_93_io_in_2 = c53_38_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_93_io_in_3 = pp_12[2]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_93_io_in_4 = c53_92_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_17_io_in_0 = c53_33_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_17_io_in_1 = c53_34_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_17_io_in_2 = c53_35_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_94_io_in_0 = c53_39_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_94_io_in_1 = c53_40_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_94_io_in_2 = c53_41_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_94_io_in_3 = pp_12[3]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_94_io_in_4 = c53_93_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_18_io_in_0 = c53_36_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_18_io_in_1 = c53_37_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_18_io_in_2 = c53_38_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_95_io_in_0 = c53_42_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_95_io_in_1 = c53_43_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_95_io_in_2 = c53_44_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_95_io_in_3 = pp_12[4]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_95_io_in_4 = c53_94_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_19_io_in_0 = c53_39_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_19_io_in_1 = c53_40_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_19_io_in_2 = c53_41_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_96_io_in_0 = c53_45_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_96_io_in_1 = c53_46_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_96_io_in_2 = c53_47_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_96_io_in_3 = pp_12[5]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_96_io_in_4 = c53_95_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_20_io_in_0 = c53_42_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_20_io_in_1 = c53_43_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_20_io_in_2 = c53_44_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_97_io_in_0 = c53_48_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_97_io_in_1 = c53_49_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_97_io_in_2 = c53_50_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_97_io_in_3 = pp_12[6]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_97_io_in_4 = c53_96_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_21_io_in_0 = c53_45_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_21_io_in_1 = c53_46_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_21_io_in_2 = c53_47_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_98_io_in_0 = c53_51_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_98_io_in_1 = c53_52_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_98_io_in_2 = c53_53_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_98_io_in_3 = c53_48_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_98_io_in_4 = c53_97_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_22_io_in_0 = c53_49_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_22_io_in_1 = c53_50_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_99_io_in_0 = c53_54_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_99_io_in_1 = c53_55_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_99_io_in_2 = c32_6_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_99_io_in_3 = c53_53_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_99_io_in_4 = c53_98_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_22_io_in_0 = c53_51_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_22_io_in_1 = c53_52_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_22_io_in_2 = c53_53_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_100_io_in_0 = c53_56_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_100_io_in_1 = c53_57_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_100_io_in_2 = c32_7_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_100_io_in_3 = c53_54_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_100_io_in_4 = c53_99_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_23_io_in_0 = c53_55_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_23_io_in_1 = c32_6_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_101_io_in_0 = c53_58_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_101_io_in_1 = c53_59_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_101_io_in_2 = c22_6_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_101_io_in_3 = c53_56_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_101_io_in_4 = c53_100_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_24_io_in_0 = c53_57_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_24_io_in_1 = c32_7_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_102_io_in_0 = c53_60_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_102_io_in_1 = c53_61_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_102_io_in_2 = c22_7_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_102_io_in_3 = c53_58_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_102_io_in_4 = c53_101_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_25_io_in_0 = c53_59_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_25_io_in_1 = c22_6_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_103_io_in_0 = c53_62_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_103_io_in_1 = c53_63_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_103_io_in_2 = pp_12[12]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_103_io_in_3 = c53_60_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_103_io_in_4 = c53_102_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_26_io_in_0 = c53_61_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_26_io_in_1 = c22_7_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_104_io_in_0 = c53_64_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_104_io_in_1 = c53_65_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_104_io_in_2 = pp_12[13]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_104_io_in_3 = c53_62_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_104_io_in_4 = c53_103_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_105_io_in_0 = c53_66_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_105_io_in_1 = c53_67_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_105_io_in_2 = c53_64_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_105_io_in_3 = c53_65_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_105_io_in_4 = c53_104_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_106_io_in_0 = c53_68_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_106_io_in_1 = c53_69_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_106_io_in_2 = c53_66_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_106_io_in_3 = c53_67_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_106_io_in_4 = c53_105_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_107_io_in_0 = c53_70_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_107_io_in_1 = c32_8_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_107_io_in_2 = c53_69_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_107_io_in_3 = c53_68_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_107_io_in_4 = c53_106_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_108_io_in_0 = c53_71_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_108_io_in_1 = c32_9_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_108_io_in_2 = c53_70_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_108_io_in_3 = c32_8_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_108_io_in_4 = c53_107_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_109_io_in_0 = c53_72_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_109_io_in_1 = c22_8_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_109_io_in_2 = c53_71_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_109_io_in_3 = c32_9_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_109_io_in_4 = c53_108_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_110_io_in_0 = c53_73_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_110_io_in_1 = c22_9_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_110_io_in_2 = c53_72_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_110_io_in_3 = c22_8_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_110_io_in_4 = c53_109_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_111_io_in_0 = c53_74_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_111_io_in_1 = pp_12[20]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c53_111_io_in_2 = c53_73_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_111_io_in_3 = c22_9_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_111_io_in_4 = c53_110_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_23_io_in_0 = c53_75_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_23_io_in_1 = pp_12[21]; // @[src/main/scala/fudian/utils/Multiplier.scala 60:38]
  assign c32_23_io_in_2 = c53_74_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_27_io_in_0 = c53_76_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_27_io_in_1 = c53_75_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_28_io_in_0 = c53_77_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_28_io_in_1 = c53_76_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_24_io_in_0 = c32_10_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c32_24_io_in_1 = c53_77_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_24_io_in_2 = c53_77_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_29_io_in_0 = c32_11_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_29_io_in_1 = c32_10_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_30_io_in_0 = c22_10_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_30_io_in_1 = c32_11_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_31_io_in_0 = c22_11_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_31_io_in_1 = c22_10_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_32_io_in_0 = c22_13_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_32_io_in_1 = c22_12_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_33_io_in_0 = c22_14_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_33_io_in_1 = c22_13_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_34_io_in_0 = c22_15_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_34_io_in_1 = c22_14_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_35_io_in_0 = c22_16_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_35_io_in_1 = c22_15_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_36_io_in_0 = c32_12_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_36_io_in_1 = c22_16_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_37_io_in_0 = c32_13_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_37_io_in_1 = c32_12_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_38_io_in_0 = c32_14_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_38_io_in_1 = c32_13_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_39_io_in_0 = c53_78_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_39_io_in_1 = c32_14_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_40_io_in_0 = c53_79_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_40_io_in_1 = c53_78_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_41_io_in_0 = c53_80_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_41_io_in_1 = c53_79_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_42_io_in_0 = c53_81_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_42_io_in_1 = c53_80_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_43_io_in_0 = c53_82_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_43_io_in_1 = c53_81_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_25_io_in_0 = c53_83_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_25_io_in_1 = c53_11_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_25_io_in_2 = c53_82_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_26_io_in_0 = c53_84_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_26_io_in_1 = c53_13_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_26_io_in_2 = c53_83_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_27_io_in_0 = c53_85_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_27_io_in_1 = c53_15_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_27_io_in_2 = c53_84_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_28_io_in_0 = c53_86_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_28_io_in_1 = c22_17_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c32_28_io_in_2 = c53_85_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_112_io_in_0 = c53_87_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_112_io_in_1 = c22_18_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_112_io_in_2 = c53_86_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_112_io_in_3 = c22_17_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_112_io_in_4 = 1'h0; // @[src/main/scala/fudian/utils/Multiplier.scala 87:24]
  assign c53_113_io_in_0 = c53_88_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_113_io_in_1 = c22_19_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_113_io_in_2 = c53_87_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_113_io_in_3 = c22_18_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_113_io_in_4 = c53_112_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_114_io_in_0 = c53_89_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_114_io_in_1 = c22_20_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_114_io_in_2 = c53_88_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_114_io_in_3 = c22_19_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_114_io_in_4 = c53_113_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_115_io_in_0 = c53_90_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_115_io_in_1 = c22_21_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_115_io_in_2 = c53_89_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_115_io_in_3 = c22_20_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_115_io_in_4 = c53_114_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_116_io_in_0 = c53_91_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_116_io_in_1 = c32_15_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_116_io_in_2 = c53_90_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_116_io_in_3 = c22_21_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_116_io_in_4 = c53_115_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_117_io_in_0 = c53_92_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_117_io_in_1 = c32_16_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_117_io_in_2 = c53_91_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_117_io_in_3 = c32_15_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_117_io_in_4 = c53_116_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_118_io_in_0 = c53_93_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_118_io_in_1 = c32_17_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_118_io_in_2 = c53_92_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_118_io_in_3 = c32_16_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_118_io_in_4 = c53_117_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_119_io_in_0 = c53_94_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_119_io_in_1 = c32_18_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_119_io_in_2 = c53_93_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_119_io_in_3 = c32_17_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_119_io_in_4 = c53_118_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_120_io_in_0 = c53_95_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_120_io_in_1 = c32_19_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_120_io_in_2 = c53_94_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_120_io_in_3 = c32_18_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_120_io_in_4 = c53_119_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_121_io_in_0 = c53_96_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_121_io_in_1 = c32_20_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_121_io_in_2 = c53_95_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_121_io_in_3 = c32_19_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_121_io_in_4 = c53_120_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_122_io_in_0 = c53_97_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_122_io_in_1 = c32_21_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_122_io_in_2 = c53_96_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_122_io_in_3 = c32_20_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_122_io_in_4 = c53_121_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_123_io_in_0 = c53_98_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_123_io_in_1 = c22_22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_123_io_in_2 = c53_97_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_123_io_in_3 = c32_21_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_123_io_in_4 = c53_122_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_124_io_in_0 = c53_99_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_124_io_in_1 = c32_22_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c53_124_io_in_2 = c53_98_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_124_io_in_3 = c22_22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_124_io_in_4 = c53_123_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_125_io_in_0 = c53_100_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_125_io_in_1 = c22_23_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_125_io_in_2 = c53_99_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_125_io_in_3 = c32_22_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c53_125_io_in_4 = c53_124_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_126_io_in_0 = c53_101_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_126_io_in_1 = c22_24_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_126_io_in_2 = c53_100_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_126_io_in_3 = c22_23_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_126_io_in_4 = c53_125_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_127_io_in_0 = c53_102_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_127_io_in_1 = c22_25_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_127_io_in_2 = c53_101_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_127_io_in_3 = c22_24_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_127_io_in_4 = c53_126_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_128_io_in_0 = c53_103_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_128_io_in_1 = c22_26_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c53_128_io_in_2 = c53_102_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_128_io_in_3 = c22_25_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_128_io_in_4 = c53_127_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c53_129_io_in_0 = c53_104_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c53_129_io_in_1 = c53_63_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_129_io_in_2 = c53_103_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c53_129_io_in_3 = c22_26_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c53_129_io_in_4 = c53_128_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c22_44_io_in_0 = c53_105_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_44_io_in_1 = c53_104_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_45_io_in_0 = c53_106_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_45_io_in_1 = c53_105_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_29_io_in_0 = c53_107_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c32_29_io_in_1 = c53_69_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_29_io_in_2 = c53_106_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_46_io_in_0 = c53_108_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_46_io_in_1 = c53_107_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_47_io_in_0 = c53_109_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_47_io_in_1 = c53_108_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_48_io_in_0 = c53_110_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_48_io_in_1 = c53_109_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_49_io_in_0 = c53_111_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_49_io_in_1 = c53_110_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_30_io_in_0 = c32_23_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c32_30_io_in_1 = c53_111_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_30_io_in_2 = c53_111_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_50_io_in_0 = c22_27_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_50_io_in_1 = c32_23_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_51_io_in_0 = c22_28_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_51_io_in_1 = c22_27_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_52_io_in_0 = c32_24_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_52_io_in_1 = c22_28_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_53_io_in_0 = c22_29_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_53_io_in_1 = c32_24_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_54_io_in_0 = c22_30_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_54_io_in_1 = c22_29_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_55_io_in_0 = c22_31_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_55_io_in_1 = c22_30_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_56_io_in_0 = c22_33_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_56_io_in_1 = c22_32_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_57_io_in_0 = c22_34_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_57_io_in_1 = c22_33_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_58_io_in_0 = c22_35_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_58_io_in_1 = c22_34_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_59_io_in_0 = c22_36_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_59_io_in_1 = c22_35_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_60_io_in_0 = c22_37_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_60_io_in_1 = c22_36_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_61_io_in_0 = c22_38_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_61_io_in_1 = c22_37_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_62_io_in_0 = c22_39_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_62_io_in_1 = c22_38_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_63_io_in_0 = c22_40_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_63_io_in_1 = c22_39_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_64_io_in_0 = c22_41_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_64_io_in_1 = c22_40_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_65_io_in_0 = c22_42_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_65_io_in_1 = c22_41_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_66_io_in_0 = c22_43_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_66_io_in_1 = c22_42_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_67_io_in_0 = c32_25_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_67_io_in_1 = c22_43_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_68_io_in_0 = c32_26_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_68_io_in_1 = c32_25_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_69_io_in_0 = c32_27_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_69_io_in_1 = c32_26_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_70_io_in_0 = c32_28_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_70_io_in_1 = c32_27_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_71_io_in_0 = c53_112_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_71_io_in_1 = c32_28_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_72_io_in_0 = c53_113_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_72_io_in_1 = c53_112_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_73_io_in_0 = c53_114_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_73_io_in_1 = c53_113_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_74_io_in_0 = c53_115_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_74_io_in_1 = c53_114_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_75_io_in_0 = c53_116_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_75_io_in_1 = c53_115_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_76_io_in_0 = c53_117_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_76_io_in_1 = c53_116_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_77_io_in_0 = c53_118_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_77_io_in_1 = c53_117_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_78_io_in_0 = c53_119_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_78_io_in_1 = c53_118_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_79_io_in_0 = c53_120_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_79_io_in_1 = c53_119_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_80_io_in_0 = c53_121_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_80_io_in_1 = c53_120_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_81_io_in_0 = c53_122_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_81_io_in_1 = c53_121_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_82_io_in_0 = c53_123_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_82_io_in_1 = c53_122_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_83_io_in_0 = c53_124_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_83_io_in_1 = c53_123_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_84_io_in_0 = c53_125_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_84_io_in_1 = c53_124_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_85_io_in_0 = c53_126_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_85_io_in_1 = c53_125_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_86_io_in_0 = c53_127_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_86_io_in_1 = c53_126_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_87_io_in_0 = c53_128_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_87_io_in_1 = c53_127_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_88_io_in_0 = c53_129_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 88:33]
  assign c22_88_io_in_1 = c53_128_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c32_31_io_in_0 = c22_44_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c32_31_io_in_1 = c53_129_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 89:35]
  assign c32_31_io_in_2 = c53_129_io_out_2; // @[src/main/scala/fudian/utils/Multiplier.scala 90:35]
  assign c22_89_io_in_0 = c22_45_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_89_io_in_1 = c22_44_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_90_io_in_0 = c32_29_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_90_io_in_1 = c22_45_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_91_io_in_0 = c22_46_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_91_io_in_1 = c32_29_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_92_io_in_0 = c22_47_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_92_io_in_1 = c22_46_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_93_io_in_0 = c22_48_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_93_io_in_1 = c22_47_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_94_io_in_0 = c22_49_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_94_io_in_1 = c22_48_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_95_io_in_0 = c32_30_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 80:29]
  assign c22_95_io_in_1 = c22_49_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_96_io_in_0 = c22_50_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_96_io_in_1 = c32_30_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 81:35]
  assign c22_97_io_in_0 = c22_51_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_97_io_in_1 = c22_50_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_98_io_in_0 = c22_52_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_98_io_in_1 = c22_51_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_99_io_in_0 = c22_53_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_99_io_in_1 = c22_52_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_100_io_in_0 = c22_54_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_100_io_in_1 = c22_53_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
  assign c22_101_io_in_0 = c22_55_io_out_0; // @[src/main/scala/fudian/utils/Multiplier.scala 75:29]
  assign c22_101_io_in_1 = c22_54_io_out_1; // @[src/main/scala/fudian/utils/Multiplier.scala 76:35]
endmodule
module CLZ(
  input  [49:0] io_in, // @[src/main/scala/fudian/utils/CLZ.scala 12:14]
  output [5:0]  io_out // @[src/main/scala/fudian/utils/CLZ.scala 12:14]
);
  wire [5:0] _io_out_T_50 = io_in[1] ? 6'h30 : 6'h31; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_51 = io_in[2] ? 6'h2f : _io_out_T_50; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_52 = io_in[3] ? 6'h2e : _io_out_T_51; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_53 = io_in[4] ? 6'h2d : _io_out_T_52; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_54 = io_in[5] ? 6'h2c : _io_out_T_53; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_55 = io_in[6] ? 6'h2b : _io_out_T_54; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_56 = io_in[7] ? 6'h2a : _io_out_T_55; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_57 = io_in[8] ? 6'h29 : _io_out_T_56; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_58 = io_in[9] ? 6'h28 : _io_out_T_57; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_59 = io_in[10] ? 6'h27 : _io_out_T_58; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_60 = io_in[11] ? 6'h26 : _io_out_T_59; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_61 = io_in[12] ? 6'h25 : _io_out_T_60; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_62 = io_in[13] ? 6'h24 : _io_out_T_61; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_63 = io_in[14] ? 6'h23 : _io_out_T_62; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_64 = io_in[15] ? 6'h22 : _io_out_T_63; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_65 = io_in[16] ? 6'h21 : _io_out_T_64; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_66 = io_in[17] ? 6'h20 : _io_out_T_65; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_67 = io_in[18] ? 6'h1f : _io_out_T_66; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_68 = io_in[19] ? 6'h1e : _io_out_T_67; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_69 = io_in[20] ? 6'h1d : _io_out_T_68; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_70 = io_in[21] ? 6'h1c : _io_out_T_69; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_71 = io_in[22] ? 6'h1b : _io_out_T_70; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_72 = io_in[23] ? 6'h1a : _io_out_T_71; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_73 = io_in[24] ? 6'h19 : _io_out_T_72; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_74 = io_in[25] ? 6'h18 : _io_out_T_73; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_75 = io_in[26] ? 6'h17 : _io_out_T_74; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_76 = io_in[27] ? 6'h16 : _io_out_T_75; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_77 = io_in[28] ? 6'h15 : _io_out_T_76; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_78 = io_in[29] ? 6'h14 : _io_out_T_77; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_79 = io_in[30] ? 6'h13 : _io_out_T_78; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_80 = io_in[31] ? 6'h12 : _io_out_T_79; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_81 = io_in[32] ? 6'h11 : _io_out_T_80; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_82 = io_in[33] ? 6'h10 : _io_out_T_81; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_83 = io_in[34] ? 6'hf : _io_out_T_82; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_84 = io_in[35] ? 6'he : _io_out_T_83; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_85 = io_in[36] ? 6'hd : _io_out_T_84; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_86 = io_in[37] ? 6'hc : _io_out_T_85; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_87 = io_in[38] ? 6'hb : _io_out_T_86; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_88 = io_in[39] ? 6'ha : _io_out_T_87; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_89 = io_in[40] ? 6'h9 : _io_out_T_88; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_90 = io_in[41] ? 6'h8 : _io_out_T_89; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_91 = io_in[42] ? 6'h7 : _io_out_T_90; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_92 = io_in[43] ? 6'h6 : _io_out_T_91; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_93 = io_in[44] ? 6'h5 : _io_out_T_92; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_94 = io_in[45] ? 6'h4 : _io_out_T_93; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_95 = io_in[46] ? 6'h3 : _io_out_T_94; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_96 = io_in[47] ? 6'h2 : _io_out_T_95; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_97 = io_in[48] ? 6'h1 : _io_out_T_96; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  assign io_out = io_in[49] ? 6'h0 : _io_out_T_97; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
endmodule
module FMUL_s1(
  input  [31:0] io_a, // @[src/main/scala/fudian/FMUL.scala 46:14]
  input  [31:0] io_b, // @[src/main/scala/fudian/FMUL.scala 46:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output        io_out_special_case_bits_nan, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output        io_out_special_case_bits_inf, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output        io_out_special_case_bits_inv, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output        io_out_special_case_bits_hasZero, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output        io_out_prod_sign, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output [8:0]  io_out_shift_amt, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output [8:0]  io_out_exp_shifted, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output        io_out_may_be_subnormal, // @[src/main/scala/fudian/FMUL.scala 46:14]
  output [2:0]  io_out_rm // @[src/main/scala/fudian/FMUL.scala 46:14]
);
  wire [49:0] lzc_clz_io_in; // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
  wire [5:0] lzc_clz_io_out; // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
  wire  fp_a_sign = io_a[31]; // @[src/main/scala/fudian/package.scala 59:19]
  wire [7:0] fp_a_exp = io_a[30:23]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [22:0] fp_a_sig = io_a[22:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  fp_b_sign = io_b[31]; // @[src/main/scala/fudian/package.scala 59:19]
  wire [7:0] fp_b_exp = io_b[30:23]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [22:0] fp_b_sig = io_b[22:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  expNotZero = |fp_a_exp; // @[src/main/scala/fudian/package.scala 32:28]
  wire  expIsOnes = &fp_a_exp; // @[src/main/scala/fudian/package.scala 33:27]
  wire  sigNotZero = |fp_a_sig; // @[src/main/scala/fudian/package.scala 34:28]
  wire  decode_a_expIsZero = ~expNotZero; // @[src/main/scala/fudian/package.scala 37:27]
  wire  decode_a_sigIsZero = ~sigNotZero; // @[src/main/scala/fudian/package.scala 40:27]
  wire  decode_a_isInf = expIsOnes & decode_a_sigIsZero; // @[src/main/scala/fudian/package.scala 42:40]
  wire  decode_a_isZero = decode_a_expIsZero & decode_a_sigIsZero; // @[src/main/scala/fudian/package.scala 43:41]
  wire  decode_a_isNaN = expIsOnes & sigNotZero; // @[src/main/scala/fudian/package.scala 44:40]
  wire  decode_a_isSNaN = decode_a_isNaN & ~fp_a_sig[22]; // @[src/main/scala/fudian/package.scala 45:37]
  wire  expNotZero_1 = |fp_b_exp; // @[src/main/scala/fudian/package.scala 32:28]
  wire  expIsOnes_1 = &fp_b_exp; // @[src/main/scala/fudian/package.scala 33:27]
  wire  sigNotZero_1 = |fp_b_sig; // @[src/main/scala/fudian/package.scala 34:28]
  wire  decode_b_expIsZero = ~expNotZero_1; // @[src/main/scala/fudian/package.scala 37:27]
  wire  decode_b_sigIsZero = ~sigNotZero_1; // @[src/main/scala/fudian/package.scala 40:27]
  wire  decode_b_isInf = expIsOnes_1 & decode_b_sigIsZero; // @[src/main/scala/fudian/package.scala 42:40]
  wire  decode_b_isZero = decode_b_expIsZero & decode_b_sigIsZero; // @[src/main/scala/fudian/package.scala 43:41]
  wire  decode_b_isNaN = expIsOnes_1 & sigNotZero_1; // @[src/main/scala/fudian/package.scala 44:40]
  wire  decode_b_isSNaN = decode_b_isNaN & ~fp_b_sig[22]; // @[src/main/scala/fudian/package.scala 45:37]
  wire [7:0] _GEN_0 = {{7'd0}, decode_a_expIsZero}; // @[src/main/scala/fudian/package.scala 83:27]
  wire [7:0] raw_a_exp = fp_a_exp | _GEN_0; // @[src/main/scala/fudian/package.scala 83:27]
  wire [23:0] raw_a_sig = {expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire [7:0] _GEN_1 = {{7'd0}, decode_b_expIsZero}; // @[src/main/scala/fudian/package.scala 83:27]
  wire [7:0] raw_b_exp = fp_b_exp | _GEN_1; // @[src/main/scala/fudian/package.scala 83:27]
  wire [23:0] raw_b_sig = {expNotZero_1,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire [8:0] exp_sum = raw_a_exp + raw_b_exp; // @[src/main/scala/fudian/FMUL.scala 75:27]
  wire [8:0] prod_exp = exp_sum - 9'h64; // @[src/main/scala/fudian/FMUL.scala 76:26]
  wire [9:0] _shift_lim_sub_T = {1'h0,exp_sum}; // @[src/main/scala/fudian/FMUL.scala 78:26]
  wire [9:0] shift_lim_sub = _shift_lim_sub_T - 10'h65; // @[src/main/scala/fudian/FMUL.scala 78:46]
  wire  prod_exp_uf = shift_lim_sub[9]; // @[src/main/scala/fudian/FMUL.scala 79:39]
  wire [8:0] shift_lim = shift_lim_sub[8:0]; // @[src/main/scala/fudian/FMUL.scala 80:37]
  wire [23:0] subnormal_sig = decode_a_expIsZero ? raw_a_sig : raw_b_sig; // @[src/main/scala/fudian/FMUL.scala 85:26]
  wire [8:0] _GEN_2 = {{3'd0}, lzc_clz_io_out}; // @[src/main/scala/fudian/FMUL.scala 87:30]
  wire  exceed_lim = shift_lim <= _GEN_2; // @[src/main/scala/fudian/FMUL.scala 87:30]
  wire [8:0] _shift_amt_T = exceed_lim ? shift_lim : {{3'd0}, lzc_clz_io_out}; // @[src/main/scala/fudian/FMUL.scala 88:44]
  wire [8:0] shift_amt = prod_exp_uf ? 9'h0 : _shift_amt_T; // @[src/main/scala/fudian/FMUL.scala 88:22]
  wire  hasZero = decode_a_isZero | decode_b_isZero; // @[src/main/scala/fudian/FMUL.scala 102:33]
  wire  hasNaN = decode_a_isNaN | decode_b_isNaN; // @[src/main/scala/fudian/FMUL.scala 103:31]
  wire  hasSNaN = decode_a_isSNaN | decode_b_isSNaN; // @[src/main/scala/fudian/FMUL.scala 104:33]
  wire  hasInf = decode_a_isInf | decode_b_isInf; // @[src/main/scala/fudian/FMUL.scala 105:31]
  wire  zero_mul_inf = hasZero & hasInf; // @[src/main/scala/fudian/FMUL.scala 108:30]
  CLZ lzc_clz ( // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
    .io_in(lzc_clz_io_in),
    .io_out(lzc_clz_io_out)
  );
  assign io_out_special_case_bits_nan = hasNaN | zero_mul_inf; // @[src/main/scala/fudian/FMUL.scala 109:27]
  assign io_out_special_case_bits_inf = decode_a_isInf | decode_b_isInf; // @[src/main/scala/fudian/FMUL.scala 105:31]
  assign io_out_special_case_bits_inv = hasSNaN | zero_mul_inf; // @[src/main/scala/fudian/FMUL.scala 110:28]
  assign io_out_special_case_bits_hasZero = decode_a_isZero | decode_b_isZero; // @[src/main/scala/fudian/FMUL.scala 102:33]
  assign io_out_prod_sign = fp_a_sign ^ fp_b_sign; // @[src/main/scala/fudian/FMUL.scala 58:29]
  assign io_out_shift_amt = prod_exp_uf ? 9'h0 : _shift_amt_T; // @[src/main/scala/fudian/FMUL.scala 88:22]
  assign io_out_exp_shifted = prod_exp - shift_amt; // @[src/main/scala/fudian/FMUL.scala 90:30]
  assign io_out_may_be_subnormal = exceed_lim | prod_exp_uf; // @[src/main/scala/fudian/FMUL.scala 96:41]
  assign io_out_rm = io_rm; // @[src/main/scala/fudian/FMUL.scala 97:13]
  assign lzc_clz_io_in = {26'h0,subnormal_sig}; // @[src/main/scala/fudian/FMUL.scala 86:20]
endmodule
module FMUL_s2(
  input         io_in_special_case_bits_nan, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input         io_in_special_case_bits_inf, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input         io_in_special_case_bits_inv, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input         io_in_special_case_bits_hasZero, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input         io_in_prod_sign, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input  [8:0]  io_in_shift_amt, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input  [8:0]  io_in_exp_shifted, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input         io_in_may_be_subnormal, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input  [2:0]  io_in_rm, // @[src/main/scala/fudian/FMUL.scala 122:14]
  input  [47:0] io_prod, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output        io_out_special_case_bits_nan, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output        io_out_special_case_bits_inf, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output        io_out_special_case_bits_inv, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output        io_out_special_case_bits_hasZero, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output        io_out_raw_out_sign, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output [8:0]  io_out_raw_out_exp, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output [73:0] io_out_raw_out_sig, // @[src/main/scala/fudian/FMUL.scala 122:14]
  output [2:0]  io_out_rm // @[src/main/scala/fudian/FMUL.scala 122:14]
);
  wire [73:0] sig_shifter_in = {26'h0,io_prod}; // @[src/main/scala/fudian/FMUL.scala 152:27]
  wire [584:0] _GEN_0 = {{511'd0}, sig_shifter_in}; // @[src/main/scala/fudian/FMUL.scala 153:41]
  wire [584:0] _sig_shifted_raw_T = _GEN_0 << io_in_shift_amt; // @[src/main/scala/fudian/FMUL.scala 153:41]
  wire [73:0] sig_shifted_raw = _sig_shifted_raw_T[73:0]; // @[src/main/scala/fudian/FMUL.scala 153:54]
  wire  exp_is_subnormal = io_in_may_be_subnormal & ~sig_shifted_raw[73]; // @[src/main/scala/fudian/FMUL.scala 154:49]
  wire  no_extra_shift = sig_shifted_raw[73] | exp_is_subnormal; // @[src/main/scala/fudian/FMUL.scala 155:55]
  wire [8:0] _exp_pre_round_T_1 = io_in_exp_shifted - 9'h1; // @[src/main/scala/fudian/FMUL.scala 157:95]
  wire [8:0] _exp_pre_round_T_2 = no_extra_shift ? io_in_exp_shifted : _exp_pre_round_T_1; // @[src/main/scala/fudian/FMUL.scala 157:53]
  wire [73:0] _sig_shifted_T_1 = {sig_shifted_raw[72:0],1'h0}; // @[src/main/scala/fudian/FMUL.scala 158:61]
  assign io_out_special_case_bits_nan = io_in_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 128:23]
  assign io_out_special_case_bits_inf = io_in_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 128:23]
  assign io_out_special_case_bits_inv = io_in_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 128:23]
  assign io_out_special_case_bits_hasZero = io_in_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 128:23]
  assign io_out_raw_out_sign = io_in_prod_sign; // @[src/main/scala/fudian/FMUL.scala 160:23]
  assign io_out_raw_out_exp = exp_is_subnormal ? 9'h0 : _exp_pre_round_T_2; // @[src/main/scala/fudian/FMUL.scala 157:26]
  assign io_out_raw_out_sig = no_extra_shift ? sig_shifted_raw : _sig_shifted_T_1; // @[src/main/scala/fudian/FMUL.scala 158:24]
  assign io_out_rm = io_in_rm; // @[src/main/scala/fudian/FMUL.scala 130:13]
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
module FMUL_s3(
  input         io_in_special_case_bits_nan, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input         io_in_special_case_bits_inf, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input         io_in_special_case_bits_inv, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input         io_in_special_case_bits_hasZero, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input         io_in_raw_out_sign, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input  [8:0]  io_in_raw_out_exp, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input  [73:0] io_in_raw_out_sig, // @[src/main/scala/fudian/FMUL.scala 168:14]
  input  [2:0]  io_in_rm, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output        io_to_fadd_fp_prod_sign, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output [7:0]  io_to_fadd_fp_prod_exp, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output [46:0] io_to_fadd_fp_prod_sig, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output        io_to_fadd_inter_flags_isNaN, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output        io_to_fadd_inter_flags_isInf, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output        io_to_fadd_inter_flags_isInv, // @[src/main/scala/fudian/FMUL.scala 168:14]
  output        io_to_fadd_inter_flags_overflow // @[src/main/scala/fudian/FMUL.scala 168:14]
);
  wire  tininess_rounder_io_in_sign; // @[src/main/scala/fudian/FMUL.scala 186:32]
  wire [26:0] tininess_rounder_io_in_sig; // @[src/main/scala/fudian/FMUL.scala 186:32]
  wire [2:0] tininess_rounder_io_rm; // @[src/main/scala/fudian/FMUL.scala 186:32]
  wire  tininess_rounder_io_tininess; // @[src/main/scala/fudian/FMUL.scala 186:32]
  wire [22:0] rounder_io_in; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_roundIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_stickyIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_signIn; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [2:0] rounder_io_rm; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [22:0] rounder_io_out; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_inexact; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire  rounder_io_cout; // @[src/main/scala/fudian/RoundingUnit.scala 44:25]
  wire [26:0] raw_in_sig = {io_in_raw_out_sig[73:48],|io_in_raw_out_sig[47:0]}; // @[src/main/scala/fudian/FMUL.scala 184:20]
  wire [8:0] _io_to_fadd_fp_prod_exp_T = io_in_special_case_bits_hasZero ? 9'h0 : io_in_raw_out_exp; // @[src/main/scala/fudian/FMUL.scala 248:32]
  wire [46:0] _GEN_1 = {{46'd0}, |io_in_raw_out_sig[25:0]}; // @[src/main/scala/fudian/FMUL.scala 251:49]
  wire [46:0] _io_to_fadd_fp_prod_sig_T_4 = io_in_raw_out_sig[72:26] | _GEN_1; // @[src/main/scala/fudian/FMUL.scala 251:49]
  TininessRounder tininess_rounder ( // @[src/main/scala/fudian/FMUL.scala 186:32]
    .io_in_sign(tininess_rounder_io_in_sign),
    .io_in_sig(tininess_rounder_io_in_sig),
    .io_rm(tininess_rounder_io_rm),
    .io_tininess(tininess_rounder_io_tininess)
  );
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
  assign io_to_fadd_fp_prod_sign = io_in_raw_out_sign; // @[src/main/scala/fudian/FMUL.scala 247:27]
  assign io_to_fadd_fp_prod_exp = _io_to_fadd_fp_prod_exp_T[7:0]; // @[src/main/scala/fudian/FMUL.scala 248:26]
  assign io_to_fadd_fp_prod_sig = io_in_special_case_bits_hasZero ? 47'h0 : _io_to_fadd_fp_prod_sig_T_4; // @[src/main/scala/fudian/FMUL.scala 249:32]
  assign io_to_fadd_inter_flags_isNaN = io_in_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 255:32]
  assign io_to_fadd_inter_flags_isInf = io_in_special_case_bits_inf & ~io_in_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 254:57]
  assign io_to_fadd_inter_flags_isInv = io_in_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 253:32]
  assign io_to_fadd_inter_flags_overflow = io_in_raw_out_exp > 9'hff; // @[src/main/scala/fudian/FMUL.scala 256:52]
  assign tininess_rounder_io_in_sign = io_in_raw_out_sign; // @[src/main/scala/fudian/FMUL.scala 181:20 182:15]
  assign tininess_rounder_io_in_sig = {io_in_raw_out_sig[73:48],|io_in_raw_out_sig[47:0]}; // @[src/main/scala/fudian/FMUL.scala 184:20]
  assign tininess_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/FMUL.scala 188:26]
  assign rounder_io_in = raw_in_sig[25:3]; // @[src/main/scala/fudian/RoundingUnit.scala 45:33]
  assign rounder_io_roundIn = raw_in_sig[2]; // @[src/main/scala/fudian/RoundingUnit.scala 46:50]
  assign rounder_io_stickyIn = |raw_in_sig[1:0]; // @[src/main/scala/fudian/RoundingUnit.scala 47:51]
  assign rounder_io_signIn = io_in_raw_out_sign; // @[src/main/scala/fudian/FMUL.scala 181:20 182:15]
  assign rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/RoundingUnit.scala 48:19]
endmodule
module FMUL(
  input  [31:0] io_a, // @[src/main/scala/fudian/FMUL.scala 260:14]
  input  [31:0] io_b, // @[src/main/scala/fudian/FMUL.scala 260:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output        io_to_fadd_fp_prod_sign, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output [7:0]  io_to_fadd_fp_prod_exp, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output [46:0] io_to_fadd_fp_prod_sig, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output        io_to_fadd_inter_flags_isNaN, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output        io_to_fadd_inter_flags_isInf, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output        io_to_fadd_inter_flags_isInv, // @[src/main/scala/fudian/FMUL.scala 260:14]
  output        io_to_fadd_inter_flags_overflow // @[src/main/scala/fudian/FMUL.scala 260:14]
);
  wire [24:0] multiplier_io_a; // @[src/main/scala/fudian/FMUL.scala 268:26]
  wire [24:0] multiplier_io_b; // @[src/main/scala/fudian/FMUL.scala 268:26]
  wire [49:0] multiplier_io_result; // @[src/main/scala/fudian/FMUL.scala 268:26]
  wire [31:0] fmul_s1_io_a; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire [31:0] fmul_s1_io_b; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire [2:0] fmul_s1_io_rm; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s1_io_out_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s1_io_out_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s1_io_out_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s1_io_out_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s1_io_out_prod_sign; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire [8:0] fmul_s1_io_out_shift_amt; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire [8:0] fmul_s1_io_out_exp_shifted; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s1_io_out_may_be_subnormal; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire [2:0] fmul_s1_io_out_rm; // @[src/main/scala/fudian/FMUL.scala 269:23]
  wire  fmul_s2_io_in_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_in_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_in_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_in_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_in_prod_sign; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [8:0] fmul_s2_io_in_shift_amt; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [8:0] fmul_s2_io_in_exp_shifted; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_in_may_be_subnormal; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [2:0] fmul_s2_io_in_rm; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [47:0] fmul_s2_io_prod; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_out_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_out_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_out_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_out_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s2_io_out_raw_out_sign; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [8:0] fmul_s2_io_out_raw_out_exp; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [73:0] fmul_s2_io_out_raw_out_sig; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire [2:0] fmul_s2_io_out_rm; // @[src/main/scala/fudian/FMUL.scala 270:23]
  wire  fmul_s3_io_in_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_in_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_in_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_in_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_in_raw_out_sign; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire [8:0] fmul_s3_io_in_raw_out_exp; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire [73:0] fmul_s3_io_in_raw_out_sig; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire [2:0] fmul_s3_io_in_rm; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_to_fadd_fp_prod_sign; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire [7:0] fmul_s3_io_to_fadd_fp_prod_exp; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire [46:0] fmul_s3_io_to_fadd_fp_prod_sig; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_to_fadd_inter_flags_isNaN; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_to_fadd_inter_flags_isInf; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_to_fadd_inter_flags_isInv; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire  fmul_s3_io_to_fadd_inter_flags_overflow; // @[src/main/scala/fudian/FMUL.scala 271:23]
  wire [7:0] raw_a_fp_exp = io_a[30:23]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [22:0] raw_a_fp_sig = io_a[22:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  raw_a_raw_nz = |raw_a_fp_exp; // @[src/main/scala/fudian/package.scala 81:69]
  wire [23:0] raw_a_sig = {raw_a_raw_nz,raw_a_fp_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire [7:0] raw_b_fp_exp = io_b[30:23]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [22:0] raw_b_fp_sig = io_b[22:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  raw_b_raw_nz = |raw_b_fp_exp; // @[src/main/scala/fudian/package.scala 81:69]
  wire [23:0] raw_b_sig = {raw_b_raw_nz,raw_b_fp_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  Multiplier multiplier ( // @[src/main/scala/fudian/FMUL.scala 268:26]
    .io_a(multiplier_io_a),
    .io_b(multiplier_io_b),
    .io_result(multiplier_io_result)
  );
  FMUL_s1 fmul_s1 ( // @[src/main/scala/fudian/FMUL.scala 269:23]
    .io_a(fmul_s1_io_a),
    .io_b(fmul_s1_io_b),
    .io_rm(fmul_s1_io_rm),
    .io_out_special_case_bits_nan(fmul_s1_io_out_special_case_bits_nan),
    .io_out_special_case_bits_inf(fmul_s1_io_out_special_case_bits_inf),
    .io_out_special_case_bits_inv(fmul_s1_io_out_special_case_bits_inv),
    .io_out_special_case_bits_hasZero(fmul_s1_io_out_special_case_bits_hasZero),
    .io_out_prod_sign(fmul_s1_io_out_prod_sign),
    .io_out_shift_amt(fmul_s1_io_out_shift_amt),
    .io_out_exp_shifted(fmul_s1_io_out_exp_shifted),
    .io_out_may_be_subnormal(fmul_s1_io_out_may_be_subnormal),
    .io_out_rm(fmul_s1_io_out_rm)
  );
  FMUL_s2 fmul_s2 ( // @[src/main/scala/fudian/FMUL.scala 270:23]
    .io_in_special_case_bits_nan(fmul_s2_io_in_special_case_bits_nan),
    .io_in_special_case_bits_inf(fmul_s2_io_in_special_case_bits_inf),
    .io_in_special_case_bits_inv(fmul_s2_io_in_special_case_bits_inv),
    .io_in_special_case_bits_hasZero(fmul_s2_io_in_special_case_bits_hasZero),
    .io_in_prod_sign(fmul_s2_io_in_prod_sign),
    .io_in_shift_amt(fmul_s2_io_in_shift_amt),
    .io_in_exp_shifted(fmul_s2_io_in_exp_shifted),
    .io_in_may_be_subnormal(fmul_s2_io_in_may_be_subnormal),
    .io_in_rm(fmul_s2_io_in_rm),
    .io_prod(fmul_s2_io_prod),
    .io_out_special_case_bits_nan(fmul_s2_io_out_special_case_bits_nan),
    .io_out_special_case_bits_inf(fmul_s2_io_out_special_case_bits_inf),
    .io_out_special_case_bits_inv(fmul_s2_io_out_special_case_bits_inv),
    .io_out_special_case_bits_hasZero(fmul_s2_io_out_special_case_bits_hasZero),
    .io_out_raw_out_sign(fmul_s2_io_out_raw_out_sign),
    .io_out_raw_out_exp(fmul_s2_io_out_raw_out_exp),
    .io_out_raw_out_sig(fmul_s2_io_out_raw_out_sig),
    .io_out_rm(fmul_s2_io_out_rm)
  );
  FMUL_s3 fmul_s3 ( // @[src/main/scala/fudian/FMUL.scala 271:23]
    .io_in_special_case_bits_nan(fmul_s3_io_in_special_case_bits_nan),
    .io_in_special_case_bits_inf(fmul_s3_io_in_special_case_bits_inf),
    .io_in_special_case_bits_inv(fmul_s3_io_in_special_case_bits_inv),
    .io_in_special_case_bits_hasZero(fmul_s3_io_in_special_case_bits_hasZero),
    .io_in_raw_out_sign(fmul_s3_io_in_raw_out_sign),
    .io_in_raw_out_exp(fmul_s3_io_in_raw_out_exp),
    .io_in_raw_out_sig(fmul_s3_io_in_raw_out_sig),
    .io_in_rm(fmul_s3_io_in_rm),
    .io_to_fadd_fp_prod_sign(fmul_s3_io_to_fadd_fp_prod_sign),
    .io_to_fadd_fp_prod_exp(fmul_s3_io_to_fadd_fp_prod_exp),
    .io_to_fadd_fp_prod_sig(fmul_s3_io_to_fadd_fp_prod_sig),
    .io_to_fadd_inter_flags_isNaN(fmul_s3_io_to_fadd_inter_flags_isNaN),
    .io_to_fadd_inter_flags_isInf(fmul_s3_io_to_fadd_inter_flags_isInf),
    .io_to_fadd_inter_flags_isInv(fmul_s3_io_to_fadd_inter_flags_isInv),
    .io_to_fadd_inter_flags_overflow(fmul_s3_io_to_fadd_inter_flags_overflow)
  );
  assign io_to_fadd_fp_prod_sign = fmul_s3_io_to_fadd_fp_prod_sign; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign io_to_fadd_fp_prod_exp = fmul_s3_io_to_fadd_fp_prod_exp; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign io_to_fadd_fp_prod_sig = fmul_s3_io_to_fadd_fp_prod_sig; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign io_to_fadd_inter_flags_isNaN = fmul_s3_io_to_fadd_inter_flags_isNaN; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign io_to_fadd_inter_flags_isInf = fmul_s3_io_to_fadd_inter_flags_isInf; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign io_to_fadd_inter_flags_isInv = fmul_s3_io_to_fadd_inter_flags_isInv; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign io_to_fadd_inter_flags_overflow = fmul_s3_io_to_fadd_inter_flags_overflow; // @[src/main/scala/fudian/FMUL.scala 290:14]
  assign multiplier_io_a = {{1'd0}, raw_a_sig}; // @[src/main/scala/fudian/FMUL.scala 277:19]
  assign multiplier_io_b = {{1'd0}, raw_b_sig}; // @[src/main/scala/fudian/FMUL.scala 278:19]
  assign fmul_s1_io_a = io_a; // @[src/main/scala/fudian/FMUL.scala 281:16]
  assign fmul_s1_io_b = io_b; // @[src/main/scala/fudian/FMUL.scala 282:16]
  assign fmul_s1_io_rm = io_rm; // @[src/main/scala/fudian/FMUL.scala 283:17]
  assign fmul_s2_io_in_special_case_bits_nan = fmul_s1_io_out_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_special_case_bits_inf = fmul_s1_io_out_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_special_case_bits_inv = fmul_s1_io_out_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_special_case_bits_hasZero = fmul_s1_io_out_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_prod_sign = fmul_s1_io_out_prod_sign; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_shift_amt = fmul_s1_io_out_shift_amt; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_exp_shifted = fmul_s1_io_out_exp_shifted; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_may_be_subnormal = fmul_s1_io_out_may_be_subnormal; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_in_rm = fmul_s1_io_out_rm; // @[src/main/scala/fudian/FMUL.scala 285:17]
  assign fmul_s2_io_prod = multiplier_io_result[47:0]; // @[src/main/scala/fudian/FMUL.scala 286:19]
  assign fmul_s3_io_in_special_case_bits_nan = fmul_s2_io_out_special_case_bits_nan; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_special_case_bits_inf = fmul_s2_io_out_special_case_bits_inf; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_special_case_bits_inv = fmul_s2_io_out_special_case_bits_inv; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_special_case_bits_hasZero = fmul_s2_io_out_special_case_bits_hasZero; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_raw_out_sign = fmul_s2_io_out_raw_out_sign; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_raw_out_exp = fmul_s2_io_out_raw_out_exp; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_raw_out_sig = fmul_s2_io_out_raw_out_sig; // @[src/main/scala/fudian/FMUL.scala 288:17]
  assign fmul_s3_io_in_rm = fmul_s2_io_out_rm; // @[src/main/scala/fudian/FMUL.scala 288:17]
endmodule
module ShiftRightJam(
  input  [49:0] io_in, // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
  input  [7:0]  io_shamt, // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
  output [49:0] io_out, // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
  output        io_sticky // @[src/main/scala/fudian/utils/ShiftRightJam.scala 11:14]
);
  wire  exceed_max_shift = io_shamt > 8'h32; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 17:35]
  wire [5:0] shamt = io_shamt[5:0]; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 18:23]
  wire [63:0] _sticky_mask_T = 64'h1 << shamt; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:11]
  wire [63:0] _sticky_mask_T_2 = _sticky_mask_T - 64'h1; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:28]
  wire [49:0] _sticky_mask_T_5 = exceed_max_shift ? 50'h3ffffffffffff : 50'h0; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:53]
  wire [49:0] sticky_mask = _sticky_mask_T_2[49:0] | _sticky_mask_T_5; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 20:47]
  wire [49:0] _io_out_T = io_in >> io_shamt; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 21:46]
  wire [49:0] _io_sticky_T = io_in & sticky_mask; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 22:23]
  assign io_out = exceed_max_shift ? 50'h0 : _io_out_T; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 21:16]
  assign io_sticky = |_io_sticky_T; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 22:38]
endmodule
module FarPath(
  input         io_in_a_sign, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [7:0]  io_in_a_exp, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [47:0] io_in_a_sig, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [47:0] io_in_b_sig, // @[src/main/scala/fudian/FADD.scala 9:14]
  input  [7:0]  io_in_expDiff, // @[src/main/scala/fudian/FADD.scala 9:14]
  input         io_in_effSub, // @[src/main/scala/fudian/FADD.scala 9:14]
  output        io_out_result_sign, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [47:0] io_out_sig_a, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [51:0] io_out_sig_b, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [7:0]  io_out_exp_a_vec_0, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [7:0]  io_out_exp_a_vec_1, // @[src/main/scala/fudian/FADD.scala 9:14]
  output [7:0]  io_out_exp_a_vec_2 // @[src/main/scala/fudian/FADD.scala 9:14]
);
  wire [49:0] shiftRightJam_io_in; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire [7:0] shiftRightJam_io_shamt; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire [49:0] shiftRightJam_io_out; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire  shiftRightJam_io_sticky; // @[src/main/scala/fudian/utils/ShiftRightJam.scala 27:31]
  wire [51:0] adder_in_sig_b_raw = {1'h0,shiftRightJam_io_out,shiftRightJam_io_sticky}; // @[src/main/scala/fudian/FADD.scala 34:31]
  wire [51:0] _adder_in_sig_b_T = ~adder_in_sig_b_raw; // @[src/main/scala/fudian/FADD.scala 35:37]
  wire [51:0] _adder_in_sig_b_T_1 = io_in_effSub ? _adder_in_sig_b_T : adder_in_sig_b_raw; // @[src/main/scala/fudian/FADD.scala 35:27]
  wire [51:0] _GEN_0 = {{51'd0}, io_in_effSub}; // @[src/main/scala/fudian/FADD.scala 35:86]
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
  input  [48:0] io_a, // @[src/main/scala/fudian/utils/LZA.scala 12:14]
  input  [48:0] io_b, // @[src/main/scala/fudian/utils/LZA.scala 12:14]
  output [48:0] io_f // @[src/main/scala/fudian/utils/LZA.scala 12:14]
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
  wire  k_24 = ~io_a[24] & ~io_b[24]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_24 = p_24 ^ ~k_23; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_25 = io_a[25] ^ io_b[25]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_25 = ~io_a[25] & ~io_b[25]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_25 = p_25 ^ ~k_24; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_26 = io_a[26] ^ io_b[26]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_26 = ~io_a[26] & ~io_b[26]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_26 = p_26 ^ ~k_25; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_27 = io_a[27] ^ io_b[27]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_27 = ~io_a[27] & ~io_b[27]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_27 = p_27 ^ ~k_26; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_28 = io_a[28] ^ io_b[28]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_28 = ~io_a[28] & ~io_b[28]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_28 = p_28 ^ ~k_27; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_29 = io_a[29] ^ io_b[29]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_29 = ~io_a[29] & ~io_b[29]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_29 = p_29 ^ ~k_28; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_30 = io_a[30] ^ io_b[30]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_30 = ~io_a[30] & ~io_b[30]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_30 = p_30 ^ ~k_29; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_31 = io_a[31] ^ io_b[31]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_31 = ~io_a[31] & ~io_b[31]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_31 = p_31 ^ ~k_30; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_32 = io_a[32] ^ io_b[32]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_32 = ~io_a[32] & ~io_b[32]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_32 = p_32 ^ ~k_31; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_33 = io_a[33] ^ io_b[33]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_33 = ~io_a[33] & ~io_b[33]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_33 = p_33 ^ ~k_32; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_34 = io_a[34] ^ io_b[34]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_34 = ~io_a[34] & ~io_b[34]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_34 = p_34 ^ ~k_33; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_35 = io_a[35] ^ io_b[35]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_35 = ~io_a[35] & ~io_b[35]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_35 = p_35 ^ ~k_34; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_36 = io_a[36] ^ io_b[36]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_36 = ~io_a[36] & ~io_b[36]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_36 = p_36 ^ ~k_35; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_37 = io_a[37] ^ io_b[37]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_37 = ~io_a[37] & ~io_b[37]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_37 = p_37 ^ ~k_36; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_38 = io_a[38] ^ io_b[38]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_38 = ~io_a[38] & ~io_b[38]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_38 = p_38 ^ ~k_37; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_39 = io_a[39] ^ io_b[39]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_39 = ~io_a[39] & ~io_b[39]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_39 = p_39 ^ ~k_38; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_40 = io_a[40] ^ io_b[40]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_40 = ~io_a[40] & ~io_b[40]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_40 = p_40 ^ ~k_39; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_41 = io_a[41] ^ io_b[41]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_41 = ~io_a[41] & ~io_b[41]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_41 = p_41 ^ ~k_40; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_42 = io_a[42] ^ io_b[42]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_42 = ~io_a[42] & ~io_b[42]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_42 = p_42 ^ ~k_41; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_43 = io_a[43] ^ io_b[43]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_43 = ~io_a[43] & ~io_b[43]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_43 = p_43 ^ ~k_42; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_44 = io_a[44] ^ io_b[44]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_44 = ~io_a[44] & ~io_b[44]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_44 = p_44 ^ ~k_43; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_45 = io_a[45] ^ io_b[45]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_45 = ~io_a[45] & ~io_b[45]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_45 = p_45 ^ ~k_44; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_46 = io_a[46] ^ io_b[46]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_46 = ~io_a[46] & ~io_b[46]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_46 = p_46 ^ ~k_45; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_47 = io_a[47] ^ io_b[47]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  k_47 = ~io_a[47] & ~io_b[47]; // @[src/main/scala/fudian/utils/LZA.scala 19:21]
  wire  f_47 = p_47 ^ ~k_46; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire  p_48 = io_a[48] ^ io_b[48]; // @[src/main/scala/fudian/utils/LZA.scala 18:18]
  wire  f_48 = p_48 ^ ~k_47; // @[src/main/scala/fudian/utils/LZA.scala 23:20]
  wire [5:0] io_f_lo_lo_lo = {f_5,f_4,f_3,f_2,f_1,1'h0}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [11:0] io_f_lo_lo = {f_11,f_10,f_9,f_8,f_7,f_6,io_f_lo_lo_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [5:0] io_f_lo_hi_lo = {f_17,f_16,f_15,f_14,f_13,f_12}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [23:0] io_f_lo = {f_23,f_22,f_21,f_20,f_19,f_18,io_f_lo_hi_lo,io_f_lo_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [5:0] io_f_hi_lo_lo = {f_29,f_28,f_27,f_26,f_25,f_24}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [11:0] io_f_hi_lo = {f_35,f_34,f_33,f_32,f_31,f_30,io_f_hi_lo_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [5:0] io_f_hi_hi_lo = {f_41,f_40,f_39,f_38,f_37,f_36}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  wire [24:0] io_f_hi = {f_48,f_47,f_46,f_45,f_44,f_43,f_42,io_f_hi_hi_lo,io_f_hi_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
  assign io_f = {io_f_hi,io_f_lo}; // @[src/main/scala/fudian/utils/LZA.scala 26:14]
endmodule
module CLZ_1(
  input  [48:0] io_in, // @[src/main/scala/fudian/utils/CLZ.scala 12:14]
  output [5:0]  io_out // @[src/main/scala/fudian/utils/CLZ.scala 12:14]
);
  wire [5:0] _io_out_T_49 = io_in[1] ? 6'h2f : 6'h30; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_50 = io_in[2] ? 6'h2e : _io_out_T_49; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_51 = io_in[3] ? 6'h2d : _io_out_T_50; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_52 = io_in[4] ? 6'h2c : _io_out_T_51; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_53 = io_in[5] ? 6'h2b : _io_out_T_52; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_54 = io_in[6] ? 6'h2a : _io_out_T_53; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_55 = io_in[7] ? 6'h29 : _io_out_T_54; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_56 = io_in[8] ? 6'h28 : _io_out_T_55; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_57 = io_in[9] ? 6'h27 : _io_out_T_56; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_58 = io_in[10] ? 6'h26 : _io_out_T_57; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_59 = io_in[11] ? 6'h25 : _io_out_T_58; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_60 = io_in[12] ? 6'h24 : _io_out_T_59; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_61 = io_in[13] ? 6'h23 : _io_out_T_60; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_62 = io_in[14] ? 6'h22 : _io_out_T_61; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_63 = io_in[15] ? 6'h21 : _io_out_T_62; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_64 = io_in[16] ? 6'h20 : _io_out_T_63; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_65 = io_in[17] ? 6'h1f : _io_out_T_64; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_66 = io_in[18] ? 6'h1e : _io_out_T_65; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_67 = io_in[19] ? 6'h1d : _io_out_T_66; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_68 = io_in[20] ? 6'h1c : _io_out_T_67; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_69 = io_in[21] ? 6'h1b : _io_out_T_68; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_70 = io_in[22] ? 6'h1a : _io_out_T_69; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_71 = io_in[23] ? 6'h19 : _io_out_T_70; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_72 = io_in[24] ? 6'h18 : _io_out_T_71; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_73 = io_in[25] ? 6'h17 : _io_out_T_72; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_74 = io_in[26] ? 6'h16 : _io_out_T_73; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_75 = io_in[27] ? 6'h15 : _io_out_T_74; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_76 = io_in[28] ? 6'h14 : _io_out_T_75; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_77 = io_in[29] ? 6'h13 : _io_out_T_76; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_78 = io_in[30] ? 6'h12 : _io_out_T_77; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_79 = io_in[31] ? 6'h11 : _io_out_T_78; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_80 = io_in[32] ? 6'h10 : _io_out_T_79; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_81 = io_in[33] ? 6'hf : _io_out_T_80; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_82 = io_in[34] ? 6'he : _io_out_T_81; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_83 = io_in[35] ? 6'hd : _io_out_T_82; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_84 = io_in[36] ? 6'hc : _io_out_T_83; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_85 = io_in[37] ? 6'hb : _io_out_T_84; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_86 = io_in[38] ? 6'ha : _io_out_T_85; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_87 = io_in[39] ? 6'h9 : _io_out_T_86; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_88 = io_in[40] ? 6'h8 : _io_out_T_87; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_89 = io_in[41] ? 6'h7 : _io_out_T_88; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_90 = io_in[42] ? 6'h6 : _io_out_T_89; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_91 = io_in[43] ? 6'h5 : _io_out_T_90; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_92 = io_in[44] ? 6'h4 : _io_out_T_91; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_93 = io_in[45] ? 6'h3 : _io_out_T_92; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_94 = io_in[46] ? 6'h2 : _io_out_T_93; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  wire [5:0] _io_out_T_95 = io_in[47] ? 6'h1 : _io_out_T_94; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
  assign io_out = io_in[48] ? 6'h0 : _io_out_T_95; // @[src/main/scala/chisel3/util/Mux.scala 50:70]
endmodule
module NearPath(
  input         io_in_a_sign, // @[src/main/scala/fudian/FADD.scala 84:14]
  input  [7:0]  io_in_a_exp, // @[src/main/scala/fudian/FADD.scala 84:14]
  input  [47:0] io_in_a_sig, // @[src/main/scala/fudian/FADD.scala 84:14]
  input         io_in_b_sign, // @[src/main/scala/fudian/FADD.scala 84:14]
  input  [47:0] io_in_b_sig, // @[src/main/scala/fudian/FADD.scala 84:14]
  input         io_in_need_shift_b, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_result_sign, // @[src/main/scala/fudian/FADD.scala 84:14]
  output [7:0]  io_out_result_exp, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_sig_is_zero, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_a_lt_b, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_lza_error, // @[src/main/scala/fudian/FADD.scala 84:14]
  output        io_out_int_bit, // @[src/main/scala/fudian/FADD.scala 84:14]
  output [48:0] io_out_sig_raw, // @[src/main/scala/fudian/FADD.scala 84:14]
  output [5:0]  io_out_lzc // @[src/main/scala/fudian/FADD.scala 84:14]
);
  wire [48:0] lza_ab_io_a; // @[src/main/scala/fudian/FADD.scala 109:22]
  wire [48:0] lza_ab_io_b; // @[src/main/scala/fudian/FADD.scala 109:22]
  wire [48:0] lza_ab_io_f; // @[src/main/scala/fudian/FADD.scala 109:22]
  wire [48:0] lzc_clz_io_in; // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
  wire [5:0] lzc_clz_io_out; // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
  wire [48:0] _b_sig_T = {io_in_b_sig,1'h0}; // @[src/main/scala/fudian/FADD.scala 103:19]
  wire [48:0] b_sig = _b_sig_T >> io_in_need_shift_b; // @[src/main/scala/fudian/FADD.scala 103:37]
  wire [48:0] b_neg = ~b_sig; // @[src/main/scala/fudian/FADD.scala 104:16]
  wire [49:0] _a_minus_b_T = {1'h0,io_in_a_sig,1'h0}; // @[src/main/scala/fudian/FADD.scala 106:22]
  wire [49:0] _a_minus_b_T_1 = {1'h1,b_neg}; // @[src/main/scala/fudian/FADD.scala 106:45]
  wire [49:0] _a_minus_b_T_3 = _a_minus_b_T + _a_minus_b_T_1; // @[src/main/scala/fudian/FADD.scala 106:40]
  wire [49:0] a_minus_b = _a_minus_b_T_3 + 50'h1; // @[src/main/scala/fudian/FADD.scala 106:63]
  wire  a_lt_b = a_minus_b[49]; // @[src/main/scala/fudian/FADD.scala 107:30]
  wire [48:0] sig_raw = a_minus_b[48:0]; // @[src/main/scala/fudian/FADD.scala 108:31]
  wire  lza_str_zero = ~(|lza_ab_io_f); // @[src/main/scala/fudian/FADD.scala 113:22]
  wire  need_shift_lim = io_in_a_exp < 8'h31; // @[src/main/scala/fudian/FADD.scala 116:30]
  wire [49:0] _shift_lim_mask_raw_T_2 = 50'h2000000000000 >> io_in_a_exp[5:0]; // @[src/main/scala/fudian/FADD.scala 119:41]
  wire [48:0] shift_lim_mask_raw = _shift_lim_mask_raw_T_2[48:0]; // @[src/main/scala/fudian/FADD.scala 120:14]
  wire [48:0] shift_lim_mask = need_shift_lim ? shift_lim_mask_raw : 49'h0; // @[src/main/scala/fudian/FADD.scala 121:27]
  wire [48:0] _shift_lim_bit_T = shift_lim_mask_raw & sig_raw; // @[src/main/scala/fudian/FADD.scala 122:43]
  wire  shift_lim_bit = |_shift_lim_bit_T; // @[src/main/scala/fudian/FADD.scala 122:54]
  wire [48:0] lzc_str = shift_lim_mask | lza_ab_io_f; // @[src/main/scala/fudian/FADD.scala 124:32]
  wire  _int_bit_mask_T_5 = lzc_str[47] & ~(|lzc_str[48]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_10 = lzc_str[46] & ~(|lzc_str[48:47]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_15 = lzc_str[45] & ~(|lzc_str[48:46]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_20 = lzc_str[44] & ~(|lzc_str[48:45]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_25 = lzc_str[43] & ~(|lzc_str[48:44]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_30 = lzc_str[42] & ~(|lzc_str[48:43]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_35 = lzc_str[41] & ~(|lzc_str[48:42]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_40 = lzc_str[40] & ~(|lzc_str[48:41]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_45 = lzc_str[39] & ~(|lzc_str[48:40]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_50 = lzc_str[38] & ~(|lzc_str[48:39]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_55 = lzc_str[37] & ~(|lzc_str[48:38]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_60 = lzc_str[36] & ~(|lzc_str[48:37]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_65 = lzc_str[35] & ~(|lzc_str[48:36]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_70 = lzc_str[34] & ~(|lzc_str[48:35]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_75 = lzc_str[33] & ~(|lzc_str[48:34]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_80 = lzc_str[32] & ~(|lzc_str[48:33]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_85 = lzc_str[31] & ~(|lzc_str[48:32]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_90 = lzc_str[30] & ~(|lzc_str[48:31]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_95 = lzc_str[29] & ~(|lzc_str[48:30]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_100 = lzc_str[28] & ~(|lzc_str[48:29]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_105 = lzc_str[27] & ~(|lzc_str[48:28]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_110 = lzc_str[26] & ~(|lzc_str[48:27]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_115 = lzc_str[25] & ~(|lzc_str[48:26]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_120 = lzc_str[24] & ~(|lzc_str[48:25]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_125 = lzc_str[23] & ~(|lzc_str[48:24]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_130 = lzc_str[22] & ~(|lzc_str[48:23]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_135 = lzc_str[21] & ~(|lzc_str[48:22]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_140 = lzc_str[20] & ~(|lzc_str[48:21]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_145 = lzc_str[19] & ~(|lzc_str[48:20]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_150 = lzc_str[18] & ~(|lzc_str[48:19]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_155 = lzc_str[17] & ~(|lzc_str[48:18]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_160 = lzc_str[16] & ~(|lzc_str[48:17]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_165 = lzc_str[15] & ~(|lzc_str[48:16]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_170 = lzc_str[14] & ~(|lzc_str[48:15]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_175 = lzc_str[13] & ~(|lzc_str[48:14]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_180 = lzc_str[12] & ~(|lzc_str[48:13]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_185 = lzc_str[11] & ~(|lzc_str[48:12]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_190 = lzc_str[10] & ~(|lzc_str[48:11]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_195 = lzc_str[9] & ~(|lzc_str[48:10]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_200 = lzc_str[8] & ~(|lzc_str[48:9]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_205 = lzc_str[7] & ~(|lzc_str[48:8]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_210 = lzc_str[6] & ~(|lzc_str[48:7]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_215 = lzc_str[5] & ~(|lzc_str[48:6]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_220 = lzc_str[4] & ~(|lzc_str[48:5]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_225 = lzc_str[3] & ~(|lzc_str[48:4]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_230 = lzc_str[2] & ~(|lzc_str[48:3]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_235 = lzc_str[1] & ~(|lzc_str[48:2]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire  _int_bit_mask_T_240 = lzc_str[0] & ~(|lzc_str[48:1]); // @[src/main/scala/fudian/FADD.scala 129:40]
  wire [5:0] int_bit_mask_lo_lo_lo = {_int_bit_mask_T_215,_int_bit_mask_T_220,_int_bit_mask_T_225,_int_bit_mask_T_230,
    _int_bit_mask_T_235,_int_bit_mask_T_240}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [11:0] int_bit_mask_lo_lo = {_int_bit_mask_T_185,_int_bit_mask_T_190,_int_bit_mask_T_195,_int_bit_mask_T_200,
    _int_bit_mask_T_205,_int_bit_mask_T_210,int_bit_mask_lo_lo_lo}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [5:0] int_bit_mask_lo_hi_lo = {_int_bit_mask_T_155,_int_bit_mask_T_160,_int_bit_mask_T_165,_int_bit_mask_T_170,
    _int_bit_mask_T_175,_int_bit_mask_T_180}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [23:0] int_bit_mask_lo = {_int_bit_mask_T_125,_int_bit_mask_T_130,_int_bit_mask_T_135,_int_bit_mask_T_140,
    _int_bit_mask_T_145,_int_bit_mask_T_150,int_bit_mask_lo_hi_lo,int_bit_mask_lo_lo}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [5:0] int_bit_mask_hi_lo_lo = {_int_bit_mask_T_95,_int_bit_mask_T_100,_int_bit_mask_T_105,_int_bit_mask_T_110,
    _int_bit_mask_T_115,_int_bit_mask_T_120}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [11:0] int_bit_mask_hi_lo = {_int_bit_mask_T_65,_int_bit_mask_T_70,_int_bit_mask_T_75,_int_bit_mask_T_80,
    _int_bit_mask_T_85,_int_bit_mask_T_90,int_bit_mask_hi_lo_lo}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [5:0] int_bit_mask_hi_hi_lo = {_int_bit_mask_T_35,_int_bit_mask_T_40,_int_bit_mask_T_45,_int_bit_mask_T_50,
    _int_bit_mask_T_55,_int_bit_mask_T_60}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [48:0] int_bit_mask = {lzc_str[48],_int_bit_mask_T_5,_int_bit_mask_T_10,_int_bit_mask_T_15,_int_bit_mask_T_20,
    _int_bit_mask_T_25,_int_bit_mask_T_30,int_bit_mask_hi_hi_lo,int_bit_mask_hi_lo,int_bit_mask_lo}; // @[src/main/scala/fudian/FADD.scala 127:25]
  wire [48:0] _GEN_0 = {{48'd0}, lza_str_zero}; // @[src/main/scala/fudian/FADD.scala 133:20]
  wire [48:0] _int_bit_predicted_T = int_bit_mask | _GEN_0; // @[src/main/scala/fudian/FADD.scala 133:20]
  wire [48:0] _int_bit_predicted_T_1 = _int_bit_predicted_T & sig_raw; // @[src/main/scala/fudian/FADD.scala 133:36]
  wire  int_bit_predicted = |_int_bit_predicted_T_1; // @[src/main/scala/fudian/FADD.scala 133:47]
  wire [48:0] _int_bit_rshift_1_T = {{1'd0}, int_bit_mask[48:1]}; // @[src/main/scala/fudian/FADD.scala 135:20]
  wire [48:0] _int_bit_rshift_1_T_1 = _int_bit_rshift_1_T & sig_raw; // @[src/main/scala/fudian/FADD.scala 135:35]
  wire  int_bit_rshift_1 = |_int_bit_rshift_1_T_1; // @[src/main/scala/fudian/FADD.scala 135:46]
  wire  _exceed_lim_mask_T_1 = |lza_ab_io_f[48]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_3 = |lza_ab_io_f[48:47]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_5 = |lza_ab_io_f[48:46]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_7 = |lza_ab_io_f[48:45]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_9 = |lza_ab_io_f[48:44]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_11 = |lza_ab_io_f[48:43]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_13 = |lza_ab_io_f[48:42]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_15 = |lza_ab_io_f[48:41]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_17 = |lza_ab_io_f[48:40]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_19 = |lza_ab_io_f[48:39]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_21 = |lza_ab_io_f[48:38]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_23 = |lza_ab_io_f[48:37]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_25 = |lza_ab_io_f[48:36]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_27 = |lza_ab_io_f[48:35]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_29 = |lza_ab_io_f[48:34]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_31 = |lza_ab_io_f[48:33]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_33 = |lza_ab_io_f[48:32]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_35 = |lza_ab_io_f[48:31]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_37 = |lza_ab_io_f[48:30]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_39 = |lza_ab_io_f[48:29]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_41 = |lza_ab_io_f[48:28]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_43 = |lza_ab_io_f[48:27]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_45 = |lza_ab_io_f[48:26]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_47 = |lza_ab_io_f[48:25]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_49 = |lza_ab_io_f[48:24]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_51 = |lza_ab_io_f[48:23]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_53 = |lza_ab_io_f[48:22]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_55 = |lza_ab_io_f[48:21]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_57 = |lza_ab_io_f[48:20]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_59 = |lza_ab_io_f[48:19]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_61 = |lza_ab_io_f[48:18]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_63 = |lza_ab_io_f[48:17]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_65 = |lza_ab_io_f[48:16]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_67 = |lza_ab_io_f[48:15]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_69 = |lza_ab_io_f[48:14]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_71 = |lza_ab_io_f[48:13]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_73 = |lza_ab_io_f[48:12]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_75 = |lza_ab_io_f[48:11]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_77 = |lza_ab_io_f[48:10]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_79 = |lza_ab_io_f[48:9]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_81 = |lza_ab_io_f[48:8]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_83 = |lza_ab_io_f[48:7]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_85 = |lza_ab_io_f[48:6]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_87 = |lza_ab_io_f[48:5]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_89 = |lza_ab_io_f[48:4]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_91 = |lza_ab_io_f[48:3]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_93 = |lza_ab_io_f[48:2]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire  _exceed_lim_mask_T_95 = |lza_ab_io_f[48:1]; // @[src/main/scala/fudian/FADD.scala 139:61]
  wire [5:0] exceed_lim_mask_lo_lo_lo = {_exceed_lim_mask_T_85,_exceed_lim_mask_T_87,_exceed_lim_mask_T_89,
    _exceed_lim_mask_T_91,_exceed_lim_mask_T_93,_exceed_lim_mask_T_95}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [11:0] exceed_lim_mask_lo_lo = {_exceed_lim_mask_T_73,_exceed_lim_mask_T_75,_exceed_lim_mask_T_77,
    _exceed_lim_mask_T_79,_exceed_lim_mask_T_81,_exceed_lim_mask_T_83,exceed_lim_mask_lo_lo_lo}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [5:0] exceed_lim_mask_lo_hi_lo = {_exceed_lim_mask_T_61,_exceed_lim_mask_T_63,_exceed_lim_mask_T_65,
    _exceed_lim_mask_T_67,_exceed_lim_mask_T_69,_exceed_lim_mask_T_71}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [23:0] exceed_lim_mask_lo = {_exceed_lim_mask_T_49,_exceed_lim_mask_T_51,_exceed_lim_mask_T_53,
    _exceed_lim_mask_T_55,_exceed_lim_mask_T_57,_exceed_lim_mask_T_59,exceed_lim_mask_lo_hi_lo,exceed_lim_mask_lo_lo}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [5:0] exceed_lim_mask_hi_lo_lo = {_exceed_lim_mask_T_37,_exceed_lim_mask_T_39,_exceed_lim_mask_T_41,
    _exceed_lim_mask_T_43,_exceed_lim_mask_T_45,_exceed_lim_mask_T_47}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [11:0] exceed_lim_mask_hi_lo = {_exceed_lim_mask_T_25,_exceed_lim_mask_T_27,_exceed_lim_mask_T_29,
    _exceed_lim_mask_T_31,_exceed_lim_mask_T_33,_exceed_lim_mask_T_35,exceed_lim_mask_hi_lo_lo}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [5:0] exceed_lim_mask_hi_hi_lo = {_exceed_lim_mask_T_13,_exceed_lim_mask_T_15,_exceed_lim_mask_T_17,
    _exceed_lim_mask_T_19,_exceed_lim_mask_T_21,_exceed_lim_mask_T_23}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [48:0] exceed_lim_mask = {1'h0,_exceed_lim_mask_T_1,_exceed_lim_mask_T_3,_exceed_lim_mask_T_5,
    _exceed_lim_mask_T_7,_exceed_lim_mask_T_9,_exceed_lim_mask_T_11,exceed_lim_mask_hi_hi_lo,exceed_lim_mask_hi_lo,
    exceed_lim_mask_lo}; // @[src/main/scala/fudian/FADD.scala 137:28]
  wire [48:0] _exceed_lim_T = exceed_lim_mask & shift_lim_mask_raw; // @[src/main/scala/fudian/FADD.scala 142:41]
  wire  exceed_lim = need_shift_lim & ~(|_exceed_lim_T); // @[src/main/scala/fudian/FADD.scala 142:20]
  LZA lza_ab ( // @[src/main/scala/fudian/FADD.scala 109:22]
    .io_a(lza_ab_io_a),
    .io_b(lza_ab_io_b),
    .io_f(lza_ab_io_f)
  );
  CLZ_1 lzc_clz ( // @[src/main/scala/fudian/utils/CLZ.scala 22:21]
    .io_in(lzc_clz_io_in),
    .io_out(lzc_clz_io_out)
  );
  assign io_out_result_sign = a_lt_b ? io_in_b_sign : io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 166:27]
  assign io_out_result_exp = io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 168:20 170:14]
  assign io_out_sig_is_zero = lza_str_zero & ~sig_raw[0]; // @[src/main/scala/fudian/FADD.scala 173:38]
  assign io_out_a_lt_b = a_minus_b[49]; // @[src/main/scala/fudian/FADD.scala 107:30]
  assign io_out_lza_error = ~int_bit_predicted & ~exceed_lim; // @[src/main/scala/fudian/FADD.scala 147:38]
  assign io_out_int_bit = exceed_lim ? shift_lim_bit : int_bit_rshift_1 | int_bit_predicted; // @[src/main/scala/fudian/FADD.scala 145:8]
  assign io_out_sig_raw = a_minus_b[48:0]; // @[src/main/scala/fudian/FADD.scala 108:31]
  assign io_out_lzc = lzc_clz_io_out; // @[src/main/scala/fudian/FADD.scala 177:14]
  assign lza_ab_io_a = {io_in_a_sig,1'h0}; // @[src/main/scala/fudian/FADD.scala 102:18]
  assign lza_ab_io_b = ~b_sig; // @[src/main/scala/fudian/FADD.scala 104:16]
  assign lzc_clz_io_in = shift_lim_mask | lza_ab_io_f; // @[src/main/scala/fudian/FADD.scala 124:32]
endmodule
module FCMA_ADD_s1(
  input  [55:0] io_a, // @[src/main/scala/fudian/FADD.scala 185:14]
  input  [55:0] io_b, // @[src/main/scala/fudian/FADD.scala 185:14]
  input         io_b_inter_flags_isNaN, // @[src/main/scala/fudian/FADD.scala 185:14]
  input         io_b_inter_flags_isInf, // @[src/main/scala/fudian/FADD.scala 185:14]
  input         io_b_inter_flags_isInv, // @[src/main/scala/fudian/FADD.scala 185:14]
  input         io_b_inter_flags_overflow, // @[src/main/scala/fudian/FADD.scala 185:14]
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
  output [47:0] io_out_far_sig_a, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [51:0] io_out_far_sig_b, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_far_exp_a_vec_0, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_far_exp_a_vec_1, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [7:0]  io_out_far_exp_a_vec_2, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_sig_is_zero, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_lza_error, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_near_path_int_bit, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [48:0] io_out_near_path_sig_raw, // @[src/main/scala/fudian/FADD.scala 185:14]
  output [5:0]  io_out_near_path_lzc, // @[src/main/scala/fudian/FADD.scala 185:14]
  output        io_out_sel_far_path // @[src/main/scala/fudian/FADD.scala 185:14]
);
  wire  far_path_mods_0_io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [47:0] far_path_mods_0_io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [47:0] far_path_mods_0_io_in_b_sig; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_in_expDiff; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire  far_path_mods_0_io_in_effSub; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire  far_path_mods_0_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [47:0] far_path_mods_0_io_out_sig_a; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [51:0] far_path_mods_0_io_out_sig_b; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_out_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_out_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire [7:0] far_path_mods_0_io_out_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 239:26]
  wire  near_path_mods_0_io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_0_io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [47:0] near_path_mods_0_io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_in_b_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [47:0] near_path_mods_0_io_in_b_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_in_need_shift_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_0_io_out_result_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_a_lt_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_lza_error; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_0_io_out_int_bit; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [48:0] near_path_mods_0_io_out_sig_raw; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [5:0] near_path_mods_0_io_out_lzc; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_in_a_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_1_io_in_a_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [47:0] near_path_mods_1_io_in_a_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_in_b_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [47:0] near_path_mods_1_io_in_b_sig; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_in_need_shift_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_result_sign; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [7:0] near_path_mods_1_io_out_result_exp; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_a_lt_b; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_lza_error; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  near_path_mods_1_io_out_int_bit; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [48:0] near_path_mods_1_io_out_sig_raw; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire [5:0] near_path_mods_1_io_out_lzc; // @[src/main/scala/fudian/FADD.scala 263:27]
  wire  fp_a_sign = io_a[55]; // @[src/main/scala/fudian/package.scala 59:19]
  wire [7:0] fp_a_exp = io_a[54:47]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [46:0] fp_a_sig = io_a[46:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  fp_b_sign = io_b[55]; // @[src/main/scala/fudian/package.scala 59:19]
  wire [7:0] fp_b_exp = io_b[54:47]; // @[src/main/scala/fudian/package.scala 60:18]
  wire [46:0] fp_b_sig = io_b[46:0]; // @[src/main/scala/fudian/package.scala 61:18]
  wire  decode_a_expNotZero = |fp_a_exp; // @[src/main/scala/fudian/package.scala 32:28]
  wire  decode_a_expIsOnes = &fp_a_exp; // @[src/main/scala/fudian/package.scala 33:27]
  wire  decode_a_sigNotZero = |fp_a_sig; // @[src/main/scala/fudian/package.scala 34:28]
  wire  decode_a__expIsZero = ~decode_a_expNotZero; // @[src/main/scala/fudian/package.scala 37:27]
  wire  decode_a__sigIsZero = ~decode_a_sigNotZero; // @[src/main/scala/fudian/package.scala 40:27]
  wire  decode_a__isInf = decode_a_expIsOnes & decode_a__sigIsZero; // @[src/main/scala/fudian/package.scala 42:40]
  wire  decode_a__isNaN = decode_a_expIsOnes & decode_a_sigNotZero; // @[src/main/scala/fudian/package.scala 44:40]
  wire  decode_a__isSNaN = decode_a__isNaN & ~fp_a_sig[46]; // @[src/main/scala/fudian/package.scala 45:37]
  wire  decode_b_expNotZero = |fp_b_exp; // @[src/main/scala/fudian/package.scala 32:28]
  wire  decode_b_expIsOnes = &fp_b_exp; // @[src/main/scala/fudian/package.scala 33:27]
  wire  decode_b__expIsZero = ~decode_b_expNotZero; // @[src/main/scala/fudian/package.scala 37:27]
  wire [7:0] _GEN_0 = {{7'd0}, decode_a__expIsZero}; // @[src/main/scala/fudian/package.scala 83:27]
  wire [7:0] raw_a_exp = fp_a_exp | _GEN_0; // @[src/main/scala/fudian/package.scala 83:27]
  wire [47:0] raw_a_sig = {decode_a_expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire [7:0] _GEN_1 = {{7'd0}, decode_b__expIsZero}; // @[src/main/scala/fudian/package.scala 83:27]
  wire [7:0] raw_b_exp = fp_b_exp | _GEN_1; // @[src/main/scala/fudian/package.scala 83:27]
  wire [47:0] raw_b_sig = {decode_b_expNotZero,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  wire  eff_sub = fp_a_sign ^ fp_b_sign; // @[src/main/scala/fudian/FADD.scala 199:28]
  wire  special_path_hasNaN = decode_a__isNaN | io_b_inter_flags_isNaN; // @[src/main/scala/fudian/FADD.scala 210:44]
  wire  special_path_hasSNaN = decode_a__isSNaN | io_b_inter_flags_isInv; // @[src/main/scala/fudian/FADD.scala 211:46]
  wire  special_path_hasInf = decode_a__isInf | io_b_inter_flags_isInf; // @[src/main/scala/fudian/FADD.scala 212:44]
  wire  special_path_inf_iv = decode_a__isInf & io_b_inter_flags_isInf & eff_sub; // @[src/main/scala/fudian/FADD.scala 213:55]
  wire [8:0] _exp_diff_a_b_T = {1'h0,raw_a_exp}; // @[src/main/scala/fudian/FADD.scala 218:25]
  wire [8:0] _exp_diff_a_b_T_1 = {1'h0,raw_b_exp}; // @[src/main/scala/fudian/FADD.scala 218:52]
  wire [8:0] exp_diff_a_b = _exp_diff_a_b_T - _exp_diff_a_b_T_1; // @[src/main/scala/fudian/FADD.scala 218:47]
  wire [8:0] exp_diff_b_a = _exp_diff_a_b_T_1 - _exp_diff_a_b_T; // @[src/main/scala/fudian/FADD.scala 219:47]
  wire  need_swap = exp_diff_a_b[8] | io_b_inter_flags_overflow; // @[src/main/scala/fudian/FADD.scala 221:47]
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
  assign io_out_far_path_mul_of = io_b_inter_flags_overflow | decode_b_expIsOnes & _sel_far_path_T; // @[src/main/scala/fudian/FADD.scala 283:46]
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
  assign io_out_sel_far_path = ~eff_sub | ea_minus_eb > 8'h1 | io_b_inter_flags_overflow; // @[src/main/scala/fudian/FADD.scala 224:52]
  assign far_path_mods_0_io_in_a_sign = ~need_swap ? fp_a_sign : fp_b_sign; // @[src/main/scala/fudian/FADD.scala 232:10]
  assign far_path_mods_0_io_in_a_exp = ~need_swap ? raw_a_exp : raw_b_exp; // @[src/main/scala/fudian/FADD.scala 232:10]
  assign far_path_mods_0_io_in_a_sig = ~need_swap ? raw_a_sig : raw_b_sig; // @[src/main/scala/fudian/FADD.scala 232:10]
  assign far_path_mods_0_io_in_b_sig = _T ? raw_b_sig : raw_a_sig; // @[src/main/scala/fudian/FADD.scala 233:10]
  assign far_path_mods_0_io_in_expDiff = _T_5[7:0]; // @[src/main/scala/fudian/FADD.scala 242:28]
  assign far_path_mods_0_io_in_effSub = fp_a_sign ^ fp_b_sign; // @[src/main/scala/fudian/FADD.scala 199:28]
  assign near_path_mods_0_io_in_a_sign = io_a[55]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_0_io_in_a_exp = fp_a_exp | _GEN_0; // @[src/main/scala/fudian/package.scala 83:27]
  assign near_path_mods_0_io_in_a_sig = {decode_a_expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_0_io_in_b_sign = io_b[55]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_0_io_in_b_sig = {decode_b_expNotZero,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_0_io_in_need_shift_b = raw_a_exp[1:0] != raw_b_exp[1:0]; // @[src/main/scala/fudian/FADD.scala 256:43]
  assign near_path_mods_1_io_in_a_sign = io_b[55]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_1_io_in_a_exp = fp_b_exp | _GEN_1; // @[src/main/scala/fudian/package.scala 83:27]
  assign near_path_mods_1_io_in_a_sig = {decode_b_expNotZero,fp_b_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_1_io_in_b_sign = io_a[55]; // @[src/main/scala/fudian/package.scala 59:19]
  assign near_path_mods_1_io_in_b_sig = {decode_a_expNotZero,fp_a_sig}; // @[src/main/scala/fudian/package.scala 84:23]
  assign near_path_mods_1_io_in_need_shift_b = raw_a_exp[1:0] != raw_b_exp[1:0]; // @[src/main/scala/fudian/FADD.scala 256:43]
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
  input  [47:0] io_in_far_sig_a, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [51:0] io_in_far_sig_b, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_far_exp_a_vec_0, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_far_exp_a_vec_1, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [7:0]  io_in_far_exp_a_vec_2, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_sig_is_zero, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_lza_error, // @[src/main/scala/fudian/FADD.scala 336:14]
  input         io_in_near_path_int_bit, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [48:0] io_in_near_path_sig_raw, // @[src/main/scala/fudian/FADD.scala 336:14]
  input  [5:0]  io_in_near_path_lzc, // @[src/main/scala/fudian/FADD.scala 336:14]
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
  wire [51:0] adder_in_sig_a = {1'h0,io_in_far_sig_a,3'h0}; // @[src/main/scala/fudian/FADD.scala 362:27]
  wire [51:0] adder_result = adder_in_sig_a + io_in_far_sig_b; // @[src/main/scala/fudian/FADD.scala 363:37]
  wire  cout = adder_result[51]; // @[src/main/scala/fudian/FADD.scala 365:31]
  wire  keep = adder_result[51:50] == 2'h1; // @[src/main/scala/fudian/FADD.scala 366:35]
  wire  cancellation = adder_result[51:50] == 2'h0; // @[src/main/scala/fudian/FADD.scala 367:43]
  wire  _far_path_res_sig_T = keep | io_in_small_add; // @[src/main/scala/fudian/FADD.scala 370:20]
  wire  _far_path_res_sig_T_2 = cancellation & ~io_in_small_add; // @[src/main/scala/fudian/FADD.scala 370:47]
  wire [26:0] _far_path_res_sig_T_6 = {adder_result[51:26],|adder_result[25:0]}; // @[src/main/scala/fudian/FADD.scala 372:36]
  wire [26:0] _far_path_res_sig_T_11 = {adder_result[50:25],|adder_result[24:0]}; // @[src/main/scala/fudian/FADD.scala 373:44]
  wire [26:0] _far_path_res_sig_T_16 = {adder_result[49:24],|adder_result[23:0]}; // @[src/main/scala/fudian/FADD.scala 374:44]
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
  wire [7:0] _GEN_1 = {{2'd0}, io_in_near_path_lzc}; // @[src/main/scala/fudian/FADD.scala 428:40]
  wire [7:0] exp_s1 = io_in_near_path_out_exp - _GEN_1; // @[src/main/scala/fudian/FADD.scala 428:40]
  wire [7:0] _GEN_2 = {{7'd0}, io_in_near_path_lza_error}; // @[src/main/scala/fudian/FADD.scala 429:23]
  wire [7:0] exp_s2 = exp_s1 - _GEN_2; // @[src/main/scala/fudian/FADD.scala 429:23]
  wire [7:0] near_path_res_exp = io_in_near_path_int_bit ? exp_s2 : 8'h0; // @[src/main/scala/fudian/FADD.scala 430:27]
  wire  near_path_is_zero = near_path_res_exp == 8'h0 & io_in_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 424:49]
  wire [111:0] _GEN_4 = {{63'd0}, io_in_near_path_sig_raw}; // @[src/main/scala/fudian/FADD.scala 432:41]
  wire [111:0] _sig_s1_T = _GEN_4 << io_in_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 432:41]
  wire [48:0] sig_s1 = _sig_s1_T[48:0]; // @[src/main/scala/fudian/FADD.scala 432:48]
  wire [48:0] _sig_s2_T_1 = {sig_s1[47:0],1'h0}; // @[src/main/scala/fudian/FADD.scala 433:50]
  wire [48:0] sig_s2 = io_in_near_path_lza_error ? _sig_s2_T_1 : sig_s1; // @[src/main/scala/fudian/FADD.scala 433:19]
  wire [26:0] near_path_sig = {sig_s2[48:23],|sig_s2[22:0]}; // @[src/main/scala/fudian/FADD.scala 442:57]
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
  assign near_path_tininess_rounder_io_in_sig = {sig_s2[48:23],|sig_s2[22:0]}; // @[src/main/scala/fudian/FADD.scala 442:57]
  assign near_path_tininess_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/FADD.scala 447:36]
  assign near_path_rounder_io_in = near_path_sig[25:3]; // @[src/main/scala/fudian/RoundingUnit.scala 45:33]
  assign near_path_rounder_io_roundIn = near_path_sig[2]; // @[src/main/scala/fudian/RoundingUnit.scala 46:50]
  assign near_path_rounder_io_stickyIn = |near_path_sig[1:0]; // @[src/main/scala/fudian/RoundingUnit.scala 47:51]
  assign near_path_rounder_io_signIn = io_in_near_path_out_sign; // @[src/main/scala/fudian/FADD.scala 419:{31,31}]
  assign near_path_rounder_io_rm = io_in_rm; // @[src/main/scala/fudian/RoundingUnit.scala 48:19]
endmodule
module FCMA_ADD(
  input  [55:0] io_a, // @[src/main/scala/fudian/FADD.scala 725:14]
  input  [55:0] io_b, // @[src/main/scala/fudian/FADD.scala 725:14]
  input         io_b_inter_flags_isNaN, // @[src/main/scala/fudian/FADD.scala 725:14]
  input         io_b_inter_flags_isInf, // @[src/main/scala/fudian/FADD.scala 725:14]
  input         io_b_inter_flags_isInv, // @[src/main/scala/fudian/FADD.scala 725:14]
  input         io_b_inter_flags_overflow, // @[src/main/scala/fudian/FADD.scala 725:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FADD.scala 725:14]
  output [31:0] io_result, // @[src/main/scala/fudian/FADD.scala 725:14]
  output [4:0]  io_fflags // @[src/main/scala/fudian/FADD.scala 725:14]
);
  wire [55:0] fadd_s1_io_a; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [55:0] fadd_s1_io_b; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_b_inter_flags_isNaN; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_b_inter_flags_isInf; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_b_inter_flags_isInv; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_b_inter_flags_overflow; // @[src/main/scala/fudian/FADD.scala 734:23]
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
  wire [47:0] fadd_s1_io_out_far_sig_a; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [51:0] fadd_s1_io_out_far_sig_b; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_far_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_far_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [7:0] fadd_s1_io_out_far_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_lza_error; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire  fadd_s1_io_out_near_path_int_bit; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [48:0] fadd_s1_io_out_near_path_sig_raw; // @[src/main/scala/fudian/FADD.scala 734:23]
  wire [5:0] fadd_s1_io_out_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 734:23]
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
  wire [47:0] fadd_s2_io_in_far_sig_a; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [51:0] fadd_s2_io_in_far_sig_b; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_far_exp_a_vec_0; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_far_exp_a_vec_1; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [7:0] fadd_s2_io_in_far_exp_a_vec_2; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_sig_is_zero; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_lza_error; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_near_path_int_bit; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [48:0] fadd_s2_io_in_near_path_sig_raw; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [5:0] fadd_s2_io_in_near_path_lzc; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire  fadd_s2_io_in_sel_far_path; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [31:0] fadd_s2_io_result; // @[src/main/scala/fudian/FADD.scala 735:23]
  wire [4:0] fadd_s2_io_fflags; // @[src/main/scala/fudian/FADD.scala 735:23]
  FCMA_ADD_s1 fadd_s1 ( // @[src/main/scala/fudian/FADD.scala 734:23]
    .io_a(fadd_s1_io_a),
    .io_b(fadd_s1_io_b),
    .io_b_inter_flags_isNaN(fadd_s1_io_b_inter_flags_isNaN),
    .io_b_inter_flags_isInf(fadd_s1_io_b_inter_flags_isInf),
    .io_b_inter_flags_isInv(fadd_s1_io_b_inter_flags_isInv),
    .io_b_inter_flags_overflow(fadd_s1_io_b_inter_flags_overflow),
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
  assign fadd_s1_io_b_inter_flags_isNaN = io_b_inter_flags_isNaN; // @[src/main/scala/fudian/FADD.scala 740:28]
  assign fadd_s1_io_b_inter_flags_isInf = io_b_inter_flags_isInf; // @[src/main/scala/fudian/FADD.scala 740:28]
  assign fadd_s1_io_b_inter_flags_isInv = io_b_inter_flags_isInv; // @[src/main/scala/fudian/FADD.scala 740:28]
  assign fadd_s1_io_b_inter_flags_overflow = io_b_inter_flags_overflow; // @[src/main/scala/fudian/FADD.scala 740:28]
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
module FCMA(
  input         clock,
  input         reset,
  input  [31:0] io_a, // @[src/main/scala/fudian/FCMA.scala 9:14]
  input  [31:0] io_b, // @[src/main/scala/fudian/FCMA.scala 9:14]
  input  [31:0] io_c, // @[src/main/scala/fudian/FCMA.scala 9:14]
  input  [2:0]  io_rm, // @[src/main/scala/fudian/FCMA.scala 9:14]
  output [31:0] io_result, // @[src/main/scala/fudian/FCMA.scala 9:14]
  output [4:0]  io_fflags // @[src/main/scala/fudian/FCMA.scala 9:14]
);
  wire [31:0] fmul_io_a; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire [31:0] fmul_io_b; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire [2:0] fmul_io_rm; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire  fmul_io_to_fadd_fp_prod_sign; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire [7:0] fmul_io_to_fadd_fp_prod_exp; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire [46:0] fmul_io_to_fadd_fp_prod_sig; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire  fmul_io_to_fadd_inter_flags_isNaN; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire  fmul_io_to_fadd_inter_flags_isInf; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire  fmul_io_to_fadd_inter_flags_isInv; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire  fmul_io_to_fadd_inter_flags_overflow; // @[src/main/scala/fudian/FCMA.scala 16:20]
  wire [55:0] fadd_io_a; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire [55:0] fadd_io_b; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire  fadd_io_b_inter_flags_isNaN; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire  fadd_io_b_inter_flags_isInf; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire  fadd_io_b_inter_flags_isInv; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire  fadd_io_b_inter_flags_overflow; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire [2:0] fadd_io_rm; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire [31:0] fadd_io_result; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire [4:0] fadd_io_fflags; // @[src/main/scala/fudian/FCMA.scala 17:20]
  wire [8:0] fadd_io_b_hi = {fmul_io_to_fadd_fp_prod_sign,fmul_io_to_fadd_fp_prod_exp}; // @[src/main/scala/fudian/FCMA.scala 25:36]
  FMUL fmul ( // @[src/main/scala/fudian/FCMA.scala 16:20]
    .io_a(fmul_io_a),
    .io_b(fmul_io_b),
    .io_rm(fmul_io_rm),
    .io_to_fadd_fp_prod_sign(fmul_io_to_fadd_fp_prod_sign),
    .io_to_fadd_fp_prod_exp(fmul_io_to_fadd_fp_prod_exp),
    .io_to_fadd_fp_prod_sig(fmul_io_to_fadd_fp_prod_sig),
    .io_to_fadd_inter_flags_isNaN(fmul_io_to_fadd_inter_flags_isNaN),
    .io_to_fadd_inter_flags_isInf(fmul_io_to_fadd_inter_flags_isInf),
    .io_to_fadd_inter_flags_isInv(fmul_io_to_fadd_inter_flags_isInv),
    .io_to_fadd_inter_flags_overflow(fmul_io_to_fadd_inter_flags_overflow)
  );
  FCMA_ADD fadd ( // @[src/main/scala/fudian/FCMA.scala 17:20]
    .io_a(fadd_io_a),
    .io_b(fadd_io_b),
    .io_b_inter_flags_isNaN(fadd_io_b_inter_flags_isNaN),
    .io_b_inter_flags_isInf(fadd_io_b_inter_flags_isInf),
    .io_b_inter_flags_isInv(fadd_io_b_inter_flags_isInv),
    .io_b_inter_flags_overflow(fadd_io_b_inter_flags_overflow),
    .io_rm(fadd_io_rm),
    .io_result(fadd_io_result),
    .io_fflags(fadd_io_fflags)
  );
  assign io_result = fadd_io_result; // @[src/main/scala/fudian/FCMA.scala 30:13]
  assign io_fflags = fadd_io_fflags; // @[src/main/scala/fudian/FCMA.scala 31:13]
  assign fmul_io_a = io_a; // @[src/main/scala/fudian/FCMA.scala 19:13]
  assign fmul_io_b = io_b; // @[src/main/scala/fudian/FCMA.scala 20:13]
  assign fmul_io_rm = io_rm; // @[src/main/scala/fudian/FCMA.scala 21:14]
  assign fadd_io_a = {io_c,24'h0}; // @[src/main/scala/fudian/FCMA.scala 24:19]
  assign fadd_io_b = {fadd_io_b_hi,fmul_io_to_fadd_fp_prod_sig}; // @[src/main/scala/fudian/FCMA.scala 25:36]
  assign fadd_io_b_inter_flags_isNaN = fmul_io_to_fadd_inter_flags_isNaN; // @[src/main/scala/fudian/FCMA.scala 27:25]
  assign fadd_io_b_inter_flags_isInf = fmul_io_to_fadd_inter_flags_isInf; // @[src/main/scala/fudian/FCMA.scala 27:25]
  assign fadd_io_b_inter_flags_isInv = fmul_io_to_fadd_inter_flags_isInv; // @[src/main/scala/fudian/FCMA.scala 27:25]
  assign fadd_io_b_inter_flags_overflow = fmul_io_to_fadd_inter_flags_overflow; // @[src/main/scala/fudian/FCMA.scala 27:25]
  assign fadd_io_rm = io_rm; // @[src/main/scala/fudian/FCMA.scala 28:14]
endmodule
