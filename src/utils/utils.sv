
module Decoder1(
	input logic [0: 0] A,
	output logic [1: 0] Y
);
	assign Y[1] = A;
	assign Y[0] = ~A;
endmodule

module Decoder2(
	input logic [1: 0] A,
	output logic [3: 0] Y
);
	wire nA0, nA1;
	not n2(nA0, A[0]), n3(nA1, A[1]);
	and nd1(Y[0], nA0, nA1), nd2(Y[1], A[0], nA1),
		nd3(Y[2], nA0, A[1]), nd4(Y[3], A[1], A[0]);
endmodule

module Decoder3(
	input logic [2: 0] in,
	output logic [7: 0] out
);
	always_comb begin
		case(in)
		3'b000: out=8'h01;
		3'b001: out=8'h02;
		3'b010: out=8'h04;
		3'b011: out=8'h08;
		3'b100: out=8'h10;
		3'b101: out=8'h20;
		3'b110: out=8'h40;
		3'b111: out=8'h80;
		endcase
	end
endmodule

module Decoder4(
	input logic [3: 0] in,
	output logic [15: 0] out
);
	always_comb begin
		case(in)
		4'h0: out=16'h0001;
		4'h1: out=16'h0002;
		4'h2: out=16'h0004;
		4'h3: out=16'h0008;
		4'h4: out=16'h0010;
		4'h5: out=16'h0020;
		4'h6: out=16'h0040;
		4'h7: out=16'h0080;
		4'h8: out=16'h0100;
		4'h9: out=16'h0200;
		4'ha: out=16'h0400;
		4'hb: out=16'h0800;
		4'hc: out=16'h1000;
		4'hd: out=16'h2000;
		4'he: out=16'h4000;
		4'hf: out=16'h8000;
		endcase
	end
endmodule

module Decoder5(
	input logic [4: 0] in,
	output logic [31: 0] out
);
	logic [3: 0] de1;
	logic [7: 0] out1;
	Decoder2 d1(in[4: 3], de1);
	Decoder3 d2(in[2: 0], out1);
	assign out = {{8{de1[3]}} & out1, {8{de1[2]}} & out1, {8{de1[1]}} & out1, {8{de1[0]}} & out1};
endmodule

module Decoder6(
	input logic [5: 0] in,
	output logic [63: 0] out
);
	logic [3: 0] de1;
	logic [15: 0] out1;
	Decoder2 d1(in[5: 4], de1);
	Decoder4 d2(in[3: 0], out1);
	assign out = {{16{de1[3]}} & out1, {16{de1[2]}} & out1, {16{de1[1]}} & out1, {16{de1[0]}} & out1};
endmodule

module Decoder7(
	input logic [6: 0] in,
	output logic [127: 0] out
);
	logic [3: 0] de1;
	logic [31: 0] out1;
	Decoder2 d1(in[6: 5], de1);
	Decoder2 d2(in[4: 0], out1);
	assign out = {{32{de1[3]}} & out1, {32{de1[2]}} & out1, {32{de1[1]}} & out1, {32{de1[0]}} & out1};
endmodule

module Decoder #(
	parameter RADIX=16,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [WIDTH-1: 0] in,
	output logic [RADIX-1: 0] out
);
	generate;
		case(WIDTH)
		1: Decoder1 decoder(in, out);
		2: Decoder2 decoder(in, out);
		3: Decoder3 decoder(in, out);
		4: Decoder4 decoder(in, out);
		5: Decoder5 decoder(in, out);
		6: Decoder6 decoder(in, out);
		7: Decoder7 decoder(in, out);
		default: Decoder1 decoder(in, out);
		endcase
	endgenerate
endmodule

module Encoder2(
	input logic [1: 0] in,
	output logic [0: 0] out
);
	assign out = in[1];
endmodule

module Encoder4(
	input logic [3: 0] in,
	output logic [1: 0] out
);
	assign out[0] = in[1] | in[3];
	assign out[1] = in[2] | in[3];
endmodule

module Encoder8(
	input logic [7: 0] in,
	output logic [2: 0] out
);
	assign out[2] = in[4] | in[5] | in[6] | in[7];
	assign out[1] = in[2] | in[3] | in[6] | in[7];
	assign out[0] = in[1] | in[3] | in[5] | in[7];
