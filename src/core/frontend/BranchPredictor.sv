`include "../../defines/defines.svh"
module BranchPredictor(
    input logic clk,
    input logic rst,
    BpuFsqIO.bpu bpu_fsq_io
);
    logic `VADDR_BUS pc;
    BranchHistory history;
    RedirectCtrl redirect /*verilator split_var*/;
    SquashInfo squashInfo;
    BranchUpdateInfo updateInfo;
    logic squash;
    logic update;
    logic stall_normal;
    BpuBtbIO #(`BTB_TAG_SIZE) btb_io(.*);
    BpuTageIO tage_io(.*);
    BpuUBtbIO ubtb_io(.*);
    BpuRASIO ras_io(.*);

    PredictionResult s1_result;
    PredictionResult s2_result_in, s2_result_out;
    PredictionResult redirect_result;
    PredictionMeta s1_meta;
    PredictionMeta s2_meta_in, s2_meta_out;
    // PredictionResult s3_result_in, s3_result_out;

    assign squash = bpu_fsq_io.squash;
    assign squashInfo = bpu_fsq_io.squashInfo;
    assign update = bpu_fsq_io.update;
    assign updateInfo = bpu_fsq_io.updateInfo;
    assign btb_io.pc = pc;
    assign btb_io.request = 1'b1;
    BTB btb(.*);
    assign tage_io.pc = pc;
    Tage tage(.*);

    HistoryControl history_control(
        .*,
        .result(redirect_result),
        .redirect(redirect),
        .history(history)
    );
    

    always_comb begin
        s1_result = ubtb_io.result;
        s1_result.redirect_info.rasInfo = ras_io.rasInfo;
    end
    assign ubtb_io.pc = pc;
    assign ubtb_io.fsqIdx = bpu_fsq_io.stream_idx;
    assign ubtb_io.fsqDir = bpu_fsq_io.stream_dir;
    UBTB ubtb(.*);

    RAS ras(.*, .lastStage(s2_result_out.en  & ~redirect.flush), .lastStageIdx(s2_result_out.stream_idx));
    
    assign redirect.s2_redirect = s2_result_out.en && s2_result_out.redirect[0];
    assign redirect.tage_ready = tage_io.ready;
    assign redirect.flush = bpu_fsq_io.squash;
    assign redirect.stall = bpu_fsq_io.stall & ~redirect.s2_redirect | ~tage_io.ready;
    assign stall_normal = bpu_fsq_io.stall | ~tage_io.ready;
    assign redirect_result = s2_result_out;
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            pc <= `RESET_PC;
        end
        else if(redirect.flush)begin
            pc <= squashInfo.target_pc;
        end
        else if(redirect.s2_redirect)begin
            pc <= s2_result_out.stream.target;
        end
        else if(!stall_normal)begin
            pc <= s1_result.stream.target;
        end

        if(rst == `RST)begin
            s2_result_in <= 0;
            s2_meta_in <= 0;
        end
        else if(redirect.flush)begin
            s2_result_in.en <= 1'b0;
        end
        else if(~stall_normal | redirect.s2_redirect)begin
            s2_result_in <= s1_result;
            s2_meta_in <= s1_meta;
        end

        // if(rst == `RST || redirect.flush)begin
        //     s3_result_in <= '{default: 0};
        // end
        // else if(!redirect.stall)begin
        //     s3_result_in <= s2_result_out;
        // end
    end

    assign bpu_fsq_io.en = bpu_fsq_io.prediction.en & ~redirect.flush;
    assign bpu_fsq_io.prediction = redirect.s2_redirect ? s2_result_out : s1_result;
    assign bpu_fsq_io.redirect = redirect.s2_redirect & ~redirect.flush;
    assign bpu_fsq_io.lastStage = s2_result_out.en  & ~redirect.flush;
    assign bpu_fsq_io.lastStageIdx = s2_result_out.stream_idx;
    assign bpu_fsq_io.lastStageMeta = s2_meta_out;
    assign bpu_fsq_io.lastStagePred = s2_result_out;
    assign bpu_fsq_io.ras_addr = ras_io.entry.pc;
    S2Control s2_control(
        .stall(stall_normal),
        .pc(s2_result_in.stream.start_addr),
        .entry(btb_io.entry),
        .tag(btb_io.tag),
        .prediction(tage_io.prediction),
        .ras_io(ras_io.control),
        .result_i(s2_result_in),
        .result_o(s2_result_out)
    );
    assign s1_meta.ubtb = ubtb_io.meta;
    assign s1_meta.tage = 0;
    assign s2_meta_out.ubtb = s2_meta_in.ubtb;
    assign s2_meta_out.tage = tage_io.meta;


