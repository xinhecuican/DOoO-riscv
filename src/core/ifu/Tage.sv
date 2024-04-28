`include "../../defines/defines.svh"

module Tage(
    input logic clk,
    input logic rst,
    BpuTageIO.tage tage_io
);

	typedef struct {
		logic en;
		logic `N(`TAGE_SET_WIDTH) lookup_idx;
		logic `N(`TAGE_TAG_SIZE) lookup_tag;
		logic update_en;
		logic `N(`TAGE_SET_WIDTH) update_idx;
		TageEntry `N(`SLOT_NUM) update_entry;
	} BankCtrl;
	BankCtrl bank_ctrl `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) table_hits `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) table_u `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) prediction `N(`TAGE_BANK);

	logic `N(`TAGE_SET_WIDTH) compress_index `N(`TAGE_BANK);
	logic `N(`TAGE_TAG_COMPRESS1) compress_tag1 `N(`TAGE_BANK);
	logic `N(`TAGE_TAG_COMPRESS2) compress_tag2 `N(`TAGE_BANK);

    generate;
        for(genvar i=0; i<`TAGE_BANK; i++)begin
			GetIndex #(
				.COMPRESS_LENGTH(`TAGE_SET_WIDTH),
				.INDEX_SIZE($clog2(tage_set_size[i])),
				.BANK(i)
			)get_index(
				.pc(tage_io.pc),
				.path_hist(tage_io.history.phist),
				.compress(compress_index[i]),
				.index(bank_ctrl[i].lookup_idx)
			);
			GetTag #(
				.COMPRESS1_LENGTH(12),
				.COMPRESS2_LENGTH(10),
				.INDEX_SIZE(`TAGE_SET_WIDTH),
				.TAG_SIZE(`TAGE_TAG_SIZE)
			) get_tag(
				.pc(pc),
				.path_hist(tage_io.history.phist),
				.compress_index1(i == 0 ? 0 : compress_index[i-1]),
				.compress_index2(compress_index[i]),
				.compress1(compress_tag1[i]),
				.compress2(compress_tag2[i]),
				.tag(bank_ctrl[i].lookup_tag)
			);

			TageTable #(
				.HEIGHT(tage_set_size[i])
			)tage_table(
				.clk(clk),
				.rst(rst),
				.en(bank_ctrl[i].en & ~tage_io.redirect.stall),
				.update_en(bank_ctrl[i].update_en),
				.lookup_idx(bank_ctrl[i].lookup_idx),
				.lookup_tag(bank_ctrl[i].lookup_tag),
				.update_idx(bank_ctrl[i].update_idx),
				.update_entry(bank_ctrl[i].update_entry),
				.lookup_match(table_hits[i]),
				.lookup_u(table_u[i]),
				.taken(prediction[i])
			);
        end
    endgenerate

	logic base_we;
	logic `N($clog2(`TAGE_BASE_SIZE)) base_lookup_idx, base_update_idx;
	logic `ARRAY(`SLOT_NUM, `TAGE_BASE_CTR) base_ctr, base_update_ctr;
	SDPRAM #(
		.WIDTH(`TAGE_BASE_CTR * `SLOT_NUM),
		.DEPTH(`TAGE_BASE_SIZE),
		.READ_LATENCY1(1)
	) base_table (
		.clk(clk),
		.rst(rst),
		.en(!tage_io.redirect.stall),
		.we(base_we),
		.addr0(base_update_idx),
		.addr1(base_lookup_idx),
		.rdata1(base_ctr),
		.wdata(base_update_ctr)
	);

	generate;
		for(genvar br=0; br<`SLOT_NUM; br++)begin
			assign tage_io.prediction[br] = |({prediction[br], base_ctr[br][`TAGE_BASE_CTR-1]} &
										   {table_hits[br], 1'b1});
			assign tage_io.meta.table_hits = |prediction[br];
		end
	endgenerate

endmodule

module TageTable #(
	parameter WIDTH = $bits(TageEntry) * `SLOT_NUM,
	parameter HEIGHT = 1024,
	parameter ADDR_WIDTH = $clog2(HEIGHT)
)(
	input logic clk,
	input logic rst,
	input logic en,
	input logic `N(ADDR_WIDTH) lookup_idx,
	input logic `N(`TAGE_TAG_SIZE) lookup_tag,
	input logic update_en,
	input logic `N(ADDR_WIDTH) update_idx,
	input TageEntry `N(`SLOT_NUM) update_entry,
	output logic `N(`SLOT_NUM) lookup_match,
	output logic `N(`SLOT_NUM) u,
	output logic `N(`SLOT_NUM) taken
);
	logic `ARRAY(`SLOT_NUM, `TAGE_TAG_SIZE) match_tag;
	always_ff @(posedge clk)begin
		match_tag <= lookup_tag;
	end
	TageEntry `N(`SLOT_NUM) lookup_entry;
	generate;
		for(genvar i=0; i<`SLOT_NUM; i++)begin
			assign lookup_match[i] = lookup_entry[i].tag == match_tag;
			assign u[i] = lookup_entry[i].u != 0;
			assign taken[i] = lookup_entry[i].ctr[`TAGE_CTR_SIZE-1];
		end
	endgenerate

	SDPRAM #(
		.WIDTH(WIDTH),
		.DEPTH(HEIGHT),
		.READ_LATENCY(1)
	)tage_bank(
		.clk(clk),
		.rst(rst),
		.en(en),
		.we(update_en),
		.addr0(update_idx),
		.addr1(lookup_idx),
		.rdata1(lookup_entry),
		.wdata(update_entry)
	);
endmodule

module F #(
	parameter INDEX_SIZE=7
)(
	input logic [31: 0] path_hist,
	output logic [INDEX_SIZE-1: 0] out
);
	assign out = path_hist ^ (path_hist >> INDEX_SIZE);
endmodule

module GetIndex #(
	parameter COMPRESS_LENGTH=8,
	parameter INDEX_SIZE=7,
	parameter BANK=0,
	parameter SHIFT_SIZE=INDEX_SIZE > BANK ? INDEX_SIZE-BANK+1 : BANK-INDEX_SIZE+1
)(
	input logic `VADDR_BUS pc,
	input logic [31: 0] path_hist,
	input logic [COMPRESS_LENGTH-1: 0] compress,
	output logic [INDEX_SIZE-1: 0] index
);
	// logic [INDEX_SIZE-1: 0] func_out;
	// F #(INDEX_SIZE)func(path_hist, func_out);
	// assign index = pc ^ (pc >> SHIFT_SIZE) ^ compress ^ func_out;

	// maintain path_hist is difficult
	// may be path hist can also fold
	assign index = pc ^ (pc >> SHIFT_SIZE) ^ compress;
endmodule

module GetTag #(
	parameter COMPRESS1_LENGTH=8,
	parameter COMPRESS2_LENGTH=8,
	parameter INDEX_SIZE=8,
	parameter TAG_SIZE=7
)(
	input logic `VADDR_BUS pc,
	input logic [31: 0] path_hist,
	input logic [INDEX_SIZE-1: 0] compress_index1,
	input logic [INDEX_SIZE-1: 0] compress_index2,
	input logic [COMPRESS1_LENGTH-1: 0] compress1,
	input logic [COMPRESS2_LENGTH-1: 0] compress2,
	output logic [TAG_SIZE-1: 0] tag
);
	logic [COMPRESS1_LENGTH-1: 0] compress_index, tag_before, tag_expand;
	// logic [TAG_SIZE-1: 0] func_out;
	// F #(TAG_SIZE)func(path_hist, func_out);
	assign compress_index = (compress_index1 << 2) ^ pc ^ (pc >> 2) ^ compress_index2;
	// assign tag_before = (compress_index >> 1) ^ (compress_index[0] << 10) ^ func_out ^ (compress1 ^ (compress2 << 1));
	assign tag_before = (compress_index >> 1) ^ (compress_index[0] << 10) ^ (compress1 ^ (compress2 << 1));
	assign tag_expand = tag_before ^ (tag_before >> TAG_SIZE);
	assign tag = tag_expand[TAG_SIZE-1: 0];
endmodule