endmodule

module Encoder16(
	input logic [15: 0] in,
	output logic [3: 0] out
);
	logic [2: 0] out_high, out_low;
	encoder_8to3 high(in[7: 0], out_low);
	encoder_8to3 low(in[15: 8], out_high);
	assign out[3] = |in[15: 8];
	assign out[2: 0] = out[3] ? out_high : out_low;
endmodule

module Encoder64(
	input logic [63: 0] in,
	output logic [5: 0] out
);
	logic [3: 0] out1, out2, out3, out4;
	encoder_16to4 part1(in[15: 0], out1);
	encoder_16to4 part2(in[31: 16], out2);
	encoder_16to4 part3(in[47: 32], out3);
	encoder_16to4 part4(in[63: 48], out4);
	logic [3: 0] select;
	assign select[0] = |in[15: 0];
	assign select[1] = |in[31: 16];
	assign select[2] = |in[47: 32];
	assign select[3] = |in[63: 48];
	encoder_4to2 encoder(select, out[5: 4]);
	assign out[3: 0] = {4{select[0]}} & out1 | {4{select[1]}} & out2 | {4{select[2]}} & out3 | {4{select[3]}} & out4;
endmodule

module Encoder #(
	parameter RADIX=16,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [RADIX-1: 0] in,
	output logic [WIDTH-1: 0] out
);
	generate;
		case(RADIX)
		2: Encoder2 encoder(in, out);
		4: Encoder4 encoder(in, out);
		8: Encoder8 encoder(in, out);
		16: Encoder16 encoder(in, out);
		64: Encoder64 encoder(in, out);
		default: Encoder2 encoder(in, out);
		endcase
	endgenerate
endmodule

module PEncoder4 (
	input logic [3: 0] in,
	output logic [1: 0] out
);
	always_comb begin
		if(in[3]) out = 2'b11;
		else if(in[2]) out = 2'b10;
		else if(in[1]) out = 2'b01;
		else if(in[0]) out = 2'b00;
		else out = 2'b00;
	end
endmodule

module PEncoder8 (
	input logic [7: 0] in,
	output logic [2: 0] out
);
	always_comb begin
		if(in[7]) out = 3'b111;
		else if(in[6]) out = 3'b110;
		else if(in[5]) out = 3'b101;
		else if(in[4]) out = 3'b100;
		else if(in[3]) out = 3'b011;
		else if(in[2]) out = 3'b010;
		else if(in[1]) out = 3'b001;
		else out = 3'b000;
	end
endmodule

module PEncoder16(
	input logic [15: 0] in,
	output logic [3: 0] out
);
	logic [2: 0] out1, out2;
	logic is_high;
	PEncoder8 high(in[15: 8], out1);
	PEncoder8 low(in[7: 0], out2);
	assign is_high = |in[15: 8];
	assign out[3] = is_high;
	assign out[2: 0] = is_high ? out1 : out2;
endmodule

module PEncoder32(
	input logic [31: 0] in,
	output logic [4: 0] out
);
	logic [2: 0] out1, out2, out3, out4;
	logic [3: 0] _or;
	PEncoder8 encoder2(in[15: 8], out2);
	PEncoder8 encoder1(in[7: 0], out1);
	PEncoder8 encoder3(in[23: 16], out3);
	PEncoder8 encoder4(in[31: 24], out4);
	assign _or[0] = |in[7: 0];
	assign _or[1] = |in[15: 8];
	assign _or[2] = |in[23: 16];
	assign _or[3] = |in[31: 24];
	PEncoder4 encoder_high(_or, out[4: 3]);
	assign out[2: 0] = out[4: 3] == 2'b11 ? out4 : out[4: 3] == 2'b10 ? out3 : out[4: 3] == 2'b01 ? out2 : out1;
endmodule

module PEncoder #(
	parameter RADIX=16,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [RADIX-1: 0] in,
	output logic [WIDTH-1: 0] out
);

generate;
	case(RADIX)
	4: PEncoder4(in, out);
	8: PEncoder8(in, out);
	16: PEncoder16(in, out);
	32: PEncoder32(in, out);
	default: PEncoder4(in, out);
	endcase
endgenerate

endmodule

