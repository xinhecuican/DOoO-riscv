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
`ifdef RVM
    DisIssueIO.dis dis_mult_io,
`endif
`ifdef RVA
    DisIssueIO.dis dis_amo_io,
`endif
    WakeupBus.in int_wakeupBus,
`ifdef RVF
    WakeupBus.in fp_wakeupBus,
    DisIssueIO.dis dis_fmisc_io,
    DisIssueIO.dis dis_fma_io,
    DisIssueIO.dis dis_fdiv_io,
`endif
`ifdef FEAT_MEMPRED
    StoreSetIO.dis storeset_io,
`endif
    CommitBus.in commitBus,
    FenceBus.dis fenceBus,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl/*verilator split_var*/,
    input logic redirect,
    output logic full
);
    BusyTableIO #(`INT_BUSY_PORT) int_busy_io();
`ifdef RVF
    BusyTableIO #(`FP_BUSY_PORT) fp_busy_io();
`endif
    DisStatusBundle `N(`FETCH_WIDTH) dis_status;

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        DecodeInfo di;
        assign di = rename_dis_io.op[i].di;
        assign dis_status[i] = '{we: di.we, 
                                rs1: rename_dis_io.prs1[i], rs2: rename_dis_io.prs2[i], rd: rename_dis_io.prd[i],
                                robIdx: rename_dis_io.robIdx[i],
`ifdef RVF
                                frs1_sel: di.frs1_sel,
                                frs2_sel: di.frs2_sel,
                                rs3: rename_dis_io.prs3[i],
`endif
                                default: 0};
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
        logic jal, jalr;
        BranchType br_type;
        assign rd = di.rd;
        assign rs = di.rs1;
        assign op = di.branchop;
        assign push = rd == 5'h1 || rd == 5'h5;
        assign pop = (rs == 5'h1 || rs == 5'h5) && (rs != rd);
        assign jal = op == `BRANCH_JAL;
        assign jalr = op == `BRANCH_JALR;
        always_comb begin
            if(di.branchv)begin
                if(~(jal | jalr))begin
                    br_type = CONDITION;
                end
                else if(jalr)begin
                    case({push, pop})
                    2'b00: br_type = INDIRECT;
                    2'b01: br_type = POP;
                    2'b10: br_type = INDIRECT_CALL;
                    2'b11: br_type = POP_PUSH;
                    endcase
                end
                else begin
                    if(push)begin
                        br_type = PUSH;
                    end
                    else begin
                        br_type = DIRECT;
                    end
                end
            end
            else begin
                br_type = DIRECT;
            end
        end
        IntIssueBundle bundle;
        assign bundle = '{intv: di.intv, branchv: di.branchv, uext: di.uext, immv: di.immv,
                        intop: di.intop, branchop: di.branchop, imm: di.imm, br_type: br_type,
                        fsqInfo: rename_dis_io.op[i].fsqInfo
`ifdef RVC
                        , rvc: di.rvc
`endif
`ifdef RV64I
                        , word: di.word
`endif
                        };
        assign int_io.en[i] = rename_dis_io.op[i].en & 
                              (di.intv | di.branchv) &
                              (~(redirect));
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
        redirect_n1 <= redirect;
        redirect_n2 <= redirect_n1;
        load_redirect_n <= load_redirect;
        store_redirect_n <= store_redirect;
        load_rd_free_n <= load_rd_free;
        store_rd_free_n <= store_rd_free;
        load_redirectIdx_n2 <= load_redirectIdx_n;
        store_redirectIdx_n2 <= store_redirectIdx_n;
    end
    always_ff @(posedge clk or negedge rst)begin
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
        assign data = '{uext: di.uext, memop: di.memop, imm: di.imm[19: 8],
`ifdef RVF
                        fp_en: di.frs1_sel | di.flt_we,
`endif
`ifdef FEAT_MEMPRED
                        ssitEntry: storeset_io.ssit_entrys[i],
`endif
                        fsqInfo: rename_dis_io.op[i].fsqInfo,
                        lqIdx: lq_eq_tail[i], sqIdx: sq_eq_tail[i]};
        assign di = rename_dis_io.op[i].di;
        assign load_io.en[i] = rename_dis_io.op[i].en & (di.memv) & ~di.memop[`MEMOP_WIDTH-1] &
                               (~(redirect));
        assign load_io.data[i] = data;
        assign store_io.en[i] = rename_dis_io.op[i].en & di.memv & di.memop[`MEMOP_WIDTH-1] &
                                (~(redirect));
        assign store_io.data[i] = data;
`ifdef FEAT_MEMPRED
        assign storeset_io.lfst_we[i] = store_io.en[i] & data.ssitEntry.en;
        assign storeset_io.lfst_waddr[i] = data.ssitEntry.idx;
        assign storeset_io.lfst_widx[i] = store_io.dis_status[i].robIdx;
`endif
    end
`ifdef FEAT_MEMPRED
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        MemIssueBundle data;
        assign data = load_io.data_o[i];
        assign storeset_io.lfst_raddr[i] = data.ssitEntry.idx;
    end
`endif
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
        .OUT_WIDTH(`STORE_DIS_PORT),
        .FSELV(1)
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
        assign data.imm = di.imm[19: 3];
        assign data.fsqInfo = rename_dis_io.op[i].fsqInfo;
        assign data.exc_valid = di.exccode != `EXC_NONE;
        assign data.exccode = di.exccode;
        assign data.inst = rename_dis_io.op[i].inst;
        assign di = rename_dis_io.op[i].di;
        assign csr_io.en[i] = rename_dis_io.op[i].en & di.csrv & (~(redirect));
        assign csr_io.data[i] = data;
    end
endgenerate

`ifdef RVM
    DispatchQueueIO #($bits(MultIssueBundle), `MULT_DIS_PORT) mult_io(.*);
    DispatchQueue #(
        .DATA_WIDTH($bits(MultIssueBundle)),
        .DEPTH(`MULT_DIS_SIZE),
        .OUT_WIDTH(`MULT_DIS_PORT)
    ) mult_dispatch_queue (
        .*,
        .io(mult_io)
    );
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : mult_in
        DecodeInfo di;
        MultIssueBundle data;
        assign di = rename_dis_io.op[i].di;
        assign data.multop = di.multop;
