`include "../../defines/defines.svh"

module ROB(
    input logic clk,
    input logic rst,
    input BackendRedirectInfo backendRedirect,
    input StoreWBData `N(`STORE_PIPELINE) storeWBData,
    RenameDisIO.dis dis_io,
    ROBRenameIO.rob rob_rename_io,
    WriteBackBus wbBus,
    CommitBus.rob commitBus,
    CommitWalk.rob commitWalk,
    output logic full

`ifdef DIFFTEST
    ,FsqBackendIO.backend fsq_back_io
`endif
);

    typedef enum { IDLE, WALK } RobState;

    typedef struct packed {
        logic `N(`FSQ_WIDTH+1) remainCount;
    } WalkInfo;

    typedef struct packed {
        logic we;
        logic mem;
        logic store;
        FsqIdxInfo fsqInfo;
        logic `N(5) vrd;
        logic `N(`PREG_WIDTH) prd;
    } RobData;

    localparam ROB_BANK_SIZE = `ROB_SIZE / `FETCH_WIDTH;
    RobState state;
    WalkInfo walkInfo;
    logic `N(`ROB_SIZE) wb; // set to 0 when commit, set to 1 when write back
    logic `N(`COMMIT_WIDTH) commitValid;
    logic `N($clog2(`COMMIT_WIDTH) + 1) commit_en_num;
    logic `N(`COMMIT_WIDTH) wbValid, commit_en_pre, commit_en;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`ROB_SIZE)) dataWIdx;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`ROB_SIZE)) dataRIdx;
    logic `N(`FETCH_WIDTH) data_en;
    logic `N(`ROB_WIDTH) head, tail, tail_n, head_n;
    logic `N(`COMMIT_WIDTH) commit_we;
    logic hdir, tdir; // tail direction
    logic `N(`ROB_WIDTH+1) remainCount, remainCount_n;

    logic `N(`FETCH_WIDTH) dis_en;
    logic `N(`FETCH_WIDTH * 2) dis_en_shift;
    logic `N($clog2(`FETCH_WIDTH) + 1) dis_validNum, addNum, subNum;
    logic initReady;
    logic `N(`COMMIT_WIDTH) commit_store, commit_mem;

    RobData `N(`FETCH_WIDTH) robData, rob_wdata;
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign rob_wdata[i].we = dis_io.op[i].di.we;
        assign rob_wdata[i].mem = dis_io.op[i].di.memv;
        assign rob_wdata[i].store = dis_io.op[i].di.memop[`MEMOP_WIDTH-1];
        assign rob_wdata[i].fsqInfo = dis_io.op[i].fsqInfo;
        assign rob_wdata[i].vrd = dis_io.op[i].di.rd;
        assign rob_wdata[i].prd = dis_io.prd[i];
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

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign dis_en[i] = dis_io.op[i].en;
    end
    assign dis_en_shift = dis_en << tail[$clog2(`FETCH_WIDTH)-1: 0];
    assign data_en = dis_en_shift[`FETCH_WIDTH-1: 0] | dis_en_shift[`FETCH_WIDTH * 2 - 1 : `FETCH_WIDTH];
    ParallelAdder #(1, `FETCH_WIDTH) adder_dis_valid (dis_en, dis_validNum);
endgenerate

generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign wbValid[i] = wb[dataRIdx[i]];
        assign commit_we[i] = robData[i].we;
        assign commit_store[i] = robData[i].store;
        assign commit_mem[i] = robData[i].mem;
    end
    assign commit_en_num = remainCount < `COMMIT_WIDTH ? remainCount : `COMMIT_WIDTH;
    assign commitValid = (1 << commit_en_num) - 1;
    assign commit_en_pre = commitValid & wbValid;
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commit_en[i] = &commit_en_pre[i: 0];
    end
