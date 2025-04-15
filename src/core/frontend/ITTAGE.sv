`include "../../defines/defines.svh"

module ITTAGE(
    input logic clk,
    input logic rst,
    BpuITTAGEIO.ittage io
);
    typedef struct packed {
    logic `N(`ITTAGE_U_SIZE) u;
    logic `N(`ITTAGE_CTR_SIZE) ctr;
    logic `N(`ITTAGE_OFFSET) offset;
    } ITTageData;
    logic `N(`ITTAGE_BANK) table_hits, table_hits_rev;
    ITTageData `N(`ITTAGE_BANK) lookup_data;
    ITTageData `N(`ITTAGE_BANK) lookup_data_rev;
    logic `N(`ITTAGE_BANK) provider, provider_s3;
    logic lookup_valid, lookup_valid_n;
    ITTageData select_data, select_alt_data, select_data_s3;
    logic `N(`ITTAGE_OFFSET) offset_s3, alt_offset_s3;
    logic `N(`ITTAGE_REGION) lookup_region;

    logic update_en;
    ITTageMeta meta;
    BTBUpdateInfo btbEntry;
    logic `N(`ITTAGE_BANK) alloc, update_u_en, update_commit_en, provider_mask_low, provider_mask;
    logic `ARRAY(`ITTAGE_BANK, `ITTAGE_CTR_SIZE) update_ctr, update_commit_ctr;
    logic `ARRAY(`ITTAGE_BANK, `ITTAGE_U_SIZE) update_u;
    logic reset_u;
    logic `N(`ITTAGE_RESETU_CTR) resetu_ctr;
    logic pred_error, alt_pred_error;
    logic `N($clog2(`ITTAGE_BANK)+1) update_u_cnt;


	parameter [`ITTAGE_BANK*16-1: 0] ittage_set_size  = `ITTAGE_SET_SIZE;
    parameter [`ITTAGE_BANK*16-1: 0] ittage_hist_length = `ITTAGE_HIST_LENGTH;
generate
    for(genvar i=0; i<`ITTAGE_BANK; i++)begin
        logic `N($clog2(ittage_set_size[i*16 +: 16])) lookup_idx, update_idx;
        logic `N(`ITTAGE_TAG_SIZE) lookup_tag, update_tag;
        SCGIndex #(
            $clog2(ittage_set_size[i*16 +: 16]),
            ittage_hist_length[i*16 +: 16],
            `SC_GHIST_WIDTH
        ) gindex (io.pc, io.history.sc_ghist, lookup_idx);
        SCGTag #(
            `ITTAGE_TAG_SIZE,
            ittage_hist_length[i*16 +: 16],
            `SC_GHIST_WIDTH
        ) gtag (io.pc, io.history.sc_ghist, lookup_tag);
        SCGIndex #(
            $clog2(ittage_set_size[i*16 +: 16]),
            ittage_hist_length[i*16 +: 16],
            `SC_GHIST_WIDTH
        ) gindex_update (io.updateInfo.start_addr, io.updateInfo.redirectInfo.sc_ghist, update_idx);
        SCGTag #(
            `ITTAGE_TAG_SIZE,
            ittage_hist_length[i*16 +: 16],
            `SC_GHIST_WIDTH
        ) gtag_update (io.updateInfo.start_addr, io.updateInfo.redirectInfo.sc_ghist, update_tag);
        ITTAGETable #(
            .HEIGHT(ittage_set_size[i*16 +: 16])
        ) ittage_table (
            .clk,
            .rst,
            .en(~io.redirect.stall),
            .lookup_idx(lookup_idx),
            .lookup_tag(lookup_tag),
            .lookup_match(table_hits[i]),
            .lookup_offset(lookup_data[i].offset),
            .lookup_ctr(lookup_data[i].ctr),
            .lookup_u(lookup_data[i].u),
            .update_en(update_en),
            .provider(meta.provider[i]),
            .alloc(alloc[i]),
            .update_u_en(update_u_en[i]),
            .update_u(update_u[i]),
            .reset_u(reset_u),
            .update_ctr(update_ctr[i]),
            .update_idx(update_idx),
            .update_tag(update_tag),
            .update_offset(io.updateInfo.target_pc[`ITTAGE_OFFSET: 1])
        );
        CAMQueue #(
            `ITTAGE_COMMIT_SIZE,
            $clog2(ittage_set_size[i*16 +: 16]),
            `ITTAGE_CTR_SIZE
        ) bank_cam (
            .clk,
            .rst,
            .we(update_en & (meta.provider[i] | alloc[i])),
            .wtag(update_idx),
            .wdata(update_ctr[i]),
            .rtag(update_idx),
            .rhit(update_commit_en[i]),
            .rdata(update_commit_ctr[i])
        );
        assign lookup_data_rev[i] = lookup_data[`ITTAGE_BANK-1-i];
        assign table_hits_rev[i] = table_hits[`ITTAGE_BANK-1-i];
    end
endgenerate
`ifdef FEAT_ITTAGE_REGION
    ITTAGERegion region(
        .clk,
        .rst,
        .en(io.last_stage_ind & lookup_valid_n),
        .lookup_idx(io.region_idx),
        .lookup_region(lookup_region),
        .update_tag(io.update_tag),
        .tag_hit_idx(io.update_region_idx),
        .update(update_en),
        .update_region(io.updateInfo.target_pc[`VADDR_SIZE-1: `VADDR_SIZE-`ITTAGE_REGION])
    );
`endif

// lookup
    OldestSelect #(`ITTAGE_BANK, 1, $bits(ITTageData)) select_provider_data(
        table_hits, lookup_data, lookup_valid, select_data
    );
    OldestSelect #(`ITTAGE_BANK, 1, $bits(ITTageData)) select_alt_provider(
        table_hits_rev, lookup_data_rev, , select_alt_data
    );
    PSelector #(`ITTAGE_BANK) select_provider(table_hits, provider);
    always_ff @(posedge clk)begin
        select_data_s3 <= select_data;
        provider_s3 <= provider;
        alt_offset_s3 <= select_alt_data.offset;
        lookup_valid_n <= lookup_valid;
    end
    assign io.meta.ctr = select_data_s3.ctr;
    assign io.meta.u = select_data_s3.u;
    assign io.meta.provider = provider_s3;
    assign io.meta.offset = select_data_s3.offset;
    assign io.meta.alt_offset = alt_offset_s3;
