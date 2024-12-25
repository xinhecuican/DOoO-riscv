`include "../../defines/defines.svh"

// btb update: idx, updateEntry
// tage update: pred, pred error

module FSQ (
    input logic clk,
    input logic rst,
    BpuFsqIO.fsq bpu_fsq_io,
    FsqCacheIO.fsq fsq_cache_io,
    PreDecodeRedirect.redirect pd_redirect,
    FsqBackendIO.fsq fsq_back_io,
    CommitBus.in commitBus,
    input FrontendCtrl frontendCtrl
);
    // TODO: update branch predictor when squash. Because branch metas are stored in ram
    // so even Wrongly updated branch predictor, it can be recovered when update
    logic `N(`FSQ_WIDTH) search_head, commit_head, tail, write_index;
    logic `N(`FSQ_WIDTH) search_head_n1, tail_n1, n_commit_head;
    logic `N(`FSQ_WIDTH) write_tail;
    logic `N(`FSQ_WIDTH) squashIdx;
    logic full;
    logic queue_we;
    logic last_stage_we;
    logic last_search;
    logic cache_req;
    logic cache_req_ok;
    BTBUpdateInfo oldEntry;
    logic `N(`FSQ_SIZE) directionTable;
    logic tdir, hdir, shdir;
    logic `N(`FSQ_WIDTH) searchIdx;
    FetchStream commitStream, searchStream, writeStream;
    logic `N(`PREDICTION_WIDTH) commitSize;
    logic initReady;
    logic commitValid;
    FetchStream `N(`ALU_SIZE) back_streams;

    assign tail_n1 = tail + 1;
    assign search_head_n1 = search_head + 1;
    assign write_tail = bpu_fsq_io.redirect ? bpu_fsq_io.prediction.stream_idx : tail;
    assign queue_we = bpu_fsq_io.en & (~full | bpu_fsq_io.redirect);
    assign last_stage_we = bpu_fsq_io.lastStage & (~full | bpu_fsq_io.redirect);
    assign write_index = pd_redirect.en ? pd_redirect.fsqIdx.idx :
                         bpu_fsq_io.redirect ? bpu_fsq_io.prediction.stream_idx : tail;
    assign searchIdx = fsq_back_io.redirect.en ? fsq_back_io.redirect.fsqInfo.idx : search_head;
    assign writeStream = pd_redirect.en ? pd_redirect.stream :
                            bpu_fsq_io.prediction.stream;
    // read ports: cache, wb, commit
    MPRAM #(
        .WIDTH($bits(FetchStream)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1 + `ALU_SIZE + 1),
        .WRITE_PORT(1),
        .RESET(1)
    ) fs_queue(
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en({cache_req_ok | fsq_back_io.redirect.en, {(`ALU_SIZE+1){1'b1}}}),
        .we((queue_we | pd_redirect.en)),
        .waddr(write_index),
        .raddr({searchIdx, fsq_back_io.fsqIdx, n_commit_head}),
        .wdata(writeStream),
        .rdata({searchStream, back_streams, commitStream}),
        .ready(initReady)
    );


    RedirectInfo u_redirectInfo, commit_redictInfo;
    assign squashIdx = fsq_back_io.redirect.en ? fsq_back_io.redirect.fsqInfo.idx : pd_redirect.fsqIdx.idx;
    MPRAM #(
        .WIDTH($bits(RedirectInfo)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(2),
        .WRITE_PORT(1),
        .RESET(1)
    ) redirect_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(2'b11),
        .we(bpu_fsq_io.lastStage),
        .waddr(bpu_fsq_io.lastStageIdx),
        .raddr({commit_head, squashIdx}),
        .wdata(bpu_fsq_io.lastStagePred.redirect_info),
        .rdata({commit_redictInfo, u_redirectInfo}),
        .ready()
    );

    MPRAM #(
        .WIDTH($bits(BTBUpdateInfo)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1)
    ) btb_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(1'b1),
        .raddr(n_commit_head),
        .rdata(oldEntry),
        .we(queue_we),
        .waddr(write_tail),
        .wdata(bpu_fsq_io.prediction.btbEntry),
        .ready()
    );

    PredictionMeta updateMeta;
    MPRAM #(
        .WIDTH($bits(PredictionMeta)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1)
    ) meta_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(1'b1),
        .raddr(commit_head),
        .rdata(updateMeta),
        .we(bpu_fsq_io.lastStage),
        .waddr(bpu_fsq_io.lastStageIdx),
        .wdata(bpu_fsq_io.lastStageMeta),
        .ready()
    );

    // for predecode redirect
    MPRAM #(
        .WIDTH($bits(`VADDR_SIZE)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) ras_addr_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(1'b1),
        .raddr(pd_redirect.fsqIdx_pre),
        .rdata(pd_redirect.ras_addr),
        .we(bpu_fsq_io.lastStage),
        .waddr(bpu_fsq_io.lastStageIdx),
        .wdata(bpu_fsq_io.ras_addr),
        .ready()
    );

    typedef struct packed {
        logic `N(2) condNum;
        logic `N(`SLOT_NUM) condHist;
        logic `N(`SLOT_NUM) condValid;
        logic `ARRAY(`SLOT_NUM, `PREDICTION_WIDTH) offsets;
    } PredictionInfo;

    PredictionInfo predictionInfos `N(`FSQ_SIZE);
    PredictionInfo pd_wr_info;
    logic `N(`SLOT_NUM) condSmallNum, pd_smallNum;
    logic `N(`SLOT_NUM) condSmallNumAll, pd_smallNumAll;
    logic redirectIsCond;
    PredictionInfo redirectPredInfo;
    PredictionInfo pd_predInfo;
    PredictionInfo u_predInfo;

    assign pd_wr_info.condNum = bpu_fsq_io.prediction.cond_num;
    assign pd_wr_info.condHist = bpu_fsq_io.prediction.predTaken;
    BTBUpdateInfo predEntry;
    assign predEntry = bpu_fsq_io.prediction.btbEntry;
generate
    for(genvar i=0; i<`SLOT_NUM-1; i++)begin
        assign pd_wr_info.offsets[i] = predEntry.slots[i].offset;
    end
    assign pd_wr_info.condValid = bpu_fsq_io.prediction.cond_valid;
    assign pd_wr_info.offsets[`SLOT_NUM-1] = predEntry.tailSlot.offset;
endgenerate

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            predictionInfos <= '{default: 0};
        end
        else begin
            if(queue_we)begin
                predictionInfos[write_tail] <= pd_wr_info;
            end
        end
    end

// cache
    assign cache_req = ((search_head != tail) | (shdir ^ tdir)) & 
                       ~pd_redirect.en  & ~fsq_back_io.redirect.en;
    always_ff @(posedge clk)begin
        if(cache_req_ok | fsq_back_io.redirect.en | pd_redirect.en)begin
            fsq_cache_io.en <= cache_req;
            fsq_cache_io.fsqIdx.idx <= search_head;
            fsq_cache_io.fsqIdx.dir <= directionTable[search_head];
        end
        fsq_cache_io.abandon <= bpu_fsq_io.redirect;
        fsq_cache_io.abandonIdx.idx <= bpu_fsq_io.prediction.stream_idx;
        fsq_cache_io.abandonIdx.dir <= bpu_fsq_io.prediction.stream_dir;
    end
    assign fsq_cache_io.stream = searchStream;
    assign fsq_cache_io.flush = pd_redirect.en | fsq_back_io.redirect.en;
    assign fsq_cache_io.stall = frontendCtrl.ibuf_full;
    assign bpu_fsq_io.stream_idx = tail;
    assign bpu_fsq_io.stream_dir = tdir;
    assign bpu_fsq_io.stall = full;
    assign cache_req_ok = fsq_cache_io.ready;

    logic `N(`PREDICTION_WIDTH) shiftOffset, shiftIdx;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            shiftOffset <= 0;
            shiftIdx <= 0;
        end
        else begin
            
            if(fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en)begin
                shiftOffset <= 0;
                shiftIdx <= 0;
            end
            else if(fsq_back_io.redirect.en)begin
                // redirect mem, start from next instr
                shiftOffset <= fsq_back_io.redirect.fsqInfo.offset;
`ifdef RVC
                shiftIdx <= fsq_back_io.redirect.fsqInfo.size;
`endif
            end
            else if(cache_req_ok)begin
                shiftOffset <= 0;
                shiftIdx <= 0;
            end
        end
    end
    always_ff @(posedge clk)begin
        fsq_cache_io.shiftOffset <= shiftOffset;
`ifdef RVC
        fsq_cache_io.shiftIdx <= shiftIdx;
`endif
    end

    // logic `N(`SLOT_NUM) condFree;
    // PEncoder #(`SLOT_NUM) encoder_condFree({~oldEntry.slots[0].en, ~oldEntry.tailSlot.en}, condFree);

    CondPredInfo redirectCondInfo, pd_condInfo;
    assign pd_predInfo = predictionInfos[pd_redirect.fsqIdx.idx];
    assign redirectPredInfo = predictionInfos[fsq_back_io.redirect.fsqInfo.idx];

generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        assign pd_smallNum[i] = pd_predInfo.condValid[i] & (pd_predInfo.offsets[i] < pd_redirect.stream.size);
        assign condSmallNum[i] = redirectPredInfo.condValid[i] & (redirectPredInfo.offsets[i] < fsq_back_io.redirect.fsqInfo.offset);
    end
endgenerate
    assign redirectIsCond = fsq_back_io.redirectBr.en & fsq_back_io.redirectBr.br_type == CONDITION;
    `UNPARAM(SLOT_NUM, 2, "condSmallNum adder")
    assign condSmallNumAll = condSmallNum[0] + condSmallNum[1];
    assign pd_smallNumAll[1] = pd_smallNum[0] & pd_smallNum[1];
    assign pd_smallNumAll[0] = pd_smallNum[0] ^ pd_smallNum[1];
    
    assign pd_condInfo.condNum = pd_smallNumAll;
    assign pd_condInfo.taken = 0;
    always_comb begin
        if(redirectIsCond)begin
            if(condSmallNumAll < `SLOT_NUM)begin
                redirectCondInfo.condNum = condSmallNumAll + 1;
                redirectCondInfo.taken = fsq_back_io.redirectBr.taken;
            end
            else begin
                redirectCondInfo.condNum = `SLOT_NUM;
                redirectCondInfo.taken = 0;
            end
        end
        else begin
            redirectCondInfo.condNum = condSmallNumAll;
            redirectCondInfo.taken = 0;
        end
    end

// squash
    logic `N(`VADDR_SIZE) squash_target_pc;
    logic `N(`FSQ_WIDTH) pd_redirect_n1, bpu_fsq_redirect_n1, redirect_n1;
    logic memRedirectValid;

    assign pd_redirect_n1 = pd_redirect.fsqIdx.idx + 1;
    assign bpu_fsq_redirect_n1 = bpu_fsq_io.prediction.stream_idx + 1;
    assign redirect_n1 = fsq_back_io.redirect.fsqInfo.idx + 1;

    CondPredInfo squash_pred_info;
    BranchType squash_br_type;
    logic [1: 0] squash_ras_type;
    logic squash_redirect_en, squash_pd_en;
    logic `VADDR_BUS pd_start_addr;
    logic `N(`PREDICTION_WIDTH) squash_offset;
    assign n_commit_head = commitValid ? commit_head + 1 : commit_head;
    assign full = commit_head == tail && (hdir ^ tdir);
    assign bpu_fsq_io.squashInfo.redirectInfo = u_redirectInfo;
    assign bpu_fsq_io.squashInfo.start_addr = squash_redirect_en ? searchStream.start_addr : pd_start_addr;
    assign bpu_fsq_io.squashInfo.offset = squash_offset;
    assign bpu_fsq_io.squashInfo.target_pc = memRedirectValid ? searchStream.target : squash_target_pc;
    assign bpu_fsq_io.squashInfo.predInfo = squash_pred_info;
    assign bpu_fsq_io.squashInfo.br_type = squash_br_type;
    assign bpu_fsq_io.squashInfo.ras_type = memRedirectValid ? u_redirectInfo.rasInfo.ras_type : squash_ras_type;
    assign bpu_fsq_io.squashInfo.squash_front = ~squash_redirect_en & squash_pd_en;
    always_ff @(posedge clk)begin
        squash_redirect_en <= fsq_back_io.redirectBr.en;
        squash_pd_en <= pd_redirect.en;
        pd_start_addr <= pd_redirect.stream.start_addr;
        memRedirectValid <= fsq_back_io.redirect.en & ~fsq_back_io.redirectBr.en & ~fsq_back_io.redirectCsr.en;
        bpu_fsq_io.squash <= pd_redirect.en | fsq_back_io.redirect.en;
        // bpu_fsq_io.squashInfo.redirectInfo <= u_redirectInfo;
        squash_target_pc <= fsq_back_io.redirectCsr.en ? fsq_back_io.redirectCsr.exc_pc :
                            fsq_back_io.redirectBr.en ? fsq_back_io.redirectBr.target : 
                                                        pd_redirect.stream.target;
        squash_pred_info <= fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en ? redirectCondInfo : pd_condInfo;
        squash_br_type <= fsq_back_io.redirectBr.en ? fsq_back_io.redirectBr.br_type : pd_redirect.br_type;
        squash_ras_type <= fsq_back_io.redirectBr.en ? fsq_back_io.redirectBr.ras_type : pd_redirect.ras_type;
        squash_offset <= fsq_back_io.redirect.en ? fsq_back_io.redirect.fsqInfo.offset : pd_redirect.stream.size;
    end
`ifdef RVC
    logic squash_rvc;
    assign bpu_fsq_io.squashInfo.rvc = squash_rvc;
    always_ff @(posedge clk)begin
        squash_rvc <= fsq_back_io.redirect.en ? fsq_back_io.redirect.rvc : pd_redirect.stream.rvc;
    end
`endif

// idx maintain
    logic search_bigger, search_eq, search_abandon;
    LoopCompare #(`FSQ_WIDTH) cmp_redirect_search({bpu_fsq_io.prediction.stream_idx, bpu_fsq_io.prediction.stream_dir}, {search_head, shdir}, search_bigger);
    assign search_eq = {bpu_fsq_io.prediction.stream_idx, bpu_fsq_io.prediction.stream_dir} == {search_head, shdir};
    assign search_abandon = search_bigger | search_eq;
    always_ff @(posedge clk)begin
        last_search <= search_head == tail && fsq_cache_io.en;
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            search_head <= 0;
            commit_head <= 0;
            tail <= 0;
        end
        else begin
            if(fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en)begin
                search_head <= redirect_n1;
            end
            else if(fsq_back_io.redirect.en)begin
                search_head <= fsq_back_io.redirect.fsqInfo.idx;
            end
            else if(pd_redirect.en)begin
                if(pd_redirect.direct)begin
                    search_head <= pd_redirect_n1;
                end
                else begin
                    search_head <= pd_redirect.fsqIdx.idx;
                end
            end
            else if(bpu_fsq_io.redirect & search_abandon)begin
                search_head <= bpu_fsq_io.prediction.stream_idx;
            end
            else if(cache_req_ok & cache_req) begin
                search_head <= search_head_n1;
            end

            if(fsq_back_io.redirect.en)begin
                tail <= redirect_n1;
            end
            else if(pd_redirect.en)begin
                tail <= pd_redirect_n1;
            end
            else if(bpu_fsq_io.redirect)begin
                tail <= bpu_fsq_redirect_n1;
            end
            else if(bpu_fsq_io.en & ~full)begin
                tail <= tail_n1;
            end

            commit_head <= n_commit_head;
        end
    end

    logic `N(`FSQ_WIDTH) redirect_dir_idx, redirect_dir_idx_n1;
    assign redirect_dir_idx = fsq_back_io.redirect.fsqInfo.idx;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            tdir <= 0;
            hdir <= 0;
            shdir <= 0;
            directionTable <= '{default: 0};
        end
        else begin
            if(fsq_back_io.redirect.en)begin
                tdir <= redirect_dir_idx[`FSQ_WIDTH-1] & ~redirect_n1[`FSQ_WIDTH-1] ? ~directionTable[redirect_dir_idx] : directionTable[redirect_dir_idx];
            end
            else if(pd_redirect.en)begin
                tdir <= pd_redirect.fsqIdx.idx[`FSQ_WIDTH-1] & ~pd_redirect_n1[`FSQ_WIDTH-1] ? ~pd_redirect.fsqIdx.dir : pd_redirect.fsqIdx.dir;
            end
            else if(bpu_fsq_io.redirect)begin
                tdir <= bpu_fsq_io.prediction.stream_idx[`FSQ_WIDTH-1] & ~bpu_fsq_redirect_n1[`FSQ_WIDTH-1] ? ~bpu_fsq_io.prediction.stream_dir : bpu_fsq_io.prediction.stream_dir;
            end
            else if(bpu_fsq_io.en & ~full)begin
                tdir <= tail[`FSQ_WIDTH-1] & ~tail_n1[`FSQ_WIDTH-1] ? ~tdir : tdir;
            end

            if(fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en)begin
                shdir <= redirect_dir_idx[`FSQ_WIDTH-1] & ~redirect_n1[`FSQ_WIDTH-1] ? ~directionTable[redirect_dir_idx] : directionTable[redirect_dir_idx];
            end
            else if(fsq_back_io.redirect.en)begin
                shdir <= directionTable[redirect_dir_idx];
            end
            else if(pd_redirect.en)begin
                if(pd_redirect.direct)begin
                    shdir <= pd_redirect.fsqIdx.idx[`FSQ_WIDTH-1] & ~pd_redirect_n1[`FSQ_WIDTH-1] ? ~pd_redirect.fsqIdx.dir : pd_redirect.fsqIdx.dir;
                end
                else begin
                    shdir <= pd_redirect.fsqIdx.dir;
                end
            end
            else if(bpu_fsq_io.redirect & search_abandon)begin
                shdir <= bpu_fsq_io.prediction.stream_dir;
            end
            else if(cache_req_ok & cache_req)begin
                shdir <= search_head[`FSQ_WIDTH-1] & ~search_head_n1[`FSQ_WIDTH-1] ? ~shdir : shdir;
            end

            if(commitValid)begin
                hdir <= commit_head[`FSQ_WIDTH-1] & ~n_commit_head[`FSQ_WIDTH-1] ? ~hdir : hdir;
            end

            if(bpu_fsq_io.en & ~full)begin
                directionTable[tail] <= tdir;
            end
        end
    end

// wb & commit
    typedef struct packed {
        logic exception;
        logic taken;
`ifdef RVC
        logic rvc;
        logic `N(`PREDICTION_WIDTH) size;
`endif
        BranchType br_type;
        logic [1: 0] ras_type;
        logic `N(`VADDR_SIZE) target;
        logic `N(`PREDICTION_WIDTH) offset;
    } WBInfo;

    WBInfo wbInfos `N(`FSQ_SIZE);
    WBInfo commitWBInfo;
    logic `N(`FSQ_SIZE) pred_error_en;
    logic pred_error;
    BranchRedirectInfo rd;
    CSRRedirectInfo cr;
    assign rd = fsq_back_io.redirectBr;
    assign cr = fsq_back_io.redirectCsr;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            wbInfos <= '{default: 0};
            pred_error_en <= 0;
        end
        else begin
            if(pd_redirect.en & pd_redirect.direct)begin
                wbInfos[pd_redirect.fsqIdx.idx] <= {1'b0, 1'b1, 
`ifdef RVC
                pd_redirect.stream.rvc, pd_redirect.size,
`endif
                pd_redirect.br_type, pd_redirect.ras_type, 
                pd_redirect.stream.target, pd_redirect.stream.size};
            end
            if(rd.en | cr.en)begin
                wbInfos[fsq_back_io.redirect.fsqInfo.idx] <= {cr.en, rd.taken, 
`ifdef RVC
                fsq_back_io.redirect.rvc, fsq_back_io.redirect.fsqInfo.size,
`endif
                rd.br_type, rd.ras_type, rd.target, fsq_back_io.redirect.fsqInfo.offset};
            end
            if(queue_we)begin
                pred_error_en[write_index] <= 1'b0;
            end
            if(fsq_back_io.redirect.en)begin
                pred_error_en[fsq_back_io.redirect.fsqInfo.idx] <= rd.en | cr.en;
            end
            if(pd_redirect.en & pd_redirect.direct)begin
                pred_error_en[pd_redirect.fsqIdx.idx] <= 1'b1;
            end
        end
    end

    localparam FSQ_INST_WIDTH=$clog2(`FSQ_SIZE*`BLOCK_INST_SIZE);
    logic `N(FSQ_INST_WIDTH+1) commitNum;
    BTBUpdateInfo commitUpdateEntry;
    FsqIdxInfo commitFsqInfo;
    logic `N(`PREDICTION_WIDTH) commitFsqSize;
`ifdef RVC
    assign commitFsqSize = commitWBInfo.size;
`else
    assign commitFsqSize = commitWBInfo.offset;
`endif
    // because streamVec is not init
    assign commitValid = initReady & (
                        (|commitNum[FSQ_INST_WIDTH: `PREDICTION_WIDTH]) || 
                        (commitNum[`PREDICTION_WIDTH-1: 0] > commitSize) ||
                        (pred_error_en[commit_head] & (commitNum[`PREDICTION_WIDTH-1: 0] > commitFsqSize)));
    assign pred_error = initReady & pred_error_en[commit_head] & 
                        ((|commitNum[FSQ_INST_WIDTH: `PREDICTION_WIDTH]) | (commitNum[`PREDICTION_WIDTH-1: 0] > commitFsqSize));

    logic `N(`PREDICTION_WIDTH) streamCommitSize;
    logic `N(`PREDICTION_WIDTH+1) streamCommitNum;

    assign streamCommitSize = pred_error_en[commit_head] ? commitFsqSize : commitSize;
    assign streamCommitNum = streamCommitSize + 1;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            commitNum <= 0;
        end
        else begin
            commitNum <= commitNum + commitBus.num - ({`PREDICTION_WIDTH+1{commitValid}} & streamCommitNum);
        end
    end

    logic `N(`SLOT_NUM) realTaken, allocSlot;
    assign commitWBInfo = wbInfos[commit_head];
    assign u_predInfo = predictionInfos[commitFsqInfo.idx];
    assign commitFsqInfo.idx = commit_head;
`ifdef RVC
    assign commitFsqInfo.size = commitWBInfo.size;
`endif
    assign commitFsqInfo.offset = commitWBInfo.offset;
    BTBEntryGen commit_btb_entry_gen (
        .oldEntry(oldEntry),
        .pc(commitStream.start_addr),
        .fsqInfo(commitFsqInfo),
        .normalOffset(commitStream.size),
        .br_type(commitWBInfo.br_type),
        .ras_type(commitWBInfo.ras_type),
        .pred_error(pred_error),
        .exception(commitWBInfo.exception),
        .target(commitWBInfo.target),
        .taken(commitWBInfo.taken),
`ifdef RVC
        .rvc(commitWBInfo.rvc),
`endif
        .predTaken(u_predInfo.condHist),
        .updateEntry(commitUpdateEntry),
        .realTaken(realTaken),
        .allocSlot(allocSlot)
    );

    logic update_taken, update_tail_taken;
    logic `N(`VADDR_SIZE) update_start_addr;
    logic `N(`VADDR_SIZE) update_target_pc;
    BTBUpdateInfo update_btb_entry; 
    logic `N(`SLOT_NUM) update_real_taken;
    logic `N(`SLOT_NUM) update_alloc_slot;
    assign bpu_fsq_io.updateInfo.meta = updateMeta;
    assign bpu_fsq_io.updateInfo.taken = update_taken;
    assign bpu_fsq_io.updateInfo.start_addr = update_start_addr;
    assign bpu_fsq_io.updateInfo.target_pc = update_target_pc;
    assign bpu_fsq_io.updateInfo.btbEntry = update_btb_entry;
    assign bpu_fsq_io.updateInfo.realTaken = update_real_taken;
    assign bpu_fsq_io.updateInfo.allocSlot = update_alloc_slot;
    assign bpu_fsq_io.updateInfo.tailTaken = update_tail_taken;
    assign bpu_fsq_io.updateInfo.redirectInfo = commit_redictInfo;
`ifdef DIFFTEST
    assign bpu_fsq_io.updateInfo.fsqIdx = commit_head;
`endif
    always_ff @(posedge clk)begin
        bpu_fsq_io.update <= commitValid;
        update_taken <= commitWBInfo.taken;
        update_start_addr <= commitStream.start_addr;
        update_target_pc <= commitWBInfo.target;
        update_btb_entry <= pred_error ? commitUpdateEntry : oldEntry;
        update_real_taken <= realTaken;
        update_alloc_slot <= allocSlot;
        update_tail_taken <= pred_error ? commitWBInfo.br_type != CONDITION :
                            ~(|u_predInfo.condHist) & commitStream.taken;
    end

    logic `N(`FSQ_WIDTH) exception_head, exception_head_n;
    logic `N(`PREDICTION_WIDTH) pd_size;
    logic exc_wen;
    logic `N(`FSQ_WIDTH) exc_widx;
    logic `N(`VADDR_SIZE) exc_waddr;
    assign exception_head_n = exception_head + commitValid;
    always_ff @(posedge clk)begin
        exc_wen <= pd_redirect.exc_en;
        exc_widx <= pd_redirect.fsqIdx.idx;
        exc_waddr <= pd_redirect.stream.start_addr;
        pd_size <= pd_redirect.size;
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            exception_head <= 0;
        end
        else begin
            exception_head <= exception_head_n;
        end
    end

    logic `ARRAY(`COMMIT_WIDTH, `FSQ_WIDTH) exception_idxs;
    logic `ARRAY(`COMMIT_WIDTH, `VADDR_SIZE) exception_addrs;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign exception_idxs[i] = exception_head_n + i;
    end