`ifdef RV64I
        assign data.word = di.word;
`endif
        assign mult_io.en[i] = rename_dis_io.op[i].en & di.multv & ~redirect;
        assign mult_io.data[i] = data;
    end
endgenerate
`endif

`ifdef RVA
    DispatchQueueIO #($bits(AmoIssueBundle), `AMO_DIS_PORT) amo_io(.*);
    DispatchQueue #(
        .DATA_WIDTH($bits(AmoIssueBundle)),
        .DEPTH(`AMO_DIS_SIZE),
        .OUT_WIDTH(`AMO_DIS_PORT)
    ) amo_dispatch_queue (
        .*,
        .io(amo_io)
    );
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : amo_in
        DecodeInfo di;
        AmoIssueBundle data;
        assign di = rename_dis_io.op[i].di;
        assign data.amoop = di.amoop;
`ifdef RV64I
        assign data.word = di.word;
`endif
        assign amo_io.en[i] = rename_dis_io.op[i].en & di.amov & ~redirect;
        assign amo_io.data[i] = data;
    end
endgenerate
`endif

`ifdef RVF
    DispatchQueueIO #($bits(FMiscIssueBundle), `FMISC_DIS_PORT) fmisc_io(.*);
    DispatchQueueIO #($bits(FMAIssueBundle), `FMA_DIS_PORT) fma_io(.*);
    DispatchQueueIO #($bits(FDivIssueBundle), `FDIV_DIS_PORT) fdiv_io(.*);
    DispatchQueue #(
        .DATA_WIDTH($bits(FMiscIssueBundle)),
        .DEPTH(`FMISC_DIS_SIZE),
        .OUT_WIDTH(`FMISC_DIS_PORT),
        .FSELV(1)
    ) fmisc_dispatch_queue (
        .*,
        .io(fmisc_io)
    );
    DispatchQueue #(
        .DATA_WIDTH($bits(FMAIssueBundle)),
        .DEPTH(`FMA_DIS_SIZE),
        .OUT_WIDTH(`FMA_DIS_PORT),
        .RS3V(1)
    ) fma_dispatch_queue (
        .*,
        .io(fma_io)
    );
    DispatchQueue #(
        .DATA_WIDTH($bits(FDivIssueBundle)),
        .DEPTH(`FDIV_DIS_SIZE),
        .OUT_WIDTH(`FDIV_DIS_PORT)
    ) fdiv_dispatch_queue (
        .*,
        .io(fdiv_io)
    );
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin : fp_in
        DecodeInfo di;
        FMiscIssueBundle misc_bundle;
        FMAIssueBundle fma_bundle;
        FDivIssueBundle fdiv_bundle;
        logic div;
        assign di = rename_dis_io.op[i].di;
        assign div = di.fltop == `FLT_DIV || di.fltop == `FLT_SQRT;
        assign misc_bundle.fltop = di.fltop;
        assign misc_bundle.flt_we = di.flt_we;
        assign misc_bundle.uext = di.uext;
        assign misc_bundle.rm = di.rm;
