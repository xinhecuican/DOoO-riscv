

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
		default: begin
			Decoder2 decoder(in, out);
			always_comb begin
				$display("unimpl Decoder");
			end
		end
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
		32: Encoder32 encoder(in, out);
		64: Encoder64 encoder(in, out);
		default: begin
			Encoder2 encoder(in, out);
			always_comb begin
				$display("unimpl Encoder");
			end
		end
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
	1: PEncoder1 pencoder(in, out);
	2: PEncoder2 pencoder(in, out);
	4: PEncoder4 pencoder(in, out);
	7: PEncoder7 pencoder(in, out);
	8: PEncoder8 pencoder(in, out);
	16: PEncoder16 pencoder(in, out);
	17: PEncoder17 pencoder(in, out);
	32: PEncoder32 pencoder(in, out);
	default: begin
		PEncoder2 pencoder(in, out);
		always_comb begin
			$display("unimpl PEncoder");
		end
	end
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
	default: begin
		PREncoder2 pencoder(in, out);
		always_comb begin
			$display("unimpl PREncoder");
		end
	end
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

// module Matcher #(
// 	parameter WIDTH = 4
// )(
// 	input logic [WIDTH-1: 0] in1,
// 	input logic [WIDTH-1: 0] in2,
// 	output logic equal
// );
// 	logic [WIDTH-1: 0] compare;
// 	generate;
// 		for(genvar i=0; i<WIDTH; i++)begin
// 			assign compare[i] = ~(in1[i] ^ in2[i]);
// 		end
// 	endgenerate
// 	assign equal = &compare;
// endmodule

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
	default: begin
		Sort2 #(WIDTH, DATA_WIDTH) sort(origin, data_i, out, data_o);
		always_comb begin
			$display("unimpl Sort");
		end
	end
	endcase
endgenerate
endmodule

module FairSelect #(
	parameter RADIX = 2,
	parameter DATA_WIDTH = 4
)(
	input logic [RADIX-1: 0] en,
	input logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_i,
	output logic en_o,
	output logic [DATA_WIDTH-1: 0] data_o
);
	if(RADIX == 1)begin
		assign en_o = en;
		assign data_o = data_i;
	end
	else if(RADIX == 2)begin
		assign en_o = en[0] | en[1];
		assign data_o = {DATA_WIDTH{en[0]}} & data_i[0] |
						{DATA_WIDTH{en[1]}} & data_i[1];
	end
	else begin
		logic [DATA_WIDTH-1: 0] data1, data2;
		logic en1, en2;
		FairSelect #(
			.RADIX(RADIX/2),
			.DATA_WIDTH(DATA_WIDTH)
		) select1 (
			.en(en[RADIX/2-1: 0]),
			.data_i(data_i[RADIX/2-1: 0]),
			.en_o(en1),
			.data_o(data1)
		);
		FairSelect #(
			.RADIX(RADIX-RADIX/2),
			.DATA_WIDTH(DATA_WIDTH)
		) select2 (
			.en(en[RADIX-1: RADIX/2]),
			.data_i(data_i[RADIX-1: RADIX/2]),
			.en_o(en2),
			.data_o(data2)
		);
		assign en_o = en1 | en2;
		assign data_o = {DATA_WIDTH{en1}} & data1 |
						{DATA_WIDTH{en2}} & data2;
	end
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

module LoopOldestSelect #(
	parameter RADIX = 2,
	parameter WIDTH = 4,
	parameter DATA_WIDTH = 4
)(
	input logic [RADIX-1: 0] en,
	input logic [RADIX-1: 0][WIDTH: 0] cmp,
	input logic [RADIX-1: 0][DATA_WIDTH-1: 0] data_i,
	output logic en_o,
	output logic [WIDTH: 0] cmp_o,
	output logic [DATA_WIDTH-1: 0] data_o
);
generate
	if(RADIX == 1)begin
		assign en_o = en;
		assign cmp_o = cmp;
		assign data_o = data_i;
	end
	else if(RADIX == 2)begin
		logic older;
		LoopCompare #(WIDTH) cmp_older (cmp[0], cmp[1], older);
		assign en_o = en[0] | en[1];
		assign cmp_o = en[0] & older | en[0] & ~en[1] ? cmp[0] : cmp[1];
		assign data_o = en[0] & older | en[0] & ~en[1] ? data_i[0] : data_i[1];
	end
	else begin
		logic [1: 0] en_t;
		logic [1: 0][DATA_WIDTH-1: 0] data_t;
		logic [1: 0][WIDTH: 0] cmp_t;
		LoopOldestSelect #(
			.RADIX(RADIX/2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select1 (
			.en(en[RADIX/2-1: 0]),
			.cmp(cmp[RADIX/2-1: 0]),
			.data_i(data_i[RADIX/2-1: 0]),
			.en_o(en_t[0]),
			.cmp_o(cmp_t[0]),
			.data_o(data_t[0])
		);
		LoopOldestSelect #(
			.RADIX(RADIX-RADIX/2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select2 (
			.en(en[RADIX-1: RADIX/2]),
			.cmp(cmp[RADIX-1: RADIX/2]),
			.data_i(data_i[RADIX-1: RADIX/2]),
			.en_o(en_t[1]),
			.cmp_o(cmp_t[1]),
			.data_o(data_t[1])
		);
		LoopOldestSelect #(
			.RADIX(2),
			.WIDTH(WIDTH),
			.DATA_WIDTH(DATA_WIDTH)
		) select_o(
			.en(en_t),
			.cmp(cmp_t),
			.data_i(data_t),
			.en_o(en_o),
			.cmp_o(cmp_o),
			.data_o(data_o)
		);
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
	else begin
		always_comb begin
			$display("unimpl UpdateCounter");
		end
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
	5: MaskGen8 mask_gen(in, out);
	8: MaskGen8 mask_gen(in, out);
	16: MaskGen16 mask_gen(in, out);
	17: MaskGen17 mask_gen(in, out);
	20: MaskGen20 mask_gen(in, out);
	22: MaskGen22 mask_gen(in, out);
	32: MaskGen32 mask_gen(in, out);
	64: MaskGen64 mask_gen(in, out);
	default: begin
		MaskGen2 mask_gen(in, out);
		always_comb begin
			$display("unimpl MaskGen %d", RADIX);
		end
	end
	endcase
endgenerate
endmodule

// in1 older if bigger set
module LoopCompare #(
	parameter WIDTH=4
)(
	input logic [WIDTH: 0] in1,
	input logic [WIDTH: 0] in2,
	output logic bigger
);
	assign bigger = (in1[0] ^ in2[0]) ^ (in1[WIDTH: 1] < in2[WIDTH: 1]);
