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
    logic `N(`SLOT_NUM) lookup_carry;
    logic `N($clog2(`UBTB_SIZE)) lookup_index, updateIdx, updateSelectIdx;
    logic `N(`UBTB_TAG_SIZE) lookup_tag, update_tag;
    logic `N(`SLOT_NUM) br_takens;
    logic tail_taken;
    logic `N(`JAL_OFFSET) br_offset, br_offset_normal;
    logic `N(`PREDICTION_WIDTH+1) fthOffset;
    logic [`VADDR_SIZE-`JAL_OFFSET-2: 0] br_target_high;
    logic [`VADDR_SIZE-`JALR_OFFSET-2: 0] tail_target_high;
    logic `VADDR_BUS tail_target, br_target;
    TargetState br_tar_state, tail_tar_state, br_tar_state_normal;
    logic `N(`PREDICTION_WIDTH) br_size, tail_size, br_size_normal;
    logic lookup_hit, updateHit;
    logic [1: 0] br_num;
    logic `N(`SLOT_NUM) isBr, cond_valid;
    logic `N(`SLOT_NUM) cond_history;
    logic older;
`ifdef RVC
    logic br_rvc;
    logic br_rvc_normal;
`endif

    ReplaceD1IO #(.WAY_NUM(`UBTB_SIZE)) replace_io();

    Encoder #(`UBTB_SIZE) encoder_lookup(lookup_hits, lookup_index);
    Encoder #(`UBTB_SIZE) encoder_update(updateHits, updateIdx);
    BTBTagGen #(
        `INST_OFFSET,
        `UBTB_TAG_SIZE
    )gen_tag(ubtb_io.pc, lookup_tag);
    assign replace_io.hit_en = 0;
    assign replace_io.hit_way = 0;
    assign lookup_hit = |lookup_hits;
    assign updateHit = |updateHits;
    assign updateSelectIdx = updateHit ? updateIdx : replace_io.miss_way;
    assign lookup_entry = entrys[lookup_index];
    assign lookup_ctr = ctrs[lookup_index];
    assign tail_tar_state = lookup_entry.tailSlot.tar_state;
    assign tail_target_high = tail_tar_state == TAR_OV ? ubtb_io.pc[`VADDR_SIZE-1: `JALR_OFFSET+1] + 1 :
                            tail_tar_state == TAR_UN ? ubtb_io.pc[`VADDR_SIZE-1: `JALR_OFFSET+1] - 1 :
                                                     ubtb_io.pc[`VADDR_SIZE-1: `JALR_OFFSET+1];
    assign tail_taken = lookup_entry.tailSlot.en && lookup_entry.tailSlot.br_type != CONDITION;
`ifdef RVC
    assign fthOffset = lookup_entry.fthAddr + {~lookup_entry.fth_rvc, lookup_entry.fth_rvc};
`else
    assign fthOffset = lookup_entry.fthAddr + 1;
`endif
    assign tail_target = tail_taken ? {tail_target_high, lookup_entry.tailSlot.target, 1'b0} : 
                         {fthOffset, {`INST_OFFSET{1'b0}}} + ubtb_io.pc;
    assign tail_size = tail_taken ? lookup_entry.tailSlot.offset : lookup_entry.fthAddr;
    PMux2 #(`JAL_OFFSET) pmux2_br_offset(br_takens, 
                                        lookup_entry.slots[0].target,lookup_entry.tailSlot.target[`JAL_OFFSET-1: 0],
                                        br_offset_normal);
    PMux2 #(`PREDICTION_WIDTH) pmux2_br_size(br_takens, 
                                        lookup_entry.slots[0].offset,lookup_entry.tailSlot.offset,
                                        br_size_normal);
`ifdef RVC
    PMux2 #(1) pmux2_br_rvc(br_takens,
                            lookup_entry.slots[0].rvc, lookup_entry.tailSlot.rvc,
                            br_rvc_normal);
`endif
    PMux2 #(2) pmux2_br_tar(br_takens,
                            lookup_entry.slots[0].tar_state, lookup_entry.tailSlot.tar_state,
                            br_tar_state_normal);
    assign br_target_high = br_tar_state == TAR_OV ? ubtb_io.pc[`VADDR_SIZE-1: `JAL_OFFSET+1] + 1 :
                            br_tar_state == TAR_UN ? ubtb_io.pc[`VADDR_SIZE-1: `JAL_OFFSET+1] - 1 :
                                                     ubtb_io.pc[`VADDR_SIZE-1: `JAL_OFFSET+1];
    assign br_target = {br_target_high, br_offset, 1'b0};
    assign older = lookup_entry.slots[0].offset < lookup_entry.tailSlot.offset;
    BTBTagGen #(
        `INST_OFFSET,
        `UBTB_TAG_SIZE
    )gen_update_tag(ubtb_io.updateInfo.start_addr, update_tag);
