`include "../../defines/defines.svh"

module UBTB(
    input logic clk,
    input logic rst,
    BpuUBtbIO.ubtb ubtb_io
);
    // TODO: 一次只更新一级BTB
    `BTB_ENTRY_GEN(`UBTB_TAG_SIZE)
    BTBEntry `N(`UBTB_SIZE) entrys;
    logic `ARRAY(`SLOT_NUM, 2) ctrs `N(`UBTB_SIZE);
    BTBEntry lookup_entry;
    logic `ARRAY(`SLOT_NUM, 2) lookup_ctr;
    logic `N(`UBTB_SIZE) lookup_hits, updateHits;
    logic `N($clog2(`UBTB_SIZE)) lookup_index, updateIdx, updateSelectIdx, replaceIdx;
    logic `N(`UBTB_SIZE) update_way;
    logic `N(`UBTB_TAG_SIZE) lookup_tag, update_tag;
    logic lookup_hit, updateHit;
    logic `N(`SLOT_NUM) cond_history;
    logic older;
`ifdef RVC
    logic br_rvc;
    logic br_rvc_normal;
`endif

    UBTBMeta meta;
    logic `N(`SLOT_NUM) update_carry, update_en;
    logic `ARRAY(`SLOT_NUM, 2) u_ctr, commit_ctr, ctr_i, cam_ctr;
    logic commit_ctr_hit;

    ReplaceIO #(.DEPTH(1), .WAY_NUM(`UBTB_SIZE)) replace_io();

    Encoder #(`UBTB_SIZE) encoder_lookup(lookup_hits, lookup_index);
    Encoder #(`UBTB_SIZE) encoder_update(updateHits, updateIdx);
    Encoder #(`UBTB_SIZE) encoder_replace(replace_io.miss_way, replaceIdx);
    BTBTagGen #(
        `INST_OFFSET,
        `UBTB_TAG_SIZE
    )gen_tag(ubtb_io.pc, lookup_tag);
    assign replace_io.hit_en = result_i.en | ubtb_io.update & ubtb_io.updateInfo.btbEntry.en;
    assign replace_io.hit_index = 0;
    assign replace_io.hit_invalid = 0;
    assign replace_io.hit_way = ubtb_io.update & ubtb_io.updateInfo.btbEntry.en ? update_way : lookup_hits;
    assign replace_io.miss_index = 0;
    assign lookup_hit = |lookup_hits;
    assign updateHit = |updateHits;
    assign updateSelectIdx = updateHit ? updateIdx : replaceIdx;
    assign update_way = updateHit ? updateHits : replace_io.miss_way;
    assign lookup_entry = entrys[lookup_index];
    assign lookup_ctr = ctrs[lookup_index];
    BTBTagGen #(
        `INST_OFFSET,
        `UBTB_TAG_SIZE
    )gen_update_tag(ubtb_io.updateInfo.start_addr, update_tag);
generate;
    for(genvar i=0; i<`UBTB_SIZE; i++)begin
        assign lookup_hits[i] = entrys[i].en && entrys[i].tag == lookup_tag;
        assign updateHits[i] = entrys[i].en && entrys[i].tag == update_tag;
    end
    for(genvar br=0; br<`SLOT_NUM; br++)begin
        assign cond_history[br] = lookup_ctr[br][1];
    end
endgenerate

    PredictionResult result_i, result_o;
    BTBUpdateInfo lookup_entry_i;
    assign lookup_entry_i = lookup_entry[$bits(BTBUpdateInfo)-1: 0];
    always_comb begin
        result_i = 0;
        result_i.en = ubtb_io.redirect.tage_ready & ~ubtb_io.redirect.stall;
        result_i.stream.start_addr = ubtb_io.pc;
        result_i.stream_idx = ubtb_io.fsqIdx;
        result_i.stream_dir = ubtb_io.fsqDir;
        result_i.redirect_info.ghistIdx = ubtb_io.history.ghistIdx;
        result_i.redirect_info.tage_history = ubtb_io.history.tage_history;
        result_i.redirect_info.rasInfo = 0;
        result_i.redirect_info.sc_ghist = ubtb_io.history.sc_ghist;
`ifdef IMLI_VALID
        result_i.redirect_info.imli = ubtb_io.history.imli;
`endif
        result_i.stream.target = ubtb_io.pc + `BLOCK_SIZE;
`ifdef RVC
        result_i.stream.size = `BLOCK_INST_SIZE - 2;
`else
        result_i.stream.size = `BLOCK_INST_SIZE - 1;
`endif
        ubtb_io.meta.ctr = lookup_ctr;
    end

    PredictionResultGen result_gen (
        .pc(ubtb_io.pc),
        .hit((|lookup_hits)),
        .entry(lookup_entry_i),
        .prediction(cond_history),
        .ras_addr(),
        .ind_addr(),
        .rasInfo(),
        .result_i,
        .result_o
    );
    assign ubtb_io.result = result_o;

    PLRU #(
        .DEPTH(1),
        .WAY_NUM(`UBTB_SIZE)
    ) replace (
        .clk,
        .rst,
        .replace_io
    );

    assign meta = ubtb_io.updateInfo.meta.ubtb;

    CAMQueue #(
        .DEPTH(`UBTB_COMMIT_SIZE),
        .TAG_WIDTH(`UBTB_WIDTH),
        .DATA_WIDTH(`SLOT_NUM * 2) 
    ) ctr_cam (
        .clk,
        .rst,
        .we(|update_en),
        .wtag(updateSelectIdx),
        .wdata(cam_ctr),
        .rtag(updateSelectIdx),
        .rhit(commit_ctr_hit),
        .rdata(commit_ctr)
    );

    assign ctr_i = commit_ctr_hit ? commit_ctr : meta.ctr;
generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        UpdateCounter #(2) updateCounter (ctr_i[i], ubtb_io.updateInfo.realTaken[i], u_ctr[i]);
        assign cam_ctr[i] = update_en[i] ? u_ctr[i] : ctr_i[i];
    end
    for(genvar i=0; i<`SLOT_NUM-1; i++)begin
        assign update_carry[i] = ubtb_io.updateInfo.btbEntry.slots[i].carry;
        assign update_en[i] = ubtb_io.updateInfo.btbEntry.slots[i].en & ubtb_io.updateInfo.allocSlot[i];
    end
    assign update_carry[`SLOT_NUM-1] = ubtb_io.updateInfo.btbEntry.tailSlot.carry;
    assign update_en[`SLOT_NUM-1] = ubtb_io.updateInfo.btbEntry.tailSlot.en && ubtb_io.updateInfo.btbEntry.tailSlot.br_type == CONDITION & ubtb_io.updateInfo.allocSlot[`SLOT_NUM-1];
endgenerate
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            entrys <= '{default: 0};
            ctrs <= '{default: 0};
        end
        else begin
            if(ubtb_io.update & ubtb_io.updateInfo.btbEntry.en)begin
                for(int i=0; i<`UBTB_SIZE; i++)begin
                    if(update_way[i])begin
                        entrys[i] <= {update_tag, ubtb_io.updateInfo.btbEntry};
                    end
                end
                for(int i=0; i<`SLOT_NUM; i++)begin
                    if(update_en[i])begin
                        if(~update_carry[i])begin
                            ctrs[updateSelectIdx][i] <= u_ctr[i];
                        end
                        else begin
                            ctrs[updateSelectIdx][i] <= 2'b10;
                        end
                    end
                end
            end
        end
    end

    `Log(DLog::Debug, T_BTB, ubtb_io.update & ubtb_io.updateInfo.btbEntry.en,
    $sformatf("update ubtb. %h->%h[%h]", ubtb_io.updateInfo.start_addr, updateSelectIdx, update_tag))

endmodule