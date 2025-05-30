`include "../../defines/defines.svh"

module Tage(
    input logic clk,
    input logic rst,
    BpuTageIO.tage tage_io
);

	typedef struct packed {
		logic en;
		logic `N(`TAGE_SET_WIDTH) lookup_idx;
		logic `N(`TAGE_TAG_SIZE) lookup_tag;
		logic `N(`SLOT_NUM) update_en;
		logic `N(`SLOT_NUM) update_u_en;
		logic `N(`SLOT_NUM) provider;
		logic `N(`SLOT_NUM) alloc;
		logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) update_u;
		logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) update_ctr;
		logic `N(`TAGE_TAG_SIZE) update_tag;
		logic `N(`TAGE_SET_WIDTH) update_idx;
	} BankCtrl;
	BankCtrl bank_ctrl `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) table_hits `N(`TAGE_BANK);
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) table_hits_reorder;
	logic `N(`SLOT_NUM) table_u `N(`TAGE_BANK);
	logic `N(`SLOT_NUM) prediction `N(`TAGE_BANK);
	logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) lookup_ctr `N(`TAGE_BANK);
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) pred_reverse;
	logic `ARRAY(`SLOT_NUM, `TAGE_ALT_CTR) altCtr;
	logic `ARRAY(`SLOT_NUM, `TAGE_BANK) provider;
	logic `ARRAY(`TAGE_BANK, `TAGE_SET_WIDTH) lookup_idx_n;
	logic `ARRAY(`TAGE_BANK, `TAGE_TAG_SIZE) lookup_tag_n;
	logic `N(`SLOT_NUM) reset_u;
	logic `ARRAY(`SLOT_NUM, `TAGE_RESETU_CTR+1) resetu_ctrs;
	logic `ARRAY(`SLOT_NUM, $clog2(`TAGE_BANK)+1) update_u_cnt;

	parameter [`TAGE_BANK*16-1: 0] tage_set_size  = `TAGE_SET_SIZE;
    generate;
        for(genvar i=0; i<`TAGE_BANK; i++)begin
			localparam SET_SIZE = tage_set_size[i * 16 +: 16];
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
			always_ff @(posedge clk)begin
				if(~tage_io.redirect.stall)begin
					lookup_idx_n[i] <= bank_ctrl[i].lookup_idx;
					lookup_tag_n[i] <= bank_ctrl[i].lookup_tag;
				end
			end
			assign bank_ctrl[i].en = 1'b1;
			TageTable #(
				.HEIGHT(SET_SIZE)
			)tage_table(
				.clk(clk),
				.rst(rst),
				.en(bank_ctrl[i].en & ~tage_io.redirect.stall),
				.update_en(bank_ctrl[i].update_en),
				.lookup_idx(bank_ctrl[i].lookup_idx),
				.lookup_tag(bank_ctrl[i].lookup_tag),
				.provider(bank_ctrl[i].provider),
				.alloc(bank_ctrl[i].alloc),
				.update_u_en(bank_ctrl[i].update_u_en),
				.update_u(bank_ctrl[i].update_u),
				.reset_u(reset_u),
				.update_ctr(bank_ctrl[i].update_ctr),
				.update_idx(bank_ctrl[i].update_idx),
				.update_tag(bank_ctrl[i].update_tag),
				.lookup_match(table_hits[i]),
				.u(table_u[i]),
				.taken(prediction[i]),
				.lookup_ctr(lookup_ctr[i]),
				.lookup_u(tage_io.meta.u[i])
			);
			assign tage_io.meta.tage_ctrs[i] = lookup_ctr[i];
        end
    endgenerate

	logic base_we, base_commit_en;
	logic `N($clog2(`TAGE_BASE_SIZE)) base_lookup_idx, base_update_idx;
	logic `ARRAY(`SLOT_NUM, `TAGE_BASE_CTR) base_ctr, base_update_ctr, base_ctr_inc, base_commit_ctr;
	assign base_lookup_idx = tage_io.pc[`TAGE_BASE_WIDTH+`INST_OFFSET-1: `INST_OFFSET] ^
							 tage_io.pc[`VADDR_SIZE-1: `VADDR_SIZE-`TAGE_BASE_WIDTH];
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
		.rst_sync(1'b0),
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
				assign pred_reverse[br][bank] = prediction[bank][br];
			end
			PSelector #(`TAGE_BANK) selector_provider(table_hits_reorder[br], provider[br]);
			assign tage_prediction[br] = |table_hits_reorder[br] ? |(pred_reverse[br] & provider[br]) : base_ctr[br][`TAGE_BASE_CTR-1];
			assign tage_io.prediction[br] = altCtr[br][`TAGE_ALT_CTR-1] ? base_ctr[br][`TAGE_BASE_CTR-1] : tage_prediction[br];
			logic `N($clog2(`TAGE_BANK)) provider_idx;
			PEncoder #(`TAGE_BANK) encoder_provider (table_hits_reorder[br], provider_idx);
			assign tage_io.provider_ctr[br] = |table_hits_reorder[br] ? lookup_ctr[provider_idx] : {1'b1, {`TAGE_CTR_SIZE-1{1'b0}}};
			assign tage_io.meta.tagePred[br] = tage_prediction[br];
			assign tage_io.use_tage[br] = ~altCtr[br][`TAGE_ALT_CTR-1] & (|table_hits_reorder[br]);
		end
	endgenerate
	assign tage_io.meta.provider = provider;
	assign tage_io.meta.base_ctr = base_ctr;
	assign tage_io.meta.predTaken = tage_io.prediction;

	// update
	logic `N(`SLOT_NUM) predError, predTaken;
	logic `N(`SLOT_NUM) u_slot_en, base_provider;
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
	logic `TENSOR(`TAGE_BANK, `SLOT_NUM, `TAGE_CTR_SIZE) u_ctrs;

	assign predTaken = meta.predTaken;
	assign predError = predTaken ^ tage_io.updateInfo.realTaken;
	assign btbEntry = tage_io.updateInfo.btbEntry;
	assign meta = tage_io.updateInfo.meta.tage;
	assign u_provider = meta.provider;
	assign update_u_origin = meta.u;
	assign update_en = u_slot_en;
generate
	for(genvar i=0; i<`SLOT_NUM; i++)begin
		assign altPred[i] = meta.base_ctr[i][`TAGE_BASE_CTR-1];
	end
endgenerate
	assign dec_use = altPred ^ meta.tagePred;

	CAMQueue #(
		`TAGE_COMMIT_SIZE, 
		`TAGE_BASE_WIDTH, 
		`TAGE_BASE_CTR * `SLOT_NUM
	) base_cam (
		.clk,
		.rst,
		.we(base_we),
		.wtag(base_update_idx),
		.wdata(base_update_ctr),
		.rtag(base_update_idx),
		.rhit(base_commit_en),
		.rdata(base_commit_ctr)
	);
generate
	for(genvar i=0; i<`SLOT_NUM; i++)begin
		logic `N(`TAGE_BASE_CTR) base_ctr_i;
		assign base_ctr_i = base_commit_en ? base_commit_ctr[i] : meta.base_ctr[i];
		UpdateCounter #(`TAGE_BASE_CTR) updateCounter (base_ctr_i, tage_io.updateInfo.realTaken[i], base_ctr_inc[i]);
		assign base_update_ctr[i] = u_slot_en[i] ? base_ctr_inc[i] : base_ctr_i;
		assign base_provider[i] = u_slot_en[i] & ~(|u_provider[i]);
	end
	assign base_we = |base_provider;
	assign base_update_idx = tage_io.updateInfo.start_addr[`TAGE_BASE_WIDTH+`INST_OFFSET-1: `INST_OFFSET] ^
							 tage_io.updateInfo.start_addr[`VADDR_SIZE-1: `VADDR_SIZE-`TAGE_BASE_WIDTH];

	for(genvar i=0; i<`SLOT_NUM-1; i++)begin
		assign u_slot_en[i] = tage_io.update & tage_io.updateInfo.allocSlot[i] & btbEntry.slots[i].en & ~btbEntry.slots[i].carry;
	end
	assign u_slot_en[`SLOT_NUM-1] = tage_io.update & tage_io.updateInfo.allocSlot[`SLOT_NUM-1] & btbEntry.tailSlot.en & (btbEntry.tailSlot.br_type == CONDITION) & ~btbEntry.tailSlot.carry;
	for(genvar i=0; i<`TAGE_BANK; i++)begin
		logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) bank_u;
		assign bank_u = update_u_origin[i];
		for(genvar j=0; j<`SLOT_NUM; j++)begin
			assign update_u_valid[j][i] = |bank_u[j];
		end
	end
	for(genvar i=0; i<`SLOT_NUM; i++)begin
		logic `N(`TAGE_BANK) provider_mask_low, provider_mask;
		LowMaskGen #(`TAGE_BANK) low_mask_provider (u_provider[i], provider_mask_low);
		assign provider_mask = ~(|u_provider[i]) ? {`TAGE_BANK{1'b1}} : provider_mask_low & ~u_provider[i];
		ParallelAdder #(1, `TAGE_BANK) adder_update_u (update_u_valid[i], update_u_cnt[i]);
		PRSelector #(`TAGE_BANK) selector_alloc (~update_u_valid[i] & provider_mask & {`TAGE_BANK{predError[i]}}, alloc[i]);
		assign alloc_combine[i] = (|alloc[i]);
		for(genvar j=0; j<`TAGE_BANK; j++)begin
			logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) bank_u;
			assign bank_u = update_u_origin[j];
			UpdateCounter #(`TAGE_U_SIZE) updateCounter (bank_u[i], ~predError[i], update_u[j][i]);
			assign update_u_en[j][i] = (~alloc_combine[i] & predError[i]) |
									   (u_provider[i][j] & dec_use[i]);
		end

		logic `N(`TAGE_ALT_CTR) altCtr_d;
		UpdateCounter #(`TAGE_ALT_CTR) updateAltCtr (altCtr[i], ~(tage_io.updateInfo.realTaken[i] ^ altPred[i]), altCtr_d);
		always_ff @(posedge clk, negedge rst)begin
			if(rst == `RST)begin
				altCtr[i] <= 0;
			end
			else begin
				if(update_en[i] & dec_use)begin
					altCtr[i] <= altCtr_d;
				end
			end
		end
	end

	always_ff @(posedge clk, negedge rst)begin
		if(rst == `RST)begin
			reset_u <= 0;
			resetu_ctrs <= 0;
		end
		else begin
			for(int i=0; i<`SLOT_NUM; i++)begin
				if(resetu_ctrs[i] == {`TAGE_RESETU_CTR{1'b1}})begin
					resetu_ctrs[i] <= 0;
				end
				else if(update_en[i] & predError[i])begin
					if(update_u_cnt[i] < `TAGE_BANK / 2)begin
						resetu_ctrs[i] <= resetu_ctrs[i] - 1;
					end
					else begin
						resetu_ctrs[i] <= resetu_ctrs[i] + 1;
					end
				end
				reset_u <= resetu_ctrs[i] == {`TAGE_RESETU_CTR{1'b1}};
			end
		end
	end


	for(genvar i=0; i<`TAGE_BANK; i++)begin
		logic bank_commit_en;
		logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) bank_commit_ctr;
		logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) update_ctr, update_ctr_provider;
		logic `N(`SLOT_NUM) bank_alloc;
		localparam SET_SIZE = tage_set_size[i*16 +: 16];
		logic `N($clog2(SET_SIZE)) update_idx;
		logic `N(`TAGE_TAG_SIZE) update_tag;
		GetIndex #(
			.COMPRESS_LENGTH(`TAGE_SET_WIDTH),
			.INDEX_SIZE($clog2(SET_SIZE)),
			.BANK(i)
		)get_index(
			.pc(tage_io.updateInfo.start_addr),
			// .path_hist(tage_io.history.phist),
			.compress(tage_io.updateInfo.redirectInfo.tage_history.fold_idx[i]),
			.index(update_idx)
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
			.tag(update_tag)
		);
		CAMQueue #(
			`TAGE_COMMIT_SIZE, 
			`TAGE_SET_WIDTH, 
			`TAGE_CTR_SIZE * `SLOT_NUM
		) bank_cam (
			.clk,
			.rst,
			.we((|(update_en & (bank_ctrl[i].provider | bank_ctrl[i].alloc)))),
			.wtag(update_idx),
			.wdata(update_ctr),
			.rtag(update_idx),
			.rhit(bank_commit_en),
			.rdata(bank_commit_ctr)
		);
		assign u_ctrs[i] = bank_commit_en ? bank_commit_ctr : meta.tage_ctrs[i];
		for(genvar j=0; j<`SLOT_NUM; j++)begin
			assign bank_alloc[j] = alloc[j][i];
			assign update_ctr[j] = !update_en[j] ? u_ctrs[i][j] : 
									bank_alloc[j] & ~bank_commit_en ? 
										(tage_io.updateInfo.realTaken[j] ? 
										(1 << (`TAGE_CTR_SIZE - 1)) : 
										(1 << (`TAGE_CTR_SIZE - 1)) - 1) : 
									update_ctr_provider[j];
			UpdateCounter #(`TAGE_CTR_SIZE) updateCtr (u_ctrs[i][j], tage_io.updateInfo.realTaken[j], update_ctr_provider[j]);
		end
		assign bank_ctrl[i].update_en = update_en;
		assign bank_ctrl[i].provider = {u_provider[1][i], u_provider[0][i]};
		assign bank_ctrl[i].alloc = bank_alloc;
		assign bank_ctrl[i].update_u = update_u[i];
		assign bank_ctrl[i].update_u_en = update_u_en[i];
		assign bank_ctrl[i].update_ctr = update_ctr;
		assign bank_ctrl[i].update_idx = update_idx;
		assign bank_ctrl[i].update_tag = update_tag;
	end
endgenerate

`ifdef DIFFTEST
	`Log(DLog::Debug, T_TAGE, ~tage_io.redirect.stall, $sformatf("tage lookup. %2b %8h %h %h", tage_prediction, tage_io.pc, bank_ctrl[0].lookup_idx, bank_ctrl[0].lookup_tag))
	`Log(DLog::Debug, T_TAGE, tage_io.update, $sformatf("tage update. %2b %8h %h %h", update_en, tage_io.updateInfo.start_addr, bank_ctrl[0].update_idx, bank_ctrl[0].update_tag))
`endif
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
	input logic `N(`SLOT_NUM) provider,
	input logic `N(`SLOT_NUM) alloc,
	input logic `N(`SLOT_NUM) update_u_en,
	input logic `N(`SLOT_NUM) reset_u,
	input logic `ARRAY(`SLOT_NUM, `TAGE_U_SIZE) update_u,
	input logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) update_ctr,
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
	generate;
		for(genvar i=0; i<`SLOT_NUM; i++)begin
			assign lookup_match[i] = search_tag[i] == match_tag[i];
			assign u[i] = lookup_u[i] != 0;
			assign taken[i] = lookup_ctr[i][`TAGE_CTR_SIZE-1];
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
			.rst_sync(1'b0),
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
			.RESET(1),
			.ENABLE_SYNC_RST(1)
		) u_bank (
			.clk(clk),
			.rst(rst),
			.rst_sync(reset_u[i]),
			.en(en),
			.we(update_en[i] & (update_u_en[i] | alloc[i])),
			.waddr(update_idx),
			.raddr(lookup_idx),
			.rdata(lookup_u[i]),
			.wdata(update_u[i] & {`TAGE_U_SIZE{~alloc[i]}}),
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
