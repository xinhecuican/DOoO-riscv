`include "../../../defines/defines.svh"

module Dispatch(
    input logic clk,
    input logic rst,
    input LoadIdx lqIdx,
    input StoreIdx sqIdx,
    RenameDisIO.dis rename_dis_io,
    DisIssueIO.dis dis_int_io,
    DisIssueIO.dis dis_load_io,
    DisIssueIO.dis dis_store_io,
    DisIssueIO.dis dis_csr_io,
`ifdef EXT_M
    DisIssueIO.dis dis_mult_io,
`endif
    WakeupBus wakeupBus,
    CommitBus.in commitBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl,
    output logic full
);
    BusyTableIO busytable_io();
    DisStatusBundle `N(`FETCH_WIDTH) dis_status;

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        DecodeInfo di;
        assign di = rename_dis_io.op[i].di;
        assign dis_status[i] = '{we: di.we, 
                                rs1: rename_dis_io.prs1[i], rs2: rename_dis_io.prs2[i], rd: rename_dis_io.prd[i],
                                robIdx: rename_dis_io.robIdx[i]};
    end
endgenerate
// enqueue
    DispatchQueueIO #($bits(IntIssueBundle), `INT_DIS_PORT) int_io(.*);
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : int_in
        DecodeInfo di;
        assign di = rename_dis_io.op[i].di;

        // br type & ras type
        logic push, pop;
        logic `N(`PREG_WIDTH) rd, rs;
        logic `N(`BRANCHOP_WIDTH) op;
        RasType ras_type, ras_type_all;
        BranchType br_type;
        assign rd = di.rd;
        assign rs = di.rs1;
        assign op = di.branchop;
        assign push = rd == 5'h1 || rd == 5'h5;
        assign pop = rs == 5'h1 || rs == 5'h5;
        always_comb begin
            case({push, pop})
            2'b00: ras_type = NONE;
            2'b01: ras_type = POP;
            2'b10: ras_type = PUSH;
            2'b11: ras_type = POP_PUSH;
            endcase
            ras_type_all = (op == `BRANCH_JAL) & push ? PUSH :
                        (op == `BRANCH_JALR) ? ras_type : NONE;
            if(op == `BRANCH_JAL)begin
                br_type = DIRECT;
            end
            else if(op == `BRANCH_JALR)begin
                br_type = INDIRECT;
            end
            else begin
                br_type = CONDITION;
            end
        end
        IntIssueBundle bundle;
        assign bundle = '{intv: di.intv, branchv: di.branchv, uext: di.uext, immv: di.immv,
                        intop: di.intop, branchop: di.branchop, imm: di.imm,
                        br_type: br_type, ras_type: ras_type,
                        fsqInfo: rename_dis_io.op[i].fsqInfo};
        assign int_io.en[i] = rename_dis_io.op[i].en & 
                              (di.intv | di.branchv) &
                              (~(backendCtrl.redirect));
        assign int_io.data[i] = bundle;
    end