`ifdef FEAT_ITTAGE_REGION
    assign io.meta.region = lookup_region;
    assign io.target = {lookup_region, select_data_s3.offset, 1'b0};
`else
    assign io.target = {select_data_s3.offset, 1'b0};
`endif

// update
    assign update_en = io.update & io.updateInfo.tailTaken & btbEntry.tailSlot.en & 
        ((btbEntry.tailSlot.br_type == INDIRECT) | (btbEntry.tailSlot.br_type == INDIRECT_CALL));
    assign meta = io.updateInfo.meta.ittage;
    assign btbEntry = io.updateInfo.btbEntry;
    assign pred_error = {meta.region, meta.offset, 1'b0} != io.updateInfo.target_pc;
    assign alt_pred_error = {meta.region, meta.alt_offset, 1'b0} != io.updateInfo.target_pc;

    LowMaskGen #(`ITTAGE_BANK) low_mask_provider (meta.provider, provider_mask_low);
    assign provider_mask = ~(|meta.provider) ? {`ITTAGE_BANK{1'b1}} : provider_mask_low;
    PRSelector #(`ITTAGE_BANK) selector_alloc (~meta.u & provider_mask, alloc);
    ParallelAdder #(1, `ITTAGE_BANK) adder_update_u (meta.u, update_u_cnt);

