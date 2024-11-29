`include "../../defines/defines.svh"

module Tage(
    input logic clk,
    input logic rst,
    BpuTageIO.tage tage_io
);
`ifdef DIFFTEST
	typedef struct packed {
`else
	typedef struct {
`endif
		logic en;
		logic `N(`TAGE_SET_WIDTH) lookup_idx;
		logic `N(`TAGE_TAG_SIZE) lookup_tag;
		logic `N(`SLOT_NUM) update_en;
		logic `N(`SLOT_NUM) realTaken;
		logic `N(`SLOT_NUM) update_u_en;
		logic `N(`SLOT_NUM) provider;
		logic `N(`SLOT_NUM) alloc;
		logic `N(`SLOT_NUM) predError;
		logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) update_u;
		logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) update_origin_ctr;
		logic `N(`TAGE_TAG_SIZE) update_tag;
		logic `N(`TAGE_SET_WIDTH) update_idx;
	} BankCtrl;
	BankCtrl bank_ctrl `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) table_hits `N(`TAGE_BANK);
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) table_hits_reorder;
	logic `N(`SLOT_NUM) table_u `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) prediction `N(`TAGE_BANK);
	logic `ARRAY(`SLOT_NUM, `TAGE_ALT_CTR) altCtr;
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) provider;
	parameter [12: 0] tage_set_size `N(`TAGE_BANK) = {13'd2048, 13'd2048, 13'd2048, 13'd2048};
    generate;
        for(genvar i=0; i<`TAGE_BANK; i++)begin
			localparam SET_SIZE = tage_set_size[i];
			GetIndex #(
				.COMPRESS_LENGTH(`TAGE_SET_WIDTH),
				.INDEX_SIZE($clog2(SET_SIZE)),
				.BANK(i)
			)get_index(
				.pc(tage_io.pc),
				// .path_hist(tage_io.history.phist),
				.compress(tage_io.history.tage_history.fold_idx[i]),
				.index(bank_ctrl[i].lookup_idx)
			);
			GetTag #(
				.COMPRESS1_LENGTH(12),
				.COMPRESS2_LENGTH(10),
				.INDEX_SIZE(`TAGE_SET_WIDTH),
				.TAG_SIZE(`TAGE_TAG_SIZE)
			) get_tag(
				.pc(tage_io.pc),
				// .path_hist(tage_io.history.phist),
				.compress_index1(i == 0 ? `TAGE_SET_WIDTH'b0 : tage_io.history.tage_history.fold_idx[i-1]),
				.compress_index2(tage_io.history.tage_history.fold_idx[i]),
				.compress1(tage_io.history.tage_history.fold_tag1[i]),
				.compress2(tage_io.history.tage_history.fold_tag2[i]),
				.tag(bank_ctrl[i].lookup_tag)
			);
			assign bank_ctrl[i].en = 1'b1;
			TageTable #(
				.HEIGHT(SET_SIZE)
			)tage_table(
				.clk(clk),
				.rst(rst),
				.en(bank_ctrl[i].en & ~tage_io.redirect.stall),
				.realTaken(bank_ctrl[i].realTaken),
				.update_en(bank_ctrl[i].update_en),
				.lookup_idx(bank_ctrl[i].lookup_idx),
				.lookup_tag(bank_ctrl[i].lookup_tag),
				.provider(bank_ctrl[i].provider),
				.alloc(bank_ctrl[i].alloc),
				.predError(bank_ctrl[i].predError),
				.update_u_en(bank_ctrl[i].update_u_en),
				.update_u(bank_ctrl[i].update_u),
				.update_origin_ctr(bank_ctrl[i].update_origin_ctr),
				.update_idx(bank_ctrl[i].update_idx),
				.update_tag(bank_ctrl[i].update_tag),
				.lookup_match(table_hits[i]),
				.u(table_u[i]),
				.taken(prediction[i]),
				.lookup_ctr(tage_io.meta.tage_ctrs[i]),
				.lookup_u(tage_io.meta.u[i])
			);
        end
    endgenerate

	logic base_we;
	logic `N($clog2(`TAGE_BASE_SIZE)) base_lookup_idx, base_update_idx;
	logic `ARRAY(`SLOT_NUM, `TAGE_BASE_CTR) base_ctr, base_update_ctr, base_ctr_inc;
	assign base_lookup_idx = tage_io.pc[`TAGE_BASE_WIDTH+1: `INST_OFFSET] ^ tage_io.pc[`TAGE_BASE_WIDTH * `INST_OFFSET + 1 : `TAGE_BASE_WIDTH + `INST_OFFSET];
	MPRAM #(
		.WIDTH((`TAGE_BASE_CTR * `SLOT_NUM)),
		.DEPTH(`TAGE_BASE_SIZE),
		.READ_PORT(1),
		.WRITE_PORT(1),
		.BANK_SIZE(`TAGE_BASE_SLICE),
		.RESET(1)
	) base_table (
		.clk(clk),
		.rst(rst),
		.en(!tage_io.redirect.stall),
		.we(base_we),
		.waddr(base_update_idx),
		.raddr(base_lookup_idx),
		.rdata(base_ctr),
		.wdata(base_update_ctr),
		.ready(tage_io.ready)
	);

	logic `N(`SLOT_NUM) tage_prediction;
	generate;
		for(genvar br=0; br<`SLOT_NUM; br++)begin
			for(genvar bank=0; bank<`TAGE_BANK; bank++)begin
				assign table_hits_reorder[br][bank] = table_hits[bank][br];
			end
			PSelector #(`TAGE_BANK) selector_provider(table_hits_reorder[br], provider[br]);
			assign tage_prediction[br] = |provider[br] ? |(prediction[br] & provider[br]) : base_ctr[br][`TAGE_BASE_CTR-1];
			assign tage_io.prediction[br] = tage_prediction[br];
			assign tage_io.meta.altPred[br] = base_ctr[br][`TAGE_BASE_CTR-1];
		end
	endgenerate
	assign tage_io.meta.provider = provider;
	assign tage_io.meta.base_ctr = base_ctr;
	assign tage_io.meta.predTaken = tage_prediction;

	// update
	logic `N(`SLOT_NUM) predError, predTaken;
	logic `N(`SLOT_NUM) u_slot_en;
	logic `N(`SLOT_NUM) update_en;
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) u_provider;
	logic [`TAGE_BANK-1: 0][`SLOT_NUM-1: 0][`TAGE_U_SIZE-1: 0] update_u_origin, update_u;
	logic `ARRAY(`TAGE_BANK, `SLOT_NUM) update_u_en;
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) update_u_valid;
	BTBUpdateInfo btbEntry;
	TageMeta meta;
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) alloc;
	logic `N(`SLOT_NUM) alloc_combine;
	logic `N(`SLOT_NUM) altPred;
	logic `N(`SLOT_NUM) dec_use;
	logic `ARRAY(`TAGE_BANK, `SLOT_NUM * `TAGE_CTR_SIZE) u_ctrs;

	assign predTaken = meta.predTaken;
	assign predError = predTaken ^ tage_io.updateInfo.realTaken;
	assign btbEntry = tage_io.updateInfo.btbEntry;
	assign meta = tage_io.updateInfo.meta.tage;
	assign u_provider = meta.provider;
	assign update_u_origin = meta.u;
	assign update_en = u_slot_en;
	assign altPred = meta.altPred;
	assign dec_use = altPred ^ predTaken;
	assign u_ctrs = meta.tage_ctrs;
