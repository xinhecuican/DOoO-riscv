`include "../../defines/defines.svh"

// btb update: idx, updateEntry
// tage update: pred, pred error

module FSQ (
    input logic clk,
    input logic rst,
    BpuFsqIO.fsq bpu_fsq_io,
    FsqCacheIO.fsq fsq_cache_io,
    PreDecodeRedirect.redirect pd_redirect,
    FsqBackendIO.fsq fsq_back_io
);
    logic `N(`FSQ_WIDTH) search_head, commit_head, tail, write_index, tail_n1, n_commit_head;
    logic `N(`FSQ_WIDTH) squashIdx;
    logic full, enqueue, dequeue;
    logic queue_we;
    logic last_search;
    logic empty;
    logic cache_req_ok;
    BTBEntry oldEntry, updateEntry;
    RedirectInfo u_redirectInfo;
    logic `N(`BLOCK_INST_SIZE) predErrorVec `N(`FSQ_SIZE);
    logic directionTable `N(`FSQ_SIZE);
    logic direction;
    FetchStream commitStream;

    assign tail_n1 = tail + 1;
    assign queue_we = bpu_fsq_io.en;
    assign write_index = bpu_fsq_io.redirect ? bpu_fsq_io.stream_idx : tail;
    MPRAM #(
        .WIDTH($bits(FetchStream)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1+`ALU_SIZE + 1)
    ) fs_queue(
        .clk(clk),
        .en(1'b1),
        .we(queue_we),
        .waddr(tail),
        .raddr({search_head, fsq_back_io.fsqIdx, n_commit_head}),
        .wdata(bpu_fsq_io.prediction.stream),
        .rdata({fsq_cache_io.stream, fsq_back_io.streams, commitStream})
    );

    SDPRAM #(
        .WIDTH($bits(RedirectInfo)),
        .DEPTH(`FSQ_SIZE)
    ) redirect_queue(
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .we(queue_we),
        .raddr0(tail),
        .raddr1(squashIdx),
        .wdata(bpu_fsq_io.prediction.redirect_info),
        .rdata1(u_redirectInfo)
    );

    SDRPAM #(
        .WIDTH($bits(BTBEntry)),
        .DEPTH(`FSQ_SIZE)
    ) btb_queue(
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .we(queue_we),
        .raddr0(tail),
        .raddr1(search_head),
        .wdata(bpu_fsq_io.btbEntry),
        .rdata1(oldEntry)
    );

    assign fsq_cache_io.en = search_head != tail || full;
    assign fsq_cache_io.abandon = bpu_fsq_io.redirect;
    assign fsq_cache_Io.abandonIdx = bpu_fsq_io.prediction.stream_idx;
    assign fsq_cache_io.flush = pd_redirect.en;
    assign bpu_fsq_io.stream_idx = tail;
    assign bpu_fsq_io.stall = full;
    assign cache_req_ok = fsq_cache_io.en & fsq_cache_io.ready;

    logic `N(`SLOT_NUM) condFree;
    PEncoder #(`SLOT_NUM) encoder_condFree({~oldEntry.slots[0].en, ~oldEntry.tailSlot.en}, condFree);
    assign bpu_fsq_io.squash = pd_redirect.en;
    assign bpu_fsq_io.btb_en = pd_redirect.en;
    assign bpu_fsq_io.btbEntry = updateEntry;

    assign enqueue = bpu_fsq_io.en;
    assign dequeue = pd_redirect.en | cache_req_ok | (bpu_fsq_io.redirect && (tail != bpu_fsq_io.stream_idx));
    BTBEntryGen frontend_redirect (oldEntry, pd_redirect.pc, {pd_redirect.fsqIdx, pd_redirect.fsqOffset}, 1'b0, pd_redirect.branch_type, pd_redirect.ras_type, pd_redirect.redirect_addr, updateEntry);
    always_ff @(posedge clk)begin
        last_search <= search_head == tail && fsq_cache_io.en;
        bpu_fsq_io.squash <= pd_redirect.en;
        bpu_fsq_io.squashInfo.squash_pc <= pd_redirect.pc;
        bpu_fsq_io.squashInfo.redirectInfo <= u_redirectInfo;
        bpu_fsq_io.squashInfo.btbEntry <= updateEntry;
        bpu_fsq_io.squashInfo.target_pc <= pd_redirect.redirect_addr;
        if(rst == `RST)begin
            search_head <= 0;
            commit_head <= 0;
            tail <= 0;
            full <= 0;
            predErrorVec <= '{default: 0};
        end
        else begin
            if(full && dequeue)begin
                full <= 1'b0;
            end
            if(!full && enqueue && !dequeue && (tail_n1 == commit_head))begin
                full <= 1'b1;
            end
            if(pd_redirect.en)begin
                search_head <= pd_redirect.fsqIdx;
            end
            else if(cache_req_ok)begin
                search_head <= search_head + 1;
            end
            if(pd_redirect.en)begin
                tail <= pd_redirect.fsqIdx;
            end
            else if(bpu_fsq_io.redirect)begin
                tail <= bpu_fsq_io.stream_idx;
            end
            else if(bpu_fsq_io.en)begin
                tail <= tail_n1;
            end

            if(fsq_back_io.redirect.en)begin
                predErrorVec[fsq_back_io.redirect.fsqInfo.idx] <= predErrorVec[fsq_back_io.redirect.fsqInfo.idx] | (1 << fsq_back_io.redirect.fsqInfo.offset);
            end
        end
    end

    always_ff @(posedge clk)begin
        for(int i=0; i<`ALU_SIZE; i++)begin
            fsq_back_io.directions[i] <= directionTable[fsq_back_io.fsqIdx[i]];
        end

        if(rst == `RST)begin
            direction <= 0;
            directionTable <= '{default: 0};
        end
        else begin
            if(pd_redirect.en)begin
                direction <= directionTable[pd_redirect.fsqIdx];
            end
            else if(bpu_fsq_io.redirect)begin
                direction <= bpu_fsq_Io.stream_idx;
            end
            else if(bpu_fsq_io.en)begin
                direction <= tail[`FSQ_WIDTH-1] ^ tail_n1[`FSQ_WIDTH-1] ? ~direction : direction;
            end

            if(bpu_fsq_io.en)begin
                directionTable[tail] <= direction;
            end
        end
    end

    typedef struct packed {
        logic en;
        logic taken;
        BranchType br_type;
        RasType ras_type;
        logic `N(`VADDR_SIZE) target;
        logic `N(`PREDICTION_WIDTH) offset;
    } WBInfo;

    WBInfo wbInfos `N(`RAS_SIZE);
    BackendRedirectInfo rd;
    assign rd = fsq_back_io.redirect;
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            wbInfos <= '{default: 0};
        end
        else begin
            if(rd.en)begin
                wbInfos[rd.fsqInfo.idx] <= {1'b1, rd.taken, rd.br_type, rd.ras_type, rd.target, rd.fsqInfo.offset};
            end
        end
    end
endmodule

module BTBEntryGen #(
    parameter IS_WB = 0
)(
    input BTBEntry oldEntry,
    input logic `VADDR_BUS pc,
    input FsqIdxInfo fsqInfo,
    input logic realTaken,
    input BranchType br_type,
    input RasType ras_type,
    input logic `VADDR_BUS target,
    output BTBEntry updateEntry
);
generate
if(IS_WB)begin
    always_comb begin
        updateEntry.en = 1'b1;
        updateEntry.tag = pc`BTB_TAG_BUS;
        updateEntry.fthAddr = fsqInfo.offset;
        if(pd_redirect.branch_type != CONDITION)begin
            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot.en = 1'b1;
            updateEntry.tailSlot.carry = 1'b1;
            updateEntry.tailSlot.br_type = br_type;
            updateEntry.tailSlot.ras_type = ras_type;
            updateEntry.tailSlot.offset = fsqInfo.offset;
            updateEntry.tailSlot.target = target;
        end
        else begin
            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot = oldEntry.tailSlot;
        end
    end
end
else begin
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
    
    for(genvar i=0; i<`SLOT_NUM-1; i++)begin
        assign free[i] = !oldEntry.slots[i].en;
        assign offsets[i] = oldEntry.slots[i].offset;
        assign equal[i] = oldEntry.slots[i].en && oldEntry.slots[i].offset == fsqInfo.offset;
        assign we[i] = |equal ? equal[i] :
                       |free ? free_p[i] :
                       oldest[i];
    end
    assign free[`SLOT_NUM-1] = !oldEntry.tailSlot.en;
    assign offsets[`SLOT_NUM-1] = oldEntry.tailSlot.offset;
    assign equal[`SLOT_NUM-1] = oldEntry.tailSlot.en && oldEntry.tailSlot.br_type == CONDITION &&  oldEntry.tailSlot.offset == fsqInfo.offset;
    assign offsets[`SLOT_NUM] = fsqInfo.offset;
    PSelector #(`SLOT_NUM) selector_free (free, free_p);
    for(genvar i=0; i<`SLOT_NUM+1; i++)begin
        assign idx[i] = i;
    end
    OldestSelect #(
        .RADIX(`SLOT_NUM+1),
        .WIDTH(`PREDICTION_WIDTH),
        .DATA_WIDTH($clog2(`SLOT_NUM+1))
    ) oldest_select (
        .cmp(offset),
        .data_i(idx),
        .cmp_o(oldestOffset),
        .data_o(oldestIdx)
    );
    Decoder #($clog2(`SLOT_NUM+1)) decode_oldest(oldestIdx, oldestDecode);
    assign oldest = oldestDecode[`SLOT_NUM-1: 0];


    always_comb begin
        if(br_type != CONDITION)begin
            updateEntry.en = 1'b1;
            updateEntry.tag = pc`BTB_TAG_BUS;
            updateEntry.fthAddr = fsqInfo.offset;

            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot.en = 1'b1;
            updateEntry.tailSlot.carry = ~oldEntry.tailSlot.en;
            updateEntry.tailSlot.br_type = br_type;
            updateEntry.tailSlot.ras_type = ras_type;
            updateEntry.tailSlot.offset = fsqInfo.offset;
            updateEntry.tailSlot.target = target;
        end
        else begin
            for(int i=0; i<`SLOT_NUM-1; i++)begin
                updateEntry.slots[i].en = we[i] | oldEntry.slots[i].en;
                updateEntry.slots[i].carry = free_p[i] & ~equal[i];
                updateEntry.slots[i].offset = we[i] ? offset : oldEntry.slots[i].offset;
                updateEntry.slots[i].target = we[i] ? target : oldEntry.slots[i].target;
            end
            updateEntry.tailSlot.en = we[`SLOT_NUM-1] ? 1'b1 : oldEntry.tailSlot.en;
            updateEntry.tailSlot.carry = free_p[`SLOT_NUM-1] & ~equal[`SLOT_NUM-1];
            updateEntry.tailSlot.br_type = we[`SLOT_NUM-1] ? br_type : oldEntry.br_type;
            updateEntry.tailSlot.ras_type = we[`SLOT_NUM-1] ? ras_type : oldEntry.ras_type;
            updateEntry.tailSlot.offset = we[`SLOT_NUM-1] ? offset : oldEntry.tailSlot.offset;
            updateEntry.tailSlot.target = we[`SLOT_NUM-1] ? target : oldEntry.tailSlot.target;

            updateEntry.en = 1'b1;
            updateEntry.tag = pc`BTB_TAG_BUS;
            updateEntry.fthAddr = (~(|free)) & (~(|equal)) ? oldestOffset-1 : oldEntry.fthAddr;
        end
    end
end
endgenerate

endmodule