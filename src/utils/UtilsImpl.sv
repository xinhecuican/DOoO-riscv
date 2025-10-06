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

module PEncoder3(
	input logic [2: 0] in,
	output logic [1: 0] out
);
	assign out[0] = in[1] & ~in[2];
	assign out[1] = in[2];
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

module PREncoder3(
	input logic [2: 0] in,
	output logic [1: 0] out
);
	assign out[0] = in[1] & ~in[0];
	assign out[1] = in[2] & ~in[1] & ~in[0];
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
	output logic [1: 0][DATA_WIDTH-1: 0] data_o
);
	logic bigger;
	assign bigger = origin[0] < origin[1];
	assign data_o = bigger ? 2'b10 : 2'b01;
endmodule

module Sort4 #(
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [3: 0][WIDTH-1: 0] origin,
	output logic [3: 0][DATA_WIDTH-1: 0] data_o
);
	logic bigger1, bigger2, bigger3, bigger4, bigger5, bigger6;
	assign bigger1 = origin[0] < origin[1];
	assign bigger2 = origin[2] < origin[3];
	assign bigger3 = origin[0] < origin[2];
	assign bigger4 = origin[1] < origin[3];
	assign bigger5 = origin[0] < origin[3];
	assign bigger6 = origin[1] < origin[2];
	always_comb begin
		case({bigger4, bigger3, bigger2, bigger1})
		4'b0000: data_o = bigger6 ? 8'b00_10_01_11 : 8'b00_01_10_11;
		4'b0001: data_o = 8'b00_01_11_10;
		4'b0010: data_o = 8'b01_00_10_11;
		4'b0011: data_o = bigger5 ? 8'b10_00_11_01 : 8'b01_00_11_10;
		4'b0100: data_o = 8'b00_11_01_10;
		4'b0101: begin
			case({bigger6, bigger5})
			2'b00: data_o = 8'b00_10_11_01;
			2'b01: data_o = 8'b01_10_11_00;
			2'b10: data_o = 8'b00_11_10_01;
			2'b11: data_o = 8'b01_11_10_00; // unexist
			endcase
		end
		4'b0110: data_o = 8'b11_10_00_01; // unexist
		4'b0111: data_o = 8'b10_01_11_00;
		4'b1000: data_o = 8'b01_10_00_11;
		4'b1001: data_o = 8'b00_01_11_10; // unexist
		4'b1010: begin
			case({bigger6, bigger5})
			2'b00: data_o = 8'b10_00_01_11;
			2'b01: data_o = 8'b11_00_01_10;
			2'b10: data_o = 8'b10_01_00_11;
			2'b11: data_o = 8'b11_01_00_10;
			endcase
		end
		4'b1011: data_o = 8'b11_00_10_01;
		4'b1100: data_o = bigger5 ? 8'b10_11_00_01 : 8'b01_11_00_10;
		4'b1101: data_o = 8'b10_11_01_00;
		4'b1110: data_o = 8'b11_10_00_01;
		4'b1111: data_o = bigger6 ? 8'b00_10_01_11 : 8'b00_01_10_11;
		endcase
	end
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
	CalValidNum3 calValidNum(en[2: 0], out[2: 0]);
	assign out[3] = {en[0] & en[1] | en[0] & en[2] | en[1] & en[2], ^en[2: 0]};
endmodule

`define CAL_VALID_NUM_TEMPLATE(num, num_log) \
module CalValidNum``num``( \
	input logic [``num``-1: 0] en, \
	output logic [``num``-1: 0][``num_log``-1: 0] out /*verilator split_var*/\
); \
	assign out[0] = 0; \
generate \
	for(genvar i=1; i<``num``; i++)begin \
		localparam WIDTH = $clog2(i+1) > 1 ? $clog2(i+1) : 1; \
		assign out[i][WIDTH-1: 0] = out[i-1][WIDTH-1: 0] + en[i-1]; \
		if(WIDTH < ``num_log``)begin \
			assign out[i][``num_log``-1: WIDTH] = 0; \
		end \
	end \
endgenerate \
endmodule

`CAL_VALID_NUM_TEMPLATE(8, 3)
`CAL_VALID_NUM_TEMPLATE(16, 4)

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

module Mux2 #(
	parameter WIDTH=4
)(
	input logic [1:0] sel,
	input logic [1:0][WIDTH-1:0] in,
	input logic [WIDTH-1:0] default_value,
	output logic [WIDTH-1:0] out
);
	always_comb begin
		case(sel)
		2'b01: out = in[0];
		2'b10: out = in[1];
		default: out = default_value;
		endcase
	end
endmodule

module Mux3 #(
	parameter WIDTH=4
)(
	input logic [2:0] sel,
	input logic [2:0][WIDTH-1:0] in,
	input logic [WIDTH-1:0] default_value,
	output logic [WIDTH-1:0] out
);
	always_comb begin
		case(sel)
		3'b001: out = in[0];
		3'b010: out = in[1];
		3'b100: out = in[2];
		default: out = default_value;
		endcase
	end
endmodule

module Mux4 #(
	parameter WIDTH=4
)(
	input logic [3:0] sel,
	input logic [3:0][WIDTH-1:0] in,
	input logic [WIDTH-1:0] default_value,
	output logic [WIDTH-1:0] out
);
	always_comb begin
		case(sel)
		4'b0001: out = in[0];
		4'b0010: out = in[1];
		4'b0100: out = in[2];
		4'b1000: out = in[3];
		default: out = default_value;
		endcase
	end
endmodule

module Mux5 #(
	parameter WIDTH=4
)(
	input logic [4:0] sel,
	input logic [4:0][WIDTH-1:0] in,
	input logic [WIDTH-1:0] default_value,
	output logic [WIDTH-1:0] out
);
	always_comb begin
		case(sel)
		5'b00001: out = in[0];
		5'b00010: out = in[1];
		5'b00100: out = in[2];
		5'b01000: out = in[3];
		5'b10000: out = in[4];
		default: out = default_value;
		endcase
	end
endmodule