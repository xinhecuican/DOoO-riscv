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
    logic `N(`SC_GHIST_WIDTH) sc_ghist, sc_ghist_red;
    logic `N(`SC_IMLI_WIDTH) imli, imli_red;
    logic `N(`GHIST_WIDTH) pos;
    logic `ARRAY(`SLOT_NUM, `GHIST_WIDTH) we_idx;
    logic `N(`SLOT_NUM) ghist_we;
    logic `N(`SLOT_NUM) cond_result;
    logic prediction_redirect;

    logic [1: 0] squashCondNum;
    logic `N(2) condNum;
    logic taken;

    assign prediction_redirect = redirect.s2_redirect | redirect.s3_redirect;
    assign squashCondNum = squashInfo.predInfo.condNum;
    assign condNum = squash ? squashCondNum : result.cond_num;
    assign taken = squash ? squashInfo.predInfo.taken : |result.predTaken;
    assign ghist_we[0] = (squash & (|squashCondNum)) | 
                        (~squash & result.en & (|result.cond_num));
    assign ghist_we[1] = (squash & squashCondNum[1]) | 
                        (~squash & result.en & result.cond_num[1]);
    assign we_idx[0] =  redirect.flush ? squashInfo.redirectInfo.ghistIdx : 
                                        result.redirect_info.ghistIdx;
    assign we_idx[1] = redirect.flush ? squashInfo.redirectInfo.ghistIdx + 1 : 
                                        result.redirect_info.ghistIdx + 1;
    assign sc_ghist_red = result.en & result.redirect ? result.redirect_info.sc_ghist : sc_ghist;
    assign imli_red = result.en & result.redirect ? result.redirect_info.imli : imli;
generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        assign cond_result[i] = (condNum == (i+1)) & taken;
    end
endgenerate
    assign tage_input_history = redirect.flush ? squashInfo.redirectInfo.tage_history :
                                                 result.redirect_info.tage_history;
    assign history.ghistIdx = pos;
    assign history.tage_history = tage_history;
    assign history.sc_ghist = sc_ghist;
    assign history.imli = imli;
    localparam [`TAGE_BANK*16-1: 0] tage_hist_length = `TAGE_HIST_LENGTH;
generate;
    for(genvar i=0; i<`TAGE_BANK; i++)begin
        logic [`SLOT_NUM-1: 0] reverse_dir;
        logic `ARRAY(`SLOT_NUM, `GHIST_WIDTH) reverse_idx;
        for(genvar j=0; j<`SLOT_NUM; j++)begin
            assign reverse_idx[j] = history.ghistIdx-tage_hist_length[i*16 +: 16] + j;
            assign reverse_dir[j] = ghist[reverse_idx[j]];
        end
        CompressHistory #(
            .COMPRESS_LENGTH(`TAGE_SET_WIDTH),
            .ORIGIN_LENGTH(tage_hist_length[i*16 +: 16]),
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
            .ORIGIN_LENGTH(tage_hist_length[i*16 +: 16]),
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
            .ORIGIN_LENGTH(tage_hist_length[i*16 +: 16]),
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

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            ghist <= 0;
            pos <= 0;
            tage_history <= 0;
            sc_ghist <= 0;
            imli <= 0;
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
            if(squash)begin
                if(squashCondNum == 2)begin
                    sc_ghist <= {squashInfo.redirectInfo.sc_ghist[`SC_GHIST_WIDTH-3: 0], 1'b0, squashInfo.predInfo.taken};
                    imli <= squashInfo.predInfo.taken;
                end
                else if(squashCondNum == 1)begin
                    sc_ghist <= {squashInfo.redirectInfo.sc_ghist[`SC_GHIST_WIDTH-2: 0], squashInfo.predInfo.taken};
                    imli <= squashInfo.predInfo.taken ? squashInfo.redirectInfo.imli + 1 : 0;
                end
                else begin
                    sc_ghist <= squashInfo.redirectInfo.sc_ghist;
                    imli <= squashInfo.redirectInfo.imli;
                end
            end
            else if(result.en)begin
                if(result.cond_num == 2)begin
                    sc_ghist <= {sc_ghist_red[`SC_GHIST_WIDTH-3: 0], 1'b0, |result.predTaken};
                    imli <= |result.predTaken;
                end
                else if(result.cond_num == 1)begin
                    sc_ghist <= {sc_ghist_red[`SC_GHIST_WIDTH-2: 0], |result.predTaken};
                    imli <= |result.predTaken ? imli_red + 1 : 0;
                end
            end
        end
    end

`ifdef DIFFTEST
    logic [31: 0] diff_hist;
    logic squash_next;
    always_ff @(posedge clk)begin
        squash_next <= squash;
    end
generate
    for(genvar i=0; i<32; i++)begin
        logic `N(`GHIST_WIDTH) diff_pos;
        assign diff_pos = pos -1 - i;
        assign diff_hist[i] = ghist[diff_pos];
    end
endgenerate
    `Log(DLog::Debug, T_BR_HIST, squash_next, $sformatf("branch hist [%h]. %32b", pos, diff_hist))
`endif
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
generate
    if(ORIGIN_LENGTH < COMPRESS_LENGTH)begin
        always_comb begin
            if(condNum == 1)begin
                out = (origin << 1) | dir;
            end
            else begin
                out = (origin << 2) | dir;
            end
        end
    end
    else begin
        always_comb begin
            if(condNum == 1)begin
                out = ((origin << 1) | dir) ^ {reverse_dir, {OUTPUT_POINT{1'b0}}} ^ origin[COMPRESS_LENGTH-1];
            end
            else begin
                out = ((origin << 2) | dir) ^ {reverse_dir, {OUTPUT_POINT{1'b0}}} ^ origin[COMPRESS_LENGTH-1: COMPRESS_LENGTH-2];
            end
        end
    end
endgenerate

endmodule