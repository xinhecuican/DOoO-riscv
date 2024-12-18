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
        .result(bpu_fsq_io.prediction),
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

`ifdef T_DEBUG
    assign ras_io.lastStage = s2_result_out.en  & ~redirect.flush;
    assign ras_io.lastStageIdx = s2_result_out.stream_idx;
`endif
`ifdef FEAT_LINKRAS
    LinkRAS ras(.*);
`else
    RAS ras(.*);
`endif
    
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

module PredictionResultGen #(
    parameter RASV=0,
    parameter REDIRECTV=0
)(
    input logic `VADDR_BUS pc,
    input logic hit,
    input BTBUpdateInfo entry,
    input logic `N(`SLOT_NUM) prediction,
    input logic `VADDR_BUS ras_addr,
    input RasRedirectInfo rasInfo,
    input PredictionResult result_i,
    output PredictionResult result_o
);
    logic `N(`SLOT_NUM) isBr, br_takens, carry;
    logic `ARRAY(`SLOT_NUM, `PREDICTION_WIDTH) offsets;
    logic `ARRAY(`SLOT_NUM, `JAL_OFFSET) br_targets;
    TargetState `N(`SLOT_NUM) tar_states;
    logic `N(`JAL_OFFSET) br_offset;
    TargetState br_tar_state;

    logic `N(`PREDICTION_WIDTH) tail_size;
    logic tail_taken;
    TargetState tail_tar_state;
    logic `N(`PREDICTION_WIDTH+1) fthOffset;

    logic [`VADDR_SIZE-`JAL_OFFSET-1: 0] br_target_high;
    logic [`VADDR_SIZE-`JALR_OFFSET-1: 0] tail_target_high;
    logic `VADDR_BUS tail_target, br_target, tail_indirect_target, predict_pc;
`ifdef RVC
    logic br_rvc;
`endif
    logic `N(`PREDICTION_WIDTH) br_size;
    logic `N(`SLOT_NUM) cond_num, cond_valid, predTaken;
    logic older;

    assign br_takens = isBr & (prediction | carry);
generate;
    for(genvar br=0; br<`SLOT_NUM-1; br++)begin
        assign isBr[br] = entry.slots[br].en;
        assign carry[br] = entry.slots[br].carry;
        assign offsets[br] = entry.slots[br].offset;
        assign br_targets[br] = entry.slots[br].target;
        assign tar_states[br] = entry.slots[br].tar_state;
    end
    assign isBr[`SLOT_NUM-1] = entry.tailSlot.en && entry.tailSlot.br_type == CONDITION;
    assign carry[`SLOT_NUM-1] = entry.tailSlot.carry;
    assign offsets[`SLOT_NUM-1] = entry.tailSlot.offset;
    assign br_targets[`SLOT_NUM-1] = entry.tailSlot.target[`JAL_OFFSET-1: 0];
    assign tar_states[`SLOT_NUM-1] = entry.tailSlot.tar_state;
endgenerate
    assign older = offsets[0] < offsets[1];
    always_comb begin
        if(br_takens[0] & (older | ~br_takens[1] & ~older))begin
            br_offset = br_targets[0];
            br_size = offsets[0];
            br_tar_state = tar_states[0];
`ifdef RVC
            br_rvc = entry.slots[0].rvc;
`endif
        end
        else begin
            br_offset = br_targets[1];
            br_size = offsets[1];
            br_tar_state = tar_states[1];
`ifdef RVC
            br_rvc = entry.tailSlot.rvc;
`endif
        end
        predTaken[0] = br_takens[0] & (older | ~br_takens[1] & ~older);
        predTaken[1] = br_takens[1] & (~older | ~br_takens[0] & older);
        cond_valid[0] = isBr[0] & ~(br_takens[1] & ~older);
        cond_valid[1] = isBr[1] & ~(br_takens[0] & older);
        if(isBr[0] & isBr[1] & ~(br_takens[0] & older) & ~(br_takens[1] & ~older))begin
            cond_num = 2'b10;
        end
        else if(isBr[0] | isBr[1])begin
            cond_num = 2'b01;
        end
        else begin
            cond_num = 2'b00;
        end
    end
    assign br_target_high = br_tar_state == TAR_OV ? pc[`VADDR_SIZE-1: `JAL_OFFSET+1] + 1 :
                            br_tar_state == TAR_UN ? pc[`VADDR_SIZE-1: `JAL_OFFSET+1] - 1 :
                                                     pc[`VADDR_SIZE-1: `JAL_OFFSET+1];
    assign br_target = {br_target_high, br_offset, 1'b0};

    assign tail_size = tail_taken ? entry.tailSlot.offset : entry.fthAddr;
    assign tail_tar_state = entry.tailSlot.tar_state;
    assign tail_taken = entry.tailSlot.en && entry.tailSlot.br_type != CONDITION;
`ifdef RVC
    assign fthOffset = entry.fthAddr + {~entry.fth_rvc, entry.fth_rvc};
`else
    assign fthOffset = entry.fthAddr + 1;
`endif
    assign tail_target_high = tail_tar_state == TAR_OV ? pc[`VADDR_SIZE-1: `JALR_OFFSET+1] + 1 :
                            tail_tar_state == TAR_UN ? pc[`VADDR_SIZE-1: `JALR_OFFSET+1] - 1 :
                                                     pc[`VADDR_SIZE-1: `JALR_OFFSET+1];
generate
    if(RASV)begin
        assign tail_indirect_target = entry.tailSlot.br_type == CALL && entry.tailSlot.ras_type[0] ?
                                      ras_addr : {tail_target_high, entry.tailSlot.target, 1'b0};
    end
    else begin
        assign tail_indirect_target = {tail_target_high, entry.tailSlot.target, 1'b0};
    end
endgenerate
    assign tail_target = tail_taken ? tail_indirect_target : {fthOffset, {`INST_OFFSET{1'b0}}} + pc;
    assign predict_pc = |br_takens ? br_target : tail_target;

    always_comb begin
        if(REDIRECTV)begin
            result_o.redirect = hit & ((predTaken != result_i.predTaken) | 
                    tail_taken & (tail_indirect_target != result_i.stream.target));
        end
        else begin
            result_o.redirect = 0;
        end
        result_o.stream.taken = hit & ((|br_takens) | tail_taken);
        result_o.btb_hit = hit;
        result_o.br_type = |br_takens ? CONDITION : entry.tailSlot.br_type;
        result_o.ras_type = entry.tailSlot.ras_type;
        result_o.stream.size = ~hit ? result_i.stream.size : 
                               |br_takens ? br_size : tail_size;
`ifdef RVC
        result_o.stream.rvc = ~hit ? 0 : 
                                |br_takens ? br_rvc :
                                tail_taken ? entry.tailSlot.rvc : entry.fth_rvc;
`endif
        result_o.stream.target = ~hit ? result_i.stream.target : predict_pc;
        result_o.cond_num = ~hit ? 0 : cond_num;
        result_o.cond_valid = cond_valid;
        result_o.taken = (|br_takens) | tail_taken;
        result_o.tail_taken = ~(|br_takens) & tail_taken;
        result_o.predTaken = predTaken;
        result_o.btbEntry = ~hit ? 0 : entry;
        result_o.btbEntry.en = hit & entry.en;
        result_o.en = result_i.en;
        result_o.stream.start_addr = result_i.stream.start_addr;
        result_o.stream_idx = result_i.stream_idx;
        result_o.stream_dir = result_i.stream_dir;
        result_o.redirect_info = result_i.redirect_info;
        if(RASV)begin
            result_o.redirect_info.rasInfo = rasInfo;
            result_o.redirect_info.rasInfo.ras_type = entry.tailSlot.ras_type;
        end
    end
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
    logic `N(`SLOT_NUM) cond_valid, predTaken;
    logic `N(`BTB_TAG_SIZE) lookup_tag;
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
    PredictionResultGen #(
        .RASV(1),
        .REDIRECTV(1)
    ) result_gen (
        .pc,
        .hit(btb_hit),
        .entry(entry_i),
        .prediction,
        .ras_addr(ras_io.entry.pc),
        .rasInfo(ras_io.rasInfo),
        .result_i,
        .result_o
    );

    assign ras_io.request = result_i.en & (~stall | result_o.redirect) & btb_hit & 
                            result_o.tail_taken & (result_o.br_type == CALL);
    assign ras_io.ras_type = entry_i.tailSlot.ras_type;
`ifdef RVC
    assign ras_io.target = pc + {entry_i.tailSlot.offset, {`INST_OFFSET{1'b0}}} +
                            {~entry_i.tailSlot.rvc, entry_i.tailSlot.rvc, 1'b0};
`else
    assign ras_io.target = pc + {entry_i.tailSlot.offset, {`INST_OFFSET{1'b0}}} + 4;
`endif

endmodule