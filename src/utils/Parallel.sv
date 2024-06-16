
module ParallelAdder #(
    parameter WIDTH=1,
    parameter DEPTH=4
)(
    input logic [DEPTH-1: 0][WIDTH-1: 0] data,
    output logic [WIDTH+$clog2(DEPTH)-1: 0] out
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

module ParallelOR #(
    parameter WIDTH=1,
    parameter DEPTH=4
)(
    input logic [DEPTH-1: 0][WIDTH-1: 0] data,
    output logic [WIDTH-1: 0] out
);
generate
    if(DEPTH == 1)begin
        assign out = data;
    end
    else if(DEPTH == 2)begin
        assign out = data[0] | data[1];
    end
    else begin
        logic [WIDTH-1: 0] out1, out2;
        ParallelOR #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH/2)
        ) or1(
            data[DEPTH/2-1: 0],
            out1
        );
        ParallelOR #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH-DEPTH/2)
        ) or2 (
            data[DEPTH-1: DEPTH/2],
            out2
        );
        assign out = out1 | out2;
    end
endgenerate
endmodule

module ParallelAND #(
    parameter WIDTH=1,
    parameter DEPTH=4
)(
    input logic [DEPTH-1: 0][WIDTH-1: 0] data,
    output logic [WIDTH-1: 0] out
);
generate
    if(DEPTH == 1)begin
        assign out = data;
    end
    else if(DEPTH == 2)begin
        assign out = data[0] & data[1];
    end
    else begin
        logic [WIDTH-1: 0] out1, out2;
        ParallelAND #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH/2)
        ) or1(
            data[DEPTH/2-1: 0],
            out1
        );
        ParallelAND #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH-DEPTH/2)
        ) or2 (
            data[DEPTH-1: DEPTH/2],
            out2
        );
        assign out = out1 & out2;
    end
endgenerate
endmodule

module ParallelEQ #(
	parameter RADIX = 2,
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
    input logic [WIDTH-1: 0] origin,
    input logic [RADIX-1: 0] cmp_en,
	input logic [RADIX-1: 0][WIDTH-1: 0] cmp,
	input logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_i,
    output logic [RADIX-1: 0] eq,
	output logic [DATA_WIDTH-1: 0] data_o
);
generate
	if(RADIX == 1)begin
        assign eq = origin == cmp && cmp_en;
		assign data_o = data_i;
	end
	else if(RADIX == 2)begin
        logic eq0, eq1;
        assign eq[0] = cmp[0] == origin && cmp_en[0];
        assign eq[1] = cmp[1] == origin && cmp_en[1];
		assign data_o = ({WIDTH{eq[0]}} & data_i[0]) | ({WIDTH{eq[1]}} & data_i[1]);
	end
	else begin
		logic [DATA_WIDTH-1: 0] data1, data2;
        logic eq0, eq1;
		ParallelEQ #(
			.RADIX(RADIX/2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select1 (
            .origin(origin),
            .cmp_en(cmp_en[RADIX/2-1: 0]),
			.cmp(cmp[RADIX/2-1: 0]),
			.data_i(data_i[RADIX/2-1: 0]),
            .eq(eq[RADIX/2-1: 0]),
			.data_o(data1)
		);
		ParallelEQ #(
			.RADIX(RADIX-RADIX/2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select2 (
            .origin(origin),
            .cmp_en(cmp_en[RADIX-1: RADIX/2]),
			.cmp(cmp[RADIX-1: RADIX/2]),
			.data_i(data_i[RADIX-1: RADIX/2]),
            .eq(eq[RADIX-1: RADIX/2]),
			.data_o(data2)
		);
        assign eq0 = |eq[RADIX/2-1: 0];
        assign eq1 = |eq[RADIX-1: RADIX/2];
		assign data_o = ({WIDTH{eq0}} & data1) | ({WIDTH{eq1}} & data2);
	end
endgenerate
endmodule