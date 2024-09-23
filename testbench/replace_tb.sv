`include "../src/defines/defines.svh"

module replace_tb;

    parameter WAYS = 4;
    parameter NUM_RANDOM_ACCESS = 10000;  // Number of random accesses
    parameter STRIDE = 1;

    logic clk;
    logic reset;
    logic [WAYS-1:0] access;
    logic [WAYS-1:0] replace;

    int replace_count[WAYS];  // Array to count replacements per way
    ReplaceIO #(4, WAYS) replace_io();
    // Instantiate the PLRU module
    PLRU #(4, WAYS) uut (
        .clk(clk),
        .rst(reset),
        .replace_io
    );
    assign replace_io.hit_way = access;
    assign replace = replace_io.miss_way;

    // Clock generation
    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, replace_tb);
    end

    // Utility task for statistics
    task print_statistics;
        int max_replaced, min_replaced, total_replaced;
        real mean_replaced, std_dev;
        real sum_square_diff;

        begin
            max_replaced = replace_count[0];
            min_replaced = replace_count[0];
            total_replaced = 0;

            // Calculate max, min, and total replaced
            for (int i = 0; i < WAYS; i++) begin
                if (replace_count[i] > max_replaced)
                    max_replaced = replace_count[i];
                if (replace_count[i] < min_replaced)
                    min_replaced = replace_count[i];
                total_replaced += replace_count[i];
            end

            mean_replaced = total_replaced / WAYS;

            // Calculate standard deviation
            sum_square_diff = 0;
            for (int i = 0; i < WAYS; i++) begin
                sum_square_diff += (replace_count[i] - mean_replaced) ** 2;
            end
            std_dev = $sqrt(sum_square_diff / WAYS);

            // Display statistics
            $display("Replacement Statistics:");
            $display("Max Replaced = %0d", max_replaced);
            $display("Min Replaced = %0d", min_replaced);
            $display("Mean Replaced = %0.2f", mean_replaced);
            $display("Standard Deviation = %0.2f", std_dev);
        end
    endtask

    // Task to run different access patterns
    task run_access_patterns;
        begin
            // Sequential Access Pattern
            $display("Sequential Access Pattern:");
            for (int i = 0; i < WAYS * 2; i++) begin
                access = 1 << (i % WAYS);
                #10;
                for (int j = 0; j < WAYS; j++)
                    if (replace[j]) replace_count[j]++;
            end

            // Reverse Sequential Access Pattern
            $display("Reverse Sequential Access Pattern:");
            for (int i = WAYS * 2 - 1; i >= 0; i--) begin
                access = 1 << (i % WAYS);
                #10;
                for (int j = 0; j < WAYS; j++)
                    if (replace[j]) replace_count[j]++;
            end

            // Locality Access Pattern
            $display("Locality Access Pattern:");
            for (int i = 0; i < WAYS * 2; i++) begin
                access = 1 << $urandom_range(0, WAYS / 2 - 1);
                #10;
                for (int j = 0; j < WAYS; j++)
                    if (replace[j]) replace_count[j]++;
            end

            // Stride Access Pattern
            $display("Stride Access Pattern:");
            for (int i = 0; i < WAYS * 2; i++) begin
                access = 1 << ((i * STRIDE) % WAYS);
                #10;
                for (int j = 0; j < WAYS; j++)
                    if (replace[j]) replace_count[j]++;
            end

            // Random Access Pattern
            $display("Random Access Pattern:");
            for (int i = 0; i < NUM_RANDOM_ACCESS; i++) begin
                access = 1 << $urandom_range(0, WAYS-1);
                #10;
                for (int j = 0; j < WAYS; j++)
                    if (replace[j]) replace_count[j]++;
            end
        end
    endtask

    // Testbench logic
    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;
        access = 0;

        // Reset the replacement counters
        for (int i = 0; i < WAYS; i++) begin
            replace_count[i] = 0;
        end

        // Apply reset
        #10 reset = 0;
        replace_io.hit_en = 1;
        replace_io.hit_index = 0;
        replace_io.miss_index = 0;

        // Run various access patterns
        run_access_patterns();

        // Print statistics after running all patterns
        print_statistics();

        // Finish simulation
        #10 $stop;
    end

endmodule
