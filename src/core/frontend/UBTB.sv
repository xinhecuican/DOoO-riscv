`include "../../defines/defines.svh"

module UBTB(
    input logic clk,
    input logic rst,
    BpuUBtbIO.btb ubtb_io
);

    BTBEntry entrys `N(`UBTB_SIZE);
    logic `ARRAY(`SLOT_NUM, 2) ctrs `N(`UBTB_SIZE);
    BTBEntry lookup_entry, updateEntry;
    logic `ARRAY(`SLOT_NUM, 2) lookup_ctr;
    logic `N(`UBTB_SIZE) lookup_hits, updateHits;
    logic `N($clog2(`UBTB_SIZE)) lookup_index, updateIdx, updateSelectIdx;
    logic `N(`UBTB_TAG_SIZE) lookup_tag;
    logic `N(`SLOT_NUM) br_takens;
    logic `N(`JAL_OFFSET) br_offset;
    logic `VADDR_BUS tail_target, br_target;
    logic `N(`PREDICTION_WIDTH) br_size, tail_size;
    logic lookup_hit, updateHit;
    logic [1: 0] br_num;
    logic `N(`SLOT_NUM) isBr, cond_valid;
    logic `N(`SLOT_NUM) cond_history;
    logic older;

    ReplaceIO #(.DEPTH(1),.WAY_NUM(`UBTB_SIZE)) replace_io;

    Encoder #(`UBTB_SIZE) encoder_lookup(lookup_hits, lookup_index);
    Encoder #(`UBTB_SIZE) encoder_update(updateHits, updateIdx);
    assign lookup_tag = ubtb_io.pc[`UBTB_TAG_SIZE+1: 2];
    assign lookup_hit = |lookup_hits;
    assign updateHit = |updateHits;
    assign updateSelectIdx = updateHit ? updateIdx : replace_io.miss_way;
    assign lookup_entry = entrys[lookup_index];
    assign lookup_ctr = ctrs[lookup_index];
    assign tail_target = lookup_entry.tailSlot.en ? {{(`VADDR_SIZE-`JALR_OFFSET){lookup_entry.tailSlot.offset[`JALR_OFFSET-1]}}, 
                        lookup_entry.tailSlot.target} + ubtb_io.pc : lookup_entry.fthAddr + ubtb_io.pc;
    assign tail_size = lookup_entry.tailSlot.en ? lookup_entry.tailSlot.offset : lookup_entry.fthAddr;
    PMux2 #(`JAL_OFFSET) pmux2_br_offset(br_takens, 
                                        lookup_entry.slots[0].target,lookup_entry.tailSlot.target[`JAL_OFFSET-1: 0],
                                        br_offset);
    PMux2 #(`PREDICTION_WIDTH) pmux2_br_size(br_takens, 
                                        lookup_entry.slots[0].target,lookup_entry.tailSlot.target,
                                        br_size);
    assign br_target = {{(`VADDR_SIZE-`JAL_OFFSET){br_offset[`JAL_OFFSET-1]}}, br_offset} + ubtb_io.pc;
    assign older = lookup_entry.slots[0].offset < lookup_entry.tailSlot.offset;
    assign br_num = lookup_entry.slots[0].en + 
                    (lookup_entry.tailSlot.en & (lookup_entry.tailSlot.br_type == CONDITION));
generate;
    for(genvar i=0; i<`UBTB_SIZE; i++)begin
        assign lookup_hits[i] = entrys[i].en && entrys[i].tag == lookup_tag;
        assign updateHits[i] = entrys[i].en && entrys[i].tag == ubtb_io.updateInfo.start_addr[`UBTB_TAG_SIZE+1: 2];
    end
    for(genvar br=0; br<`SLOT_NUM-1; br++)begin
        assign isBr[br] = lookup_entry.slots[br].en;
    end
    for(genvar br=0; br<`SLOT_NUM; br++)begin
        assign cond_history[br] = lookup_ctr[br][1];
    end
    assign isBr[`SLOT_NUM-1] = lookup_entry.tailSlot.en &&
                                lookup_entry.tailSlot.br_type == CONDITION;
    assign br_takens = isBr & cond_history;
endgenerate

    always_comb begin
        if(br_takens[0] & older)begin
            br_num = 2'b1;
            cond_valid = 2'b1;
        end
        else if(br_takens[1] & ~older)begin
            br_num = 2'b1;
            cond_valid = 2'b10;
        end
        else begin
            br_num = isBr[0] + isBr[1];
            cond_valid = isBr;
        end
    end

    always_comb begin
        ubtb_io.result.en = ~ubtb_io.flush & ~ubtb_io.s2_redirect;
        ubtb_io.result.stream.taken = lookup_hit & (|br_takens);
        ubtb_io.result.stream.branch_type = |br_takens ? CONDITION : lookup_entry.tailSlot.br_type;
        ubtb_io.result.stream.ras_type = NONE;
        ubtb_io.result.stream.start_addr = ubtb_io.pc;
        ubtb_io.result.stream.size = ~(lookup_hit) ? `BLOCK_WIDTH :
                                    |br_takens ? br_size : tail_size;
        ubtb_io.result.stream.target = ~(lookup_hit) ? ubtb_io.pc + `BLOCK_SIZE :
                                |br_takens ? br_target : tail_target;
        ubtb_io.result.redirect = 0;
        ubtb_io.result.cond_num = ~lookup_hit ? 0 : br_num;
        ubtb_io.result.cond_valid = cond_valid;
        ubtb_io.result.taken = |br_takens;
        ubtb_io.result.predTaken = br_takens;
        ubtb_io.result.stream_idx = ubtb_io.fsqIdx;
        ubtb_io.result.redirect_info.ghistIdx = ubtb_io.ghistIdx;
        ubtb_io.meta.ctr = br_takens;
    end

    RandomReplace #(
        .DEPTH(1),
        .WAY_NUM(`UBTB_SIZE)
    ) replace (
        .clk(clk),
        .rst(rst),
        .replace_io(replace_io)
    );

    UBTBMeta meta;
    logic `ARRAY(`SLOT_NUM, 2) u_ctr;
generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        UpdateCounter updateCounter (meta.ctr[i], ubtb_io.updateInfo.realTaken[i], u_ctr[i]);
    end
endgenerate
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            entrys <= '{default: 0};
            ctrs <= '{default: 0};
        end
        else begin
            if(ubtb_io.update)begin
                entrys[updateSelectIdx] <= ubtb_io.updateInfo.btbEntry;
                ctrs[updateSelectIdx] <= u_ctr;
            end
        end
    end

endmodule