// select last bit
module PSelector #(
	parameter RADIX=16
)(
	input logic [RADIX-1: 0] in,
	output logic [RADIX-1: 0] out
);
	logic [RADIX-1: 0] reverse;
	assign reverse[RADIX-1] = 1'b1;
	for(genvar i=RADIX-2; i>=0; i--)begin
		assign reverse[i] = ~in[i+1] & reverse[i+1];
	end
	for(genvar i=0; i<RADIX; i++)begin
		assign out[i] = reverse[i] & in[i];
	end
endmodule

// priority reverse selector
module PRSelector #(
	parameter RADIX=4
)(
	input logic [RADIX-1: 0] in,
	output logic [RADIX-1: 0] out
);
	logic [RADIX-1: 0] reverse;
	assign reverse[0] = 1'b1;
	for(genvar i=1; i<RADIX; i++)begin
		assign reverse[i] = ~in[i-1] & reverse[i-1];
	end
	for(genvar i=0; i<RADIX; i++)begin
		assign out[i] = reverse[i] & in[i];
	end
endmodule

module Matcher #(
	parameter WIDTH = 4
)(
	input logic [WIDTH-1: 0] in1,
	input logic [WIDTH-1: 0] in2,
	output logic equal
);
	logic [WIDTH-1: 0] compare;
	generate;
		for(genvar i=0; i<WIDTH; i++)begin
			assign compare[i] = ~(in1[i] ^ in2[i]);
		end
	endgenerate
	assign equal = &compare;
endmodule

module Mux2 #(
	parameter WIDTH = 4
)(
	input logic compare,
	input logic [WIDTH-1: 0] in1,
	input logic [WIDTH-1: 0] in2,
	output logic [WIDTH-1: 0] out
);
	assign out = compare ? in2 : in1;
endmodule

module Mux3 #(
	parameter WIDTH = 4
)(
	input logic [1: 0] compare,
	input logic [WIDTH-1: 0] in1,
	input logic [WIDTH-1: 0] in2,
	input logic [WIDTH-1: 0] in3,
	output logic [WIDTH-1: 0] out
);
	always_comb begin
		case(compare)
		2'b00: out = in1;
		2'b01: out = in2;
		2'b10: out = in3;
		2'b11: out = in1;
		endcase
	end
endmodule

module Mux4 #(
	parameter WIDTH = 4
)(
	input logic [1: 0] compare,
	input logic [WIDTH-1: 0] in1,
	input logic [WIDTH-1: 0] in2,
	input logic [WIDTH-1: 0] in3,
	input logic [WIDTH-1: 0] in4,
	output logic [WIDTH-1: 0] out
);
	always_comb begin
		case(compare)
		2'b00: out = in1;
		2'b01: out = in2;
		2'b10: out = in3;
		2'b11: out = in4;
		endcase
	end
endmodule

module Mux5 #(
	parameter WIDTH = 4
)(
	input logic [1: 0] compare,
	input logic [WIDTH-1: 0] in1,
	input logic [WIDTH-1: 0] in2,
	input logic [WIDTH-1: 0] in3,
	input logic [WIDTH-1: 0] in4,
	output logic [WIDTH-1: 0] out
);
	always_comb begin
		case(compare)
		2'b00: out = in1;
		2'b01: out = in2;
		2'b10: out = in3;
		2'b11: out = in4;
		endcase
	end
endmodule

// priority mux
module PMux2 #(
	parameter WIDTH = 4
)(
	input logic [1: 0] selector,
	input logic [WIDTH-1: 0] in1,
	input logic [WIDTH-1: 0] in2,
	output logic [WIDTH-1: 0] out
);
	assign out = selector[0] ? in1 : in2;
endmodule

module Sort2 #(
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [1: 0][WIDTH-1: 0] origin,
	input logic [1: 0][DATA_WIDTH-1: 0] data_i,
	output logic [1: 0][WIDTH-1: 0] sort,
	output logic [1: 0][DATA_WIDTH-1: 0] data_o
);
	logic bigger;
	assign bigger = origin[1] < origin[0];
	assign sort = bigger ? {origin[1], origin[0]} : origin;
	assign data_o = bigger ? {data_o[1], data_o[0]} : data_i;
endmodule