`ifdef RV64I
        assign misc_bundle.word = di.word;
`endif
        assign fma_bundle.fltop = di.fltop;
        assign fma_bundle.rm = di.rm;
        assign fdiv_bundle.div = di.fltop == `FLT_DIV;
        assign fdiv_bundle.rm = di.rm;
`ifdef RVD
        assign misc_bundle.db = di.db;
        assign fma_bundle.db = di.db;
        assign fdiv_bundle.db = di.db;
`endif
        assign fmisc_io.en[i] = rename_dis_io.op[i].en & di.fmiscv & ~redirect;
        assign fma_io.en[i] = rename_dis_io.op[i].en & di.fcalv & ~div & ~redirect;
        assign fdiv_io.en[i] = rename_dis_io.op[i].en & di.fcalv & div & ~redirect;
        assign fmisc_io.data[i] = misc_bundle;
        assign fma_io.data[i] = fma_bundle;
        assign fdiv_io.data[i] = fdiv_bundle;
    end
endgenerate
`endif

    assign full = int_io.full | load_io.full | store_io.full | csr_io.full | fenceBus.valid
`ifdef RVM
                  | mult_io.full
`endif
`ifdef RVA
                  | amo_io.full
`endif
`ifdef RVF
                  | fmisc_io.full | fma_io.full | fdiv_io.full
`endif
    ;

    assign int_busy_io.dis_en = rename_dis_io.int_wen & ~{`FETCH_WIDTH{backendCtrl.dis_full}};
    assign int_busy_io.dis_rd = rename_dis_io.prd;
    assign int_busy_io.preg = {
`ifdef RVF
                                fmisc_io.rs1_o,
`endif
`ifdef RVA
                                amo_io.rs2_o, amo_io.rs1_o,
`endif
`ifdef RVM
                                mult_io.rs2_o, mult_io.rs1_o,
`endif
                                store_io.rs2_o, store_io.rs1_o, load_io.rs1_o,
                                int_io.rs2_o, int_io.rs1_o};
    BusyTable #(`INT_WAKEUP_PORT, `INT_BUSY_PORT, `INT_PREG_SIZE, 0) int_busy_table(
        .*, 
        .io(int_busy_io.busytable),
        .wakeupBus(int_wakeupBus)
    );
`ifdef RVF
    assign fp_busy_io.dis_en = rename_dis_io.fp_wen & ~{`FETCH_WIDTH{backendCtrl.dis_full}};
    assign fp_busy_io.dis_rd = rename_dis_io.prd;
    assign fp_busy_io.preg = {fdiv_io.rs2_o, fdiv_io.rs1_o,
                              fma_io.rs3_o, fma_io.rs2_o, fma_io.rs1_o,
                              fmisc_io.rs2_o, fmisc_io.rs1_o,
                              store_io.rs2_o};
    BusyTable #(`FP_WAKEUP_PORT, `FP_BUSY_PORT, `FP_PREG_SIZE, 1) fp_busy_table(
        .*,
        .io(fp_busy_io.busytable),
        .wakeupBus(fp_wakeupBus)
    );
`endif
// dequeue
    
`define DEF_TEMPLATE(name, PORT_BASE, PORT_SIZE, RS1V, RS2V) \
    assign dis_``name``_io.en = ``name``_io.en_o; \
    assign dis_``name``_io.data = ``name``_io.data_o; \
    assign ``name``_io.issue_full = dis_``name``_io.full; \
generate \
    for(genvar i=0; i<PORT_SIZE; i++)begin : ``name``_out \
        IssueStatusBundle bundle; \
        logic rs1v, rs2v; \
        if(RS1V)begin \
            assign rs1v = int_busy_io.reg_en[PORT_BASE+i]; \
        end \
        else begin \
            assign rs1v = 0; \
        end \
        if(RS2V)begin \
            assign rs2v = int_busy_io.reg_en[PORT_BASE+PORT_SIZE+i]; \
        end \
        else begin \
            assign rs2v = 0; \
        end \
        assign bundle = {rs1v, rs2v, ``name``_io.status_o[i]}; \
        assign dis_``name``_io.status[i] = bundle; \
    end \
