
// sv2v --write=build/CompressHist_tb.v -I=src/defines -I=build --top=CompressHist_tb testbench/CompressHist_tb.sv src/core/frontend/HistoryControl.sv
// iverilog -g2012 build/CompressHist_tb.v -s CompressHist_tb -o build/sim.out
// vvp -n build/sim.out
module CompressHist_tb();
    logic [10: 0] comp_hist, comp_hist_o;
    logic [31: 0] hist;
    logic [1: 0] reverse_dir;
    logic [4: 0] pos, reverse_pos0, reverse_pos1;

    CompressHistory #(
        11, 8, 2
    ) compress (
        comp_hist,
        2'b01,
        hist[pos],
        reverse_dir,
        comp_hist_o
    );
    assign reverse_pos0 = pos - 8;
    assign reverse_pos1 = pos - 7;
    assign reverse_dir[0] = hist[reverse_pos0];
    assign reverse_dir[1] = hist[reverse_pos1];

    initial begin
        $dumpfile("build/tb.vcd");
        $dumpvars(0, CompressHist_tb);
    end

    initial begin
        comp_hist = 11'h747;
        hist = 32'h673;
        pos = 0;
        for(int i=0; i<8; i++)begin
            #10;
            pos = pos + 1;
            comp_hist = comp_hist_o;
        end
        #10;
        $finish;
    end
endmodule