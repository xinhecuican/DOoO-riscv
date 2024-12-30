`include "../../defines/defines.svh"

// 当推测更新ras时，如果先执行pop再push会导致ras中的一项被覆盖
// 即使redirect更新指针也无法修正其中的值
// 一种方法为在commit时写入来修复错误，但是在squash后commit前这一段时间读取会导致错误
// 并且commit会影响推测更新的结果    
// 下面是另一种方法，记录所有inflight的push地址，这样当redirect时不会因为pop-push操作导致覆盖
`ifdef FEAT_LINKRAS
module LinkRAS(
    input logic clk,
    input logic rst,
    BpuRASIO.ras ras_io
);
    RasInflightIdx top, listTop, listBottom;
    logic `N(`RAS_WIDTH) commitTop, inflightTop;
    RasInflightIdx top_p1, top_n1, listTop_n1, rtop_p1, rtop_n1;
    RasInflightIdx rlistTop_n1, listBottom_n1, listBottom_p1, list_p1;
    RasInflightIdx `N(`RAS_INFLIGHT_SIZE) topList;
    logic `N(`RAS_INFLIGHT_SIZE) topInvalid;
    logic preTopInvalid;

    logic [1: 0] squashType, lookupType, commitType;
    logic commitValid;
    RasRedirectInfo r;
    BTBUpdateInfo btbEntry;

    logic we, commit_we;
    RasInflightIdx raddr;
    logic `N(`RAS_WIDTH) commit_raddr;
    logic `N(`RAS_INFLIGHT_WIDTH) waddr;
    logic `N(`RAS_WIDTH) commit_waddr;
    RasEntry entry, commitEntry, updateEntry, commitUpdateEntry;
    logic `VADDR_BUS squash_target;

    logic select_commit;
    logic select_bypass; // push then pop in the next cycle
    RasEntry bypassEntry;
    logic commit_update;

    function inRange(RasInflightIdx raddr);
        logic bottom, top;
        bottom = (listBottom.dir ^ raddr.dir) ^ (raddr.idx < listBottom.idx);
        top = (listTop.dir ^ raddr.dir) ^ (raddr.idx < listTop.idx);
        return ~bottom & top;
    endfunction

    LoopAdder #(`RAS_INFLIGHT_WIDTH, 1) add_top_n1 (1, top, top_n1);
    LoopSub #(`RAS_INFLIGHT_WIDTH, 1) sub_top_p1 (1, ras_io.linfo.rasTop, top_p1);
    LoopAdder #(`RAS_INFLIGHT_WIDTH, 1) add_listtop_n1 (1, ras_io.linfo.listTop, listTop_n1);
    LoopSub #(`RAS_INFLIGHT_WIDTH, 1) sub_rtop_p1 (1, r.rasTop, rtop_p1);
    LoopAdder #(`RAS_INFLIGHT_WIDTH, 1) add_rlisttop_n1 (1, r.listTop, rlistTop_n1);
    LoopAdder #(`RAS_INFLIGHT_WIDTH, 1) add_rtop_n1 (1, r.rasTop, rtop_n1);
    LoopAdder #(`RAS_INFLIGHT_WIDTH, 1) add_listbottom_n1 (1, listBottom, listBottom_n1);
    LoopSub #(`RAS_INFLIGHT_WIDTH, 1) sub_list_bottom_p1 (1, listBottom, listBottom_p1);
    LoopSub #(`RAS_INFLIGHT_WIDTH, 1) sub_list_p1 (1, topList[top_p1.idx], list_p1);

    always_comb begin
        squashType = getRasType(ras_io.squashInfo.br_type);
        lookupType = getRasType(ras_io.br_type);
        commitType = getRasType(btbEntry.tailSlot.br_type);
        commitValid = rasValid(btbEntry.tailSlot.br_type);
    end
    assign r = ras_io.squashInfo.redirectInfo.rasInfo;
    assign btbEntry = ras_io.updateInfo.btbEntry;

    assign we = ~ras_io.squash & ras_io.request & lookupType[1] |
                ras_io.squash & squashType[1];
    assign waddr = ras_io.squash ? r.listTop.idx : ras_io.linfo.listTop.idx;
    assign raddr = ras_io.request & lookupType[0] & ~lookupType[1] ? list_p1 : top_p1;
    assign commit_raddr = ras_io.request & lookupType[0] & ~lookupType[1] ? inflightTop - 2 : inflightTop - 1;
    assign commit_waddr = btbEntry.tailSlot.br_type == POP_PUSH ? commitTop - 1 : commitTop;

    always_ff @(posedge clk)begin
        select_commit <= ~inRange(raddr) | preTopInvalid | 
                        (ras_io.request & (lookupType[0] & ~lookupType[1]) & topInvalid[top_p1.idx]);
        select_bypass <= ras_io.request & lookupType[1];
        bypassEntry.pc <= ras_io.target;
    end

