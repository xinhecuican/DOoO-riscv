`include "../../defines/defines.svh"

module RAS(
    input logic clk,
    input logic rst,
    input logic lastStage,
    input logic `N(`FSQ_WIDTH) lastStageIdx,
    BpuRASIO.ras ras_io
);
    logic `N(`RAS_WIDTH) top, top_p1, top_n1;
    logic `N(`RAS_WIDTH) bottom, bottom_n1, redirect_bottom_n1;
    logic `N(`RAS_WIDTH) redirect_p1, redirect_n1;
    logic `N(`RAS_WIDTH) commit_top;
    logic bdir, tdir, bdir_n, rbdir_n;
    logic `N(`RAS_WIDTH) waddr, commit_waddr;
    logic `N(`RAS_SIZE) speculate, spec_pop, spec_push, speculate_mask;
    logic `N(`RAS_SIZE) redirect_valid_mask, redirect_top_mask, redirect_bottom_mask;
    logic `N(`RAS_SIZE) commit_mask;
    RasEntry entry, updateEntry, commitUpdateEntry, commitEntry;
    logic [1: 0] squashType;
    RasRedirectInfo r;
    BTBUpdateInfo btbEntry;
    logic we, commit_we;
    logic commit_update;
    logic full, empty, redirect_full, redirect_empty;
    logic `VADDR_BUS squash_target;

    assign top_p1 = top - 1;
    assign top_n1 = top + 1;
    assign redirect_p1 = r.rasTop - 1;
    assign redirect_n1 = r.rasTop + 1;
    LoopAdder #(`RAS_WIDTH, 1) adder_bottom(1'b1, {bottom, bdir}, {bottom_n1, bdir_n});
    LoopAdder #(`RAS_WIDTH, 1) adder_rbottom(1'b1, {r.rasBottom, r.ras_bdir}, {redirect_bottom_n1, rbdir_n});
    assign full = (bdir ^ tdir) & (top == bottom);
    assign empty = (bdir == tdir) & (top == bottom);
    assign r = ras_io.squashInfo.redirectInfo.rasInfo;
    assign btbEntry = ras_io.updateInfo.btbEntry;
    assign redirect_full = (r.ras_bdir ^ r.ras_tdir) & (r.rasTop == r.rasBottom);
    assign redirect_empty = (r.ras_bdir == r.ras_tdir) & (r.rasTop == r.rasBottom);
    MaskGen #(`RAS_SIZE) mask_gen_top (r.rasTop, redirect_top_mask);
    MaskGen #(`RAS_SIZE) mask_gen_bottom (r.rasBottom, redirect_bottom_mask);
    Decoder #(`RAS_SIZE) decoder_commit_top (commit_top, commit_mask);
    assign redirect_valid_mask = redirect_full ? {`RAS_SIZE{1'b1}} :
                                 redirect_empty ? {`RAS_SIZE{1'b0}} :
            redirect_top_mask ^ redirect_bottom_mask ^ {`RAS_SIZE{r.ras_bdir ^ r.ras_tdir}};
    assign speculate_mask = redirect_valid_mask & spec_pop & spec_push;
    assign waddr = ras_io.squash && squashType == POP_PUSH ? r.rasTop - 1 :
                   ras_io.squash ? r.rasTop :
                   ras_io.ras_type == POP_PUSH ? top_p1 : top;
    assign commit_waddr = btbEntry.tailSlot.ras_type == POP_PUSH ? commit_top - 1 : commit_top;

`ifdef RVC
    assign squash_target = ras_io.squashInfo.start_addr + {ras_io.squashInfo.offset, {`INST_OFFSET{1'b0}}} + {~ras_io.squashInfo.rvc, ras_io.squashInfo.rvc, 1'b0};
    assign commitUpdateEntry.pc = ras_io.updateInfo.start_addr + {btbEntry.tailSlot.offset, {`INST_OFFSET{1'b0}}} + {~btbEntry.tailSlot.rvc, btbEntry.tailSlot.rvc, 1'b0};
`else
    assign squash_target = ras_io.squashInfo.start_addr + {ras_io.squashInfo.offset, {`INST_OFFSET{1'b0}}} + 4;
    assign commitUpdateEntry.pc = ras_io.updateInfo.start_addr + {btbEntry.tailSlot.offset, {`INST_OFFSET{1'b0}}} + 4;
`endif
    assign updateEntry.pc = ras_io.squash ? squash_target : ras_io.target;
    assign squashType = ras_io.squashInfo.ras_type;
    assign we = ~ras_io.squash & ras_io.request & ras_io.ras_type[1] | 
                ras_io.squash & squashType[1];
    assign commit_we = ras_io.update & ras_io.updateInfo.tailTaken & 
                        (btbEntry.tailSlot.br_type == CALL) &
                        btbEntry.tailSlot.ras_type[1];
    assign commit_update = ras_io.update & ras_io.updateInfo.tailTaken & (btbEntry.tailSlot.br_type == CALL);


    assign ras_io.en = ~empty;
    assign ras_io.rasInfo.rasTop = top;
    assign ras_io.rasInfo.ras_tdir = tdir;
    assign ras_io.rasInfo.rasBottom = bottom;
    assign ras_io.rasInfo.ras_bdir = bdir;
    assign ras_io.entry = speculate[top_p1] & ~spec_push[top_p1] ? commitEntry : entry;

    MPRAM #(
        .WIDTH($bits(RasEntry)),
        .DEPTH(`RAS_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .READ_LATENCY(0)
    ) ras (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .we(we),
        .waddr(waddr),
        .raddr(top_p1),
        .wdata(updateEntry),
        .rdata(entry),
        .ready()
    );

    MPRAM #(
        .WIDTH($bits(RasEntry)),
        .DEPTH(`RAS_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .READ_LATENCY(0)
    ) commit_ras (
        .clk,
        .rst,
        .en(1'b1),
        .we(commit_we),
        .waddr(commit_waddr),
        .raddr(top_p1),
        .wdata(commitUpdateEntry),
        .rdata(commitEntry),
        .ready()
    );

    // 当推测更新ras时，如果先执行pop再push会导致ras中的一项被覆盖
    // 即使redirect更新指针也无法修正其中的值
    // 一种方法为在commit时写入来修复错误，但是在squash后commit前这一段时间读取会导致错误
    // 并且commit会影响推测更新的结果    
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            top <= 0;
            bottom <= 0;
            bdir <= 0;
            tdir <= 0;
            speculate <= 0;
            spec_pop <= 0;
            spec_push <= 0;
            commit_top <= 0;
        end
        else begin
            if(ras_io.squash)begin
                if(!ras_io.squashInfo.squash_front)begin
                    spec_pop <= 0;
                    spec_push <= 0;
                end
                if(squashType == POP && !redirect_empty)begin
                    top <= r.rasTop - 1;
                    tdir <= redirect_p1[`RAS_WIDTH-1] & ~r.rasTop[`RAS_WIDTH-1] ? ~r.ras_tdir : r.ras_bdir;
                end
                else if(squashType == PUSH)begin
                    top <= r.rasTop + 1;
                    tdir <= r.rasTop[`RAS_WIDTH-1] & ~redirect_n1[`RAS_WIDTH-1] ? ~r.ras_tdir : r.ras_bdir;
                end
                else begin
                    top <= r.rasTop;
                    tdir <= r.ras_tdir;
                end
                if(squashType == PUSH && redirect_full)begin
                    bottom <= redirect_bottom_n1;
                    bdir <= rbdir_n;
                end
                else begin
                    bottom <= r.rasBottom;
                    bdir <= r.ras_bdir;
                end
            end
            else if(ras_io.request)begin
                if(ras_io.ras_type == POP && !empty)begin
                    top <= top_p1;
                    tdir <= top_p1[`RAS_WIDTH-1] & ~top[`RAS_WIDTH-1] ? ~tdir : tdir;
                end
                else if(ras_io.ras_type == PUSH)begin
                    top <= top_n1;
                    tdir <= top[`RAS_WIDTH-1] & ~top_n1[`RAS_WIDTH-1] ? ~tdir : tdir;
                    if(full)begin
                        bottom <= bottom_n1;
                        bdir <= bdir_n;
                    end
                end
            end

            if(ras_io.squashInfo.squash_front & squashType[0] & ~redirect_empty)begin
                spec_pop[redirect_p1] <= 1'b1;
            end
            else if(ras_io.request & ras_io.ras_type[0] & ~empty)begin
                spec_pop[top_p1] <= 1'b1;
            end
            
            if(ras_io.squashInfo.squash_front & squashType[1])begin
                if(squashType[0])begin
                    spec_push[redirect_p1] <= 1'b1;
                end
                else begin
                    spec_push[r.rasTop] <= 1'b1;
                end
            end
            else if(ras_io.request & ras_io.ras_type[1])begin
                if(ras_io.ras_type[0])begin
                    spec_push[top_p1] <= 1'b1;
                end
                else begin
                    spec_push[top] <= 1'b1;
                end
            end

            for(int i=0; i<`RAS_SIZE; i++)begin
                speculate[i] <= (speculate[i] | speculate_mask[i] & ras_io.squash & ~ras_io.squashInfo.squash_front) &
                                ~(commit_we & commit_mask[i]);
            end

            if(commit_update)begin
                if(btbEntry.tailSlot.ras_type == POP)begin
                    commit_top <= commit_top - 1;
                end
                else if(btbEntry.tailSlot.ras_type == PUSH)begin
                    commit_top <= commit_top + 1;
                end
            end
        end
    end

    `Log(DLog::Debug, T_RAS, ~ras_io.squash & ras_io.request & ras_io.ras_type != NONE,
        $sformatf("ras lookup. %d %d %b %b %h %h", top, bottom, tdir, bdir, ras_io.target, ras_io.ras_type))
    `Log(DLog::Debug, T_RAS, ras_io.squash & squashType != NONE,
        $sformatf("ras squash. %h %h", squash_target, squashType))

`ifdef T_DEBUG
    logic `ARRAY(`FSQ_SIZE, `RAS_WIDTH) lookup_idx;
    logic update_n;
    logic `N(`FSQ_WIDTH) fsqIdx;
    always_ff @(posedge clk)begin
        update_n <= ras_io.update;
        fsqIdx <= ras_io.updateInfo.fsqIdx;
        if(lastStage)begin
            lookup_idx[lastStageIdx] <= top;
        end
    end
    `Log(DLog::Debug, T_DEBUG, update_n && (commit_top != lookup_idx[fsqIdx]),
    $sformatf("ras commit top mismatch"))
`endif

endmodule