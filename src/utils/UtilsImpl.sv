module Decoder2(
	input logic [0: 0] A,
	output logic [1: 0] Y
);
	assign Y[1] = A;
	assign Y[0] = ~A;
endmodule

module Decoder3(
	input logic [1: 0] in,
	output logic [2: 0] out
);
	assign out[0] = ~in[0] & ~in[1];
	assign out[1] = in[0] & ~in[1];
	assign out[2] = in[1];
endmodule

module Decoder4(
	input logic [1: 0] A,
	output logic [3: 0] Y
);
	wire nA0, nA1;
	not n2(nA0, A[0]), n3(nA1, A[1]);
	and nd1(Y[0], nA0, nA1), nd2(Y[1], A[0], nA1),
		nd3(Y[2], nA0, A[1]), nd4(Y[3], A[1], A[0]);
endmodule

module Decoder8(
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

module Decoder16(
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

module Decoder32(
	input logic [4: 0] in,
	output logic [31: 0] out
);
	logic [3: 0] de1;
	logic [7: 0] out1;
	Decoder4 d1(in[4: 3], de1);
	Decoder8 d2(in[2: 0], out1);
	assign out = {{8{de1[3]}} & out1, {8{de1[2]}} & out1, {8{de1[1]}} & out1, {8{de1[0]}} & out1};
endmodule

module Decoder64(
	input logic [5: 0] in,
	output logic [63: 0] out
);
	logic [3: 0] de1;
	logic [15: 0] out1;
	Decoder4 d1(in[5: 4], de1);
	Decoder16 d2(in[3: 0], out1);
	assign out = {{16{de1[3]}} & out1, {16{de1[2]}} & out1, {16{de1[1]}} & out1, {16{de1[0]}} & out1};
endmodule

module Decoder128(
	input logic [6: 0] in,
	output logic [127: 0] out
);
	logic [3: 0] de1;
	logic [31: 0] out1;
	Decoder4 d1(in[6: 5], de1);
	Decoder32 d2(in[4: 0], out1);
	assign out = {{32{de1[3]}} & out1, {32{de1[2]}} & out1, {32{de1[1]}} & out1, {32{de1[0]}} & out1};
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
	Encoder8 low(in[7: 0], out_low);
	Encoder8 high(in[15: 8], out_high);
	assign out[3] = |in[15: 8];
	assign out[2: 0] = out_high | out_low;
endmodule

module Encoder32(
	input logic [31: 0] in,
	output logic [4: 0] out
);
	logic [3: 0] out_high, out_low;
	Encoder16 high(in[31: 16], out_high);
	Encoder16 low(in[15: 0], out_low);
	assign out[4] = |in[31: 16];
	assign out[3: 0] = out_high | out_low;
endmodule

module Encoder64(
	input logic [63: 0] in,
	output logic [5: 0] out
);
	logic [3: 0] out1, out2, out3, out4;
	Encoder16 part1(in[15: 0], out1);
	Encoder16 part2(in[31: 16], out2);
	Encoder16 part3(in[47: 32], out3);
	Encoder16 part4(in[63: 48], out4);
	logic [3: 0] select;
	assign select[0] = |in[15: 0];
	assign select[1] = |in[31: 16];
	assign select[2] = |in[47: 32];
	assign select[3] = |in[63: 48];
	Encoder4 encoder(select, out[5: 4]);
	assign out[3: 0] = out1 | out2 | out3 | out4;
endmodule

module PEncoder1(
	input logic in,
	output logic out
);
	assign out = 0;
endmodule

module PEncoder2(
	input logic [1: 0] in,
	output logic [0: 0] out
);
	assign out = in[1];
endmodule

module PEncoder4 (
	input logic [3: 0] in,
	output logic [1: 0] out
);
	assign out[1] = in[3] | in[2];
	assign out[0] = in[3] | ((~in[2]) & in[1]);
endmodule

module PEncoder7 (
	input logic [6: 0] in,
	output logic [2: 0] out
);
	logic [1: 0] out1, out2;
	logic is_high;
	PEncoder4 high({1'b0, in[6: 4]}, out1);
	PEncoder4 low(in[3: 0], out2);
	assign is_high = |in[6: 4];
	assign out[2] = is_high;
	assign out[1: 0] = is_high ? out1 : out2;
endmodule

module PEncoder8 (
	input logic [7: 0] in,
	output logic [2: 0] out
);
	logic [1: 0] out1, out2;
	logic is_high;
	PEncoder4 high(in[7: 4], out1);
	PEncoder4 low(in[3: 0], out2);
	assign is_high = |in[7: 4];
	assign out[2] = is_high;
	assign out[1: 0] = is_high ? out1 : out2;
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

module PEncoder17(
	input logic [16: 0] in,
	output logic [4: 0] out
);
	logic [2: 0] out1, out2;
	logic is_high;
	PEncoder8 high(in[15: 8], out1);
	PEncoder8 low(in[7: 0], out2);
	assign is_high = |in[15: 8];
	assign out[4] = in[16];
	assign out[3] = is_high & ~in[16];
	assign out[2: 0] = {3{is_high & ~in[16]}} & out1 | {3{~is_high & ~in[16]}} & out2;
endmodule

module PEncoder32(
	input logic [31: 0] in,
	output logic [4: 0] out
);
	logic [2: 0] out1, out2, out3, out4;
	logic [3: 0] _or;
	logic [1: 0] out_high;
	PEncoder8 encoder2(in[15: 8], out2);
	PEncoder8 encoder1(in[7: 0], out1);
	PEncoder8 encoder3(in[23: 16], out3);
	PEncoder8 encoder4(in[31: 24], out4);
	assign _or[0] = |in[7: 0];
	assign _or[1] = |in[15: 8];
	assign _or[2] = |in[23: 16];
	assign _or[3] = |in[31: 24];
	PEncoder4 encoder_high(_or, out_high);
	assign out[4: 3] = out_high;
	assign out[2: 0] = out_high == 2'b11 ? out4 : 
					   out_high == 2'b10 ? out3 : 
					   out_high == 2'b01 ? out2 : out1;
endmodule

module PEncoder64(
	input logic [63: 0] in,
	output logic [5: 0] out
);
	logic [4: 0] out1, out2;
	logic is_high;
	PEncoder32 high(in[63: 32], out1);
	PEncoder32 low(in[31: 0], out2);
	assign is_high = |in[63: 32];
	assign out[5] = is_high;
	assign out[4: 0] = is_high ? out1 : out2;
endmodule

module PREncoder2(
	input logic [1: 0] in,
	output logic [0: 0] out
);
	assign out = in[1] & ~in[0];
endmodule

module PREncoder4 (
	input logic [3: 0] in,
	output logic [1: 0] out
);
	always_comb begin
		if(in[0]) out = 2'b00;
		else if(in[1]) out = 2'b01;
		else if(in[2]) out = 2'b10;
		else out = 2'b11;
	end
endmodule

module PREncoder8 (
	input logic [7: 0] in,
	output logic [2: 0] out
);
	always_comb begin
		if(in[0]) out = 3'b000;
		else if(in[1]) out = 3'b001;
		else if(in[2]) out = 3'b010;
		else if(in[3]) out = 3'b011;
		else if(in[4]) out = 3'b100;
		else if(in[5]) out = 3'b101;
		else if(in[6]) out = 3'b110;
		else out = 3'b111;
	end
endmodule

module PREncoder16(
	input logic [15: 0] in,
	output logic [3: 0] out
);
	logic [2: 0] out1, out2;
	logic is_low;
	PREncoder8 high(in[15: 8], out1);
	PREncoder8 low(in[7: 0], out2);
	assign is_low = |in[7: 0];
	assign out[3] = ~is_low;
	assign out[2: 0] = is_low ? out2 : out1;
endmodule

module PREncoder32(
	input logic [31: 0] in,
	output logic [4: 0] out
);
	logic [3: 0] out1, out2;
	logic is_low;
	PREncoder16 low(in[15: 0], out1);
	PREncoder16 high(in[31: 16], out2);
	assign is_low = |in[15: 0];
	assign out[4] = ~is_low;
	assign out[3: 0] = is_low ? out1 : out2;
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
	assign sort = bigger ? {origin[0], origin[1]} : origin;
	assign data_o = bigger ? {data_i[0], data_i[1]} : data_i;
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

module MaskGen2(
	input logic in,
	output logic [1: 0] out
);
	assign out[0] = in;
	assign out[1] = 1'b0;
endmodule

module MaskGen3(
	input logic [1: 0] in,
	output logic [2: 0] out
);
	assign out[0] = in[0] | in[1];
	assign out[1] = in[1];
	assign out[2] = 1'b0;
endmodule

module MaskGen4(
	input logic [1: 0] in,
	output logic [3: 0] out
);
	assign out[0] = in[1] | in[0];
	assign out[1] = in[1];
	assign out[2] = in[1] & in[0];
	assign out[3] = 0;
endmodule

module MaskGen5(
	input logic [2: 0] in,
	output logic [4: 0] out
);
	logic [3: 0] low;
	MaskGen4 gen_low (in[1: 0], low);
	assign out[4] = 0;
	assign out[3: 0] = low | {4{in[2]}};
endmodule

module MaskGen8(
	input logic [2: 0] in,
	output logic [7: 0] out
);
	logic [3: 0] low;
	MaskGen4 gen_low (in[1: 0], low);
	assign out[7: 4] = low & {4{in[2]}};
	assign out[3: 0] = low | {4{in[2]}};
endmodule

module MaskGen16(
	input logic [3: 0] in,
	output logic [15: 0] out
);
	logic [7: 0] low;
	MaskGen8 gen_low (in[2: 0], low);
	assign out[15: 8] = low & {8{in[3]}};
	assign out[7: 0] = low | {8{in[3]}};
endmodule

module MaskGen17(
	input logic [4: 0] in,
	output logic [16: 0] out
);
	logic [15: 0] low;
	MaskGen16 gen_low (in[3: 0], low);
	assign out[16] = 0;
	assign out[15: 0] = low | {16{in[4]}};
endmodule

module MaskGen20(
	input logic [4: 0] in,
	output logic [19: 0] out
);
	logic [15: 0] low;
	MaskGen16 gen_low (in[3: 0], low);
	assign out[19: 16] = low[3: 0] & {4{in[4]}};
	assign out[15: 0] = low | {16{in[4]}};
endmodule

module MaskGen22(
	input logic [4: 0] in,
	output logic [21: 0] out
);
	logic [15: 0] low;
	MaskGen16 gen_low (in[3: 0], low);
	assign out[21: 16] = low[3: 0] & {6{in[4]}};
	assign out[15: 0] = low | {16{in[4]}};
endmodule

module MaskGen25(
	input logic [4: 0] in,
	output logic [24: 0] out
);
	logic [15: 0] low;
	MaskGen16 gen_low(in[3: 0], low);
	assign out[24: 16] = low[8: 0] & {9{in[4]}};
	assign out[15: 0] = low | {16{in[4]}};
endmodule

module MaskGen32(
	input logic [4: 0] in,
	output logic [31: 0] out
);
	logic [15: 0] low;
	MaskGen16 gen_low (in[3: 0], low);
	assign out[31: 16] = low & {16{in[4]}};
	assign out[15: 0] = low | {16{in[4]}};
endmodule

module MaskGen44(
	input logic [5: 0] in,
	output logic [43: 0] out
);
	logic [31: 0] low;
	MaskGen32 gen_low (in[4: 0], low);
	assign out[43: 32] = low[11: 0] & {12{in[5]}};
	assign out[31: 0] = low | {32{in[5]}};
endmodule

module MaskGen64(
	input logic [5: 0] in,
	output logic [63: 0] out
);
	logic [31: 0] low;
	MaskGen32 gen_low (in[4: 0], low);
	assign out[63: 32] = low & {32{in[5]}};
	assign out[31: 0] = low | {32{in[5]}};
endmodule

module CalValidNum1(
	input logic en,
	output logic out
);
	assign out = 1'b0;
endmodule

module CalValidNum2(
	input logic [1: 0] en,
	output logic [1: 0] out
);
	assign out[0] = 1'b0;
	assign out[1] = en[0];
endmodule

module CalValidNum3(
	input logic [2: 0] en,
	output logic [2: 0][1: 0] out
);
	assign out[0] = 2'b0;
	assign out[1] = {1'b0, en[0]};
	assign out[2] = {en[0] & en[1], en[0] ^ en[1]};
endmodule

module CalValidNum4(
	input logic [3: 0] en,
	output logic [3: 0][1: 0] out
);
	logic en_xor; // 1为奇数，0为偶数
	CalValidNum3 calValidNum(en[2: 0], out[2: 0]);
	assign en_xor = ^en[2: 0];
	assign out[3] = {~en_xor & (|en[2: 0]), en_xor};
endmodule

`define CAL_VALID_NUM_TEMPLATE(num, half, num_log, half_log) \
module CalValidNum``num``( \
	input logic [``num``-1: 0] en, \
	output logic [``num``-1: 0][``num_log``-1: 0] out \
); \
	logic [``half``-1: 0][``half_log``-1: 0] out_low, out_high; \
	logic [``num_log``-1: 0] num1; \
	CalValidNum``half  low (en[``half``-1: 0], out_low); \
	CalValidNum``half  high (en[``num``-1: ``half``], out_high); \
	ParallelAdder #(1, ``half``) adder_low (en[``half``-1: 0], num1); \
generate \
	for(genvar i=0; i<``half``; i++)begin \
		assign out[i] = {1'b0, out_low[i]}; \
		assign out[i+``half``] = out_high[i] + num1; \
	end \
endgenerate \
endmodule

`CAL_VALID_NUM_TEMPLATE(8, 4, 3, 2)
`CAL_VALID_NUM_TEMPLATE(16, 8, 4, 3)

module Arbiter2 #(
	parameter DATA_WIDTH=4
)(
	input logic [1: 0] valid,
	input logic [1: 0][DATA_WIDTH-1: 0] data,
	output logic [1: 0] ready,
	output logic valid_o,
	output logic [DATA_WIDTH-1: 0] data_o
);
	assign ready[0] = ~valid[1];
	assign ready[1] = 1'b1;
	assign valid_o = |valid;
	assign data_o = valid[1] ? data[1] : data[0];
endmodule

module Arbiter3 #(
	parameter DATA_WIDTH=4
)(
	input logic [2: 0] valid,
	input logic [2: 0][DATA_WIDTH-1: 0] data,
	output logic [2: 0] ready,
	output logic valid_o,
	output logic [DATA_WIDTH-1: 0] data_o
);
	assign ready[0] = ~valid[1] & ~valid[2];
	assign ready[1] = ~valid[2];
	assign ready[2] = 1'b1;
	assign valid_o = |valid;
	assign data_o = valid[2] ? data[2] :
					valid[1] ? data[1] : data[0];
endmodule