endgenerate
    DispatchQueue #(
        .DATA_WIDTH($bits(IntIssueBundle)),
        .DEPTH(`INT_DIS_SIZE),
        .OUT_WIDTH(`INT_DIS_PORT)
    ) int_dispatch_queue(
        .*,
        .io(int_io)
    );

    DispatchQueueIO #($bits(MemIssueBundle), `LOAD_DIS_PORT, `LOAD_DIS_SIZE) load_io(.*);
    DispatchQueueIO #($bits(MemIssueBundle), `STORE_DIS_PORT, `STORE_DIS_SIZE) store_io(.*);
    LoadIdx lq_tail, lq_tail_n;
    StoreIdx sq_tail, sq_tail_n;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) lq_add_num, sq_add_num;
    LoadIdx `N(`FETCH_WIDTH) lq_eq_tail;
    StoreIdx `N(`FETCH_WIDTH) sq_eq_tail;
    logic `N($clog2(`FETCH_WIDTH)+1) lq_num, sq_num;
    logic redirect_n1, redirect_n2;
    logic load_redirect, store_redirect, load_redirect_n, store_redirect_n;
    logic load_rd_free, store_rd_free, load_rd_free_n, store_rd_free_n;
    LoadIdx load_redirect_idx, load_redirectIdx_n, load_redirectIdx_n2;
    StoreIdx store_redirect_idx, store_redirectIdx_n, store_redirectIdx_n2;

    CalValidNum #(`FETCH_WIDTH) cal_lq_valid (load_io.en, lq_add_num);
    CalValidNum #(`FETCH_WIDTH) cal_sq_valid (store_io.en, sq_add_num);
    ParallelAdder #(1, `FETCH_WIDTH) adder_lq_num (load_io.en , lq_num);
    ParallelAdder #(1, `FETCH_WIDTH) adder_sq_num (store_io.en, sq_num);
    LoopAdder #(`LOAD_QUEUE_WIDTH, $clog2(`FETCH_WIDTH)+1) adder_lq_tail (lq_num, lq_tail, lq_tail_n);
    LoopAdder #(`STORE_QUEUE_WIDTH, $clog2(`FETCH_WIDTH)+1) adder_sq_tail (sq_num, sq_tail, sq_tail_n);
    LoopAdder #(`LOAD_QUEUE_WIDTH, 1) adder_lq_redirect (1'b1, load_redirect_idx, load_redirectIdx_n);
    LoopAdder #(`STORE_QUEUE_WIDTH, 1) adder_sq_redirect (1'b1, store_redirect_idx, store_redirectIdx_n);
    always_ff @(posedge clk)begin
        redirect_n1 <= backendCtrl.redirect;
        redirect_n2 <= redirect_n1;
        load_redirect_n <= load_redirect;
        store_redirect_n <= store_redirect;
        load_rd_free_n <= load_rd_free;
        store_rd_free_n <= store_rd_free;
        load_redirectIdx_n2 <= load_redirectIdx_n;
        store_redirectIdx_n2 <= store_redirectIdx_n;
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            lq_tail <= 0;
            sq_tail <= 0;
        end
        else if(redirect_n2)begin
            if(load_rd_free_n)begin
                lq_tail <= lqIdx;
            end
            else if(load_redirect_n)begin
                lq_tail <= load_redirectIdx_n2;
            end
            if(store_rd_free_n)begin
                sq_tail <= sqIdx;
            end
            else if(store_redirect_n)begin
                sq_tail <= store_redirectIdx_n2;
            end
        end
        else if(~backendCtrl.dis_full)begin
            lq_tail <= lq_tail_n;
            sq_tail <= sq_tail_n;
        end
    end
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : load_in
        LoopAdder #(`LOAD_QUEUE_WIDTH, $clog2(`FETCH_WIDTH)) adder_lqIdx (lq_add_num[i], lq_tail, lq_eq_tail[i]);
        LoopAdder #(`STORE_QUEUE_WIDTH, $clog2(`FETCH_WIDTH)) adder_sqIdx (sq_add_num[i], sq_tail, sq_eq_tail[i]);
        DecodeInfo di;
        MemIssueBundle data;
        assign data.uext = di.uext;
        assign data.memop = di.memop;
        assign data.imm = di.imm[11: 0];
        assign data.fsqInfo = rename_dis_io.op[i].fsqInfo;
        assign data.lqIdx = lq_eq_tail[i];
        assign data.sqIdx = sq_eq_tail[i];
        assign di = rename_dis_io.op[i].di;
        assign load_io.en[i] = rename_dis_io.op[i].en & (di.memv) & ~di.memop[`MEMOP_WIDTH-1] &
                               (~(backendCtrl.redirect));
        assign load_io.data[i] = data;
        assign store_io.en[i] = rename_dis_io.op[i].en & di.memv & di.memop[`MEMOP_WIDTH-1] &
                                (~(backendCtrl.redirect));
        assign store_io.data[i] = data;
    end
