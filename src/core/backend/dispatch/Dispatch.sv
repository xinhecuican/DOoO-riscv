`include "../../../defines/defines.svh"

module Dispatch(
    input logic clk,
    input logic rst,
    RenameDisIO.dis rename_dis_io
);
    BusyTableIO busytable_io;

    ROB rob(.*, .dis_io(rename_dis_io.rob));

    DispatchQueueIO #($bits(IntIssueBundle), `INT_DISPATCH_PORT) int_io;
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        DecodeInfo di;
        assign di = rename_dis_io.op[i].di;
        assign int_io.en[i] = rename_dis_io.op[i].en & 
                              (di.intv | di.branchv);
        assign int_io.rs1[i] = di.rs1;
        assign int_io.rs2[i] = di.rs2;
        assign int_io.data[i] = {di.intv, di.branchv, di.sext, di.immv, di.intop, di.branchop, di.rd, di.imm, rename_dis_io.op[i].fsqInfo};
    end
endgenerate
    DispatchQueue #(
        .DATA_WIDTH($bits(IntIssueBundle)),
        .DEPTH(`INT_DISPATCH_SIZE),
        .OUT_WIDTH(`INT_DISPATCH_PORT)
    ) int_dispatch_queue(
        .*,
        .io(int_io)
    );

    assign busytable_io.dis_en = rename_dis_io.wen;
    assign busytable_io.dis_rd = rename_dis_io.prd;
    assign busytable_io.rs1 = int_io.rs1_o;
    assign busytable_io.rs2 = int_io.rs2_o;
    BusyTable busy_table(.*, .io(busytable_io.busytable));

    DisIntIssueIO dis_intissue_io;
    assign dis_intissue_io.en = int_io.en_o;
    assign dis_intissue_io.data = int_io.data_o;
generate
    for(genvar i=0; i<`INT_DISPATCH_PORT; i++)begin
        IssueStatusBundle bundle;
        assign bundle.rs1v = busytable_io.rs1_en[i];
        assign bundle.rs2v = busytable_io.rs2_en[i];
        assign bundle.rs1 = int_io.rs1_o[i];
        assign bundle.rs2 = int_io.rs2_o[i];
        assign dis_intissue_io.status[i] = bundle;
    end
endgenerate
    IntIssueQueue int_issue_queue(
        .*,
        .dis_issue_io(dis_int_issue_io)
    );

endmodule

interface DispatchQueueIO #(
    parameter DATA_WIDTH = 1,
    parameter OUT_WIDTH = 4
);
    logic `N(`FETCH_WIDTH) en;
    logic `N(`PREG_WIDTH) rs1;
    logic `N(`PREG_WIDTH) rs2;
    logic `ARRAY(`FETCH_WIDTH, DATA_WIDTH) data;
    logic `N(OUT_WIDTH) en_o;
    logic `N(`PREG_WIDTH) rs1_o;
    logic `N(`PREG_WIDTH) rs2_o;
    logic `ARRAY(OUT_WIDTH, DATA_WIDTH) data_o;
    logic full;

    modport dis_queue (input en, rs1, rs2, data, output en_o, rs1_o, rs2_o, data_o, full);
endinterface

module DispatchQueue #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH = 16,
    parameter OUT_WIDTH = 4,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    DispatchQueueIO.dis_queue io
);

    typedef struct packed {
        logic `N(`PREG_WIDTH) rs1, rs2;
        logic `N(DATA_WIDTH) data;
    } Entry;
    logic `N(ADDR_WIDTH) index `N(`FETCH_WIDTH);
    logic `N($bits(Entry)) entrys `N(DEPTH);
    logic `N(ADDR_WIDTH) head, tail;
    logic `N(ADDR_WIDTH+1) num;
    logic `N($clog2(`FETCH_WIDTH)) addNum, subNum;

    ParallelAdder #(1, `FETCH_WIDTH) adder (en, addNum);
    assign subNum = num >= `FETCH_WIDTH ? `FETCH_WIDTH : num;
    assign io.full = num + addNum - subNum > DEPTH;
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
        assign io.en_o[i] = num > i;
        assign io.rs1_o[i] = entry.rs1;
        assign io.rs2_o[i] = entry.rs2;
        assign io.data_o[i] = entry.data;
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            entrys <= '{default: 0};
            head <= 0;
            tail <= 0;
            num <= 0;
        end
        else begin
            head <= head + subNum;
            tail <= tail + addNum;
            num <= num + addNum - subNum;
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if(io.en[i])begin
                    entrys[index[i]] <= {io.rs1[i], io.rs2[i], io.data[i]};
                end
            end
        end
    end

endmodule