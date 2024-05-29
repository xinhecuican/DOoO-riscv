`include "../../../defines/defines.svh"

module Dispatch(
    input logic clk,
    input logic rst,
    RenameDisIO.dis rename_dis_io,
    DisIntIssueIO.dis dis_intissue_io,
    WriteBackBus wbBus,
    CommitBus.in commitBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl,
    output logic full
);
    BusyTableIO busytable_io();

    DispatchQueueIO #($bits(IntIssueBundle), `INT_DISPATCH_PORT) int_io();
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : int_in
        DecodeInfo di;
        assign di = rename_dis_io.op[i].di;
        assign int_io.en[i] = rename_dis_io.op[i].en & 
                              (di.intv | di.branchv) &
                              (~(backendCtrl.redirect | backendCtrl.dis_full));
        assign int_io.rs1[i] = di.rs1;
        assign int_io.rs2[i] = di.rs2;
        assign int_io.data[i] = {di.intv, di.branchv, di.sext, di.immv, di.intop, di.branchop,
            rename_dis_io.robIdx[i], rename_dis_io.prd[i], di.imm, rename_dis_io.op[i].fsqInfo};
    end
    assign int_io.robIdx = rename_dis_io.robIdx;
endgenerate
    DispatchQueue #(
        .DATA_WIDTH($bits(IntIssueBundle)),
        .DEPTH(`INT_DISPATCH_SIZE),
        .OUT_WIDTH(`INT_DISPATCH_PORT),
        .NEED_WALK(0)
    ) int_dispatch_queue(
        .*,
        .io(int_io)
    );
    assign full = int_io.full;

    assign busytable_io.dis_en = rename_dis_io.wen & ~backendCtrl.dis_full;
    assign busytable_io.dis_rd = rename_dis_io.prd;
    assign busytable_io.rs1 = int_io.rs1_o;
    assign busytable_io.rs2 = int_io.rs2_o;
    BusyTable busy_table(.*, .io(busytable_io.busytable));

    assign dis_intissue_io.en = int_io.en_o;
    assign dis_intissue_io.data = int_io.data_o;
    assign int_io.issue_full = dis_intissue_io.full;
generate
    for(genvar i=0; i<`INT_DISPATCH_PORT; i++)begin : int_out
        IssueStatusBundle bundle;
        IntIssueBundle issueBundle;
        assign issueBundle = int_io.data_o[i];
        assign bundle.rs1v = busytable_io.rs1_en[i];
        assign bundle.rs2v = busytable_io.rs2_en[i];
        assign bundle.rs1 = int_io.rs1_o[i];
        assign bundle.rs2 = int_io.rs2_o[i];
        assign bundle.robIdx = issueBundle.robIdx;
        assign dis_intissue_io.status[i] = bundle;
    end
endgenerate

endmodule

interface DispatchQueueIO #(
    parameter DATA_WIDTH = 1,
    parameter OUT_WIDTH = 4
);
    logic `N(`FETCH_WIDTH) en;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rs1;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rs2;
    logic `ARRAY(`FETCH_WIDTH, $bits(RobIdx)) robIdx;
    logic `ARRAY(`FETCH_WIDTH, DATA_WIDTH) data;
    /* verilator lint_off UNOPTFLAT */
    logic `N(OUT_WIDTH) en_o;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rs1_o;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rs2_o;
    logic `ARRAY(OUT_WIDTH, DATA_WIDTH) data_o;
    /* verilator lint_off UNOPTFLAT */
    logic full;
    logic issue_full;

    modport dis_queue (input en, rs1, rs2, robIdx, data, issue_full, output en_o, rs1_o, rs2_o, data_o, full);
endinterface

module DispatchQueue #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH = 16,
    parameter OUT_WIDTH = 4,
    parameter NEED_WALK = 1,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    DispatchQueueIO.dis_queue io,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);

    typedef struct packed {
        logic `N(`PREG_WIDTH) rs1, rs2;
        logic `N(DATA_WIDTH) data;
    } Entry;
    /* verilator lint_off UNOPTFLAT */
    logic `N(ADDR_WIDTH) index `N(`FETCH_WIDTH);
    RobIdx robIdx `N(DEPTH);
    logic `N($bits(Entry)) entrys `N(DEPTH);
    logic `N(ADDR_WIDTH) head, tail;
    logic `N(ADDR_WIDTH+1) num;
    logic `N($clog2(`FETCH_WIDTH)+1) addNum, subNum;

    ParallelAdder #(1, `FETCH_WIDTH) adder (io.en, addNum);
    assign subNum = io.issue_full ? 0 : 
                    num >= `FETCH_WIDTH ? `FETCH_WIDTH : num;
    assign io.full = num + addNum > DEPTH;
generate
    assign index[0] = tail;
    for(genvar i=1; i<`FETCH_WIDTH; i++)begin
        assign index[i] = index[i-1] + io.en[i];
    end

    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N(ADDR_WIDTH) raddr;
        Entry entry;
        assign entry = entrys[raddr];
        assign raddr = head + i;
        assign io.en_o[i] = (num > i) & ~io.issue_full;
        assign io.rs1_o[i] = entry.rs1;
        assign io.rs2_o[i] = entry.rs2;
        assign io.data_o[i] = entry.data;
    end
endgenerate

// redirect
generate
    if(NEED_WALK)begin
        logic `N(DEPTH) valid, bigger, en, validStart, validEnd;
        logic `N(DEPTH) headShift, tailShift;
        logic `N(ADDR_WIDTH) validSelect1, validSelect2;
        logic `N(ADDR_WIDTH) walk_tail;
        logic `N(ADDR_WIDTH + 1) walkNum;
        assign headShift = (1 << head) - 1;
        assign tailShift = (1 << tail) - 1;
        assign en = tail > head ? headShift ^ tailShift : ~(headShift ^ tailShift);
        assign valid = en & bigger;

        for(genvar i=0; i<DEPTH; i++)begin
            assign bigger[i] = (robIdx[i].dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > robIdx[i].idx);
            logic `N(ADDR_WIDTH) i_n;
            assign i_n = i + 1;
            assign validStart[i] = valid[i] & ~valid[i+1]; // valid[i] == 1 && valid[i + 1] == 0
            assign validEnd[i] = ~valid[i] & valid[i+1];
        end
        Encoder #(DEPTH) encoder1 (validStart, validSelect1);
        Encoder #(DEPTH) encoder2 (validEnd, validSelect2);
        ParallelAdder #(.DEPTH(DEPTH)) adder_walk_num (valid, walkNum);
        assign walk_tail = validSelect1 == head ? validSelect2 : validSelect1;
        always_ff @(posedge clk)begin
            if(rst == `RST)begin
                head <= 0;
                tail <= 0;
                num <= 0;
            end
            else begin
            if(backendCtrl.redirect)begin
                tail <= |valid ? walk_tail + 1 : head;
                num <= walkNum;
            end
            else begin
                head <= head + subNum;
                tail <= tail + addNum;
                num <= num + addNum - subNum;
            end
            end
        end
    end
    else begin
        always_ff @(posedge clk)begin
            if(rst == `RST)begin
                head <= 0;
                tail <= 0;
                num <= 0;
            end
            else begin
                head <= head + subNum;
                tail <= tail + addNum;
                num <= num + addNum - subNum;
            end
        end
    end

endgenerate


    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            entrys <= '{default: 0};
            robIdx <= '{default: 0};
        end
        else begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if(io.en[i])begin
                    entrys[index[i]] <= {io.rs1[i], io.rs2[i], io.data[i]};
                    robIdx[index[i]] <= io.robIdx[i];
                end
            end
        end
    end

endmodule