generate;
    for(genvar i=0; i<`UBTB_SIZE; i++)begin
        assign lookup_hits[i] = entrys[i].en && entrys[i].tag == lookup_tag;
        assign updateHits[i] = entrys[i].en && entrys[i].tag == update_tag;
    end
    for(genvar br=0; br<`SLOT_NUM-1; br++)begin
        assign isBr[br] = lookup_entry.slots[br].en;
        assign lookup_carry[br] = lookup_entry.slots[br].carry;
    end
    for(genvar br=0; br<`SLOT_NUM; br++)begin
        assign cond_history[br] = lookup_ctr[br][1];
    end
    assign isBr[`SLOT_NUM-1] = lookup_entry.tailSlot.en &&
                                lookup_entry.tailSlot.br_type == CONDITION;
    assign lookup_carry[`SLOT_NUM-1] = lookup_entry.tailSlot.carry;
    assign br_takens = isBr & (cond_history | lookup_carry);
endgenerate

    always_comb begin
        if(br_takens[1] & ~older)begin
            br_num = 2'b1;
            cond_valid = 2'b10;
            br_offset = lookup_entry.tailSlot.target[`JAL_OFFSET-1: 0];
            br_size = lookup_entry.tailSlot.offset;
            br_tar_state = lookup_entry.tailSlot.tar_state;
`ifdef RVC
            br_rvc = lookup_entry.tailSlot.rvc;
`endif
        end
        else begin
            br_num = isBr[0] + isBr[1];
            cond_valid = isBr;
            br_offset = br_offset_normal;
            br_size = br_size_normal;
            br_tar_state = br_tar_state_normal;
`ifdef RVC
            br_rvc = br_rvc_normal;
`endif
        end
    end

    always_comb begin
        ubtb_io.result.en = ~ubtb_io.redirect.flush & ~ubtb_io.redirect.s2_redirect & ubtb_io.redirect.tage_ready;
        ubtb_io.result.btb_hit = lookup_hit;
        ubtb_io.result.stream.taken = lookup_hit & ((|br_takens) | (tail_taken));
        ubtb_io.result.br_type = |br_takens ? CONDITION : lookup_entry.tailSlot.br_type;
        ubtb_io.result.ras_type = |br_takens ? NONE : lookup_entry.tailSlot.ras_type;
        ubtb_io.result.stream.start_addr = ubtb_io.pc;

        ubtb_io.result.stream.target = ~(lookup_hit) ? ubtb_io.pc + `BLOCK_SIZE :
                                |br_takens ? br_target : tail_target;
`ifdef RVC
        ubtb_io.result.stream.rvc = ~lookup_hit ? 0 :
                                    |br_takens ? br_rvc :
                                    tail_taken ? lookup_entry.tailSlot.rvc : lookup_entry.fth_rvc;
        ubtb_io.result.stream.size = ~(lookup_hit) ? `BLOCK_INST_SIZE - 2 :
                                    |br_takens ? br_size : tail_size;
`else
        ubtb_io.result.stream.size = ~(lookup_hit) ? `BLOCK_INST_SIZE - 1 :
                                    |br_takens ? br_size : tail_size;
`endif
        ubtb_io.result.redirect = 0;
        ubtb_io.result.cond_num = ~lookup_hit ? 0 : br_num;
        ubtb_io.result.cond_valid = cond_valid;
        ubtb_io.result.taken = (|br_takens) | tail_taken;
        ubtb_io.result.predTaken = br_takens;
        ubtb_io.result.stream_idx = ubtb_io.fsqIdx;
        ubtb_io.result.stream_dir = ubtb_io.fsqDir;
        ubtb_io.result.redirect_info.ghistIdx = ubtb_io.history.ghistIdx;
        ubtb_io.result.redirect_info.tage_history = ubtb_io.history.tage_history;
        ubtb_io.result.redirect_info.rasInfo = 0;
        ubtb_io.result.btbEntry = (|lookup_hits) ? lookup_entry[$bits(BTBUpdateInfo)-1: 0] : 0;
        ubtb_io.meta.ctr = lookup_ctr;
    end

    RandomReplaceD1 #(
        .DEPTH(1),
        .WAY_NUM(`UBTB_SIZE)
    ) replace (
        .clk(clk),
        .rst(rst),
        .replace_io(replace_io)
    );

    UBTBMeta meta;
    logic `N(`SLOT_NUM) update_carry, update_en;
    logic `ARRAY(`SLOT_NUM, 2) u_ctr, commit_ctr, ctr_i, cam_ctr;
    logic commit_ctr_hit;
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
                entrys[updateSelectIdx] <= {update_tag, ubtb_io.updateInfo.btbEntry};
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