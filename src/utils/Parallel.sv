
module ParallelAdder #(
    parameter WIDTH=1,
    parameter DEPTH=4
)(
    logic [DEPTH-1: 0][WIDTH-1: 0] data,
    logic [WIDTH+$clog2(DEPTH)-1: 0] out
);
generate
    if(DEPTH == 1)begin
        assign out = data;
    end
    else if(DEPTH == 2)begin
        assign out = data[0] + data[1];
    end
    else if (DEPTH == 3)begin
        logic [WIDTH: 0] tmp;
        assign tmp = data[1] + data[2];
        assign out = data[0] + tmp;
    end
    else begin
        logic [WIDTH+$clog2(DEPTH)-2: 0] out1, out2;
        ParallelAdder #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH/2)
        ) adder1(
            data[DEPTH/2-1: 0],
            out1
        );
        ParallelAdder #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH-DEPTH/2)
        ) adder2(
            data[DEPTH-1: DEPTH/2],
            out2
        );
        assign out = out1 + out2;
    end
endgenerate
endmodule