endgenerate

    logic `N($clog2(`COMMIT_WIDTH) + 1) commitNum, commitWeNum, commitLoadNum, commitStoreNum;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_num (commit_en, commitNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_we_num (commitBus.en & commit_we, commitWeNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_load (commitBus.en & commit_mem & ~commit_store, commitLoadNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_store (commitBus.en & commit_mem & commit_store, commitStoreNum);
    assign commitBus.wenum = commitWeNum;
    assign commitBus.we = commit_we;
    assign commitBus.robIdx.idx = head;
    assign commitBus.robIdx.dir = hdir;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitBus.fsqInfo[i] = robData[i].fsqInfo;
        assign commitBus.vrd[i] = robData[i].vrd;
        assign commitBus.prd[i] = robData[i].prd;
    end

    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        always_ff @(posedge clk)begin
            if(state == IDLE && initReady)begin
                commitBus.en[i] <= commit_en[i];
            end
            else begin
                commitBus.en[i] <= 0;
            end
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        commitBus.num <= commitNum;
        commitBus.loadNum <= commitLoadNum;
        commitBus.storeNum <= commitStoreNum;
    end

    always_comb begin
        case(state)
        IDLE:begin
            addNum = commitNum;
            subNum = {`ROB_WIDTH{~full & ~backendRedirect.en}} & rob_rename_io.validNum;
            tail_n = tail + subNum;
            head_n = head + addNum;
            remainCount_n = remainCount + addNum - subNum;
        end
        WALK:begin
            addNum = 0;
            subNum = walkInfo.remainCount < `COMMIT_WIDTH ? walkInfo.remainCount : `COMMIT_WIDTH;
            head_n = head;
            tail_n = tail - subNum;
            remainCount_n = remainCount - subNum;
        end
        default: begin
            addNum = 0;
            subNum = 0;
            tail_n = 0;
            head_n = 0;
            remainCount_n = 0;
        end
        endcase
    end

    assign full = remainCount < rob_rename_io.validNum;
    assign rob_rename_io.robIdx.idx = tail;
    assign rob_rename_io.robIdx.dir = tdir;
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            wb <= '{default: 0};
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dataWIdx[i] <= i;
            end
            hdir <= 0;
            tdir <= 0;
            remainCount <= `ROB_SIZE;
        end
        else begin
            tail <= tail_n;
            remainCount <= remainCount_n;
            if(tail[`ROB_WIDTH-1] & ~tail_n[`ROB_WIDTH-1])begin
                tdir <= ~tdir;
            end
            head <= head_n;
            if(head[`ROB_WIDTH-1] & ~head_n[`ROB_WIDTH-1])begin
                hdir <= ~hdir;
            end
            if(dis_io.op[0].en)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataWIdx[i] <= dataWIdx[i] + dis_validNum;
                end
            end
            for(int i=0; i<`WB_SIZE; i++)begin
                if(wbBus.en[i])begin
                    wb[wbBus.robIdx[i].idx] <= 1'b1;
                end
            end
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                if(storeWBData[i].en)begin
                    wb[wbBus.robIdx[i].idx] <= 1'b1;
                end
            end
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(commitBus.en[i])begin
                    wb[dis_io.robIdx[i]] <= 1'b0;
                end
            end
        end
    end

    // walk
    logic `N(`FSQ_WIDTH + 1) walk_remainCount_n, ext_tail;
    logic `N(`FETCH_WIDTH) walk_en;
    logic `N($clog2(`COMMIT_WIDTH)+1) walk_num, walk_we_num;
    assign ext_tail = {tdir ^ backendRedirect.robIdx.dir, tail};
    assign walk_remainCount_n = ext_tail - backendRedirect.robIdx + 1;
    assign walk_num = walk_remainCount_n < `COMMIT_WIDTH ? walk_remainCount_n : `COMMIT_WIDTH;
    assign walk_en = state == IDLE ? (1 << walk_num) - 1 : (1 << subNum) - 1;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_walk_we_num (walk_en & commitWalk.we, walk_we_num);
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitWalk.we[i] = robData[i].we;
    end
endgenerate
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            state <= IDLE;
            walkInfo <= '{default: 0};
            commitWalk.en <= `COMMIT_WIDTH'b0;
            commitWalk.walk <= 1'b0;
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dataRIdx[i] <= i;
            end
        end
        else begin
            case (state)
            IDLE: begin
                if(backendRedirect.en)begin
                    state <= WALK;
                    walkInfo.remainCount <= walk_remainCount_n < `COMMIT_WIDTH ? 0 : walk_remainCount_n - `COMMIT_WIDTH;

                    commitWalk.walk <= 1'b1;
                    commitWalk.walkStart <= 1'b1;
                    commitWalk.en <= (1 << walk_num) - 1;
                    commitWalk.num <= walk_num;
                    commitWalk.weNum <= walk_we_num;
                    for(int i=0; i<`FETCH_WIDTH; i++)begin
                        dataRIdx[i] <= tail - i - 1;
                    end
                end
                else begin
                    if(|commit_en)begin
                        for(int i=0; i<`FETCH_WIDTH; i++)begin
                            dataRIdx[i] <= dataRIdx[i] + commitNum;
                        end
                    end
                end
            end
            WALK: begin
                if(walkInfo.remainCount == 0)begin
                    state <= IDLE;
                    for(int i=0; i<`FETCH_WIDTH; i++)begin
                        dataRIdx[i] <= head + i;
                    end
                    commitWalk.walk <= 1'b0;
                end
                commitWalk.walkStart <= 1'b0;
                commitWalk.en <= (1 << subNum) - 1;
                commitWalk.num <= subNum;
                commitWalk.weNum <= walk_we_num;
                walkInfo.remainCount <= walkInfo.remainCount - subNum;
            end
            endcase
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
    always_ff @(posedge clk)begin
        pc <= fsq_back_io.diff_pc;
        diff_valid <= commitBus.en;
        diff_wen <= commitBus.we;
        diff_wdest <= commitBus.vrd;
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
    DifftestTrapEvent difftest_trap_event (
        .clock(clk),
        .coreid(0),
        .valid(0),
        .code(0),
        .pc(pc[0]),
        .cycleCnt(cycleCnt),
        .instrCnt(instrCnt)
    );

    logic `N($clog2(`COMMIT_WIDTH)+1) commitCnt;
    ParallelAdder #(1, `COMMIT_WIDTH) adder_commit (diff_valid, commitCnt);
    always_ff @(posedge clk)begin
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