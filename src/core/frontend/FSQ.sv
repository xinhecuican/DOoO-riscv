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
    FrontendCtrl frontendCtrl
);
    logic `N(`FSQ_WIDTH) search_head, commit_head, tail, write_index;
    logic `N(`FSQ_WIDTH) search_head_n1, tail_n1, n_commit_head;
    logic `N(`FSQ_WIDTH) write_tail;
    logic `N(`FSQ_WIDTH) squashIdx;
    logic full;
    logic queue_we;
    logic last_search;
    logic cache_req;
    logic cache_req_ok;
    BTBEntry oldEntry;
    logic directionTable `N(`FSQ_SIZE);
    logic direction, hdir, shdir;
    FetchStream commitStream;
    logic initReady;
    

    assign tail_n1 = tail + 1;
    assign search_head_n1 = search_head + 1;
    assign write_tail = bpu_fsq_io.redirect ? bpu_fsq_io.stream_idx : tail;
    assign queue_we = bpu_fsq_io.en & ~full;
    assign write_index = bpu_fsq_io.redirect ? bpu_fsq_io.stream_idx : tail;
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
        .en({cache_req_ok, {(`ALU_SIZE+1){1'b1}}}),
        .we(queue_we),
        .waddr(write_tail),
        .raddr({search_head, fsq_back_io.fsqIdx, n_commit_head}),
        .wdata(bpu_fsq_io.prediction.stream),
        .rdata({fsq_cache_io.stream, fsq_back_io.streams, commitStream}),
        .ready(initReady)
    );


    RedirectInfo u_redirectInfo;
    assign squashIdx = fsq_back_io.redirect.en ? fsq_back_io.redirect.fsqInfo.idx : pd_redirect.fsqIdx.idx;
    MPRAM #(
        .WIDTH($bits(RedirectInfo)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1)
    ) redirect_ram (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .we(queue_we),
        .waddr(write_tail),
        .raddr(squashIdx),
        .wdata(bpu_fsq_io.prediction.redirect_info),
        .rdata(u_redirectInfo),
        .ready()
    );

    MPRAM #(
        .WIDTH($bits(BTBEntry)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .RESET(1)
    ) btb_ram (
        .clk(clk),
        .rst(rst),
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
        .en(1'b1),
        .raddr(commit_head),
        .rdata(updateMeta),
        .we(bpu_fsq_io.lastStage),
        .waddr(bpu_fsq_io.lastStageIdx),
        .wdata(bpu_fsq_io.lastStageMeta),
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
    BTBEntry predEntry;
    assign predEntry = bpu_fsq_io.prediction.btbEntry;
generate
    for(genvar i=0; i<`SLOT_NUM-1; i++)begin
        assign pd_wr_info.offsets[i] = predEntry.slots[i].offset;
    end
    assign pd_wr_info.condValid = bpu_fsq_io.prediction.cond_valid;
    assign pd_wr_info.offsets[`SLOT_NUM-1] = predEntry.tailSlot.offset;
endgenerate

    always_ff @(posedge clk)begin
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
    assign cache_req = ((search_head != tail) | (shdir ^ direction)) & 
                       ~pd_redirect.en  & ~fsq_back_io.redirect.en;
    always_ff @(posedge clk)begin
        if(cache_req_ok | fsq_back_io.redirect.en)begin
            fsq_cache_io.en <= cache_req & ~fsq_back_io.redirect.en;
            fsq_cache_io.abandon <= bpu_fsq_io.redirect;
            fsq_cache_io.abandonIdx <= bpu_fsq_io.prediction.stream_idx;
            fsq_cache_io.fsqIdx.idx <= search_head;
            fsq_cache_io.fsqIdx.dir <= directionTable[search_head];
        end
    end
    assign fsq_cache_io.flush = pd_redirect.en | fsq_back_io.redirect.en;
    assign fsq_cache_io.stall = frontendCtrl.ibuf_full;
    assign bpu_fsq_io.stream_idx = tail;
    assign bpu_fsq_io.stream_dir = direction;
    assign bpu_fsq_io.stall = full;
    assign cache_req_ok = ~frontendCtrl.ibuf_full & fsq_cache_io.ready;

    // logic `N(`SLOT_NUM) condFree;
    // PEncoder #(`SLOT_NUM) encoder_condFree({~oldEntry.slots[0].en, ~oldEntry.tailSlot.en}, condFree);

    CondPredInfo redirectCondInfo, pd_condInfo;
    assign pd_predInfo = predictionInfos[pd_redirect.fsqIdx.idx];
    assign redirectPredInfo = predictionInfos[fsq_back_io.redirect.fsqInfo.idx];

generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        assign pd_smallNum[i] = pd_predInfo.condValid[i] & (pd_predInfo.offsets[i] < pd_redirect.offset);
        assign condSmallNum[i] = redirectPredInfo.condValid[i] & (redirectPredInfo.offsets[i] < fsq_back_io.redirect.fsqInfo.offset);
    end
endgenerate
    assign redirectIsCond = fsq_back_io.redirectBr.en & fsq_back_io.redirectBr.br_type == CONDITION;
    /* UNPARAM */
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

    assign pd_redirect_n1 = pd_redirect.fsqIdx.idx + 1;
    assign bpu_fsq_redirect_n1 = bpu_fsq_io.stream_idx + 1;
    assign redirect_n1 = fsq_back_io.redirect.fsqInfo.idx + 1;

    CondPredInfo squash_pred_info;
    BranchType squash_br_type;
    RasType squash_ras_type;
    assign n_commit_head = commitValid ? commit_head + 1 : commit_head;
    assign full = commit_head == tail && (hdir ^ direction);
    assign bpu_fsq_io.squashInfo.redirectInfo = u_redirectInfo;
    assign bpu_fsq_io.squashInfo.target_pc = squash_target_pc;
    assign bpu_fsq_io.squashInfo.predInfo = squash_pred_info;
    assign bpu_fsq_io.squashInfo.br_type = squash_br_type;
    assign bpu_fsq_io.squashInfo.ras_type = squash_ras_type;
    always_ff @(posedge clk)begin
        bpu_fsq_io.squash <= pd_redirect.en | fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en;
        // bpu_fsq_io.squashInfo.redirectInfo <= u_redirectInfo;
        squash_target_pc <= fsq_back_io.redirectCsr.en ? fsq_back_io.redirectCsr.exc_pc :
                            fsq_back_io.redirectBr.en ? fsq_back_io.redirectBr.target : 
                                                        pd_redirect.redirect_addr;
        squash_pred_info <= fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en ? redirectCondInfo : pd_condInfo;
        squash_br_type <= fsq_back_io.redirectBr.en ? fsq_back_io.redirectBr.br_type : DIRECT;
        squash_ras_type <= fsq_back_io.redirectBr.en ? fsq_back_io.redirectBr.ras_type : NONE;
    end

// idx maintain
    always_ff @(posedge clk)begin
        last_search <= search_head == tail && fsq_cache_io.en;
        if(rst == `RST)begin
            search_head <= 0;
            commit_head <= 0;
            tail <= 0;
        end
        else begin
            if(fsq_back_io.redirect.en)begin
                search_head <= redirect_n1;
            end
            else if(pd_redirect.en)begin
                search_head <= pd_redirect_n1;
            end
            else if(cache_req_ok & cache_req) begin
                search_head <= search_head_n1;
            end

            if(fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en)begin
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

    logic `N(`FSQ_WIDTH) redirect_dir_idx;
    assign redirect_dir_idx = fsq_back_io.redirect.fsqInfo.idx;
    always_ff @(posedge clk)begin
        for(int i=0; i<`ALU_SIZE; i++)begin
            fsq_back_io.directions[i] <= directionTable[fsq_back_io.fsqIdx[i]];
        end

        if(rst == `RST)begin
            direction <= 0;
            hdir <= 0;
            shdir <= 0;
            directionTable <= '{default: 0};
        end
        else begin
            if(fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en)begin
                direction <= redirect_dir_idx[`FSQ_WIDTH-1] & ~redirect_n1[`FSQ_WIDTH-1] ? ~directionTable[redirect_dir_idx] : directionTable[redirect_dir_idx];
            end
            else if(pd_redirect.en)begin
                direction <= pd_redirect.fsqIdx.idx & ~pd_redirect_n1 ? ~pd_redirect.fsqIdx.dir : pd_redirect.fsqIdx.dir;
            end
            else if(bpu_fsq_io.redirect)begin
                direction <= bpu_fsq_io.stream_idx & ~bpu_fsq_redirect_n1 ? ~bpu_fsq_io.stream_dir : bpu_fsq_io.stream_dir;
            end
            else if(bpu_fsq_io.en & ~full)begin
                direction <= tail[`FSQ_WIDTH-1] & ~tail_n1[`FSQ_WIDTH-1] ? ~direction : direction;
            end

            if(fsq_back_io.redirectBr.en | fsq_back_io.redirectCsr.en)begin
                shdir <= redirect_dir_idx[`FSQ_WIDTH-1] & ~redirect_n1[`FSQ_WIDTH-1] ? ~directionTable[redirect_dir_idx] : directionTable[redirect_dir_idx];
            end
            else if(pd_redirect.en)begin
                shdir <= pd_redirect.fsqIdx.idx & ~pd_redirect_n1 ? ~pd_redirect.fsqIdx.dir : pd_redirect.fsqIdx.dir;
            end
            else if(cache_req_ok & cache_req)begin
                shdir <= search_head[`FSQ_WIDTH-1] & ~search_head_n1[`FSQ_WIDTH-1] ? ~shdir : shdir;
            end

            if(commitValid)begin
                hdir <= commit_head[`FSQ_WIDTH-1] & ~n_commit_head[`FSQ_WIDTH-1] ? ~hdir : hdir;
            end

            if(bpu_fsq_io.en & ~full)begin
                directionTable[tail] <= direction;
            end
        end
    end

// wb & commit
    typedef struct packed {
        logic exception;
        logic taken;
        BranchType br_type;
        RasType ras_type;
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
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            wbInfos <= '{default: 0};
            pred_error_en <= 0;
        end
        else begin
            if(rd.en | cr.en)begin
                wbInfos[fsq_back_io.redirect.fsqInfo.idx] <= {cr.en, rd.taken, rd.br_type, rd.ras_type, rd.target, fsq_back_io.redirect.fsqInfo.offset};
            end
            if(queue_we)begin
                pred_error_en[tail] <= 1'b0;
            end
            if(rd.en | cr.en)begin
                pred_error_en[fsq_back_io.redirect.fsqInfo.idx] <= 1'b1;
            end
        end
    end

    logic `N(8) commitNum;
    logic commitValid;
    BTBEntry commitUpdateEntry;
    FsqIdxInfo commitFsqInfo;
    // because streamVec is not init
    assign commitValid = initReady & (
                        (|commitNum[7: `PREDICTION_WIDTH]) || 
                        (commitNum[`PREDICTION_WIDTH-1: 0] > commitStream.size) ||
                        (pred_error_en[commit_head] & (commitNum[`PREDICTION_WIDTH-1: 0] > commitFsqInfo.offset)));
    assign pred_error = initReady & pred_error_en[commit_head] & 
                        ((|commitNum[7: `PREDICTION_WIDTH]) | (commitNum[`PREDICTION_WIDTH-1: 0] > commitFsqInfo.offset));

    logic `N(`PREDICTION_WIDTH) streamCommitOffset;
    logic `N(`PREDICTION_WIDTH+1) streamCommitNum;

    assign streamCommitOffset = pred_error_en[commit_head] ? commitFsqInfo.offset : commitStream.size;
    assign streamCommitNum = streamCommitOffset + 1;

    always_ff @(posedge clk)begin
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
    assign commitFsqInfo.offset = commitWBInfo.offset;
    BTBEntryGen commit_btb_entry_gen (
        .oldEntry(oldEntry),
        .pc(commitStream.start_addr),
        .fsqInfo(commitFsqInfo),
        .br_type(commitWBInfo.br_type),
        .ras_type(commitWBInfo.ras_type),
        .pred_error(pred_error),
        .exception(commitWBInfo.exception),
        .target(commitWBInfo.target),
        .taken(commitWBInfo.taken),
        .predTaken(u_predInfo.condHist),
        .updateEntry(commitUpdateEntry),
        .realTaken(realTaken),
        .allocSlot(allocSlot)
    );

    logic update_taken;
    logic `N(`VADDR_SIZE) update_start_addr;
    logic `N(`VADDR_SIZE) update_target_pc;
    BTBEntry update_btb_entry; 
    logic update_real_taken;
    logic `N(`SLOT_NUM) update_alloc_slot;
    assign bpu_fsq_io.updateInfo.redirectInfo = u_redirectInfo;
    assign bpu_fsq_io.updateInfo.meta = updateMeta;
    assign bpu_fsq_io.updateInfo.taken = update_taken;
    assign bpu_fsq_io.updateInfo.start_addr = update_start_addr;
    assign bpu_fsq_io.updateInfo.target_pc = update_target_pc;
    assign bpu_fsq_io.updateInfo.btbEntry = update_btb_entry;
    assign bpu_fsq_io.updateInfo.realTaken = update_real_taken;
    assign bpu_fsq_io.updateInfo.allocSlot = update_alloc_slot;
    always_ff @(posedge clk)begin
        bpu_fsq_io.update <= commitValid;
        update_taken <= commitWBInfo.taken;
        update_start_addr <= commitStream.start_addr;
        update_target_pc <= commitWBInfo.target;
        update_btb_entry <= pred_error ? commitUpdateEntry : oldEntry;
        update_real_taken <= realTaken;
        update_alloc_slot <= allocSlot;
    end

    // TODO: fix excpetion pc time
    logic `N(`VADDR_SIZE) exception_pcs `N(`FSQ_SIZE);
    always_ff @(posedge clk)begin
        if(queue_we)begin
            exception_pcs[write_tail] <= bpu_fsq_io.prediction.stream.start_addr;
        end

    end
    assign fsq_back_io.exc_pc = exception_pcs[fsq_back_io.redirect.fsqInfo.idx] + {fsq_back_io.redirect.fsqInfo.offset, 2'b00};

`ifdef DIFFTEST
    logic `N(`VADDR_SIZE) diff_pcs `N(`FSQ_SIZE);
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign fsq_back_io.diff_pc[i] = diff_pcs[fsq_back_io.diff_fsqInfo[i].idx] + {fsq_back_io.diff_fsqInfo[i].offset, 2'b00};
    end
endgenerate
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            diff_pcs <= '{default: 0};
        end
        else begin
            if(queue_we)begin
                diff_pcs[write_tail] <= bpu_fsq_io.prediction.stream.start_addr;
            end
            
        end
    end

    `Log(DLog::Debug, bpu_fsq_io.update, $sformatf("update BP%4d. taken: %b target: %8h allocSlot: %2d", commit_head, update_taken, update_target_pc, update_alloc_slot))
`endif

endmodule

module BTBEntryGen(
    input BTBEntry oldEntry,
    input logic `VADDR_BUS pc,
    input FsqIdxInfo fsqInfo,
    input BranchType br_type,
    input RasType ras_type,
    input logic pred_error,
    input logic exception,
    input logic `VADDR_BUS target,
    input logic `N(`SLOT_NUM) predTaken,
    input logic taken,
    output BTBEntry updateEntry,
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
    logic `ARRAY(`SLOT_NUM+1, $clog2(`SLOT_NUM+1)) idx;
    logic `N(`PREDICTION_WIDTH) oldestOffset;
    logic `N($clog2(`SLOT_NUM+1)) oldestIdx;
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
    for(genvar i=0; i<`SLOT_NUM+1; i++)begin
        assign idx[i] = i;
    end
    OldestSelect #(
        .RADIX(`SLOT_NUM+1),
        .WIDTH(`PREDICTION_WIDTH),
        .DATA_WIDTH($clog2(`SLOT_NUM+1))
    ) oldest_select (
        .cmp(offsets),
        .data_i(idx),
        .cmp_o(oldestOffset),
        .data_o(oldestIdx)
    );
    Decoder #(`SLOT_NUM+1) decode_oldest(oldestIdx, oldestDecode);
    assign oldest = oldestDecode[`SLOT_NUM-1: 0];

    TargetState tarState, tailTarState;
    assign tarState = target[`VADDR_SIZE-1: `JAL_OFFSET+1] > pc[`VADDR_SIZE-1: `JAL_OFFSET+1] ? TAR_OV :
                      target[`VADDR_SIZE-1: `JAL_OFFSET+1] < pc[`VADDR_SIZE-1: `JAL_OFFSET+1] ? TAR_UN : TAR_NONE;
    assign tailTarState = target[`VADDR_SIZE-1: `JALR_OFFSET+1] > pc[`VADDR_SIZE-1: `JALR_OFFSET+1] ? TAR_OV :
                      target[`VADDR_SIZE-1: `JALR_OFFSET+1] < pc[`VADDR_SIZE-1: `JALR_OFFSET+1] ? TAR_UN : TAR_NONE;
    assign updateEntry.en = 1'b1;
    BTBTagGen gen_tag(pc, updateEntry.tag);
    always_comb begin
        if(br_type != CONDITION)begin
            updateEntry.fthAddr = fsqInfo.offset;

            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot.en = 1'b1;
            updateEntry.tailSlot.carry = ~oldEntry.tailSlot.en;
            updateEntry.tailSlot.br_type = br_type;
            updateEntry.tailSlot.ras_type = ras_type;
            updateEntry.tailSlot.offset = fsqInfo.offset;
            updateEntry.tailSlot.target = target[`JALR_OFFSET: 1];
            updateEntry.tailSlot.tar_state = tailTarState;
        end
        else begin
            for(int i=0; i<`SLOT_NUM-1; i++)begin
                updateEntry.slots[i].en = we[i] | oldEntry.slots[i].en;
                updateEntry.slots[i].carry = (updateEntry.slots[i].carry | free_p[i]) & ~equal[i];
                updateEntry.slots[i].offset = we[i] ? offsets[i] : oldEntry.slots[i].offset;
                updateEntry.slots[i].target = we[i] ? target[`JAL_OFFSET: 1] : oldEntry.slots[i].target;
                updateEntry.slots[i].tar_state = we[i] ? tarState : oldEntry.slots[i].tar_state;
            end
            updateEntry.tailSlot.en = we[`SLOT_NUM-1] ? 1'b1 : oldEntry.tailSlot.en;
            updateEntry.tailSlot.carry = (updateEntry.tailSlot.carry | free_p[`SLOT_NUM-1]) & ~equal[`SLOT_NUM-1];
            updateEntry.tailSlot.br_type = we[`SLOT_NUM-1] ? br_type : oldEntry.tailSlot.br_type;
            updateEntry.tailSlot.ras_type = we[`SLOT_NUM-1] ? ras_type : oldEntry.tailSlot.ras_type;
            updateEntry.tailSlot.offset = we[`SLOT_NUM-1] ? offsets[`SLOT_NUM-1] : oldEntry.tailSlot.offset;
            updateEntry.tailSlot.target = we[`SLOT_NUM-1] ? target : oldEntry.tailSlot.target;
            updateEntry.tailSlot.tar_state = we[`SLOT_NUM-1] ? tarState : oldEntry.tailSlot.tar_state;

            updateEntry.fthAddr = (~(|free)) & (~(|equal)) ? oldestOffset-1 : oldEntry.fthAddr;
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

    logic `N(`SLOT_NUM) predAlloc, predOldAlloc;
generate
    for(genvar i=0; i<`SLOT_NUM; i++)begin
        assign predAlloc[i] = ~free[i];
        assign predOldAlloc[i] = predAlloc[i] & (fsqInfo.offset > offsets[i]);
    end
endgenerate
    always_comb begin
        if(!pred_error)begin
            allocSlot = predAlloc;
        end
        else if(exception)begin
            allocSlot = predOldAlloc;
        end
        else begin
            allocSlot = predAlloc | ({`SLOT_NUM{~(|equal)}} & free_p);
        end
    end

endmodule