endgenerate
    MemDispatchQueue #(
        .DATA_WIDTH($bits(MemIssueBundle)),
        .IDX_WIDTH($bits(LoadIdx)),
        .DEPTH(`LOAD_DIS_SIZE),
        .OUT_WIDTH(`LOAD_DIS_PORT)
    ) load_dispatch_queue(
        .*,
        .idx(lq_eq_tail),
        .io(load_io),
        .need_redirect(load_redirect),
        .redirect_free(load_rd_free),
        .redirect_idx(load_redirect_idx)
    );
    MemDispatchQueue #(
        .DATA_WIDTH($bits(MemIssueBundle)),
        .IDX_WIDTH($bits(StoreIdx)),
        .DEPTH(`STORE_DIS_SIZE),
        .OUT_WIDTH(`STORE_DIS_PORT)
    ) store_dispatch_queue(
        .*,
        .idx(sq_eq_tail),
        .io(store_io),
        .need_redirect(store_redirect),
        .redirect_free(store_rd_free),
        .redirect_idx(store_redirect_idx)
    );

    DispatchQueueIO #($bits(CsrIssueBundle), `CSR_DIS_PORT) csr_io(.*);
    DispatchQueue #(
        .DATA_WIDTH($bits(CsrIssueBundle)),
        .DEPTH(`CSR_DIS_SIZE),
        .OUT_WIDTH(`CSR_DIS_PORT)
    ) csr_dispatch_queue (
        .*,
        .io(csr_io)
    );
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : csr_in
        DecodeInfo di;
        CsrIssueBundle data;
        assign data.csrop = di.csrop;
        assign data.imm = di.imm[4: 0];
        assign data.csrid = di.csrid;
        assign data.fsqInfo = rename_dis_io.op[i].fsqInfo;
        assign data.exc_valid = di.exccode != `EXC_NONE;
        assign data.exccode = di.exccode;
        assign di = rename_dis_io.op[i].di;
        assign csr_io.en[i] = rename_dis_io.op[i].en & di.csrv & (~(backendCtrl.redirect));
        assign csr_io.data[i] = data;
    end
endgenerate

`ifdef EXT_M
    DispatchQueueIO #($bits(MultIssueBundle), `MULT_DIS_PORT) mult_io(.*);
    DispatchQueue #(
        .DATA_WIDTH($bits(MultIssueBundle)),
        .DEPTH(`MULT_DIS_SIZE),
        .OUT_WIDTH(`MULT_DIS_PORT)
    ) mult_dispatch_queue (
        .*,
        .io(mult_io)
    );
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : mult_in
        DecodeInfo di;
        MultIssueBundle data;
        assign di = rename_dis_io.op[i].di;
        assign data.multop = di.multop;
        assign mult_io.en[i] = rename_dis_io.op[i].en & di.multv & ~backendCtrl.redirect;
        assign mult_io.data[i] = data;
    end
`endif

    assign full = int_io.full | load_io.full | store_io.full | csr_io.full
`ifdef EXT_M
                  | mult_io.full
`endif
    ;

    assign busytable_io.dis_en = rename_dis_io.wen & ~{`FETCH_WIDTH{backendCtrl.dis_full}};
    assign busytable_io.dis_rd = rename_dis_io.prd;
    assign busytable_io.preg = {
`ifdef EXT_M
                                mult_io.rs2_o, mult_io.rs1_o,
`endif
                                store_io.rs2_o, store_io.rs1_o, load_io.rs1_o,
                                int_io.rs2_o, int_io.rs1_o};
    BusyTable busy_table(.*, .io(busytable_io.busytable));

// dequeue