endgenerate
    DispatchDequeue #(
        .PORT_SIZE(`INT_DIS_PORT)
    ) int_dequeue (
        .queue_io(int_io),
        .dis_issue_io(dis_int_io),
        .int_rs1_en(int_busy_io.reg_en[`INT_DIS_PORT-1: 0]),
        .int_rs2_en(int_busy_io.reg_en[`INT_DIS_PORT*2-1: `INT_DIS_PORT]),
        .fp_rs1_en(),
        .fp_rs2_en(),
        .fp_rs3_en()
    );
    localparam LOAD_BASE = `INT_DIS_PORT * 2;
    localparam STORE_BASE = `INT_DIS_PORT * 2 + `LOAD_DIS_PORT;
    DispatchDequeue #(
        .PORT_SIZE(`LOAD_DIS_PORT),
        .RS2I(0)
    ) load_dequeue (
        .queue_io(load_io),
        .dis_issue_io(dis_load_io),
        .int_rs1_en(int_busy_io.reg_en[`LOAD_DIS_PORT+LOAD_BASE-1: LOAD_BASE]),
        .int_rs2_en(),
        .fp_rs1_en(),
        .fp_rs2_en(),
        .fp_rs3_en()
    );
    DispatchDequeue #(
        .PORT_SIZE(`STORE_DIS_PORT)
`ifdef RVF
        ,.RS2F(1)
`endif
    ) store_dequeue (
        .queue_io(store_io),
        .dis_issue_io(dis_store_io),
        .int_rs1_en(int_busy_io.reg_en[`STORE_DIS_PORT+STORE_BASE-1: STORE_BASE]),
        .int_rs2_en(int_busy_io.reg_en[`STORE_DIS_PORT+STORE_BASE +: `STORE_DIS_PORT]),
        .fp_rs1_en(),
`ifdef RVF
        .fp_rs2_en(fp_busy_io.reg_en[`STORE_DIS_PORT-1: 0]),
`else
        .fp_rs2_en(),
`endif
        .fp_rs3_en()
    );


    IssueStatusBundle csr_status;
    CsrIssueBundle csr_issue_bundle;
    assign csr_issue_bundle = csr_io.data_o;
    assign dis_csr_io.en = csr_io.en_o;
    assign dis_csr_io.data = csr_io.data_o;
    assign csr_io.issue_full = dis_csr_io.full;
    assign csr_status.rs1v = 1'b0;
    assign csr_status.rs2v = 1'b0;
    assign csr_status.rs1 = csr_io.rs1_o;
    assign csr_status.rs2 = csr_io.rs2_o;
    assign csr_status.rd = csr_io.status_o[0].rd;
    assign csr_status.robIdx = csr_io.status_o[0].robIdx;
    assign csr_status.we = csr_io.status_o[0].we;
    assign dis_csr_io.status = csr_status;

`ifdef RVM
    localparam MULT_BASE = `INT_DIS_PORT*2+`LOAD_DIS_PORT+`STORE_DIS_PORT * 2;
    DispatchDequeue #(
        .PORT_SIZE(`MULT_DIS_PORT)
    ) mult_dequeue (
        .queue_io(mult_io),
        .dis_issue_io(dis_mult_io),
        .int_rs1_en(int_busy_io.reg_en[MULT_BASE +: `MULT_DIS_PORT]),
        .int_rs2_en(int_busy_io.reg_en[`MULT_DIS_PORT + MULT_BASE +: `MULT_DIS_PORT]),
        .fp_rs1_en(),
        .fp_rs2_en(),
        .fp_rs3_en()
    );
`endif
`ifdef RVA
    localparam AMO_BASE = `INT_DIS_PORT*2+`LOAD_DIS_PORT+`STORE_DIS_PORT * 2
`ifdef RVM
    + `MULT_DIS_PORT * 2
`endif
    ;
    DispatchDequeue #(
        .PORT_SIZE(`AMO_DIS_PORT)
    ) amo_dequeue (
        .queue_io(amo_io),
        .dis_issue_io(dis_amo_io),
        .int_rs1_en(int_busy_io.reg_en[AMO_BASE +: `AMO_DIS_PORT]),
        .int_rs2_en(int_busy_io.reg_en[AMO_BASE + `AMO_DIS_PORT +: `AMO_DIS_PORT]),
        .fp_rs1_en(),
        .fp_rs2_en(),
        .fp_rs3_en()
    );
`endif

`ifdef RVF
    localparam FMISC_INT_BASE = `INT_DIS_PORT*2+`LOAD_DIS_PORT+`STORE_DIS_PORT * 2
`ifdef RVA
    + `AMO_DIS_PORT * 2
`endif
`ifdef RVM
    + `MULT_DIS_PORT * 2
`endif
    ;
    localparam FMISC_FP_BASE = `STORE_DIS_PORT;
    localparam FMA_FP_BASE = `STORE_DIS_PORT + `FMISC_DIS_PORT * 2;
    localparam FDIV_BASE = FMA_FP_BASE + `FMA_SIZE * 3;
    DispatchDequeue #(
        .PORT_SIZE(`FMISC_DIS_PORT),
        .RS1I(1),
        .RS2I(0),
        .RS1F(1),
        .RS2F(1)
    ) fmisc_dequeue (
        .queue_io(fmisc_io),
        .dis_issue_io(dis_fmisc_io),
        .int_rs1_en(int_busy_io.reg_en[FMISC_INT_BASE +: `FMISC_DIS_PORT]),
        .int_rs2_en(),
        .fp_rs1_en(fp_busy_io.reg_en[FMISC_FP_BASE +: `FMISC_DIS_PORT]),
        .fp_rs2_en(fp_busy_io.reg_en[FMISC_FP_BASE + `FMISC_DIS_PORT +: `FMISC_DIS_PORT]),
        .fp_rs3_en()
    );
    DispatchDequeue #(
        .PORT_SIZE(`FMA_DIS_PORT),
        .RS1I(0),
        .RS2I(0),
        .RS1F(1),
        .RS2F(1),
        .RS3F(1)
    ) fma_dequeue (
        .queue_io(fma_io),
        .dis_issue_io(dis_fma_io),
        .int_rs1_en(),
        .int_rs2_en(),
        .fp_rs1_en(fp_busy_io.reg_en[FMA_FP_BASE +: `FMA_SIZE]),
        .fp_rs2_en(fp_busy_io.reg_en[FMA_FP_BASE + `FMA_SIZE +: `FMA_SIZE]),
        .fp_rs3_en(fp_busy_io.reg_en[FMA_FP_BASE + `FMA_SIZE * 2 +: `FMA_SIZE])
    );
    DispatchDequeue #(
        .PORT_SIZE(`FDIV_DIS_PORT),
        .RS1I(0),
        .RS2I(0),
        .RS1F(1),
        .RS2F(1)
    ) fdiv_dequeue (
        .queue_io(fdiv_io),
        .dis_issue_io(dis_fdiv_io),
        .int_rs1_en(),
        .int_rs2_en(),
        .fp_rs1_en(fp_busy_io.reg_en[FDIV_BASE +: `FDIV_SIZE]),
        .fp_rs2_en(fp_busy_io.reg_en[FDIV_BASE + `FDIV_SIZE +: `FDIV_SIZE]),
        .fp_rs3_en()
    );
`endif
endmodule

module DispatchDequeue #(
    parameter PORT_SIZE=1,
    parameter RS1I=1,
    parameter RS2I=1,

    parameter RS1F=0,
    parameter RS2F=0,
    parameter RS3F=0

)(
    DispatchQueueIO.dequeue queue_io,
    DisIssueIO.dis dis_issue_io,
    input logic `N(PORT_SIZE) int_rs1_en,
    input logic `N(PORT_SIZE) int_rs2_en,

    input logic `N(PORT_SIZE) fp_rs1_en,
    input logic `N(PORT_SIZE) fp_rs2_en,
    input logic `N(PORT_SIZE) fp_rs3_en
);
    assign dis_issue_io.en = queue_io.en_o;
    assign dis_issue_io.data = queue_io.data_o;
    assign queue_io.issue_full = dis_issue_io.full;
generate
    for(genvar i=0; i<PORT_SIZE; i++)begin
        IssueStatusBundle bundle;
        logic rs1v, rs2v, rs3v;
        if(RS1I & RS1F) assign rs1v = queue_io.status_o[i].frs1_sel ? fp_rs1_en[i] : int_rs1_en[i];
        else if(RS1F) assign rs1v = fp_rs1_en[i];
        else if(RS1I) assign rs1v = int_rs1_en[i];
        else assign rs1v = 0;

        if(RS2I & RS2F) assign rs2v = queue_io.status_o[i].frs2_sel ? fp_rs2_en[i] : int_rs2_en[i];
        else if(RS2F) assign rs2v = fp_rs2_en[i];
        else if(RS2I) assign rs2v = int_rs2_en[i];
        else assign rs2v = 0;

        if(RS3F) assign rs3v = fp_rs3_en[i];
        else assign rs3v = 0;
        assign bundle = {rs1v, rs2v, rs3v, queue_io.status_o[i]};
        assign dis_issue_io.status[i] = bundle;
    end
endgenerate
endmodule