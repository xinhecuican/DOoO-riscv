

module Decoder #(
	parameter RADIX=16,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [WIDTH-1: 0] in,
	output logic [RADIX-1: 0] out
);
	generate;
		case(RADIX)
		2: Decoder2 decoder(in, out);
		3: Decoder3 decoder(in, out);
		4: Decoder4 decoder(in, out);
		8: Decoder8 decoder(in, out);
		16: Decoder16 decoder(in, out);
		32: Decoder32 decoder(in, out);
		64: Decoder64 decoder(in, out);
		128: Decoder128 decoder(in, out);
		default: Decoder2 decoder(in, out);
		endcase
	endgenerate
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

module PEncoder #(
	parameter RADIX=16,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [RADIX-1: 0] in,
	output logic [WIDTH-1: 0] out
);

generate;
	case(RADIX)
	2: PEncoder2 pencoder(in, out);
	4: PEncoder4 pencoder(in, out);
	8: PEncoder8 pencoder(in, out);
	16: PEncoder16 pencoder(in, out);
	32: PEncoder32 pencoder(in, out);
	default: PEncoder2 pencoder(in, out);
	endcase
endgenerate

endmodule

module PREncoder #(
	parameter RADIX=16,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [RADIX-1: 0] in,
	output logic [WIDTH-1: 0] out
);

generate;
	case(RADIX)
	2: PREncoder2 pencoder(in, out);
	4: PREncoder4 pencoder(in, out);
	8: PREncoder8 pencoder(in, out);
	16: PREncoder16 pencoder(in, out);
	32: PREncoder32 pencoder(in, out);
	default: PREncoder2 pencoder(in, out);
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
generate
	for(genvar i=RADIX-2; i>=0; i--)begin
		assign reverse[i] = &(~in[RADIX-1: i+1]);
	end
	for(genvar i=0; i<RADIX; i++)begin
		assign out[i] = reverse[i] & in[i];
	end
endgenerate
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
generate
	for(genvar i=1; i<RADIX; i++)begin
		assign reverse[i] = &(~in[i-1: 0]);
	end
	for(genvar i=0; i<RADIX; i++)begin
		assign out[i] = reverse[i] & in[i];
	end
endgenerate
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

module Sort #(
	parameter RADIX = 2,
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [RADIX-1: 0][WIDTH-1: 0] origin,
	input logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_i,
	output logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_o
);
	logic [RADIX-1: 0][WIDTH-1: 0] out;
generate
	case(RADIX)
	2: Sort2 #(WIDTH, DATA_WIDTH) sort(origin, data_i, out, data_o);
	4: Sort4 #(WIDTH, DATA_WIDTH) sort(origin, data_i, out, data_o);
	default: Sort2 #(WIDTH, DATA_WIDTH) sort(origin, data_i, out, data_o);
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
	if(WIDTH == 1)begin
		assign out = dir;
	end
	else if(WIDTH == 2)begin
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

module MaskGen #(
	parameter RADIX=4,
	parameter WIDTH=$clog2(RADIX)
)(
	input logic [WIDTH-1: 0] in,
	output logic [RADIX-1: 0] out
);
generate
	case(RADIX)
	2: MaskGen2 mask_gen(in, out);
	4: MaskGen4 mask_gen(in, out);
	8: MaskGen8 mask_gen(in, out);
	16: MaskGen16 mask_gen(in, out);
	32: MaskGen32 mask_gen(in, out);
	default MaskGen2 mask_gen(in, out);
	endcase
endgenerate
endmodule

module LoopCompare #(
	parameter WIDTH=4
)(
	input logic [WIDTH: 0] in1,
	input logic [WIDTH: 0] in2,
	output logic bigger,
	output logic [WIDTH: 0] out
);
	assign bigger = (in1[0] ^ in2[0]) ^ (in1[WIDTH: 1] < in2[WIDTH: 1]);
	assign out = bigger ? in1 : in2;
endmodule

module MaskExpand #(
	parameter WIDTH=4
)(
	input logic [WIDTH-1: 0] mask,
	output logic [WIDTH*8-1: 0] out
);
generate
	for(genvar i=0; i<WIDTH; i++)begin
		assign out[(i+1)*8-1: i*8] = {8{mask[i]}};
	end
endgenerate
endmodule

module CalValidNum #(
	parameter WIDTH=4
)(
	input logic [WIDTH-1: 0] en,
	output logic [WIDTH-1: 0][$clog2(WIDTH)-1: 0] out
);
generate
	case(WIDTH)
	4: CalValidNum4 calValidNum(en, out);
	2: CalValidNum2 calValidNum(en, out);
	default: CalValidNum2 calValidNum(en, out);
	endcase
endgenerate
endmodule