endmodule

module S2Control(
    input logic stall,
    input logic `VADDR_BUS pc,
    input logic `N(`BTB_TAG_SIZE) tag,
    input BTBUpdateInfo entry,
    input logic `N(`SLOT_NUM) prediction,
    BpuRASIO.control ras_io,
    input PredictionResult result_i,
    output PredictionResult result_o
);
    logic `VADDR_BUS predict_pc;
    logic hit;
    logic btb_hit;
    logic `N(`SLOT_NUM) isBr;
    logic `N(`SLOT_NUM) br_takens, carry;
    logic tail_taken;
    logic `N(`JAL_OFFSET) br_offset, br_offset_normal;
    logic `N(`PREDICTION_WIDTH) br_size, tail_size, br_size_normal;
    logic `N(`PREDICTION_WIDTH+1) fthOffset;
    TargetState br_tar_state, tail_tar_state, br_tar_state_normal;
    logic [`VADDR_SIZE-`JAL_OFFSET-2: 0] br_target_high;
    logic [`VADDR_SIZE-`JALR_OFFSET-2: 0] tail_target_high;
    logic `VADDR_BUS tail_target, br_target, tail_indirect_target;
    logic [1: 0] cond_num;
    logic `N(`SLOT_NUM) cond_valid;
    logic `N(`BTB_TAG_SIZE) lookup_tag;
    logic older;
    BTBUpdateInfo entry_i;
`ifdef RVC
    logic br_rvc, br_rvc_normal;
`endif

    BTBTagGen #(
        `BTB_SET_WIDTH + `INST_OFFSET + $clog2(`BTB_WAY), 
        `BTB_TAG_SIZE
    ) gen_tag(pc, lookup_tag);
    assign hit = entry.en && (lookup_tag == tag);
    assign btb_hit = hit | result_i.btb_hit;
    assign entry_i = hit ? entry : result_i.btbEntry;
    assign br_takens = isBr & (prediction | carry);
    generate;
        for(genvar br=0; br<`SLOT_NUM-1; br++)begin
            assign isBr[br] = entry_i.slots[br].en;
            assign carry[br] = entry_i.slots[br].carry;
        end
        assign isBr[`SLOT_NUM-1] = entry_i.tailSlot.en &&
                                        entry_i.tailSlot.br_type == CONDITION;
        assign carry[`SLOT_NUM-1] = entry_i.tailSlot.carry;
    endgenerate
    PMux2 #(`JAL_OFFSET) pmux2_br_offset(br_takens, 
                                        entry_i.slots[0].target,entry_i.tailSlot.target[`JAL_OFFSET-1: 0],
                                        br_offset_normal);
    PMux2 #(`PREDICTION_WIDTH) pmux2_br_size(br_takens, 
                                        entry_i.slots[0].offset,entry_i.tailSlot.offset,
                                        br_size_normal);
`ifdef RVC
    PMux2 #(1) pmux2_br_rvc(br_takens,
                            entry_i.slots[0].rvc, entry_i.tailSlot.rvc,
                            br_rvc_normal);
`endif
    PMux2 #(2) pmux2_br_tar(br_takens,
                            entry_i.slots[0].tar_state, entry_i.tailSlot.tar_state,
                            br_tar_state_normal);
    assign tail_size = tail_taken ? entry_i.tailSlot.offset : entry_i.fthAddr;
    assign tail_tar_state = entry_i.tailSlot.tar_state;
    assign tail_target_high = tail_tar_state == TAR_OV ? pc[`VADDR_SIZE-1: `JALR_OFFSET+1] + 1 :
                            tail_tar_state == TAR_UN ? pc[`VADDR_SIZE-1: `JALR_OFFSET+1] - 1 :
                                                     pc[`VADDR_SIZE-1: `JALR_OFFSET+1];
    assign tail_taken = entry_i.tailSlot.en && entry_i.tailSlot.br_type != CONDITION;
