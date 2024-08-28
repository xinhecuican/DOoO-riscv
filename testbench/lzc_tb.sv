
module lzc_tb();

    logic [5: 0] in;
    logic [2: 0] cnt;
    logic empty;

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, lzc_tb);
    end

    initial begin
        in = 0;
        #20;
        in = 6'b001000;
        #10;
        $finish;
    end

    lzc #(
        .WIDTH(6)
    ) lzc_inst(
        .in_i(in),
        .cnt_o(cnt),
        .empty_o(empty)
    );
endmodule