generate
    for(genvar i=0; i<`ITTAGE_BANK; i++)begin
        logic `N(`ITTAGE_CTR_SIZE) u_ctr, u_ctr_add;
        assign u_ctr = update_commit_en[i] ? update_commit_ctr[i] : meta.ctr;
        UpdateCounter #(`ITTAGE_CTR_SIZE) updateCtr (u_ctr, ~pred_error, u_ctr_add);
        assign update_ctr[i] = alloc[i] & ~update_commit_en[i] ? 1 : u_ctr_add;

        UpdateCounter #(`ITTAGE_U_SIZE) updateU (meta.u[i], ~pred_error, update_u[i]);
        assign update_u_en[i] = (~(|alloc)) & pred_error | meta.provider[i] & (alt_pred_error ^ pred_error);
    end
endgenerate

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            reset_u <= 0;
            resetu_ctr <= 0;
        end
        else begin
            if(resetu_ctr == {`ITTAGE_RESETU_CTR{1'b1}})begin
                resetu_ctr <= 0;
            end
            else if(update_en & pred_error) begin
                if(update_u_cnt < `ITTAGE_BANK / 2)begin
                    resetu_ctr <= resetu_ctr - 1;
                end
                else begin
                    resetu_ctr <= resetu_ctr + 1;
                end
            end
            reset_u <= resetu_ctr == {`ITTAGE_RESETU_CTR{1'b1}};
        end
    end

endmodule

// region idx is stored in btb
// update when btb tail slot generated
module ITTAGERegion(
    input logic clk,
    input logic rst,

    input logic en,
    input logic `N(`ITTAGE_REGION_WIDTH) lookup_idx,
    output logic `N(`ITTAGE_REGION) lookup_region,

    // 虽然模块位置在BPU但是tag的实际位置在BTBEntryGen附近
    // tag cmp before update and it's located in BTBEntryGen
    input logic `N(`ITTAGE_REGION_TAG) update_tag,
    output logic `N(`ITTAGE_REGION_WIDTH) tag_hit_idx,

    input logic update,
    input logic `N(`ITTAGE_REGION) update_region
);

    logic `ARRAY(`ITTAGE_REGION_SIZE, `ITTAGE_REGION_TAG) tags;
    logic `N(`ITTAGE_REGION_SIZE) tag_hits, tag_hits_select, tag_hits_n, hit_way;
    logic `N(`ITTAGE_REGION_WIDTH) tag_hits_encode, tag_hits_encode_n, miss_way_encode;
    logic tag_hit;
    logic `N(`ITTAGE_REGION_TAG) update_tag_n;

generate
    for(genvar i=0; i<`ITTAGE_REGION_SIZE; i++)begin
        assign tag_hits[i] = tags[i] == update_tag;
    end
endgenerate
    ReplaceIO #(.DEPTH(1), .WAY_NUM(`ITTAGE_REGION_SIZE)) replace_io();
    Replace #(.DEPTH(1), .WAY_NUM(`ITTAGE_REGION_SIZE)) replace(.*);
    PEncoder #(`ITTAGE_REGION_SIZE) encoder_tag_hits (tag_hits, tag_hits_encode);
    PSelector #(`ITTAGE_REGION_SIZE) selector_tag_hits (tag_hits, tag_hits_select);
    Encoder #(`ITTAGE_REGION_SIZE) encoder_miss_way (replace_io.miss_way, miss_way_encode);

    logic `N(`ITTAGE_REGION_WIDTH) lookup_idx_n;
    logic `N(`ITTAGE_REGION_SIZE) lookup_way;
    `SIG_N(lookup_idx, lookup_idx_n)
    Decoder #(`ITTAGE_REGION_SIZE) decoder_lookup_idx (lookup_idx_n, lookup_way);
    `SIG_N(tag_hits_select, tag_hits_n)
    `SIG_N(update_tag, update_tag_n)
    assign replace_io.hit_en = en | update;
    assign replace_io.hit_index = 0;
    assign replace_io.hit_invalid = 0;
    assign replace_io.hit_way = update ? hit_way : lookup_way;
    assign replace_io.miss_index = 0;

    always_ff @(posedge clk)begin
        tag_hit <= |tag_hits;
        tag_hits_encode_n <= tag_hits_encode;
    end
    assign hit_way = tag_hit ? tag_hits_n : replace_io.miss_way;
    assign tag_hit_idx = tag_hit ? tag_hits_encode_n : miss_way_encode;

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            tags <= 0;
        end
        else begin
            if(update)begin
                tags[tag_hit_idx] <= update_tag_n;
            end
        end
    end
    
    MPRAM #(
        .WIDTH(`ITTAGE_REGION),
        .DEPTH(`ITTAGE_REGION_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1)
    ) region_ram (
        .clk,
        .rst,
        .rst_sync(1'b0),
        .en(1'b1),
        .raddr(lookup_idx),
        .rdata(lookup_region),
        .we(update),
        .waddr(tag_hit_idx),
        .wdata(update_region),
        .ready()
    );

endmodule


module ITTAGETable #(
	parameter WIDTH = $bits(ITTageEntry),
	parameter HEIGHT = 1024,
	parameter ADDR_WIDTH = $clog2(HEIGHT)
)(
	input logic clk,
	input logic rst,
	input logic en,
	input logic `N(ADDR_WIDTH) lookup_idx,
	input logic `N(`ITTAGE_TAG_SIZE) lookup_tag,
	input logic update_en,
	input logic provider,
	input logic alloc,
	input logic update_u_en,
	input logic reset_u,
	input logic `N(`ITTAGE_U_SIZE) update_u,
	input logic `N(`ITTAGE_CTR_SIZE) update_ctr,
	input logic `N(`ITTAGE_TAG_SIZE) update_tag,
    input logic `N(`ITTAGE_OFFSET) update_offset,
	input logic `N(ADDR_WIDTH) update_idx,
    output logic `N(`ITTAGE_OFFSET) lookup_offset,
	output logic lookup_match,
	// meta
	output logic `N(`ITTAGE_CTR_SIZE) lookup_ctr,
	output logic `N(`ITTAGE_U_SIZE) lookup_u
);
	logic `N(`ITTAGE_TAG_SIZE) match_tag;
	always_ff @(posedge clk)begin
		if(en)begin
			match_tag <= lookup_tag;
		end
	end
	logic `N(`ITTAGE_TAG_SIZE) search_tag;

	assign lookup_match = search_tag == match_tag;

    MPRAM #(
        .WIDTH((`ITTAGE_CTR_SIZE+`ITTAGE_TAG_SIZE)),
        .DEPTH(HEIGHT),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .BANK_SIZE(`ITTAGE_SLICE),
        .RESET(1)
    )ctr_bank(
        .clk(clk),
        .rst(rst),
        .rst_sync(1'b0),
        .en(en),
        .we(update_en & (provider | alloc)),
        .waddr(update_idx),
        .raddr(lookup_idx),
        .rdata({search_tag, lookup_ctr}),
        .wdata({update_tag, update_ctr}),
        .ready()
    );

    MPRAM #(
        .WIDTH(`ITTAGE_OFFSET),
        .DEPTH(HEIGHT),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .BANK_SIZE(`ITTAGE_SLICE),
        .RESET(1)
    ) offset_bank (
        .clk,
        .rst,
        .rst_sync(1'b0),
        .en(en),
        .we(update_en & (provider & (update_ctr == 0) | alloc)),
        .waddr(update_idx),
        .raddr(lookup_idx),
        .rdata(lookup_offset),
        .wdata(update_offset),
        .ready()
    );

    MPRAM #(
        .WIDTH(`ITTAGE_U_SIZE),
        .DEPTH(HEIGHT),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .BANK_SIZE(`TAGE_SLICE),
        .RESET(1),
        .ENABLE_SYNC_RST(1)
    ) u_bank (
        .clk(clk),
        .rst(rst),
        .rst_sync(reset_u),
        .en(en),
        .we(update_en & (update_u_en | alloc)),
        .waddr(update_idx),
        .raddr(lookup_idx),
        .rdata(lookup_u),
        .wdata(update_u),
        .ready()
    );

endmodule