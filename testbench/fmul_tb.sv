`include "../src/defines/fp_defines.svh"
`include "../src/defines/defines.svh"

// sv2v --write=build/fmul_tb.v -I=src/defines -I=build --top=fmul_tb testbench/fmul_tb.sv src/core/backend/execute/FMul.sv src/core/backend/execute/FMisc.sv src/core/backend/execute/Mult.sv testbench/FMUL.v src/utils/lzc.sv
// iverilog -g2012 build/fmul_tb.v -s fmul_tb -o build/sim.out
// vvp -n build/sim.out
module fmul_tb();
    int stimulus_a[1000];
    int stimulus_b[1000];
    int corner_values[6];
    int perm_idx;
    int count = 0;
    logic clk, rst;
    roundmode_e round_mode;
    logic [31: 0] rs1_data, rs2_data, res_dut, res_ref;
    FFlags flag_dut, flag_ref;

    always #5 clk = ~clk;

    FMul #(FP32) fmul_dut (
        .clk,
        .rst,
        .round_mode,
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .fltop(5'b0),
        .mulInfo(),
        .res(res_dut),
        .status(flag_dut)
    );

    FMUL fmul_ref (
        .clock(clk),
        .reset(rst),
        .io_a(rs1_data),
        .io_b(rs2_data),
        .io_rm(round_mode),
        .io_result(res_ref),
        .io_fflags(flag_ref),
        .io_to_fadd_fp_prod_sign(),
        .io_to_fadd_fp_prod_exp(),
        .io_to_fadd_fp_prod_sig(),
        .io_to_fadd_inter_flags_isNaN(),
        .io_to_fadd_inter_flags_isInf(),
        .io_to_fadd_inter_flags_isInv(),
        .io_to_fadd_inter_flags_overflow(),
        .io_to_fadd_rm()
    );

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, fmul_tb);
    end

    // task to run the test and print the count
    task run_test(input int a[1000], input int b[1000], input int size);
        int count = 0;
        for (int i = 0; i < size; i++) begin
            rs1_data = a[i];
            rs2_data = b[i];
            #30;
            if(res_dut != res_ref || flag_dut != flag_ref)begin
                $display("Test with A: %h, B: %h error.\nDut: %h %h\nRef: %h %h", a[i], b[i], res_dut, flag_dut, res_ref, flag_ref);
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
            stimulus_a[i] = $random;
            stimulus_b[i] = $random;
        end
        $display("any * any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random & 32'h807fffff;
            stimulus_b[i] = $random & 32'h807fffff;
        end
        $display("denormal * denormal");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random & 32'h807fffff;
            stimulus_b[i] = $random;
        end
        $display("denormal * any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random | 32'h7f800000;
            stimulus_b[i] = $random;
        end
        $display("ov * any");
        run_test(stimulus_a, stimulus_b, 1000);

        // Edge Cases
        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h80000000;
            stimulus_b[i] = $random;
        end
        $display("edge cases");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'h80000000;
        end
        $display("-0 * any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'h00000000;
        end
        $display("any * 0");
        run_test(stimulus_a, stimulus_b, 1000);

        // Special floating point cases
        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h7f800000; // +Inf
            stimulus_b[i] = $random;
        end
        $display("+Inf * any");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = $random;
            stimulus_b[i] = 32'hff800000;
        end
        $display("any * -Inf");
        run_test(stimulus_a, stimulus_b, 1000);

        for (int i = 0; i < 1000; i++) begin
            stimulus_a[i] = 32'h7fc00000; // NaN
            stimulus_b[i] = $random;
        end
        $display("NaN * any");
        run_test(stimulus_a, stimulus_b, 1000);

        $display("All tests passed.");
        $finish;
    end
endmodule