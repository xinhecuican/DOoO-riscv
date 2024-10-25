`include "../../../defines/defines.svh"

interface DispatchQueueIO #(
    parameter DATA_WIDTH = 1,
    parameter OUT_WIDTH = 4,
    parameter DEPTH = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input DisStatusBundle `N(`FETCH_WIDTH) dis_status
);
    logic `N(`FETCH_WIDTH) en;
    logic `ARRAY(`FETCH_WIDTH, DATA_WIDTH) data;
    logic `N(OUT_WIDTH) en_o;
    DisStatusBundle `N(OUT_WIDTH) status_o;
    logic `ARRAY(OUT_WIDTH, `PREG_WIDTH) rs1_o, rs2_o, rs3_o;
    logic `ARRAY(OUT_WIDTH, DATA_WIDTH) data_o;
    logic full;
    logic issue_full;

    // for mem
    logic `ARRAY(`FETCH_WIDTH, ADDR_WIDTH) index;
    logic valid_full;
    logic valid_empty;
    logic `N(ADDR_WIDTH) walk_tail;

    modport dis_queue (input en, dis_status, data, issue_full, output en_o, status_o, rs1_o, rs2_o, rs3_o, data_o, full, index, valid_full, valid_empty, walk_tail);
    modport dequeue (output issue_full, input en_o, status_o, rs1_o, rs2_o, data_o);
endinterface

module DispatchQueue #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH = 16,
    parameter OUT_WIDTH = 4,
    parameter RS1V = 1,
    parameter RS2V = 1,
    parameter RS3V = 0,
    parameter FSELV = 0,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    DispatchQueueIO.dis_queue io,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl
);
    RobIdx robIdxs `N(DEPTH);
    DisStatusBundle status_ram `N(DEPTH);
    logic `N(DATA_WIDTH) entrys `N(DEPTH);
    logic `N(ADDR_WIDTH) head, tail;
    logic `N(ADDR_WIDTH+1) num;
    logic `N($clog2(`FETCH_WIDTH)+1) addNum, eqNum;
    logic `N($clog2(OUT_WIDTH)+1) subNum;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) eq_add_num;
    logic `ARRAY(`FETCH_WIDTH, ADDR_WIDTH) index;

    ParallelAdder #(1, `FETCH_WIDTH) adder (io.en, addNum);
    assign eqNum = backendCtrl.dis_full ? 0 : addNum;
    assign subNum = io.issue_full ? 0 : 
                    num >= OUT_WIDTH ? OUT_WIDTH : num;
    assign io.full = num + addNum > DEPTH;

    CalValidNum #(`FETCH_WIDTH) cal_en (io.en, eq_add_num);
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign index[i] = tail + eq_add_num[i];
    end

    for(genvar i=0; i<OUT_WIDTH; i++)begin
        logic `N(ADDR_WIDTH) raddr;
        logic bigger;
        logic older;
        assign raddr = head + i;
        assign bigger = num > i;
        // LoopCompare #(`ROB_WIDTH) compare_older (backendCtrl.redirectIdx, robIdx[raddr], older);
        assign io.en_o[i] = bigger & (~backendCtrl.redirect);
        assign io.status_o[i] = status_ram[raddr];
        assign io.rs1_o[i] = status_ram[raddr].rs1;
        assign io.rs2_o[i] = status_ram[raddr].rs2;
`ifdef RVF
        assign io.rs3_o[i] = status_ram[raddr].rs3;
`endif
        assign io.data_o[i] = entrys[raddr];
    end
endgenerate

// redirect
    logic `N(DEPTH) valid, bigger, en, validStart, validEnd;
    logic `N(DEPTH) headShift, tailShift;
    logic `N(ADDR_WIDTH) validSelect1, validSelect2;
    logic `N(ADDR_WIDTH) walk_tail;
    logic `N(ADDR_WIDTH + 1) walkNum;
    logic valid_full, valid_empty;
    assign headShift = (1 << head) - 1;
    assign tailShift = (1 << tail) - 1;
    assign en = tail > head || num == 0 ? headShift ^ tailShift : ~(headShift ^ tailShift);
    assign valid = en & bigger;
    assign valid_full = &valid;
    assign valid_empty = ~(|valid);
    assign io.index = index;
    assign io.valid_full = valid_full;
    assign io.valid_empty = valid_empty;
    assign io.walk_tail = walk_tail;

    for(genvar i=0; i<DEPTH; i++)begin
        assign bigger[i] = (status_ram[i].robIdx.dir ^ backendCtrl.redirectIdx.dir) ^ (backendCtrl.redirectIdx.idx > status_ram[i].robIdx.idx);
        logic `N(ADDR_WIDTH) i_n, i_p;
        assign i_n = i + 1;
        assign i_p = i - 1;
        assign validStart[i] = valid[i] & ~valid[i_n]; // valid[i] == 1 && valid[i + 1] == 0
        assign validEnd[i] = valid[i] & ~valid[i_p];
    end
    Encoder #(DEPTH) encoder1 (validStart, validSelect1);
    Encoder #(DEPTH) encoder2 (validEnd, validSelect2);
    ParallelAdder #(.DEPTH(DEPTH)) adder_walk_num (valid, walkNum);
    assign walk_tail = validSelect1 == head ? validSelect2 : validSelect1;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            num <= 0;
        end
        else begin
        if(backendCtrl.redirect)begin
            tail <= valid_full | valid_empty ? head : walk_tail + 1;
            num <= walkNum;
        end
        else begin
            head <= head + subNum;
            tail <= tail + eqNum;
            num <= num + eqNum - subNum;
        end
        end
    end
    always_ff @(posedge clk)begin
        for(int i=0; i<`FETCH_WIDTH; i++)begin
            if(io.en[i] & ~backendCtrl.dis_full)begin
                entrys[index[i]] <= io.data[i];
                status_ram[index[i]].robIdx <= io.dis_status[i].robIdx;
                status_ram[index[i]].we <= io.dis_status[i].we;
                status_ram[index[i]].rd <= io.dis_status[i].rd;
                if(RS1V)begin
                    status_ram[index[i]].rs1 <= io.dis_status[i].rs1;
                end
                if(RS2V)begin
                    status_ram[index[i]].rs2 <= io.dis_status[i].rs2;
                end
                if(RS3V)begin
                    status_ram[index[i]].rs3 <= io.dis_status[i].rs3;
                end
                if(FSELV)begin
                    status_ram[index[i]].frs1_sel <= io.dis_status[i].frs1_sel;
                    status_ram[index[i]].frs2_sel <= io.dis_status[i].frs2_sel;
                end
            end
        end
    end

endmodule

module MemDispatchQueue #(
    parameter DATA_WIDTH = 1,
    parameter IDX_WIDTH = 1,
    parameter DEPTH = 16,
    parameter OUT_WIDTH = 4,
    parameter RS1V = 1,
    parameter RS2V = 1,
    parameter RS3V = 0,
    parameter FSELV = 0,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    input logic `ARRAY(`FETCH_WIDTH, IDX_WIDTH) idx,
    DispatchQueueIO.dis_queue io,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl,
    output logic need_redirect,
    output logic redirect_free,
    output logic `N(IDX_WIDTH) redirect_idx
);
    logic `N(IDX_WIDTH) idxs `N(DEPTH);
    always_ff @(posedge clk)begin
        need_redirect <= ~(io.valid_full);
        redirect_free <= io.valid_empty;
        redirect_idx <= idxs[io.walk_tail];
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            idxs <= '{default: 0};
        end
        else begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if(io.en[i] & ~backendCtrl.dis_full)begin
                    idxs[io.index[i]] <= idx[i];
                end
            end
        end
    end

    DispatchQueue #(DATA_WIDTH, DEPTH, OUT_WIDTH, RS1V, RS2V, RS3V, FSELV) dispatch_queue (.*);

endmodule