`define DEQ_TEMPLATE(name, PORT_BASE, PORT_SIZE, RS1V, RS2V) \
    assign dis_``name``_io.en = ``name``_io.en_o; \
    assign dis_``name``_io.data = ``name``_io.data_o; \
    assign ``name``_io.issue_full = dis_``name``_io.full; \
generate \
    for(genvar i=0; i<PORT_SIZE; i++)begin : ``name``_out \
        IssueStatusBundle bundle; \
        logic rs1v, rs2v; \
        if(RS1V)begin \
            assign rs1v = busytable_io.reg_en[PORT_BASE+i]; \
        end \
        else begin \
            assign rs1v = 0; \
        end \
        if(RS2V)begin \
            assign rs2v = busytable_io.reg_en[PORT_BASE+PORT_SIZE+i]; \
        end \
        else begin \
            assign rs2v = 0; \
        end \
        assign bundle = {rs1v, rs2v, ``name``_io.status_o[i]}; \
        assign dis_``name``_io.status[i] = bundle; \
    end \
endgenerate

    `DEQ_TEMPLATE(int, 0, `INT_DIS_PORT, 1, 1)
    localparam LOAD_BASE = `INT_DIS_PORT * 2;
    `DEQ_TEMPLATE(load, LOAD_BASE, `LOAD_DIS_PORT, 1, 0)
    localparam STORE_BASE = `INT_DIS_PORT * 2 + `LOAD_DIS_PORT;
    `DEQ_TEMPLATE(store, STORE_BASE, `STORE_DIS_PORT, 1, 1)

    IssueStatusBundle csr_status;
    CsrIssueBundle csr_issue_bundle;
    assign csr_issue_bundle = csr_io.data_o;
    assign dis_csr_io.en = csr_io.en_o;
    assign dis_csr_io.data = csr_io.data_o;
    assign csr_io.issue_full = dis_csr_io.full;
    assign csr_status.rs1v = 1'b0;
    assign csr_status.rs2v = 1'b0;
    assign csr_status.rs1 = csr_io.rs1_o;
    assign csr_status.rs2 = 0;
    assign csr_status.rd = csr_io.status_o[0].rd;
    assign csr_status.robIdx = csr_io.status_o[0].robIdx;
    assign csr_status.we = csr_io.status_o[0].we;
    assign dis_csr_io.status = csr_status;

`ifdef EXT_M
    localparam MULT_BASE = `INT_DIS_PORT*2+`LOAD_DIS_PORT+`STORE_DIS_PORT * 2;
    `DEQ_TEMPLATE(mult, MULT_BASE, `MULT_DIS_PORT, 1, 1)
`endif
endmodule

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
    logic `ARRAY(OUT_WIDTH, `PREG_WIDTH) rs1_o, rs2_o;
    logic `ARRAY(OUT_WIDTH, DATA_WIDTH) data_o;
    logic full;
    logic issue_full;

    // for mem
    logic `ARRAY(`FETCH_WIDTH, ADDR_WIDTH) index;
    logic valid_full;
    logic valid_empty;
    logic `N(ADDR_WIDTH) walk_tail;

    modport dis_queue (input en, dis_status, data, issue_full, output en_o, status_o, rs1_o, rs2_o, data_o, full, index, valid_full, valid_empty, walk_tail);
endinterface

module DispatchQueue #(
    parameter DATA_WIDTH = 1,
    parameter DEPTH = 16,
    parameter OUT_WIDTH = 4,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    DispatchQueueIO.dis_queue io,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);

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
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            entrys <= '{default: 0};
            status_ram <= '{default: 0};
        end
        else begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if(io.en[i] & ~backendCtrl.dis_full)begin
                    entrys[index[i]] <= io.data[i];
                    status_ram[index[i]] <= io.dis_status[i];
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
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    input logic `ARRAY(`FETCH_WIDTH, IDX_WIDTH) idx,
    DispatchQueueIO.dis_queue io,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl,
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

    DispatchQueue #(DATA_WIDTH, DEPTH, OUT_WIDTH) dispatch_queue (.*);

endmodule