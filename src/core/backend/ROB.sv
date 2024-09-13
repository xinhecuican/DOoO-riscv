`include "../../defines/defines.svh"

module ROB(
    input logic clk,
    input logic rst,
    input FenceReq fence_req,
    input BackendRedirectInfo backendRedirect,
    input CSRIrqInfo irqInfo,
    input logic `N(`VADDR_SIZE) exc_pc,
    input StoreWBData `N(`STORE_PIPELINE) storeWBData,
    RenameDisIO.rob dis_io,
    ROBRenameIO.rob rob_rename_io,
    RobRedirectIO.rob rob_redirect_io,
    WriteBackBus wbBus,
    CommitBus.rob commitBus,
    CommitWalk.rob commitWalk,
    FenceBus.rob fenceBus,
    output logic full

`ifdef DIFFTEST
    ,FsqBackendIO.backend fsq_back_io
`endif
);

    typedef struct packed {
        logic `N(`ROB_WIDTH+1) remainCount;
    } WalkInfo;

    typedef struct packed {
        logic we;
        logic mem;
        logic store;
        FsqIdxInfo fsqInfo;
        logic `N(5) vrd;
        logic `N(`PREG_WIDTH) prd;
        logic `N(`PREG_WIDTH) old_prd;
`ifdef DIFFTEST
        logic sim_trap;
        logic [2: 0] trapCode;
`endif
    } RobData;

    localparam ROB_BANK_SIZE = `ROB_SIZE / `FETCH_WIDTH;
    WalkInfo walkInfo;
    logic walk_state;
    logic `N(`ROB_SIZE) wb; // set to 0 when commit, set to 1 when write back
    logic `N(`EXC_WIDTH) exccode `N(`ROB_SIZE);
    logic `N(`COMMIT_WIDTH) commitValid;
    logic `N($clog2(`COMMIT_WIDTH) + 1) commit_en_num;
    logic `N(`COMMIT_WIDTH) wbValid, commit_en_pre, commit_en_unexc, commit_en, commit_en_n;
    logic exc_exist;
    logic `N(`COMMIT_WIDTH) excValid, exc_en, exc_mask, exc_en_n;
    logic `N($clog2(`COMMIT_WIDTH)) excIdx;
    logic `ARRAY(`COMMIT_WIDTH, `EXC_WIDTH) rexccode;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`ROB_SIZE)) dataWIdx;
    logic `ARRAY(`COMMIT_WIDTH, $clog2(`ROB_SIZE)) dataRIdx;
    logic `N(`FETCH_WIDTH) data_en;
    logic `N(`ROB_WIDTH) head, tail, tail_n, head_n;
    logic `N(`COMMIT_WIDTH) commit_we;
    logic hdir, tdir; // tail direction
    logic `N(`ROB_WIDTH+1) remainCount, remainCount_n, validCount, validCount_n;

    logic `N(`FETCH_WIDTH) dis_en;
    logic `N(`FETCH_WIDTH * 2) dis_en_shift;
    localparam ROB_ADD_WIDTH = $clog2(`FETCH_WIDTH) + 1; 
    logic `N(ROB_ADD_WIDTH) dis_validNum, addNum, subNum;
    logic initReady;
    logic `N(`COMMIT_WIDTH) commit_store, commit_mem;

    logic `N(`ROB_WIDTH + 1) walk_remainCount_n, ext_tail, walk_remain_count;
    logic `N(`FETCH_WIDTH) walk_en;
    logic `N($clog2(`COMMIT_WIDTH)+1) walk_num, walk_normal_num, redirect_num, walk_we_num;

    logic exc_exist_n;
    logic `N($clog2(`COMMIT_WIDTH)) excIdx_n;
    logic `N(`ROB_WIDTH) exc_robIdx;
    logic exc_dir;
    logic `N(`EXC_WIDTH) redirect_exccode;
    logic irq_n, irq_deleg_n;

    RobData `N(`FETCH_WIDTH) robData, rob_wdata;
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign rob_wdata[i].we = dis_io.op[i].di.we;
        assign rob_wdata[i].mem = dis_io.op[i].di.memv;
        assign rob_wdata[i].store = dis_io.op[i].di.memop[`MEMOP_WIDTH-1];
        assign rob_wdata[i].fsqInfo = dis_io.op[i].fsqInfo;
        assign rob_wdata[i].vrd = dis_io.op[i].di.rd;
        assign rob_wdata[i].prd = dis_io.prd[i];
        assign rob_wdata[i].old_prd = dis_io.old_prd[i];
`ifdef DIFFTEST
        assign rob_wdata[i].sim_trap = dis_io.op[i].di.sim_trap;
        assign rob_wdata[i].trapCode = dis_io.op[i].di.imm;
`endif
    end
endgenerate
    MPRAM #(
        .WIDTH($bits(RobData)),
        .DEPTH(`ROB_SIZE),
        .READ_PORT(`COMMIT_WIDTH),
        .WRITE_PORT(`FETCH_WIDTH),
        .RESET(1)
    ) rob_data_ram (
        .clk(clk),
        .rst(rst),
        .en({`COMMIT_WIDTH{1'b1}}),
        .raddr(dataRIdx),
        .rdata(robData),
        .we(data_en),
        .waddr(dataWIdx),
        .wdata(rob_wdata),
        .ready(initReady)
    );

//enqueue
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign dis_en[i] = dis_io.op[i].en & ~backendCtrl.dis_full;
    end
    assign data_en = dis_en;
    ParallelAdder #(1, `FETCH_WIDTH) adder_dis_valid (dis_en, dis_validNum);
endgenerate

    logic wb_sfence;
    logic fence, fence_redirect;
    logic fence_end_n;
    `SIG_N(fenceBus.fence_end, fence_end_n)
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            fence <= 0;
            fence_redirect <= 0;
        end
        else begin
            if(wb_sfence & ~irqInfo.irq & ~walk_state & ~exc_exist_n & ~exc_exist)begin
                fence <= 1'b1;
                fence_redirect <= 1'b1;
            end
            if(fenceBus.fence_end)begin
                fence_redirect <= 1'b0;
            end
            if(fence_end_n)begin
                fence <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            wb_sfence <= 0;
        end
        else begin
            // en[0] is csr issue queue idx and it's in order
            if(wbBus.en[0] & fence_req.req & (wbBus.robIdx[0] == fence_req.robIdx) & ~irqInfo.irq)begin
                wb_sfence <= wbBus.en[0] & fence_req.req & (wbBus.robIdx[0] == fence_req.robIdx);
            end
            else if((|commit_en_n) | exc_exist_n)begin
                wb_sfence <= 1'b0;
            end
            commitBus.fence_valid <= wb_sfence & (commit_en[0]) & ~walk_state & ~exc_exist_n & ~exc_exist;
        end
    end

// commit
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign wbValid[i] = wb[dataRIdx[i]];
        // exception inst invalid
        assign commit_we[i] = robData[i].we & ~exc_en_n[i];
        assign commit_store[i] = robData[i].store;
        assign commit_mem[i] = robData[i].mem;
        assign rexccode[i] = exccode[dataRIdx[i]];
        assign excValid[i] = ~(&rexccode[i]);
    end
    assign commit_en_num = validCount < `COMMIT_WIDTH ? validCount : `COMMIT_WIDTH;
    assign commitValid = (1 << commit_en_num) - 1;
    assign commit_en_pre = commitValid & wbValid;
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        if(i == 0)begin
            assign commit_en_unexc[i] = commit_en_pre[0] & ~fence;
        end
        else begin
            assign commit_en_unexc[i] = (&commit_en_pre[i: 0]) & ~fence & ~wb_sfence;
        end
    end
    assign exc_en = (excValid | {`COMMIT_WIDTH{irqInfo.irq}});
    assign exc_exist = |(commit_en_unexc & exc_en);
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        if(i == 0)begin
            assign exc_mask[i] = 1'b1;
        end
        else begin
            assign exc_mask[i] = ~(|exc_en[i-1: 0]);
        end
    end
    PREncoder #(`COMMIT_WIDTH) prencoder_exc_idx (excValid, excIdx);
    assign commit_en = commit_en_unexc & exc_mask;
endgenerate

    logic `N($clog2(`COMMIT_WIDTH) + 1) commitNum, commitWeNum, commitLoadNum, commitStoreNum;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_num (commit_en, commitNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_we_num (commitBus.en & commit_we, commitWeNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_load (commitBus.en & commit_mem & ~commit_store & ~exc_en_n, commitLoadNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_store (commitBus.en & commit_mem & commit_store & ~exc_en_n, commitStoreNum);
    assign commitBus.wenum = commitWeNum;
    assign commitBus.we = commit_we;
    assign commitBus.robIdx.idx = head;
    assign commitBus.robIdx.dir = hdir;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitBus.fsqInfo[i] = robData[i].fsqInfo;
        assign commitBus.vrd[i] = robData[i].vrd;
        assign commitBus.prd[i] = robData[i].prd;
        assign commitWalk.vrd[i] = robData[i].vrd;
        assign commitWalk.prd[i] = robData[i].prd;
        assign commitWalk.old_prd[i] = robData[i].old_prd;
    end

    always_ff @(posedge clk)begin
        exc_en_n <= exc_en;
        if(!walk_state && initReady && !exc_exist_n)begin
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                commitBus.en[i] <= commit_en[i];
            end
            commitBus.num <= commitNum;
            commit_en_n <= commit_en;
        end
        else begin
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                commitBus.en[i] <= 0;
            end
            commitBus.num <= 0;
            commit_en_n <= 0;
        end
        if(initReady)begin
            commitBus.loadNum <= commitLoadNum;
            commitBus.storeNum <= commitStoreNum;
        end
        else begin
            commitBus.loadNum <= 0;
            commitBus.storeNum <= 0;
        end
    end
endgenerate


// exception

    always_ff @(posedge clk)begin
        exc_exist_n <= exc_exist && !walk_state && initReady & ~exc_exist_n;
        irq_n <= irqInfo.irq;
        irq_deleg_n <= irqInfo.deleg;
        excIdx_n <= excIdx;
        exc_robIdx <= dataRIdx[excIdx];
        exc_dir <= head[`ROB_WIDTH-1] & ~dataRIdx[excIdx][`ROB_WIDTH-1] ? ~hdir : hdir;
        redirect_exccode <= rexccode[excIdx];
    end
    assign rob_redirect_io.fence = fence_redirect;
    assign rob_redirect_io.csrRedirect.en = exc_exist_n;
    assign rob_redirect_io.csrRedirect.fsqInfo = robData[excIdx_n].fsqInfo;
    assign rob_redirect_io.csrRedirect.robIdx.idx = exc_robIdx;
    assign rob_redirect_io.csrRedirect.robIdx.dir = exc_dir;
    assign rob_redirect_io.csrInfo.en = exc_exist_n;
    assign rob_redirect_io.csrInfo.irq = irq_n;
    assign rob_redirect_io.csrInfo.irq_deleg = irq_deleg_n;
    assign rob_redirect_io.csrInfo.exccode = redirect_exccode;
    assign rob_redirect_io.csrInfo.exc_pc = exc_pc;

// idx maintain
    always_comb begin
        if(walk_state)begin
            addNum = 0;
            subNum = walk_num;
            head_n = head;
            tail_n = tail - subNum;
            remainCount_n = remainCount + subNum;
            validCount_n = validCount - subNum;
        end
        else begin
            addNum = {ROB_ADD_WIDTH{~exc_exist_n}} & commitNum;
            subNum = {ROB_ADD_WIDTH{~backendCtrl.rename_full & ~backendCtrl.dis_full & ~backendRedirect.en}} & rob_rename_io.validNum;
            tail_n = tail + subNum;
            head_n = head + addNum;
            remainCount_n = remainCount + addNum - subNum;
            validCount_n = validCount - addNum + subNum;
        end
    end

    assign full = remainCount < rob_rename_io.validNum;
    assign rob_rename_io.robIdx.idx = tail;
    assign rob_rename_io.robIdx.dir = tdir;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            wb <= '{default: 0};
            exccode <= '{default: 0};
            hdir <= 0;
            tdir <= 0;
            remainCount <= `ROB_SIZE;
            validCount <= 0;
        end
        else begin
            
            tail <= tail_n;
            remainCount <= remainCount_n;
            validCount <= validCount_n;
            if((~commitWalk.walk & tail[`ROB_WIDTH-1] & ~tail_n[`ROB_WIDTH-1]) |
               (commitWalk.walk & tail_n[`ROB_WIDTH-1] & ~tail[`ROB_WIDTH-1]))begin
                tdir <= ~tdir;
            end
            head <= head_n;
            if(head[`ROB_WIDTH-1] & ~head_n[`ROB_WIDTH-1])begin
                hdir <= ~hdir;
            end
            for(int i=0; i<`WB_SIZE; i++)begin
                if(wbBus.en[i])begin
                    wb[wbBus.robIdx[i].idx] <= 1'b1;
                    exccode[wbBus.robIdx[i].idx] <= wbBus.exccode[i];
                end
            end
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                if(storeWBData[i].en)begin
                    wb[storeWBData[i].robIdx.idx] <= 1'b1;
                    exccode[storeWBData[i].robIdx.idx] <= storeWBData[i].exccode;
                end
            end
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if((rob_rename_io.validNum > i) & ~backendCtrl.dis_full & ~backendCtrl.rename_full)begin
                    wb[tail + i] <= 1'b0;
                end
            end
        end
    end

    // walk
    assign ext_tail = {tdir ^ backendRedirect.robIdx.dir, tail};
    assign walk_remainCount_n = ext_tail - backendRedirect.robIdx.idx - 1;
    assign walk_remain_count = backendRedirect.en ? walk_remainCount_n : walkInfo.remainCount;
    /* UNPARAM */
    assign redirect_num = (|walk_remainCount_n[`ROB_WIDTH: $clog2(`COMMIT_WIDTH)]) ? `COMMIT_WIDTH : walk_remainCount_n;
    assign walk_normal_num =  (|walkInfo.remainCount[`ROB_WIDTH: $clog2(`COMMIT_WIDTH)]) ? `COMMIT_WIDTH : walkInfo.remainCount;
    assign walk_num = backendRedirect.en ? redirect_num : walk_normal_num;
    assign walk_en = backendRedirect.en ? (1 << redirect_num) - 1 : (1 << subNum) - 1;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_walk_we_num (commitWalk.en & commitWalk.we, walk_we_num);
    assign commitWalk.weNum = walk_we_num;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitWalk.we[i] = robData[i].we;
    end
endgenerate
    // TODO: dataWIdx改为rw port，walk使用widx，从而walk和commit同时进行
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            walk_state <= 1'b0;
            walkInfo <= '{default: 0};
            commitWalk.en <= `COMMIT_WIDTH'b0;
            commitWalk.walk <= 1'b0;
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                dataRIdx[i] <= i;
            end
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dataWIdx[i] <= i;
            end
        end
        else begin
            if(walk_state)begin
                if(walk_remain_count == 0)begin
                    commitWalk.walk <= 1'b0;
                    walk_state <= 1'b0;
                    commitWalk.en <= 0;
                    commitWalk.num <= 0;
                end
                commitWalk.walkStart <= 1'b0;
                commitWalk.en <= walk_en;
                commitWalk.num <= walk_num;
                walkInfo.remainCount <= walk_remain_count - walk_num;
            end
            else if(backendRedirect.en)begin
                walk_state <= 1'b1;
                walkInfo.remainCount <= walk_remainCount_n;
                commitWalk.walk <= 1'b1;
                commitWalk.walkStart <= 1'b1;
            end

            if(walk_state && walk_remain_count == 0)begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= head + i;
                end
            end
            else if(walk_state)begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= dataRIdx[i] - walk_num;
                end
            end
            else if(backendRedirect.en)begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= tail - i - 1;
                end
            end
            else begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= dataRIdx[i] + commitNum;
                end
            end

            if(backendRedirect.en)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataWIdx[i] <= backendRedirect.robIdx.idx + i + 1;
                end
            end
            else begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataWIdx[i] <= dataWIdx[i] + dis_validNum;
                end
            end

        end
    end

`ifdef DIFFTEST
    logic `ARRAY(`COMMIT_WIDTH, `VADDR_SIZE) pc;
    logic `N(32) insts `N(`ROB_SIZE);
    logic `N(`XLEN) data `N(`ROB_SIZE);
    logic `ARRAY(`COMMIT_WIDTH, 32) diff_insts, diff_insts_before;

    logic `N(`COMMIT_WIDTH) diff_valid, diff_wen;
    logic `ARRAY(`COMMIT_WIDTH, 5) diff_wdest;
    logic `ARRAY(`COMMIT_WIDTH, `XLEN) diff_data, diff_data_before;
    logic `ARRAY(`COMMIT_WIDTH, `ROB_WIDTH) dataRIdxNext, diff_robIdx;
    always_ff @(posedge clk)begin
        pc <= fsq_back_io.diff_pc;
        diff_valid <= commitBus.en;
        diff_wen <= commitBus.we;
        diff_wdest <= commitBus.vrd;
        dataRIdxNext <= dataRIdx;
        diff_robIdx <= dataRIdxNext;
        for(int i=0; i<`FETCH_WIDTH; i++)begin
            if(data_en[i])begin
                insts[dataWIdx[i]] <= dis_io.op[i].inst;
            end
        end
        for(int i=0; i<`WB_SIZE; i++)begin
            if(wbBus.en[i])begin
                data[wbBus.robIdx[i].idx] <= wbBus.res[i];
            end
        end
        for(int i=0; i<`COMMIT_WIDTH; i++)begin
            diff_insts_before[i] <= insts[dataRIdx[i]];
            diff_data_before[i] <= data[dataRIdx[i]];
        end
        diff_insts <= diff_insts_before;
        diff_data <= diff_data_before;
    end
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign fsq_back_io.diff_fsqInfo[i] = robData[i].fsqInfo;
        DifftestInstrCommit difftest_inst_commit(
            .clock(clk),
            .coreid(0),
            .index(i),
            .valid(diff_valid[i]),
            .pc(pc[i]),
            .instr(diff_insts[i]),
            .robIdx({{32-`ROB_WIDTH{1'b0}}, diff_robIdx[i]}),
            .special(1'b0),
            .skip(1'b0),
            .isRVC(1'b0),
            .scFailed(1'b0),
            .wen(diff_wen[i]),
            .wdest(diff_wdest[i]),
            .wdata(diff_data[i])
        );
    end
endgenerate

    logic `N(64) cycleCnt, instrCnt;
    logic trapValid;
    logic `N(`COMMIT_WIDTH) trapValids;
    logic `N($clog2(`COMMIT_WIDTH)) trapIdx;
    logic [7: 0] trapCode;

generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign trapValids[i] = commitBus.en[i] & robData[i].sim_trap;
    end
endgenerate
    PREncoder #(`COMMIT_WIDTH) encoder_trap_idx (trapValids, trapIdx);
    always_ff @(posedge clk)begin
        trapValid <= |trapValids;
        trapCode <= robData[trapIdx].trapCode;
    end

    DifftestTrapEvent difftest_trap_event (
        .clock(clk),
        .coreid(0),
        .valid(trapValid),
        .code(trapCode),
        .pc(pc[0]),
        .cycleCnt(cycleCnt),
        .instrCnt(instrCnt)
    );

    logic `N($clog2(`COMMIT_WIDTH)+1) commitCnt;
    ParallelAdder #(1, `COMMIT_WIDTH) adder_commit (diff_valid, commitCnt);
    assign DLog::cycleCnt = cycleCnt;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            cycleCnt <= 0;
            instrCnt <= 0;
        end
        else begin
            cycleCnt <= cycleCnt + 1;
            instrCnt <= instrCnt + commitCnt;
        end
    end
`endif
endmodule