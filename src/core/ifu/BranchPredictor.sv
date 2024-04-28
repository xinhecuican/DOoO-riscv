`include "../../defines/defines.svh"
module BranchPredictor(
    input logic clk,
    input logic rst,
    BpuFsqIO.bpu bpu_fsq_io
);
    logic `VADDR_BUS pc;
    BranchHistory history;
    RedirectCtrl redirect;
    SquashInfo squashInfo;
    logic squash;
    BpuBtbIO btb_io(.*);
    BpuTageIO tage_io(.*);
    BpuUBtbIO ubtb_io(.*);
    BpuRASIO ras_io(.*);
    logic `N(`GHIST_WIDTH) ghist_idx;

    PredictionResult s1_result;
    PredictionResult s2_result_in, s2_result_out;
    PredictionResult s3_result_in, s3_result_out;

    assign squash = bpu_fsq_io.squash;
    assign squashInfo = bpu_fsq_io.squashInfo;
    assign btb_io.pc = pc;
    assign btb_io.request = 1'b1;
    BTB btb(.*);
    assign tage_io.history = history;
    Tage tage(.*);

    HistoryControl history_control(
        .*,
        .result(bpu_fsq_io.prediction),
        .redirect(bpu_fsq_io.redirect),
        .ghist_idx(ghist_idx),
        .history(history)
    );
    
    assign s1_result = ubtb_io.result;
    assign ubtb_io.fsqIdx = bpu_fsq_io.stream_idx;
    assign ubtb_io.ghistIdx = ghist_idx;
    assign ubtb_io.history = history;
    UBTB ubtb(.*);

    RAS ras(.*);
    
    assign redirect.s2_redirect = s2_result_out.en && s2_result_out.redirect[0];
    assign redirect.flush = bpu_fsq_io.squash;
    assign redirect.stall = bpu_fsq_io.stall;
    always_ff @(clk)begin
        if(rst == `RST)begin
            pc <= `RESET_PC;
        end
        else begin
            pc <= redirect.flush ? bpu_fsq_io.flush_pc :
                  redirect.stall ? pc :
                  redirect.s2_redirect ? s2_result_out.stream.target :
                    s1_result.stream.target;
        end

        if(rst == `RST || redirect.s2_redirect)begin
            s2_result_in <= '{default: 0};
        end
        else if(!redirect.stall)begin
            s2_result_in <= s1_result;
        end

        if(rst == `RST)begin
            s3_result_in <= '{default: 0};
        end
        else if(!redirect.stall)begin
            s3_result_in <= s2_result_out;
        end
    end

    assign bpu_fsq_io.en = bpu_fsq_io.prediction.en;
    assign bpu_fsq_io.prediction = redirect.s2_redirect ? s2_result_out : s1_result;
    assign bpu_fsq_io.redirect = redirect.s2_redirect;

    S2Control s2_control(
        .pc(s2_result_in.stream.start_addr),
        .entry(btb_io.entry),
        .prediction(tage_io.prediction),
        .rasIdx(ras_io.rasIdx),
        .ras_entry(ras_io.entry),
        .result_i(s2_result_in),
        .result_o(s2_result_out)
    );


endmodule

module S2Control(
    input logic `VADDR_BUS pc,
    input BTBEntry entry,
    input logic `N(2) prediction,
    input logic `N(`RAS_WIDTH) rasIdx,
    input RasEntry ras_entry,
    input PredictionResult result_i,
    output PredictionResult result_o
);
    logic `VADDR_BUS predict_pc;
    logic hit;
    logic `N(`SLOT_NUM) isBr;
    logic `N(`SLOT_NUM) br_takens;
    logic `N(`JAL_OFFSET) br_offset;
    logic `N(`PREDICTION_WIDTH) br_size, tail_size;
    logic `VADDR_BUS tail_target, br_target, tail_indirect_target;
    logic [1: 0] cond_num;

    assign hit = entry.en && (pc`BTB_TAG_BUS == entry.tag);
    assign br_takens = isBr & prediction;
    generate;
        for(genvar br=0; br<`SLOT_NUM-1; br++)begin
            assign isBr[br] = entry.slots[br].en;
        end
        assign isBr[`SLOT_NUM-1] = entry.tailSlot.en &&
                                        entry.tailSlot.br_type == CONDITION;
    endgenerate
    PMux2 #(`JAL_OFFSET) pmux2_br_offset(br_takens, 
                                        entry.slots[0].offset,entry.tailSlot.offset[`JAL_OFFSET-1: 0],
                                        br_offset);
    PMux2 #(`PREDICTION_WIDTH) pmux2_br_size(br_takens, 
                                        entry.slots[0].offset,entry.tailSlot.offset,
                                        br_size);
    assign tail_target = entry.tailSlot.en ? tail_indirect_target : entry.fthAddr + pc;
    assign br_target = {{(`VADDR_SIZE-`JAL_OFFSET){br_offset[`JAL_OFFSET-1]}}, br_offset} + pc;
    assign predict_pc = |br_takens ? br_target : tail_target;
    assign cond_num = isBr[0] + isBr[1];
    always_comb begin
        case(entry.tailSlot.br_type)
        CONDITION, INDIRECT, DIRECT:begin
            tail_indirect_target = {{(`VADDR_SIZE-`JALR_OFFSET){entry.tailSlot.target[`JALR_OFFSET-1]}}, 
                                    entry.tailSlot.target} + pc;
        end
        CALL:begin
            tail_indirect_target = ras_entry.pc;
        end
        endcase
        if(hit && predict_pc != result_i.target)begin
            result_o.stream.taken = |br_takens;
            result_o.stream.br_type = |br_takens ? CONDITION : entry.tailSlot.br_type;
            result_o.stream.ras_type = entry.tailSlot.ras_type;
            result_o.stream.size = |br_takens ? br_size : tail_size;
            result_o.stream.target = predict_pc;
            result_o.redirect = 1;
            result_o.cond_num = cond_num;
            result_o.cond_history = prediction;
        end
        else begin
            result_o.stream.taken = result_i.taken;
            result_o.stream.br_type = result_i.br_type;
            result_o.stream.ras_type = result_i.ras_type;
            result_o.stream.target = result_i.target;
            result_o.stream.size = result_i.stream.size;
            result_o.redirect = result_i.redirect;
            result_o.cond_num = result_i.cond_num;
            result_o.cond_history = result_i.cond_history;
        end
        result_o.en = 1'b1;
        result_o.stream.start_addr= result_i.stream.start_addr;
        result_o.stream_idx = result_i.stream_idx;
        result_o.redirect_info.rasIdx = rasIdx;
        result_o.redirect_info.ras_ctr = ras_entry.ctr;
    end
endmodule