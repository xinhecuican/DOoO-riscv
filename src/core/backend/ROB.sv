`include "../../defines/defines.svh"

module ROB(
    input logic clk,
    input logic rst,
    input BackendRedirectInfo backendRedirect,
    RenameDisIO.dis dis_io,
    ROBRenameIO.rob rob_rename_io,
    WriteBackBus.slave wbBus,
    CommitBus.rob commitBus,
    CommitWalk.rob commitWalk,
    output logic full
);

    typedef enum { IDLE, WALK } RobState;

    typedef struct packed {
        logic `N(`FSQ_WIDTH+1) remainCount;
    } WalkInfo;

    typedef struct packed {
        logic we;
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
    logic `ARRAY(`FETCH_WIDTH, $clog2(ROB_BANK_SIZE)) dataWIdx;
    logic `ARRAY(`FETCH_WIDTH, $clog2(ROB_BANK_SIZE)) dataRIdx;
    logic `N(`FETCH_WIDTH) data_en;
    logic `N(`ROB_WIDTH) head, tail, tail_n, head_n;
    logic `N(`ROB_WIDTH) commitHead `N(`COMMIT_WIDTH);
    logic `N(`COMMIT_WIDTH) commit_we;
    logic tdir; // tail direction
    logic `N(`FSQ_WIDTH+1) remainCount, remainCount_n;

    logic `N(`FETCH_WIDTH) dis_en;
    logic `N(`FETCH_WIDTH * 2) dis_en_shift;
    logic `N($clog2(`FETCH_WIDTH) + 1) dis_validNum, addNum, subNum;

    RobData `N(`FETCH_WIDTH) robData, rob_wdata;
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N($clog2(`FETCH_WIDTH)) bank_widx;
        assign bank_widx = dis_io.robIdx.idx[$clog2(`FETCH_WIDTH)-1: 0];
        assign rob_wdata[i].we = dis_io.op[bank_widx].di.we;
        assign rob_wdata[i].fsqInfo = dis_io.op[bank_widx].fsqInfo;
        assign rob_wdata[i].rd = dis_io.op[bank_widx].di.rd;
        assign rob_wdata[i].prd = dis_io.prd[bank_widx];
    end
endgenerate
    MPRAM #(
        .WIDTH($bits(RobData)),
        .DEPTH(`ROB_SIZE),
        .READ_PORT(`COMMIT_WIDTH),
        .WRITE_PORT(`FETCH_WIDTH)
    ) rob_data_ram (
        .clk(clk),
        .en(1'b1),
        .raddr(dataRIdx),
        .rdata(robData),
        .we(data_en),
        .waddr(dataWIdx),
        .wdata(rob_wdata)
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
    end
    assign commit_en_num = remainCount < `COMMIT_WIDTH ? remainCount : `COMMIT_WIDTH;
    assign commitValid = (1 << commit_en_num) - 1;
    assign commit_en_pre = commitValid & wbValid;
    assign commit_en[0] = commit_en_pre[0];
    for(genvar i=1; i<`COMMIT_WIDTH; i++)begin
        assign commit_en[i] = commit_en_pre[i] & commit_en[i-1];
    end
endgenerate

    logic `N($clog2(`COMMIT_WIDTH)) commitNum, commitWeNum;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_num (commit_en, commitNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_we_num (commitBus.en & commit_we, commitWeNum);
    assign commitBus.wenum = commitWeNum;
    assign commitBus.we = commit_we;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitBus.fsqInfo[i] = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].fsqInfo;
        assign commitBus.vrd[i] = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].vrd;
        assign commitBus.prd[i] = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].prd;
    end
endgenerate
    always_ff @(posedge clk)begin
        commitBus.num <= commitNum;
        for(int i=0; i<`COMMIT_WIDTH; i++)begin
            if(state == IDLE && !(backendRedirect.en))begin
                commitBus.en[i] <= commit_en[i];
            end
            else begin
                commitBus.en[i] <= 0;
            end
        end
    end

    always_comb begin
        case(state)
        IDLE:begin
            addNum = commitNum;
            subNum = {`ROB_WIDTH{~full & ~backendRedirect.en}} & rename_dis_io.validNum;
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
        endcase
    end

    assign full = remainCount < rename_dis_io.validNum;
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
            tdir <= 0;
            remainCount <= `ROB_SIZE;
        end
        else begin
            tail <= tail_n;
            remainCount <= remainCount_n;
            if(tail[`ROB_WIDTH-1] ^ tail_n[`ROB_WIDTH-1])begin
                tdir <= ~tdir;
            end
            head <= head_n;
            if(dis_io.op[0].en)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataWIdx[i] <= dataWIdx[i] + dis_validNum;
                end
            end
            if(|commit_en)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataRIdx[i] <= dataRIdx[i] + commitNum;
                end
            end
            for(int i=0; i<`WB_SIZE; i++)begin
                if(wbBus.data[i].en)begin
                    wb[wbBus.data[i].robIdx.idx] <= 1'b1;
                end
            end
        end
    end

    // walk
    logic `N(`FSQ_WIDTH + 1) walk_remainCount_n, ext_tail;
    logic `N(`FETCH_WIDTH) walk_en;
    logic `N($clog2(`FSQ_WIDTH) + 1) walk_num, walk_we_num;
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
            commitWalk.en <= 0;
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
                    for(int i=0; i<`FETCH_WIDTH; i++)begin
                        dataRIdx[i] <= dataRIdx[i] + commitNum;
                    end
                end
            end
            WALK: begin
                if(commitWalk.remainCount == 0)begin
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

endmodule