module Sort4 #(
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [3: 0][WIDTH-1: 0] origin,
	input logic [3: 0][DATA_WIDTH-1: 0] data_i,
	output logic [3: 0][WIDTH-1: 0] sort,
	output logic [3: 0][DATA_WIDTH-1: 0] data_o
);
	logic [1: 0][WIDTH-1: 0] compare1, compare2;
	logic [1: 0][DATA_WIDTH-1: 0] data1, data2;
	Sort2 #(WIDTH, DATA_WIDTH) sort1 (origin[3: 2], data_i[3: 2], compare1, data1);
	Sort2 #(WIDTH, DATA_WIDTH) sort2 (origin[1: 0], data_i[1: 0], compare2, data2);
	Sort2 #(WIDTH, DATA_WIDTH) sort3 ({compare1[1], compare2[1]}, {data1[1], data2[1]}, sort[3: 2], data_o[3: 2]);
	Sort2 #(WIDTH, DATA_WIDTH) sort4 ({compare1[0], compare2[0]}, {data1[0], data2[0]}, sort[1: 0], data_o[1: 0]);
endmodule

module Sort #(
	parameter RADIX = 2,
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [RADIX-1: 0][WIDTH-1: 0] origin,
	input logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_i,
	output logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_o
);
	logic [RADIX-1: 0][WIDTH-1: 0] sort;
generate
	case(RADIX)
	2: Sort2 #(WIDTH, DATA_WIDTH) sort(origin, data_i, sort, data_o);
	4: Sort4 #(WIDTH, DATA_WIDTH) sort(origin, data_i, sort, data_o);
	default: Sort2 #(WIDTH, DATA_WIDTH) sort(origin, data_i, sort, data_o);
	endcase
endgenerate
endmodule

module OldestSelect #(
	parameter RADIX = 2,
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [RADIX-1: 0][WIDTH-1: 0] cmp,
	input logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_i,
	output logic [WIDTH-1: 0] cmp_o,
	output logic [DATA_WIDTH-1: 0] data_o
);
generate
	if(RADIX == 1)begin
		assign cmp_o = cmp;
		assign data_o = data_i;
	end
	else if(RADIX == 2)begin
		assign cmp_o = cmp[1] > cmp[0] ? cmp[1] : cmp[0];
		assign data_o = cmp[1] > cmp[0] ? data_i[1] : data_i[0];
	end
	else begin
		logic [DATA_WIDTH-1: 0] data1, data2;
		logic [WIDTH-1: 0] cmp1, cmp2;
		OldestSelect #(
			.RADIX(RADIX/2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select1 (
			.cmp(cmp[RADIX/2-1: 0]),
			.data_i(data_i[RADIX/2-1: 0]),
			.cmp_o(cmp1),
			.data_o(data1)
		);
		OldestSelect #(
			.RADIX(RADIX-RADIX/2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select2 (
			.cmp(cmp[RADIX-1: RADIX/2]),
			.data_i(data_i[RADIX-1: RADIX/2]),
			.cmp_o(cmp2),
			.data_o(data2)
		);
		assign cmp_o = cmp2 > cmp1 ? cmp2 : cmp1;
		assign data_o = cmp2 > cmp1 ? data2 : data1;
	end
endgenerate
endmodule

module UpdateCounter #(
	parameter WIDTH=2
) (
	input logic [WIDTH-1: 0] origin,
	input logic dir,
	output logic [WIDTH-1: 0] out
);
generate
	if(WIDTH == 2)begin
		always_comb begin
			if(dir)begin
				case(origin)
				2'b00: out = 2'b01;
				2'b01: out = 2'b10;
				2'b10: out = 2'b11;
				2'b11: out = 2'b11;
				endcase
			end
			else begin
				case (origin)
				2'b00: out = 2'b00;
				2'b01: out = 2'b00;
				2'b10: out = 2'b01;
				2'b11: out = 2'b10;
				endcase
			end
		end
	end
	else if(WIDTH == 3)begin
		logic [WIDTH: 0] add, sub;
		logic [WIDTH-1: 0] add_res, sub_res;
		assign add = origin + 1;
		assign sub = origin - 1;
		assign add_res = {WIDTH{add[WIDTH]}} ^ add[WIDTH-1: 0];
		assign sub_res = {WIDTH{sub[WIDTH]}} ^ sub[WIDTH-1: 0];
		assign out = dir ? add_res : sub_res;
	end
endgenerate
endmodule