`include "../src/defines/defines.svh"

// sv2v --write=build/selector_tb.v -I=src/defines -I=build --top=selector_tb testbench/selector_tb.sv src/core/backend/issue/Selector.sv src/utils/Parallel.sv
// iverilog -g2012 build/selector_tb.v -s selector_tb -o build/sim.out
// vvp -n build/sim.out
module selector_tb();
    logic clk, rst;
    logic [1: 0] en;
    logic [1: 0][3: 0] idx;
    logic [3: 0] ready, select;

    DirectionSelector #(4, 2) selector(.*);
    always #5 clk = ~clk;
    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, selector_tb);
    end

    initial begin
        clk = 1;
        rst = 1;
        en = 0;
        idx = 0;
        ready = 0;
        #10;
        rst = 0;
        en = 2'b11;
        idx[0] = 4'b0001;
        idx[1] = 4'b0010;
        ready = 4'b0011;
        #11;
        if(select != 4'b0001)begin
            $finish;
        end
        idx[0] = 4'b0100;
        idx[1] = 4'b1000;
        ready = 4'b1110;
        #10;
        if(select != 4'b0010)begin
            $finish;
        end
        ready = 4'b1100;
        #10;
        if(select != 4'b0100)begin
            $finish;
        end
        ready = 4'b1000;
        #10;
        if(select != 4'b1000)begin
            $finish;
        end
        $display("tests passed");
        $finish;
    end
endmodule