`ifdef RVC
    assign fthOffset = entry_i.fthAddr + {~entry_i.fth_rvc, entry_i.fth_rvc};
`else
    assign fthOffset = entry_i.fthAddr + 1;
`endif
    assign tail_target = tail_taken ? tail_indirect_target : {fthOffset, {`INST_OFFSET{1'b0}}} + pc;
    assign br_target_high = br_tar_state == TAR_OV ? pc[`VADDR_SIZE-1: `JAL_OFFSET+1] + 1 :
                            br_tar_state == TAR_UN ? pc[`VADDR_SIZE-1: `JAL_OFFSET+1] - 1 :
                                                     pc[`VADDR_SIZE-1: `JAL_OFFSET+1];
    assign br_target = {br_target_high, br_offset, 1'b0};
    assign predict_pc = |br_takens ? br_target : tail_target;
    assign older = entry_i.slots[0].offset < entry_i.tailSlot.offset;

    always_comb begin
        if(br_takens[1] & ~older)begin
            cond_num = 2'b1;
            cond_valid = 2'b10;
            br_size = entry_i.tailSlot.offset;
            br_offset = entry_i.tailSlot.target[`JAL_OFFSET-1: 0];
            br_tar_state = entry_i.tailSlot.tar_state;
`ifdef RVC
            br_rvc = entry_i.tailSlot.rvc;
`endif
        end
        else begin
            cond_num = isBr[0] + isBr[1];
            cond_valid = isBr;
            br_size = br_size_normal;
            br_offset = br_offset_normal;
            br_tar_state = br_tar_state_normal;
`ifdef RVC
            br_rvc = br_rvc_normal;
`endif
        end
    end

    assign ras_io.request = result_i.en & (~stall | result_o.redirect) & btb_hit & 
                ~(|br_takens) & entry_i.tailSlot.en & (entry_i.tailSlot.br_type == CALL);
    assign ras_io.ras_type = entry_i.tailSlot.ras_type;
`ifdef RVC
    assign ras_io.target = pc + {entry_i.tailSlot.offset, {`INST_OFFSET{1'b0}}} +
                            {~entry_i.tailSlot.rvc, entry_i.tailSlot.rvc, 1'b0};
`else
    assign ras_io.target = pc + {entry_i.tailSlot.offset, {`INST_OFFSET{1'b0}}} + 4;
`endif

    always_comb begin
        if(ras_io.en && entry_i.tailSlot.ras_type[0])begin
            tail_indirect_target = ras_io.entry.pc;
        end
        else begin
            tail_indirect_target = {tail_target_high, entry_i.tailSlot.target, 1'b0};
        end
        result_o.redirect = btb_hit & (predict_pc != result_i.stream.target);
        result_o.stream.taken = btb_hit & ((|br_takens) | tail_taken);
        result_o.btb_hit = btb_hit;
        result_o.br_type = |br_takens ? CONDITION : entry_i.tailSlot.br_type;
        result_o.ras_type = entry_i.tailSlot.ras_type;
        result_o.stream.size = ~btb_hit ? result_i.stream.size : 
                               |br_takens ? br_size : tail_size;
`ifdef RVC
        result_o.stream.rvc = ~btb_hit ? 0 : 
                                |br_takens ? br_rvc :
                                tail_taken ? entry_i.tailSlot.rvc : entry_i.fth_rvc;
`endif
        result_o.stream.target = ~btb_hit ? result_i.stream.target : predict_pc;
        result_o.cond_num = ~btb_hit ? 0 : cond_num;
        result_o.cond_valid = cond_valid;
        result_o.taken = (|br_takens) | tail_taken;
        result_o.predTaken = br_takens;
        result_o.btbEntry = entry_i;
        result_o.btbEntry.en = btb_hit & entry_i.en;
        result_o.en = result_i.en;
        result_o.stream.start_addr = result_i.stream.start_addr;
        result_o.stream_idx = result_i.stream_idx;
        result_o.stream_dir = result_i.stream_dir;
        result_o.redirect_info = result_i.redirect_info;
        result_o.redirect_info.rasInfo = ras_io.rasInfo;
        result_o.redirect_info.rasInfo.ras_type = entry_i.tailSlot.ras_type;
        // result_o.redirect_info.ras_ctr = ras_entry.ctr;
    end
endmodule