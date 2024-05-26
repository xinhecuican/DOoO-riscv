`include "../../defines/defines.svh"

module HistoryControl(
    input logic clk,
    input logic rst,
    input PredictionResult result,
    input RedirectCtrl redirect,
    input logic squash,
    input SquashInfo squashInfo,
    output BranchHistory history
);
    logic `N(`GHIST_SIZE) ghist;
    TageFoldHistory tage_history, tage_input_history, tage_update_history;
    logic `N(`GHIST_WIDTH) pos;
    /* verilator lint_off UNOPTFLAT */
    logic `N(`GHIST_WIDTH) we_idx `N(`SLOT_NUM);
    logic `N(`SLOT_NUM) ghist_we;
    logic `N(`SLOT_NUM) cond_result;
    logic prediction_redirect;

    logic [1: 0] squashCondNum;
    logic `N(2) condNum;
    logic taken;

    assign prediction_redirect = redirect.s2_redirect;
    assign squashCondNum = squashInfo.predInfo.condNum;
    assign condNum = squash ? squashCondNum : result.cond_num;
    assign taken = squash ? squashInfo.predInfo.taken : result.taken;
    assign ghist_we[0] = (squash & (|squashCondNum)) | 
                        (~squash & (|result.cond_num));
    assign ghist_we[1] = (squash & squashCondNum[1]) | 
                        (~squash & result.cond_num[1]);
    assign we_idx[0] =  redirect.flush ? squashInfo.redirectInfo.ghistIdx : 
                        prediction_redirect ? result.redirect_info.ghistIdx : pos;
    assign we_idx[1] = we_idx[0] + 1;
    assign cond_result = taken << (condNum - 1);
    assign tage_input_history = redirect.flush ? squashInfo.redirectInfo.tage_history :
                           prediction_redirect ? result.redirect_info.tage_history : tage_history;
    /* verilator lint_off UNOPTFLAT */
    assign history.ghistIdx = redirect.flush ? squashInfo.redirectInfo.ghistIdx : 
                       prediction_redirect ? result.cond_num + result.redirect_info.ghistIdx : pos;
    assign history.tage_history = tage_history;
generate;
    for(genvar i=0; i<`TAGE_BANK; i++)begin
        logic [`SLOT_NUM-1: 0] reverse_dir;
        assign reverse_dir[0] = ghist[history.ghistIdx-tage_hist_length[i]];
        assign reverse_dir[1] = ghist[history.ghistIdx-tage_hist_length[i]+1];
        CompressHistory #(
            .COMPRESS_LENGTH(`TAGE_SET_WIDTH),
            .ORIGIN_LENGTH(tage_hist_length[i]),
            .HIST_SIZE(`SLOT_NUM)
        ) compress_tage_index(
            .origin(tage_input_history.fold_idx[i]),
            .condNum(condNum),
            .dir(taken),
            .reverse_dir(reverse_dir),
            .out(tage_update_history.fold_idx[i])
        );
        CompressHistory #(
            .COMPRESS_LENGTH(`TAGE_TAG_COMPRESS1),
            .ORIGIN_LENGTH(tage_hist_length[i]),
            .HIST_SIZE(`SLOT_NUM)
        ) compress_tage_tag1(
            .origin(tage_input_history.fold_tag1[i]),
            .condNum(condNum),
            .dir(taken),
            .reverse_dir(reverse_dir),
            .out(tage_update_history.fold_tag1[i])
        );
        CompressHistory #(
            .COMPRESS_LENGTH(`TAGE_TAG_COMPRESS2),
            .ORIGIN_LENGTH(tage_hist_length[i]),
            .HIST_SIZE(`SLOT_NUM)
        ) compress_tage_tag2(
            .origin(tage_input_history.fold_tag2[i]),
            .condNum(condNum),
            .dir(taken),
            .reverse_dir(reverse_dir),
            .out(tage_update_history.fold_tag2[i])
        );
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            ghist <= 0;
            pos <= 0;
            tage_history <= 0;
        end
        else begin
            pos <= squash ? squashCondNum + squashInfo.redirectInfo.ghistIdx :
                   prediction_redirect ? result.cond_num + result.redirect_info.ghistIdx :
                   result.en ? result.cond_num + pos : pos;
            if(|ghist_we)begin
                tage_history <= tage_update_history;
            end
            for(int i=0; i<`SLOT_NUM; i++)begin
                if(ghist_we[i])begin
                    ghist[we_idx[i]] <= cond_result[i];
                end
            end
        end
    end
endmodule

module CompressHistory #(
	parameter COMPRESS_LENGTH=8,
	parameter ORIGIN_LENGTH=10,
    parameter HIST_SIZE=1,
	parameter OUTPUT_POINT=ORIGIN_LENGTH%COMPRESS_LENGTH
)(
	input logic [COMPRESS_LENGTH-1: 0] origin,
    input logic [HIST_SIZE-1: 0] condNum,
	input logic dir,
	input logic [HIST_SIZE-1: 0] reverse_dir,
	output logic [COMPRESS_LENGTH-1: 0] out
);
    always_comb begin
        if(condNum == 1)begin
            out = (origin << 1) ^ dir ^ (reverse_dir << OUTPUT_POINT) ^ origin[0];
        end
        else begin
            out = (origin << 2) ^ dir ^ (reverse_dir << OUTPUT_POINT) ^ origin[1: 0];
        end
    end
endmodule