`ifdef RVC
    assign squash_target = ras_io.squashInfo.start_addr + {ras_io.squashInfo.offset, {`INST_OFFSET{1'b0}}} + {~ras_io.squashInfo.rvc, ras_io.squashInfo.rvc, 1'b0};
    assign commitUpdateEntry.pc = ras_io.updateInfo.start_addr + {btbEntry.tailSlot.offset, {`INST_OFFSET{1'b0}}} + {~btbEntry.tailSlot.rvc, btbEntry.tailSlot.rvc, 1'b0};
`else
    assign squash_target = ras_io.squashInfo.start_addr + {ras_io.squashInfo.offset, {`INST_OFFSET{1'b0}}} + 4;
    assign commitUpdateEntry.pc = ras_io.updateInfo.start_addr + {btbEntry.tailSlot.offset, {`INST_OFFSET{1'b0}}} + 4;
`endif

    assign updateEntry.pc = ras_io.squash ? squash_target : ras_io.target;
    assign commit_update = ras_io.update & ras_io.updateInfo.tailTaken & commitValid;
    assign commit_we = ras_io.update & ras_io.updateInfo.tailTaken & commitType[1];

    assign ras_io.en = 1'b1;
    assign ras_io.rasInfo.rasTop = top;
    assign ras_io.rasInfo.listTop = listTop;
    assign ras_io.rasInfo.inflightTop = inflightTop;
    assign ras_io.rasInfo.topInvalid = preTopInvalid;
    assign ras_io.entry = select_bypass ? bypassEntry :
                          select_commit ? commitEntry : entry;

    MPRAM #(
        .WIDTH($bits(RasEntry)),
        .DEPTH(`RAS_INFLIGHT_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) inflight_ras (
        .clk(clk),
        .rst(rst),
        .rst_sync(0),
        .en(1'b1),
        .we(we),
        .waddr(waddr),
        .raddr(raddr.idx),
        .wdata(updateEntry),
        .rdata(entry),
        .ready()
    );
    MPRAM #(
        .WIDTH($bits(RasEntry)),
        .DEPTH(`RAS_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) commit_ras (
        .clk,
        .rst,
        .rst_sync(0),
        .en(1'b1),
        .we(commit_we),
        .waddr(commit_waddr),
        .raddr(commit_raddr),
        .wdata(commitUpdateEntry),
        .rdata(commitEntry),
        .ready()
    );

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            top <= 0;
            listTop <= 0;
            listBottom <= 0;
            topList <= 0;
            commitTop <= 0;
            inflightTop <= 0;
            topInvalid <= 0;
            preTopInvalid <= 0;
        end
        else begin
            if(ras_io.squash)begin
                if(squashType[1])begin
                    if(squashType[0])begin
                        topList[r.listTop.idx] <= topList[rtop_p1.idx];
                    end
                    else begin
                        topList[r.listTop.idx] <= r.rasTop;
                    end
                    topInvalid[r.listTop.idx] <= r.topInvalid;
                    preTopInvalid <= 1'b0;
                    listTop <= rlistTop_n1;
                    top <= rlistTop_n1;
                end
                else if(squashType[0])begin
                    listTop <= r.listTop;
                    if(inRange(topList[rtop_p1.idx]) & ~topInvalid[rtop_p1.idx] & ~r.topInvalid)begin
                        top <= topList[rtop_p1.idx];
                        preTopInvalid <= r.topInvalid;
                    end
                    else begin
                        top <= r.rasTop;
                        preTopInvalid <= 1'b1;
                    end
                end
                else begin
                    listTop <= r.listTop;
                    top <= r.rasTop;
                    preTopInvalid <= r.topInvalid;
                end

                if(squashType[1] & ~squashType[0])begin
                    inflightTop <= r.inflightTop + 1;
                end
                else if(squashType[0] & ~squashType[1])begin
                    inflightTop <= r.inflightTop - 1;
                end
                else begin
                    inflightTop <= r.inflightTop;
                end
            end
            else if(ras_io.request)begin
                if(lookupType[1])begin
                    if(lookupType[0])begin
                        topList[ras_io.linfo.listTop.idx] <= topList[top_p1.idx];
                    end
                    else begin
                        topList[ras_io.linfo.listTop.idx] <= top;
                    end
                    topInvalid[ras_io.linfo.listTop.idx] <= preTopInvalid;
                    preTopInvalid <= 1'b0;
                    listTop <= listTop_n1;
                    top <= listTop_n1;
                end
                else if(lookupType[0]) begin
                    listTop <= ras_io.linfo.listTop;
                    if(inRange(topList[top_p1.idx]) & ~topInvalid[top_p1.idx] & ~preTopInvalid)begin
                        top <= topList[top_p1.idx];
                    end
                    else begin
                        top <= ras_io.linfo.rasTop;
                        preTopInvalid <= 1'b1;
                    end
                end
                else begin
                    listTop <= ras_io.linfo.listTop;
                    top <= ras_io.linfo.rasTop;
                    preTopInvalid <= ras_io.linfo.topInvalid;
                end
                
                if(lookupType[1] & ~lookupType[0])begin
                    inflightTop <= ras_io.linfo.inflightTop + 1;
                end
                else if(lookupType[0] & ~lookupType[1])begin
                    inflightTop <= ras_io.linfo.inflightTop - 1;
                end
                else begin
                    inflightTop <= ras_io.linfo.inflightTop;
                end
            end

            if(commit_update)begin
                if(commitType[0] & ~commitType[1])begin
                    commitTop <= commitTop - 1;
                end
                else if(commitType[1] & ~commitType[0])begin
                    commitTop <= commitTop + 1;
                    listBottom <= listBottom_n1;
                end
            end
        end
    end
`ifdef DIFFTEST
`ifdef T_DEBUG
    logic `ARRAY(`FSQ_SIZE, `RAS_WIDTH) lookup_idx;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`FSQ_WIDTH) inflightTop_n;
    always_ff @(posedge clk)begin
        fsqIdx <= ras_io.updateInfo.fsqIdx;
        inflightTop_n <= inflightTop;
        if(ras_io.lastStage)begin
            lookup_idx[ras_io.lastStageIdx] <= inflightTop_n;
        end
    end
    `Log(DLog::Debug, T_DEBUG, ras_io.update && (commitTop != lookup_idx[fsqIdx]),
    $sformatf("ras commit top mismatch"))
`endif
`endif
endmodule
`else
module RAS(
    input logic clk,
    input logic rst,
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
        .rst_sync(0),
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
        .rst_sync(0),
        .en(1'b1),
        .we(commit_we),
        .waddr(commit_waddr),
        .raddr(top_p1),
        .wdata(commitUpdateEntry),
        .rdata(commitEntry),
        .ready()
    );

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
        if(ras_io.lastStage)begin
            lookup_idx[ras_io.lastStageIdx] <= top;
        end
    end
    `Log(DLog::Debug, T_DEBUG, update_n && (commit_top != lookup_idx[fsqIdx]),
    $sformatf("ras commit top mismatch"))
`endif

endmodule
`endif