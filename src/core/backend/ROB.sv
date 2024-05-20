`include "../../defines/defines.svh"

module ROB(
    input logic clk,
    input logic rst,
    RenameDisIO.dis dis_io,
    WriteBackBus.slave wbBus,
    CommitBus.rob commitBus
);


    typedef struct packed {
        logic we;
        FsqIdxInfo fsqInfo;
        logic `N(5) vrd;
        logic `N(`PREG_WIDTH) prd;
    } RobData;

    localparam ROB_BANK_SIZE = `ROB_SIZE / `FETCH_WIDTH;
    logic `N(`ROB_SIZE) wb; // set to 0 when commit, set to 1 when write back
    logic `N(ROB_BANK_SIZE) valid `N(`FETCH_WIDTH);
    logic `N(`COMMIT_WIDTH) commitValid, commitValid_origin;
    logic `N(`COMMIT_WIDTH * 2) commitValid_shift;
    logic `N(`COMMIT_WIDTH) wbValid, commit_en_pre, commit_en;
    logic `N($clog2(ROB_BANK_SIZE)) dataWIdx `N(`FETCH_WIDTH);
    logic `N($clog2(ROB_BANK_SIZE)) dataRIdx `N(`FETCH_WIDTH);
    logic `N(`FETCH_WIDTH) data_en;
    logic `N(`ROB_WIDTH) head, tail, tail_n;
    logic `N(`ROB_WIDTH) commitHead `N(`COMMIT_WIDTH);
    logic `N(`COMMIT_WIDTH) commit_we;
    logic hdir, tdir; // head direction

    logic `N(`FETCH_WIDTH) dis_en;
    logic `N(`FETCH_WIDTH * 2) dis_en_shift;
    logic `N($clog2(`FETCH_WIDTH)) dis_validNum;

    RobData robData `N(`FETCH_WIDTH);
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N($clog2(`FETCH_WIDTH)) bank_widx;
        assign bank_widx = dis_io.robIdx[$clog2(`FETCH_WIDTH)-1: 0];
        SDPRAM #(
            .WIDTH($bits(RobData)),
            .DEPTH(ROB_BANK_SIZE)
        ) robData (
            .clk(clk),
            .rst(rst),
            .en(1'b1),
            .addr0(dataWIdx[i]),
            .addr1(dataRIdx[i]),
            .we(data_en[i]),
            .wdata({dis_io.op[bank_idx].di.we, dis_io.op[bank_idx].fsqInfo, dis_io.op[bank_widx].di.rd, dis_io.prd[bank_widx]}),
            .rdata1(robData[i])
        );
    end
endgenerate

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign dis_en[i] = dis_io.op[i].en;
    end
    assign dis_en_shift = dis_en << tail[$clog2(`FETCH_WIDTH)-1: 0];
    assign data_en = dis_en_shift[`FETCH_WIDTH-1: 0] | dis_en_shift[`FETCH_WIDTH * 2 - 1 : `FETCH_WIDTH];
    ParallelAdder #(1, `FETCH_WIDTH) adder_dis_valid (dis_en, dis_validNum);
endgenerate
    assign tail_n = tail + dis_validNum;

generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitHead[i] = head + i;
        assign commitValid_origin[i] = valid[i][dataRIdx[i]];
        assign wbValid[i] = wb[commitHead[i]];
        assign commit_we[i] = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].we;
    end
    assign commitValid_shift = commitValid_origin << head[$clog2(`COMMIT_WIDTH)-1: 0];
    assign commitValid = commitValid[ROB_BANK_SIZE-1: ROB_BANK_SIZE] | commitValid[ROB_BANK_SIZE-1: 0];
    assign commit_en_pre = commitValid & wbValid;
    assign commit_en[0] = commit_en_pre[0];
    for(genvar i=1; i<`COMMIT_WIDTH; i++)begin
        assign commit_en[i] = commit_en_pre[i] & commit_en[i-1];
    end

    // for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
    //     assign commitBus.data[i].en = commit_en[i];
    //     assign commitBus.data[i].fsqInfo = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].fsqInfo;
    //     assign commitBus.data[i].vrd = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].vrd;
    //     assign commitBus.data[i].prd = robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].prd;
    // end
endgenerate

    logic `N($clog2(`COMMIT_WIDTH)) commitNum, commitWeNum;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_num (commit_en, commitNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_we_num (commit_en & commit_we, commitWeNum);
    always_ff @(posedge clk)begin
        commitBus.num <= commitNum;
        commitBus.wenum <= commitWeNum;
        for(int i=0; i<`COMMIT_WIDTH; i++)begin
            commitBus.en[i] <= commit_en[i];
            commitBus.we[i] <= commit_we[i];
            commitBus.fsqInfo[i] <= robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].fsqInfo;
            commitBus.vrd[i] <= robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].vrd;
            commitBus.prd[i] <= robData[commitHead[i][$clog2(`COMMIT_WIDTH)-1: 0]].prd;
        end
    end

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            wb <= '{default: 0};
            dataWIdx <= '{default: 0};
            dataRIdx <= '{default: 0};
            hdir <= 0;
            tdir <= 0;
        end
        else begin
            tail <= tail_n;
            if(tail[`ROB_WIDTH-1] ^ tail_n[`ROB_WIDTH-1])begin
                tdir <= ~tdir;
            end
            if(dis_io.op[0].en)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataWIdx[i] <= dataWIdx[i] + data_en[i];
                end
            end
            for(int i=0; i<`WB_SIZE; i++)begin
                if(wbBus.data[i].en)begin
                    wb[wbBus.data[i].robIdx] <= 1'b1;
                end
            end
        end
    end

endmodule