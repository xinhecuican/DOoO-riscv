`include "../../defines/defines.svh"

module SC(
    input logic clk,
    input logic rst,
    BpuSCIO.sc io
);

    logic `N($clog2(`SC_THRESH_DEPTH)) thresh_idx;
    logic `ARRAY(`SLOT_NUM, `SC_THRESH_CTR) thresh_data;
    logic `ARRAY(`SLOT_NUM, `SC_GTHRESH_CTR) gthresh, gthresh_update;
    logic `ARRAY(`SLOT_NUM, `SC_GTHRESH_CTR+1) lookup_thresh;

    localparam SC_ALL_SIZE = `SC_CTR_SIZE-1+$clog2(`SC_TABLE_NUM);
    logic `TENSOR(`SC_TABLE_NUM, `SLOT_NUM, `SC_CTR_SIZE) sc_ctrs;
    logic `N(`SLOT_NUM) prediction, sc_prediction;

    SCMeta meta;
    RedirectInfo r;
    BTBUpdateInfo btbEntry;
    logic `N(`SLOT_NUM) u_slot_en, update_en, update_sc, pred_error;
    logic `ARRAY(`SC_HIST_NUM, `SC_SET_WIDTH) hist_update_idx;
    logic `TENSOR(`SC_HIST_NUM, `SLOT_NUM, `SC_CTR_SIZE) hist_update_ctr;
    logic `ARRAY(`SC_IMLI_NUM+1, `SC_SET_WIDTH) imli_update_idx;
    logic `TENSOR(`SC_IMLI_NUM+1, `SLOT_NUM, `SC_CTR_SIZE) imli_update_ctr;
    logic `N($clog2(`SC_THRESH_DEPTH)) thresh_update_idx;
    logic `ARRAY(`SLOT_NUM, `SC_THRESH_CTR) thresh_update_ctr;

    localparam TAGE_WEAK_TAKEN = 1 << (`TAGE_CTR_SIZE - 1);