generate
	for(genvar i=0; i<`SLOT_NUM; i++)begin
		UpdateCounter #(`TAGE_BASE_CTR) updateCounter (meta.base_ctr[i], tage_io.updateInfo.realTaken[i], base_ctr_inc[i]);
		assign base_update_ctr[i] = u_slot_en[i] ? base_ctr_inc[i] : meta.base_ctr[i];
	end
	assign base_we = |u_slot_en;
	assign base_update_idx = tage_io.updateInfo.start_addr[`TAGE_BASE_WIDTH+1: `INST_OFFSET] ^ tage_io.updateInfo.start_addr[`TAGE_BASE_WIDTH * `INST_OFFSET + 1 : `TAGE_BASE_WIDTH + `INST_OFFSET];

	for(genvar i=0; i<`SLOT_NUM-1; i++)begin
		assign u_slot_en[i] = tage_io.update & tage_io.updateInfo.allocSlot[i] & ~btbEntry.slots[i].carry;
	end
	assign u_slot_en[`SLOT_NUM-1] = tage_io.update & tage_io.updateInfo.allocSlot[`SLOT_NUM-1] & (btbEntry.tailSlot.br_type == CONDITION) & ~btbEntry.tailSlot.carry;
	for(genvar i=0; i<`TAGE_BANK; i++)begin
		logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) bank_u;
		assign bank_u = update_u_origin[i];
		for(genvar j=0; j<`SLOT_NUM; j++)begin
			assign update_u_valid[j][i] = |bank_u[j];
		end
	end
	for(genvar i=0; i<`SLOT_NUM; i++)begin
		PRSelector #(`TAGE_BANK) selector_alloc (~update_u_valid[i], alloc[i]);
		assign alloc_combine[i] = (|alloc);
		for(genvar j=0; j<`TAGE_BANK; j++)begin
			logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) bank_u;
			assign bank_u = update_u_origin[j];
			UpdateCounter #(`TAGE_U_SIZE) updateCounter (bank_u[i], alloc_combine[i], update_u[j][i]);
			assign update_u_en[j][i] = (~(alloc_combine[i]) & predError[i]) |
									   (u_provider[i][j] & dec_use[i]);
		end
	end


	for(genvar i=0; i<`TAGE_BANK; i++)begin
		assign bank_ctrl[i].update_en = update_en;
		assign bank_ctrl[i].provider = {u_provider[1][i], u_provider[0][i]};
		assign bank_ctrl[i].alloc = {alloc[1][i], alloc[0][i]};
		assign bank_ctrl[i].predError = predError;
		assign bank_ctrl[i].realTaken = tage_io.updateInfo.realTaken;
		assign bank_ctrl[i].update_u = update_u;
		assign bank_ctrl[i].update_u_en = update_u_en;
		assign bank_ctrl[i].update_origin_ctr = u_ctrs[i];
		localparam SET_SIZE = tage_set_size[i];
		GetIndex #(
			.COMPRESS_LENGTH(`TAGE_SET_WIDTH),
			.INDEX_SIZE($clog2(SET_SIZE)),
			.BANK(i)
		)get_index(
			.pc(tage_io.updateInfo.start_addr),
			// .path_hist(tage_io.history.phist),
			.compress(tage_io.updateInfo.redirectInfo.tage_history.fold_idx[i]),
			.index(bank_ctrl[i].update_idx)
		);
		GetTag #(
			.COMPRESS1_LENGTH(12),
			.COMPRESS2_LENGTH(10),
			.INDEX_SIZE(`TAGE_SET_WIDTH),
			.TAG_SIZE(`TAGE_TAG_SIZE)
		) get_tag(
			.pc(tage_io.updateInfo.start_addr),
			// .path_hist(tage_io.history.phist),
			.compress_index1(i == 0 ? `TAGE_SET_WIDTH'b0 : tage_io.updateInfo.redirectInfo.tage_history.fold_idx[i-1]),
			.compress_index2(tage_io.updateInfo.redirectInfo.tage_history.fold_idx[i]),
			.compress1(tage_io.updateInfo.redirectInfo.tage_history.fold_tag1[i]),
			.compress2(tage_io.updateInfo.redirectInfo.tage_history.fold_tag2[i]),
			.tag(bank_ctrl[i].update_tag)
		);
	end
endgenerate

	`Log(DLog::Debug, T_TAGE, ~tage_io.redirect.stall, $sformatf("tage lookup. %2b %8h %h %h", tage_prediction, tage_io.pc, bank_ctrl[0].lookup_idx, bank_ctrl[0].lookup_tag))
	`Log(DLog::Debug, T_TAGE, tage_io.update, $sformatf("tage update. %2b %8h %h %h", update_en, tage_io.updateInfo.start_addr, bank_ctrl[0].update_idx, bank_ctrl[0].update_tag))
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
	input logic `N(`SLOT_NUM) update_en,
	input logic `N(`SLOT_NUM) realTaken,
	input logic `N(`SLOT_NUM) provider,
	input logic `N(`SLOT_NUM) alloc,
	input logic `N(`SLOT_NUM) predError,
	input logic `N(`SLOT_NUM) update_u_en,
	input logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) update_u,
	input logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) update_origin_ctr,
	input logic `N(`TAGE_TAG_SIZE) update_tag,
	input logic `N(ADDR_WIDTH) update_idx,
	output logic `N(`SLOT_NUM) lookup_match,
	output logic `N(`SLOT_NUM) u,
	output logic `N(`SLOT_NUM) taken,
	// meta
	output logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) lookup_ctr,
	output logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) lookup_u
);
	logic `ARRAY(`SLOT_NUM, `TAGE_TAG_SIZE) match_tag;
	always_ff @(posedge clk)begin
		if(en)begin
			match_tag <= {`SLOT_NUM{lookup_tag}};
		end
	end
	logic `ARRAY(`SLOT_NUM, `TAGE_TAG_SIZE) search_tag;
	logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) update_ctr, update_ctr_provider;
	generate;
		for(genvar i=0; i<`SLOT_NUM; i++)begin
			assign lookup_match[i] = search_tag[i] == match_tag[i];
			assign u[i] = lookup_u[i] != 0;
			assign taken[i] = lookup_ctr[i][`TAGE_CTR_SIZE-1];
			assign update_ctr[i] = alloc[i] ? (realTaken[i] ? (1 << (`TAGE_CTR_SIZE - 1)) : (1 << (`TAGE_CTR_SIZE - 2))) : update_ctr_provider[i];
			UpdateCounter #(`TAGE_CTR_SIZE) updateCtr (update_origin_ctr[i], realTaken[i], update_ctr_provider[i]);
		end
	endgenerate

	for(genvar i=0; i<`SLOT_NUM; i++)begin
		MPRAM #(
			.WIDTH((`TAGE_CTR_SIZE+`TAGE_TAG_SIZE)),
			.DEPTH(HEIGHT),
			.READ_PORT(1),
			.WRITE_PORT(1),
			.BANK_SIZE(`TAGE_SLICE),
			.RESET(1)
		)tage_bank(
			.clk(clk),
			.rst(rst),
			.en(en),
			.we(update_en[i] & (provider[i] | alloc[i])),
			.waddr(update_idx),
			.raddr(lookup_idx),
			.rdata({search_tag[i], lookup_ctr[i]}),
			.wdata({update_tag, update_ctr[i]}),
			.ready()
		);

		MPRAM #(
			.WIDTH(`TAGE_U_SIZE),
			.DEPTH(HEIGHT),
			.READ_PORT(1),
			.WRITE_PORT(1),
			.BANK_SIZE(`TAGE_SLICE),
			.RESET(1)
		) u_bank (
			.clk(clk),
			.rst(rst),
			.en(en),
			.we(update_en[i] & (update_u_en[i] | alloc[i])),
			.waddr(update_idx),
			.raddr(lookup_idx),
			.rdata(lookup_u[i]),
			.wdata(update_u[i]),
			.ready()
		);
		end

endmodule

// module F #(
// 	parameter INDEX_SIZE=7
// )(
// 	input logic [31: 0] path_hist,
// 	output logic [INDEX_SIZE-1: 0] out
// );
// 	assign out = path_hist ^ (path_hist >> INDEX_SIZE);
// endmodule

module GetIndex #(
	parameter COMPRESS_LENGTH=8,
	parameter INDEX_SIZE=7,
	parameter BANK=0,
	parameter SHIFT_SIZE=INDEX_SIZE > BANK ? INDEX_SIZE-BANK+1 : BANK-INDEX_SIZE+1
)(
	input logic `VADDR_BUS pc,
	// input logic [31: 0] path_hist,
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
	// input logic [31: 0] path_hist,
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
