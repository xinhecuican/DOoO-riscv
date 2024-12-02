`include "../src/defines/defines.svh"

// sv2v --write=build/div_tb.v -I=src/defines -I=build --top=div_tb testbench/div_tb.sv src/core/backend/execute/Div.sv src/utils/lzc.sv src/utils/utils.sv src/utils/UtilsImpl.sv
// iverilog -g2012 build/div_tb.v -s div_tb -o build/sim.out
// vvp -n build/sim.out
module div_tb();
    logic clk, rst;
    logic en;
    logic `N(`MULTOP_WIDTH) multop;
    logic `N(`XLEN) rs1_data;
    logic `N(`XLEN) rs2_data;
    ExStatusBundle status_i;
    WBData wbData;
    logic wakeup_en, wakeup_we;
    logic `N(`PREG_WIDTH) wakeup_rd;
    logic ready;
    logic div_end;
    BackendCtrl backendCtrl;

    DivUnit div(.*);

    always #5 clk = ~clk;
    initial begin
        $dumpfile("build/tb.vcd");
        $dumpvars(0, div_tb);
    end

    initial begin
        clk = 1;
        rs1_data = 32'h14f57a;
        rs2_data = 32'h3e8;
        rst = 1'b1;
        en = 0;
        multop = `MULT_DIVU;
        status_i = 0;
        backendCtrl = 0;
        #10;
        rst = 0;
        en = 1'b1;
        #10;
        en = 1'b0;
        if(wbData.en)begin
            if(wbData.res != (rs1_data / rs2_data))begin
                $display("error");
                $finish;
            end
            else begin
                $display("pass");
                $finish;
            end
        end
        #300;
        $finish;
    end
endmodule