endgenerate
    MPRAM #(
        .WIDTH(`VADDR_SIZE),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(`COMMIT_WIDTH),
        .WRITE_PORT(1)
    ) exception_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en({`COMMIT_WIDTH{1'b1}}),
        .raddr(exception_idxs),
        .rdata(exception_addrs),
        .we(exc_wen),
        .waddr(exc_widx),
        .wdata(exc_waddr),
        .ready()
    );
    MPRAM #(
        .WIDTH(`PREDICTION_WIDTH),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) stream_size_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(1'b1),
        .raddr(n_commit_head),
        .rdata(commitSize),
        .we(exc_wen),
        .waddr(exc_widx),
        .wdata(pd_size),
        .ready()
    );
    assign fsq_back_io.commitStreamSize = commitSize;

`ifdef RVC
    logic `N(`FSQ_SIZE) commit_head_mask, redirect_mask;
    logic `ARRAY(`ALU_SIZE, `PREDICTION_WIDTH) stream_lasts;
    logic `N(`PREDICTION_WIDTH) last_offset;
    always_ff @(posedge clk)begin
        last_offset <= pd_redirect.last_offset;
    end
    MaskGen #(`FSQ_SIZE) mask_gen_commit_head (commit_head, commit_head_mask);
    MaskGen #(`FSQ_SIZE) mask_gen_redirect (fsq_back_io.redirect.fsqInfo.idx, redirect_mask);

    MPRAM #(
        .WIDTH(`PREDICTION_WIDTH),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(`ALU_SIZE),
        .WRITE_PORT(1)
    ) stream_last_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en({`ALU_SIZE{1'b1}}),
        .raddr(fsq_back_io.fsqIdx),
        .rdata(stream_lasts),
        .we(exc_wen),
        .waddr(exc_widx),
        .wdata(last_offset),
        .ready()
    );
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        always_comb begin
            fsq_back_io.streams[i] = back_streams[i];
            fsq_back_io.streams[i].size = stream_lasts[i];
        end
    end
endgenerate
`else
    assign fsq_back_io.streams = back_streams;
`endif

    logic `N($clog2(`COMMIT_WIDTH)) exc_ridx;
    assign exc_ridx = fsq_back_io.redirect.fsqInfo.idx - commit_head;
    assign fsq_back_io.exc_pc = exception_addrs[exc_ridx] + {fsq_back_io.redirect.fsqInfo.offset, {`INST_OFFSET{1'b0}}};

`ifdef DIFFTEST
    logic `N(`VADDR_SIZE) diff_pcs `N(`FSQ_SIZE);
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign fsq_back_io.diff_pc[i] = diff_pcs[fsq_back_io.diff_fsqInfo[i].idx] + {fsq_back_io.diff_fsqInfo[i].offset, {`INST_OFFSET{1'b0}}};
    end
endgenerate
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            diff_pcs <= '{default: 0};
        end
        else begin
            if(queue_we)begin
                diff_pcs[write_tail] <= bpu_fsq_io.prediction.stream.start_addr;
            end
            
        end
    end
    FetchStream logStream;
    logic logError;
    logic redirect_n;
    logic `N(`FSQ_WIDTH) redirect_idx;
    always_ff @(posedge clk)begin
        logStream <= commitStream;
        logError <= pred_error;
        redirect_n <= fsq_back_io.redirect.en;
        redirect_idx <= fsq_back_io.redirect.fsqInfo.idx;
    end
    `Log(DLog::Debug, T_FSQ, bpu_fsq_io.update, $sformatf("update BP%4d. [%8h %4d]->%8h %8h %b", commit_head, logStream.start_addr, logStream.size, logStream.target, update_target_pc, logError))
    `Log(DLog::Debug, T_FSQ, bpu_fsq_io.squash, $sformatf("squash BP [%d %d].", redirect_idx, redirect_n))

    `PERF(pred_error_cond, commitValid & pred_error & ~commitWBInfo.exception & commitWBInfo.br_type == CONDITION)
    `PERF(pred_error_ind, commitValid & pred_error & ~commitWBInfo.exception & commitWBInfo.br_type == INDIRECT)
    `PERF(pred_error_call, commitValid & pred_error & ~commitWBInfo.exception & commitWBInfo.br_type == CALL)
    `PERF(pred_error, commitValid & pred_error & ~commitWBInfo.exception)
    `PERF(front_redirect_direct, pd_redirect.en & pd_redirect.direct)
    `PERF(front_redirect_nobranch, pd_redirect.en & ~pd_redirect.direct)

//     logic `N(6) dbg_commit_idx, dbg_commit_head;
//     logic `ARRAY(64, `FSQ_WIDTH) dbg_fsq_idxs;
//     logic `ARRAY(`COMMIT_WIDTH, 6) dbg_commit_idxs;
//     logic `ARRAY(8, 6) dbg_commit_head_idxs;

// generate
//     for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
//         assign dbg_commit_idxs[i] = dbg_commit_idx + i;
//     end
//     for(genvar i=0; i<8; i++)begin
//         assign dbg_commit_head_idxs[i] = dbg_commit_head + i;
//     end
// endgenerate

//     always_ff @(posedge clk, posedge rst)begin
//         if(rst == `RST)begin
//             dbg_commit_idx <= 0;
//             dbg_fsq_idxs <= 0;
//             dbg_commit_head <= 0;
//         end
//         else begin
//             if(commitValid)begin
//                 dbg_commit_head <= dbg_commit_head + streamCommitNum;
//             end
//             dbg_commit_idx <= dbg_commit_idx + commitBus.num;
//             for(int i=0; i<`COMMIT_WIDTH; i++)begin
//                 if(i < commitBus.num)begin
//                     dbg_fsq_idxs[dbg_commit_idxs[i]] <= commitBus.fsqInfo[i].idx;
//                 end
//             end
//         end
//     end

//     always_ff @(posedge clk)begin
//         if(commitValid)begin
//             for(int i=0; i<8; i++)begin
//                 if((i < streamCommitNum) && commit_head != dbg_fsq_idxs[dbg_commit_head_idxs[i]])begin
//                     $display("[%16d] fsq commit[%d] error", DLog::cycleCnt, commit_head);
//                 end
//             end
//         end
//     end
`endif

endmodule

module BTBEntryGen(
    input BTBUpdateInfo oldEntry,
    input logic `VADDR_BUS pc,
    input FsqIdxInfo fsqInfo,
    input logic `N(`PREDICTION_WIDTH) normalOffset,
    input BranchType br_type,
    input logic [1: 0] ras_type,
    input logic pred_error,
    input logic exception,
`ifdef RVC
    input logic rvc,
`endif
    input logic `VADDR_BUS target,
    input logic `N(`SLOT_NUM) predTaken,
    input logic taken,
    output BTBUpdateInfo updateEntry,
    output logic `N(`SLOT_NUM) allocSlot,
    output logic `N(`SLOT_NUM) realTaken
);
    // 如果不是分支指令，那么插入tailSlot
    // 如果是分支指令,判断是否有空位
    // 如果有空位则在空位中插入
    // 否则将比他大的指令踢出去
    // 踢出去的规则：
    // 1. 当包含两条分支指令时，第三条指令插入时判断三者大小关系
    //   假设存在两条指令A,B,要插入的指令为I
    //   如果当前为I, A, B,那么将I插入B中，并且此时fthAddr为B
    //   如果BIA,那么将I插入A，fthAddr为A
    //   如果为ABI,那么不插入，并且fthAddr为I

    logic `N(`SLOT_NUM) free, free_p, oldest, equal, we;
    logic `ARRAY(`SLOT_NUM+1, `PREDICTION_WIDTH) offsets;
    logic `N(`PREDICTION_WIDTH) oldestOffset;
    logic `N(`SLOT_NUM+1) oldestDecode;
    logic `N(`SLOT_NUM) taken_ext;
generate
    for(genvar i=0; i<`SLOT_NUM-1; i++)begin
        assign free[i] = !oldEntry.slots[i].en;
        assign offsets[i] = oldEntry.slots[i].offset;
        assign equal[i] = oldEntry.slots[i].en && oldEntry.slots[i].offset == fsqInfo.offset;
    end
endgenerate
    assign we = |equal ? equal :
                |free ? free_p : oldest;
    assign taken_ext = {`SLOT_NUM{taken}};
    assign free[`SLOT_NUM-1] = !oldEntry.tailSlot.en;
    assign offsets[`SLOT_NUM-1] = oldEntry.tailSlot.offset;
    assign equal[`SLOT_NUM-1] = oldEntry.tailSlot.en && oldEntry.tailSlot.br_type == CONDITION &&  oldEntry.tailSlot.offset == fsqInfo.offset;
    assign offsets[`SLOT_NUM] = fsqInfo.offset;
    PRSelector #(`SLOT_NUM) selector_free (free, free_p);

    typedef struct packed {
        logic `N($clog2(`SLOT_NUM)+1) idx;
// `ifdef RVC
//         logic rvc;
// `endif
    } OldestInfo;
    OldestInfo `N(`SLOT_NUM+1) selectInfos;
    OldestInfo oldestInfo;
// `ifdef RVC
//     for(genvar i =0; i<`SLOT_NUM-1; i++)begin
//         assign selectInfos[i].rvc = oldEntry.slots[i].rvc;
//     end
//     assign selectInfos[`SLOT_NUM-1].rvc = oldEntry.tailSlot.rvc;
//     assign selectInfos[`SLOT_NUM].rvc = rvc;
// `endif
    for(genvar i=0; i<`SLOT_NUM+1; i++)begin
        assign selectInfos[i].idx = i;
    end
    OldestSelect #(
        .RADIX(`SLOT_NUM+1),
        .WIDTH(`PREDICTION_WIDTH),
        .DATA_WIDTH($bits(OldestInfo))
    ) oldest_select (
        .cmp(offsets),
        .data_i(selectInfos),
        .cmp_o(oldestOffset),
        .data_o(oldestInfo)
    );
    Decoder #(`SLOT_NUM+1) decode_oldest(oldestInfo.idx, oldestDecode);
    assign oldest = oldestDecode[`SLOT_NUM-1: 0];

    TargetState tarState, tailTarState;
    assign tarState = target[`VADDR_SIZE-1: `JAL_OFFSET+1] > pc[`VADDR_SIZE-1: `JAL_OFFSET+1] ? TAR_OV :
                      target[`VADDR_SIZE-1: `JAL_OFFSET+1] < pc[`VADDR_SIZE-1: `JAL_OFFSET+1] ? TAR_UN : TAR_NONE;
    assign tailTarState = target[`VADDR_SIZE-1: `JALR_OFFSET+1] > pc[`VADDR_SIZE-1: `JALR_OFFSET+1] ? TAR_OV :
                      target[`VADDR_SIZE-1: `JALR_OFFSET+1] < pc[`VADDR_SIZE-1: `JALR_OFFSET+1] ? TAR_UN : TAR_NONE;
    assign updateEntry.en = 1'b1;
    always_comb begin
        if(br_type != CONDITION)begin
            updateEntry.fthAddr = fsqInfo.offset;

            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot.en = 1'b1;
            updateEntry.tailSlot.carry = ~oldEntry.tailSlot.en;
            updateEntry.tailSlot.br_type = br_type;
            updateEntry.tailSlot.ras_type = ras_type;
`ifdef RVC
            updateEntry.tailSlot.rvc = rvc;
`endif
            updateEntry.tailSlot.offset = fsqInfo.offset;
            updateEntry.tailSlot.target = target[`JALR_OFFSET: 1];
            updateEntry.tailSlot.tar_state = tailTarState;
        end
        else begin
            for(int i=0; i<`SLOT_NUM-1; i++)begin
                updateEntry.slots[i].en = we[i] | oldEntry.slots[i].en;
                updateEntry.slots[i].carry = (oldEntry.slots[i].carry | free_p[i]) & ~equal[i];
                updateEntry.slots[i].offset = we[i] ? fsqInfo.offset : 
                                              oldEntry.slots[i].en ? oldEntry.slots[i].offset :
                                              `BLOCK_INST_SIZE - 1;
                updateEntry.slots[i].target = we[i] ? target[`JAL_OFFSET: 1] : oldEntry.slots[i].target;
                updateEntry.slots[i].tar_state = we[i] ? tarState : oldEntry.slots[i].tar_state;
`ifdef RVC
                updateEntry.slots[i].rvc = we[i] ? rvc : oldEntry.slots[i].rvc;
`endif
            end
            updateEntry.tailSlot.en = we[`SLOT_NUM-1] ? 1'b1 : oldEntry.tailSlot.en;
            updateEntry.tailSlot.carry = (oldEntry.tailSlot.carry | free_p[`SLOT_NUM-1]) & ~equal[`SLOT_NUM-1];
            updateEntry.tailSlot.br_type = we[`SLOT_NUM-1] ? br_type : oldEntry.tailSlot.br_type;
            updateEntry.tailSlot.ras_type = we[`SLOT_NUM-1] ? ras_type : oldEntry.tailSlot.ras_type;
            updateEntry.tailSlot.offset = we[`SLOT_NUM-1] ? fsqInfo.offset : 
                                          oldEntry.tailSlot.en ? oldEntry.tailSlot.offset :
                                          `BLOCK_INST_SIZE - 1;
            updateEntry.tailSlot.target = we[`SLOT_NUM-1] ? target[`JAL_OFFSET: 1] : oldEntry.tailSlot.target;
            updateEntry.tailSlot.tar_state = we[`SLOT_NUM-1] ? tarState : oldEntry.tailSlot.tar_state;
`ifdef RVC
            updateEntry.tailSlot.rvc = we[`SLOT_NUM-1] ? rvc : oldEntry.tailSlot.rvc;
            updateEntry.fthAddr = (~(|free)) & (~(|equal)) ? oldestOffset-2 : 
                                  oldEntry.en ? oldEntry.fthAddr : `BLOCK_INST_SIZE-2;
            updateEntry.fth_rvc = 0;
`else
            updateEntry.fthAddr = (~(|free)) & (~(|equal)) ? oldestOffset-1 : 
                                  oldEntry.en ? oldEntry.fthAddr : `BLOCK_INST_SIZE-1;
`endif
        end
    end

    always_comb begin
        if((~pred_error) | exception)begin
            realTaken = predTaken;
        end
        else if(|equal)begin
            realTaken = (equal & taken_ext) | (~equal & predTaken);
        end
        else if(|free)begin
            realTaken = (free & taken_ext) | (~free & predTaken);
        end
        else begin
            realTaken = (oldest[`SLOT_NUM-1: 0] & taken_ext) | (~oldest[`SLOT_NUM-1: 0] & predTaken);
        end
    end

    logic `N(`SLOT_NUM) predAlloc, predOldAlloc, slotAlloc;
    logic `ARRAY(`SLOT_NUM, `SLOT_NUM) slotOldAlloc;
generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        assign predAlloc[i] = ~free[i] & ((normalOffset > offsets[i]) | equal[i]);
        assign predOldAlloc[i] = ~free[i] & ((fsqInfo.offset > offsets[i]) | equal[i]);
        for(genvar j=0; j<`SLOT_NUM; j++)begin
            if(i == j)begin
                assign slotOldAlloc[i][j] = equal[i];
            end
            else begin
                assign slotOldAlloc[i][j] = ~free[j] & equal[i] & (offsets[i] > offsets[j]);
            end
        end
    end
endgenerate
    ParallelOR #(`SLOT_NUM, `SLOT_NUM) or_slotOldAlloc (slotOldAlloc, slotAlloc);
    always_comb begin
        if((~pred_error))begin
            allocSlot = predAlloc;
        end
        else if(exception)begin
            allocSlot = predOldAlloc;
        end
        else if(|equal)begin
            allocSlot = slotAlloc;
        end
        else if(|free)begin
            allocSlot = predOldAlloc | free_p;
        end
        else begin
            allocSlot = {`SLOT_NUM{1'b1}};
        end
    end

endmodule