generate
    localparam [`SC_HIST_NUM*16-1: 0] sc_hist_length  = `SC_HIST_LENGTH;
    localparam [`SC_HIST_NUM*16-1: 0] sc_hist_depth = `SC_HIST_DEPTH;
    localparam [`SC_HIST_NUM*16-1: 0] sc_hist_thresh = `SC_HIST_THRESH_DEPTH;
    for(genvar i=0; i<`SC_HIST_NUM; i++)begin
        logic `N($clog2(sc_hist_depth[i*16 +: 16])) idx;
        SCGIndex #(
            $clog2(sc_hist_depth[i*16 +: 16]), 
            sc_hist_length[i*16 +: 16],
            `SC_GHIST_WIDTH
        ) gindex (io.pc, io.history.sc_ghist, idx);
        localparam CURRENT_THRESH = $clog2(sc_hist_thresh[i*16 +: 16]);
        logic `N(CURRENT_THRESH) sc_thresh_idx;
        assign sc_thresh_idx = io.pc[`INST_OFFSET +: CURRENT_THRESH] ^
                               io.pc[`INST_OFFSET + CURRENT_THRESH +: CURRENT_THRESH];
        SCTable #(
            .WIDTH(`SC_CTR_SIZE),
            .DEPTH(sc_hist_depth[i*16 +: 16]),
            .THRESH_WIDTH(`SC_CTR_SIZE),
            .THRESH_HEIGHT(sc_hist_thresh[i*16 +: 16]),
            .RESET_VALUE({`SLOT_NUM{`SC_HIST_INIT}})
        ) sc_table (
            .clk,
            .rst,
            .en(~io.redirect.stall),
            .lookup_idx(idx),
            .lookup_ctr(sc_ctrs[i]),
            .update_en(update_en),
            .update_idx(hist_update_idx[i]),
            .update_ctr(hist_update_ctr[i])
        );
    end
    
    localparam [`SC_IMLI_NUM*16: 0] sc_imli_depth = `SC_IMLI_DEPTH;
    localparam [`SC_IMLI_NUM*16: 0] sc_imli_thresh = `SC_IMLI_THRESH_DEPTH;
    for(genvar i=0; i<`SC_IMLI_NUM; i++)begin
        logic `N($clog2(sc_imli_depth[i*16 +: 16])) idx;
        SCGIndex #(
            $clog2(sc_imli_depth[i*16 +: 16]),
            `SC_IMLI_WIDTH,
            `SC_IMLI_WIDTH
        ) gindex (io.pc, io.history.imli, idx);
        localparam CURRENT_THRESH = $clog2(sc_imli_thresh[i*16 +: 16]);
        logic `N(CURRENT_THRESH) sc_thresh_idx;
        assign sc_thresh_idx = io.pc[`INST_OFFSET +: CURRENT_THRESH] ^
                               io.pc[`INST_OFFSET + CURRENT_THRESH +: CURRENT_THRESH];
        SCTable #(
            .WIDTH(`SC_CTR_SIZE),
            .DEPTH(sc_imli_depth[i*16 +: 16]),
            .THRESH_WIDTH(`SC_CTR_SIZE),
            .THRESH_HEIGHT(sc_imli_thresh[i*16 +: 16]),
            .RESET_VALUE({`SLOT_NUM{`SC_IMLI_INIT}})
        ) sc_table (
            .clk,
            .rst,
            .en(~io.redirect.stall),
            .lookup_idx(idx),
            .lookup_ctr(sc_ctrs[i+`SC_HIST_NUM]),
            .update_en(update_en),
            .update_idx(imli_update_idx[i]),
            .update_ctr(imli_update_ctr[i])
        );
    end
endgenerate

    SCThreshGIndex #($clog2(`SC_THRESH_DEPTH)) thresh_gindex (io.pc, thresh_idx);
    SCThreshGIndex #($clog2(`SC_THRESH_DEPTH)) thresh_update_gindex (io.updateInfo.start_addr, thresh_update_idx);
    MPRAM #(
        .WIDTH(`SC_THRESH_CTR * `SLOT_NUM),
        .DEPTH(`SC_THRESH_DEPTH),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1)
    ) thresh_ram (
        .clk,
        .rst,
        .rst_sync(0),
        .en(~io.redirect.stall),
        .raddr(thresh_idx),
        .rdata(thresh_data),
        .we(|update_en),
        .waddr(thresh_update_idx),
        .wdata(thresh_update_ctr),
        .ready()
    );

// lookup
    logic `ARRAY(`SLOT_NUM, SC_ALL_SIZE) sc_thresh_all;
    logic `ARRAY(`SLOT_NUM, `SC_CTR_SIZE+$clog2(`SC_TABLE_NUM)) sc_ctrs_all;
    logic `TENSOR(`SLOT_NUM, `SC_TABLE_NUM, `SC_CTR_SIZE-1) sc_thresh_val;
    logic `TENSOR(`SLOT_NUM, `SC_TABLE_NUM, `SC_CTR_SIZE) sc_ctrs_rev;

generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        for(genvar j=0; j<`SC_TABLE_NUM; j++)begin
            assign sc_thresh_val[i][j] = sc_ctrs[j][i][`SC_CTR_SIZE-1] ? sc_ctrs[j][i][`SC_CTR_SIZE-2: 0] : 
                                        {1'b1, {`SC_CTR_SIZE-1{1'b0}}} - sc_ctrs[j][i];
            assign sc_ctrs_rev[i][j] = sc_ctrs[j][i];
        end
        ParallelAdder #(`SC_CTR_SIZE-1, `SC_TABLE_NUM) adder_ctrs_thresh (sc_thresh_val[i], sc_thresh_all[i]);
        ParallelAdder #(`SC_CTR_SIZE, `SC_TABLE_NUM) adder_ctrs (sc_ctrs_rev[i], sc_ctrs_all[i]);
        logic low_conf, mid_conf, high_conf;
        assign low_conf = (io.tage_ctrs[i] == TAGE_WEAK_TAKEN) || 
                          (io.tage_ctrs[i] == (TAGE_WEAK_TAKEN - 1));
        assign mid_conf = (io.tage_ctrs[i] == (TAGE_WEAK_TAKEN + 1)) || 
                          (io.tage_ctrs[i] == (TAGE_WEAK_TAKEN - 2));
        assign high_conf = ~low_conf & ~mid_conf;

        assign lookup_thresh[i] = thresh_data[i] + gthresh[i];
        
        logic use_sc;
        assign use_sc = low_conf ||
                        (mid_conf && (sc_thresh_all[i] > lookup_thresh[i][`SC_THRESH_CTR-1: 2])) ||
                        (high_conf && (sc_thresh_all[i] > lookup_thresh[i][`SC_THRESH_CTR-1: 1]));

        assign sc_prediction[i] = sc_ctrs_all[i][`SC_CTR_SIZE+$clog2(`SC_TABLE_NUM)-1];
        assign prediction[i] = use_sc ? sc_prediction[i] : io.tage_prediction[i];
    end
endgenerate
    always_ff @(posedge clk)begin
        io.prediction <= prediction;
        io.meta.ctr <= sc_ctrs;
        io.meta.predTaken <= sc_prediction;
        io.meta.thresh_ctr <= thresh_data;
        for(int i=0; i<`SLOT_NUM; i++)begin
            io.meta.thresh_update[i] <= sc_thresh_all[i] < lookup_thresh[i];
        end
    end

// update

    assign meta = io.updateInfo.meta.sc;
    assign r = io.updateInfo.redirectInfo;
    assign btbEntry = io.updateInfo.btbEntry;

generate
	for(genvar i=0; i<`SLOT_NUM-1; i++)begin
		assign u_slot_en[i] = io.update & io.updateInfo.allocSlot[i] & btbEntry.slots[i].en & ~btbEntry.slots[i].carry;
	end
	assign u_slot_en[`SLOT_NUM-1] = io.update & btbEntry.tailSlot.en & (btbEntry.tailSlot.br_type == CONDITION) & ~btbEntry.tailSlot.carry;
    assign pred_error = meta.predTaken ^ io.updateInfo.realTaken;
    assign update_sc = pred_error | meta.thresh_update;
    assign update_en = u_slot_en & update_sc;

    for(genvar i=0; i<`SC_HIST_NUM; i++)begin
        logic `N($clog2(sc_hist_depth[i*16 +: 16])) idx;
        logic `ARRAY(`SLOT_NUM, `SC_CTR_SIZE) update_ctr_pre, hist_commit_ctr, update_ctr;
        logic hist_commit_en;
        SCGIndex #(
            $clog2(sc_hist_depth[i*16 +: 16]), 
            sc_hist_length[i*16 +: 16],
            `SC_GHIST_WIDTH
        ) gindex (io.updateInfo.start_addr, r.sc_ghist, idx);
        CAMQueue #(
            `SC_COMMIT_SIZE,
            $clog2(sc_hist_depth[i*16 +: 16]),
            `SLOT_NUM * `SC_CTR_SIZE
        ) hist_cam (
            .clk,
            .rst,
            .we(|update_en),
            .wtag(idx),
            .wdata(hist_update_ctr[i]),
            .rtag(idx),
            .rhit(hist_commit_en),
            .rdata(hist_commit_ctr)
        );
        assign hist_update_idx[i] = idx;
        for(genvar j=0; j<`SLOT_NUM; j++)begin
            assign update_ctr_pre[j] = hist_commit_en ? hist_commit_ctr[j] : meta.ctr[i][j];
            UpdateCounter #(`SC_CTR_SIZE) update_counter (update_ctr_pre[j], io.updateInfo.realTaken[j], update_ctr[j]);
            assign hist_update_ctr[i][j] = update_en[j] ? update_ctr[j] : update_ctr_pre[j];
        end
    end

    for(genvar i=0; i<`SC_IMLI_NUM; i++)begin
        logic `N($clog2(sc_imli_depth[i*16 +: 16])) idx;
        logic `ARRAY(`SLOT_NUM, `SC_CTR_SIZE) update_ctr_pre, hist_commit_ctr, update_ctr;
        logic hist_commit_en;
        SCGIndex #(
            $clog2(sc_imli_depth[i*16 +: 16]),
            `SC_IMLI_WIDTH,
            `SC_IMLI_WIDTH
        ) gindex (io.updateInfo.start_addr, r.imli, idx);
        CAMQueue #(
            `SC_COMMIT_SIZE,
            $clog2(sc_imli_depth[i*16 +: 16]),
            `SLOT_NUM * `SC_CTR_SIZE
        ) hist_cam (
            .clk,
            .rst,
            .we(|update_en),
            .wtag(idx),
            .wdata(imli_update_ctr[i]),
            .rtag(idx),
            .rhit(hist_commit_en),
            .rdata(hist_commit_ctr)
        );
        assign imli_update_idx[i] = idx;
        for(genvar j=0; j<`SLOT_NUM; j++)begin
            assign update_ctr_pre[j] = hist_commit_en ? hist_commit_ctr[j] : meta.ctr[i+`SC_HIST_NUM][j];
            UpdateCounter #(`SC_CTR_SIZE) update_counter (update_ctr_pre[j], io.updateInfo.realTaken[j], update_ctr[j]);
            assign imli_update_ctr[i][j] = update_en[j] ? update_ctr[j] : update_ctr_pre[j];
        end

    end
endgenerate

    logic thresh_commit_en;
    logic `ARRAY(`SLOT_NUM, `SC_THRESH_CTR) thresh_commit_ctr, thresh_update_pre;
    CAMQueue #(
        `SC_COMMIT_SIZE,
        $clog2(`SC_THRESH_DEPTH),
        `SLOT_NUM * `SC_THRESH_CTR
    ) thresh_cam (
        .clk,
        .rst,
        .we(|update_en),
        .wtag(thresh_update_idx),
        .wdata(thresh_update_ctr),
        .rtag(thresh_update_idx),
        .rhit(thresh_commit_en),
        .rdata(thresh_commit_ctr)
    );
generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        assign thresh_update_pre[i] = thresh_commit_en ? thresh_commit_ctr[i] : meta.thresh_ctr[i];
        logic `N(`SC_THRESH_CTR) update_ctr;
        UpdateCounter #(`SC_THRESH_CTR) update_counter (thresh_update_pre[i], pred_error[i], update_ctr);
        UpdateCounter #(`SC_GTHRESH_CTR) update_gcounter (gthresh[i], pred_error[i], gthresh_update[i]);
        assign thresh_update_ctr[i] = update_en[i] ? update_ctr : thresh_update_pre[i];
    end
endgenerate

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            for(int i=0; i<`SLOT_NUM; i++)begin
                gthresh[i] <= `SC_GTHRESH_INIT;
            end
        end
        else begin
            for(int i=0; i<`SLOT_NUM; i++)begin
                if(update_en[i])begin
                    gthresh[i] <= gthresh_update[i];
                end
            end
        end
    end

endmodule

module SCTable #(
    parameter WIDTH = 6,
    parameter DEPTH = 4,
	parameter THRESH_WIDTH = 6,
	parameter THRESH_HEIGHT = 32,
    parameter RESET_VALUE = 0,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter THRESH_ADDR_WIDTH = $clog2(THRESH_HEIGHT)
) (
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(ADDR_WIDTH) lookup_idx,
    output logic `ARRAY(`SLOT_NUM, WIDTH) lookup_ctr,
    input logic `N(`SLOT_NUM) update_en,
    input logic `N(ADDR_WIDTH) update_idx,
    input logic `ARRAY(`SLOT_NUM, WIDTH) update_ctr
);
    MPRAM #(
        .WIDTH(WIDTH * `SLOT_NUM),
        .DEPTH(DEPTH),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1),
        .RESET_VALUE(RESET_VALUE)
    ) data (
        .clk,
        .rst,
        .rst_sync(0),
        .en(en),
        .raddr(lookup_idx),
        .rdata(lookup_ctr),
        .we(|update_en),
        .waddr(update_idx),
        .wdata(update_ctr),
        .ready()
    );
endmodule

module SCGIndex #(
    parameter WIDTH = 4,
    parameter HIST_WIDTH = 4,
    parameter GHIST_WIDTH = 4
)(
    input logic `N(`VADDR_SIZE) pc,
    input logic `N(GHIST_WIDTH) ghist,
    output logic `N(WIDTH) idx
);
generate
    if(HIST_WIDTH == 0)begin
        assign idx = pc[`INST_OFFSET +: WIDTH] ^ pc[`INST_OFFSET + WIDTH +: WIDTH];
    end
    else if(HIST_WIDTH < WIDTH)begin
        assign idx = pc[`INST_OFFSET +: WIDTH] ^ pc[`INST_OFFSET + WIDTH +: WIDTH] ^
                     {{WIDTH-HIST_WIDTH{1'b0}}, ghist[HIST_WIDTH-1: 0]} ^
                     {ghist[HIST_WIDTH-1: 0], {WIDTH-HIST_WIDTH{1'b0}}};
    end
    else begin
        localparam REMAIN_WIDTH = HIST_WIDTH % WIDTH;
        localparam XOR_WIDTH = HIST_WIDTH - REMAIN_WIDTH;
        logic `N(WIDTH) fold_hist_pre, fold_hist;
        ParallelXOR #(WIDTH, XOR_WIDTH/WIDTH) xor_hist(ghist[XOR_WIDTH-1: 0], fold_hist_pre);
        if(REMAIN_WIDTH != 0)begin
            assign fold_hist = fold_hist_pre ^ {{WIDTH-REMAIN_WIDTH{1'b0}}, ghist[HIST_WIDTH-1: HIST_WIDTH-REMAIN_WIDTH]};
        end
        else begin
            assign fold_hist = fold_hist_pre;
        end
        assign idx = pc[`INST_OFFSET +: WIDTH] ^ pc[`INST_OFFSET + WIDTH +: WIDTH] ^
                     fold_hist;
    end
endgenerate
endmodule

module SCGTag #(
    parameter WIDTH = 4,
    parameter HIST_WIDTH = 4,
    parameter GHIST_WIDTH = 4
)(
    input logic `VADDR_BUS pc,
    input logic `N(GHIST_WIDTH) ghist,
    output logic `N(WIDTH) tag
);
generate
    if(HIST_WIDTH == 0)begin
        assign tag = pc[`INST_OFFSET +: WIDTH];
    end
    else if(HIST_WIDTH < WIDTH)begin
        assign tag = pc[`INST_OFFSET +: WIDTH] ^ 
                    {{WIDTH-HIST_WIDTH{1'b0}}, ghist[HIST_WIDTH-1: 0]} ^
                    {{WIDTH-HIST_WIDTH-1{1'b0}}, ghist[HIST_WIDTH-2: 0], 1'b0} ^
                    {1'b0, ghist[HIST_WIDTH-2: 0], {WIDTH-HIST_WIDTH-1{1'b0}}};
    end
    else begin
        localparam REMAIN_WIDTH = HIST_WIDTH % WIDTH;
        localparam XOR_WIDTH = HIST_WIDTH - REMAIN_WIDTH;
        logic `N(WIDTH) fold_hist_pre, fold_hist;
        ParallelXOR #(WIDTH, XOR_WIDTH/WIDTH) xor_hist(ghist[XOR_WIDTH-1: 0], fold_hist_pre);
        localparam REMAIN_WIDTH1 = HIST_WIDTH % (WIDTH - 1);
        localparam XOR_WIDTH1 = HIST_WIDTH - REMAIN_WIDTH1;
        logic `N(WIDTH-1) fold_hist_pre1;
        ParallelXOR #(WIDTH-1, XOR_WIDTH1/(WIDTH-1)) xor_hist1(ghist[XOR_WIDTH1-1: 0], fold_hist_pre1);
        if(REMAIN_WIDTH != 0)begin
            assign fold_hist = fold_hist_pre ^ {{WIDTH-REMAIN_WIDTH{1'b0}}, ghist[HIST_WIDTH-1: HIST_WIDTH-REMAIN_WIDTH]} ^ {fold_hist_pre1, 1'b0};
        end
        else begin
            assign fold_hist = fold_hist_pre ^ {fold_hist_pre1, 1'b0};
        end
        assign tag = pc[`INST_OFFSET +: WIDTH] ^ fold_hist;
    end
endgenerate
endmodule

module SCThreshGIndex #(
    parameter WIDTH = 4
)(
    input logic `VADDR_BUS pc,
    output `N(WIDTH) thresh
);
    assign thresh = pc[`INST_OFFSET +: WIDTH] ^ pc[`INST_OFFSET + WIDTH +: WIDTH];
endmodule