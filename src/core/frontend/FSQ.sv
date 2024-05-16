`include "../../defines/defines.svh"

module FSQ (
    input logic clk,
    input logic rst,
    BpuFsqIO.fsq bpu_fsq_io,
    FsqCacheIO.fsq fsq_cache_io,
    PreDecodeRedirect.redirect pd_redirect,
    FsqBackendIO.fsq fsq_back_io
);
    logic `N(`FSQ_WIDTH) search_head, retire_head, tail, write_index, tail_n1;
    logic `N(`FSQ_WIDTH) squashIdx;
    logic full, enqueue, dequeue;
    logic queue_we;
    logic last_search;
    logic empty;
    logic cache_req_ok;
    BTBEntry oldEntry, updateEntry;
    RedirectInfo u_redirectInfo;
    logic `N(`BLOCK_INST_SIZE) predErrorVec `N(`FSQ_SIZE);

    assign tail_n1 = tail + 1;
    assign queue_we = bpu_fsq_io.en;
    assign write_index = bpu_fsq_io.redirect ? bpu_fsq_io.stream_idx : tail;
    MPRAM #(
        .WIDTH($bits(FetchStream)),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(1+`ALU_SIZE)
    ) fsq_queue(
        .clk(clk),
        .en(1'b1),
        .we(queue_we),
        .waddr(tail),
        .raddr({search_head, fsq_back_io.fsqIdx}),
        .wdata(bpu_fsq_io.prediction.stream),
        .rdata({fsq_cache_io.stream, fsq_back_io.streams})
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
    always_comb begin
        updateEntry.en = 1'b1;
        updateEntry.tag = pd_redirect.pc`BTB_TAG_BUS;
        updateEntry.fthAddr = pd_redirect.offset;
        if(pd_redirect.branch_type != CONDITION)begin
            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot.en = 1'b1;
            updateEntry.tailSlot.carry = 1'b1;
            updateEntry.tailSlot.br_type = pd_redirect.branch_type;
            updateEntry.tailSlot.ras_type = pd_redirect.ras_type;
            updateEntry.tailSlot.offset = pd_redirect.offset;
            updateEntry.tailSlot.target = pd_redirect.redirect_addr;
        end
        else begin
            updateEntry.slots = oldEntry.slots;
            updateEntry.tailSlot = oldEntry.tailSlot;
        end
    end
    assign bpu_fsq_io.squash = pd_redirect.en;
    assign bpu_fsq_io.btb_en = pd_redirect.en;
    assign bpu_fsq_io.btbEntry = updateEntry;

    assign enqueue = bpu_fsq_io.en;
    assign dequeue = pd_redirect.en | cache_req_ok | (bpu_fsq_io.redirect && (tail != bpu_fsq_io.stream_idx));
    always_ff @(posedge clk)begin
        last_search <= search_head == tail && fsq_cache_io.en;
        bpu_fsq_io.squash <= pd_redirect.en;
        bpu_fsq_io.squashInfo.squash_pc <= pd_redirect.pc;
        bpu_fsq_io.squashInfo.redirectInfo <= u_redirectInfo;
        bpu_fsq_io.squashInfo.btbEntry <= updateEntry;
        bpu_fsq_io.squashInfo.target_pc <= pd_redirect.redirect_addr;
        if(rst == `RST)begin
            search_head <= 0;
            retire_head <= 0;
            tail <= 0;
            full <= 0;
        end
        else begin
            if(full && dequeue)begin
                full <= 1'b0;
            end
            if(!full && enqueue && !dequeue && (tail_n1 == retire_head))begin
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
        end
    end
endmodule