endmodule

module LoopAdder #(
	parameter WIDTH=4,
	parameter ADD_WIDTH=2
)(
	input logic [ADD_WIDTH-1: 0] add,
	input logic [WIDTH: 0] data,
	output logic [WIDTH: 0] data_o
);
	logic [WIDTH-1: 0] res;
	assign res = data[WIDTH: 1] + add;
	assign data_o[WIDTH: 1] = res;
	assign data_o[0] = data[WIDTH] & ~res[WIDTH-1] ? ~data[0] : data[0];
endmodule

module LoopSub #(
	parameter WIDTH=4,
	parameter ADD_WIDTH=2
)(
	input logic [ADD_WIDTH-1: 0] sub,
	input logic [WIDTH: 0] data,
	output logic [WIDTH: 0] data_o
);
	logic [WIDTH-1: 0] res;
	assign res = data[WIDTH: 1] - sub;
	assign data_o[WIDTH: 1] = res;
	assign data_o[0] = ~data[WIDTH] & res[WIDTH-1] ? ~data[0] : data[0];
endmodule

module LoopFull #(
	parameter WIDTH=4
)(
	input logic [WIDTH: 0] cmp1,
	input logic [WIDTH: 0] cmp2,
	output logic full
);
	assign full = (cmp1[0] ^ cmp2[0]) & (cmp1[WIDTH: 1] == cmp2[WIDTH: 1]);
endmodule

module LoopMaskGen #(
	parameter SIZE=4,
	parameter WIDTH=$clog2(SIZE)
)(
	input logic [WIDTH: 0] in1,
	input logic [WIDTH: 0] in2,
	output logic [SIZE-1: 0] mask
);
	logic [SIZE-1: 0] mask1, mask2;
	MaskGen #(SIZE) mask_gen_in1(in1[WIDTH: 1], mask1);
	MaskGen #(SIZE) mask_gen_in2(in2[WIDTH: 1], mask2);
	assign mask = {SIZE{in1[0] ^ in2[0]}} ^ (mask1 ^ mask2);
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
	parameter WIDTH=4,
	parameter IDX_WIDTH=WIDTH > 1 ? $clog2(WIDTH) : 1
)(
	input logic [WIDTH-1: 0] en,
	output logic [WIDTH-1: 0][IDX_WIDTH-1: 0] out
);
generate
	case(WIDTH)
	16: CalValidNum16 calValidNum(en, out);
	8: CalValidNum8 calValidNum(en, out);
	4: CalValidNum4 calValidNum(en, out);
	3: CalValidNum3 calValidNum(en, out);
	2: CalValidNum2 calValidNum(en, out);
	1: CalValidNum1 calValidNum(en, out);
	default: begin
		CalValidNum2 calValidNum(en, out);
		always_comb begin
			$display("unimpl CalValidNum");
		end
	end
	endcase
endgenerate
endmodule

// last data has highest priority
module Arbiter #(
	parameter WIDTH=2,
	parameter DATA_WIDTH=4
)(
	input logic [WIDTH-1: 0] valid,
	input logic [WIDTH-1: 0][DATA_WIDTH-1: 0] data,
	output logic [WIDTH-1: 0] ready,
	output logic valid_o,
	output logic [DATA_WIDTH-1: 0] data_o
);
generate
	case(WIDTH)
	2: Arbiter2 #(DATA_WIDTH) arbiter (valid, data, ready, valid_o, data_o);
	3: Arbiter3 #(DATA_WIDTH) arbiter (valid, data, ready, valid_o, data_o);
	default: begin
		always_comb begin
			$display("unimpl Arbiter");
		end
	end
	endcase
endgenerate
endmodule

module SyncRst(
	input logic clk,
	input logic rst_i,
	output logic rst_o
);

	logic rst1, rst2;
	always_ff @(posedge clk or posedge rst_i)begin
		if(rst_i)begin
			rst1 <= 1'b1;
			rst2 <= 1'b1;
		end
		else begin
			rst1 <= 1'b0;
			rst2 <= rst1;
		end
	end
	assign rst_o = rst2;

endmodule