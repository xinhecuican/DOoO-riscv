`include "../../../defines/defines.svh"

interface LoadQueueIO;
    logic `N(`LOAD_PIPELINE) en;
    logic `N(`LOAD_PIPELINE) miss;
    logic `N(`LOAD_PIPELINE) uncache;
    LoadIssueData `N(`LOAD_PIPELINE) data;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) paddr;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) mask;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) rmask;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) rdata;
    LoadIdx lqIdx;
    ViolationData `N(`STORE_PIPELINE) write_violation;
    ViolationData lq_violation;

    WBData `N(`LOAD_PIPELINE) int_wbData;
`ifdef RVF
    logic `N(`LOAD_PIPELINE) frd_en;
    WBData `N(`LOAD_PIPELINE) fp_wbData;
`endif
    logic `N(`LOAD_PIPELINE) wb_ready;
    logic `N(`LOAD_PIPELINE) uncache_full;


    modport queue(input en, miss, uncache, data, paddr, rdata, rmask, mask, write_violation, wb_ready,
                  output lqIdx, lq_violation, int_wbData, uncache_full
`ifdef RVF
                , output frd_en, fp_wbData
`endif
    );
endinterface

module LoadQueue(
    input logic clk,
    input logic rst,
    LoadQueueIO.queue io,
    LoadUnitIO.queue load_io,
    CommitBus.mem commitBus,
    input BackendCtrl backendCtrl,
    DCacheLoadIO.queue rio,
    AxiIO.masterr laxi_io,
    input logic fence_valid
);
    localparam BANK_SIZE = `LOAD_QUEUE_SIZE / `LOAD_PIPELINE;
    logic `N(`LOAD_QUEUE_WIDTH) head, tail, head_n, tail_n, redirect_tail;
    logic hdir, tdir, hdir_n;
    logic `ARRAY(`LOAD_PIPELINE, BANK_SIZE) eqIdx;
    logic `ARRAY(`COMMIT_WIDTH, `LOAD_QUEUE_WIDTH) commitIdx;
    logic redirect_next;
    logic `ARRAY(`LOAD_PIPELINE, `ROB_WIDTH) dis_rob_idx;
    logic `N(`LOAD_PIPELINE) full;

    logic `ARRAY(`COMMIT_WIDTH, `LOAD_QUEUE_WIDTH - $clog2(`LOAD_PIPELINE)) bank_commit_idx;
    logic `N(`LOAD_PIPELINE) bank_tail_valid, bank_tail_full;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH - $clog2(`LOAD_PIPELINE)) bank_tail_idx;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) bank_tail;
    logic bank_tail_equal, bank_tail_dir;
    logic `N(`LOAD_PIPELINE) uncache_arvalid;
    logic `ARRAY(`LOAD_PIPELINE, 2) uncache_arsize;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) uncache_addr;
    logic `N(`STORE_PIPELINE) overflow;
    logic `ARRAY(`STORE_PIPELINE, `LOAD_QUEUE_SIZE) mask_vec_all;
    logic `N(`LOAD_PIPELINE) vio_en;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) vio_idx;
    LoadVioData `N(`LOAD_PIPELINE) vio_datas;
    RobIdx `N(`LOAD_PIPELINE) vio_robIdx;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign eqIdx[i] = io.data[i].lqIdx.idx[`LOAD_QUEUE_WIDTH-1: $clog2(`LOAD_PIPELINE)];
        assign full[i] = (load_io.dis_lq_idx[i].idx == head & (load_io.dis_lq_idx[i] ^ hdir));
    end
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitIdx[i] = head + i;
    end
    for(genvar i=0; i<`LOAD_DIS_PORT; i++)begin
        assign dis_rob_idx[i] = load_io.dis_rob_idx[i].idx;
    end
endgenerate

generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign bank_commit_idx[i] = commitIdx[i][`LOAD_QUEUE_WIDTH-1: $clog2(`LOAD_PIPELINE)];
    end
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin : load_bank
        logic `N(`COMMIT_WIDTH) commit_en;
        for(genvar j=0; j<`COMMIT_WIDTH; j++)begin
            assign commit_en[j] = (j < commitBus.loadNum) & commitIdx[j][$clog2(`LOAD_PIPELINE)-1: 0] == i;
        end
        assign bank_tail[i] = {bank_tail_idx[i], i[$clog2(`LOAD_PIPELINE)-1: 0]};
        logic `ARRAY(`STORE_PIPELINE, BANK_SIZE) mask_vec;
        for(genvar j=0; j<`STORE_PIPELINE; j++)begin
            for(genvar k=0; k<BANK_SIZE; k++)begin
                assign mask_vec[j][k] = mask_vec_all[j][(k << $clog2(`LOAD_PIPELINE)) + i];
            end
        end
        logic `N($clog2(BANK_SIZE)) bank_idx;
        LoadQueueBank #(
            .BANK_SIZE(BANK_SIZE)
        ) bank (
            .clk,
            .rst,
            .dis_en(load_io.dis_en[i]),
            .dis_stall(load_io.dis_stall),
            .dis_lq_idx(load_io.dis_lq_idx[i].idx[`LOAD_QUEUE_WIDTH-1: $clog2(`LOAD_PIPELINE)]),
            .dis_rob_idx(load_io.dis_rob_idx[i]),
            .en(io.en[i]),
            .eqIdx(eqIdx[i]),
            .data(io.data[i]),
            .miss_i(io.miss[i]),
            .uncache_i(io.uncache[i]),
            .addr(io.paddr[i]),
            .rdata(io.rdata[i]),
            .mask(io.mask[i]),
            .rmask(io.rmask[i]),
            .cache_en(rio.lq_en[i]),
            .cache_lqIdx(rio.lqIdx_o[i][`LOAD_QUEUE_WIDTH-1: $clog2(`LOAD_PIPELINE)]),
            .cache_data(rio.lqData[i]),
            .redirect(backendCtrl.redirect),
            .redirectIdx(backendCtrl.redirectIdx),
            .commit_en(commit_en),
            .fence_valid(fence_valid),
            .commit_idx(bank_commit_idx),
            .commitIdx(commitBus.robIdx),
            .wb_ready(io.wb_ready[i]),
            .int_wbData(io.int_wbData[i]),
`ifdef RVF
            .fp_wbData(io.fp_wbData[i]),
`endif
            .tail_valid(bank_tail_valid[i]),
            .tail_full(bank_tail_full[i]),
            .tail(bank_tail_idx[i]),
            .uncache_arvalid(uncache_arvalid[i]),
            .uncache_arsize(uncache_arsize[i]),
            .uncache_addr(uncache_addr[i]),
            .uncache_arready(laxi_io.ar_ready),
            .uncache_rdata(laxi_io.r_data),
            .uncache_rvalid(laxi_io.r_valid),
            .uncache_full(io.uncache_full[i]),
            .write_violation(io.write_violation),
            .overflow,
            .mask_vec,
            .vio_en(vio_en[i]),
            .vio_robIdx(vio_robIdx[i]),
            .vio_data_o(vio_datas[i])
        );
        assign vio_idx[i] = {vio_datas[i].idx, i[0]};
    end
endgenerate

// redirect
    `UNPARAM(LOAD_PIPELINE, 2, "load queue bank redirect")
    assign bank_tail_equal = bank_tail_idx[0] == bank_tail_idx[1];
    always_comb begin
        if(&bank_tail_full)begin
            redirect_tail = tail;
        end
        else if(~(|bank_tail_valid))begin
            redirect_tail = head_n;
        end
        else if(~bank_tail_valid[0])begin
            redirect_tail = bank_tail[1] - 1;
        end
        else if(~bank_tail_valid[1])begin
            redirect_tail = bank_tail[0] - 1;
        end
        else if(bank_tail_full[0] | ~bank_tail_full[1] & bank_tail_valid[1] & ~bank_tail_equal)begin
            redirect_tail = bank_tail[1];
        end
        else begin
            redirect_tail = bank_tail[0];
        end
    end
    assign bank_tail_dir = &bank_tail_full ? tdir : 
                           redirect_tail < head_n ? ~hdir_n : hdir_n;

    assign io.lqIdx.idx = tail;
    assign io.lqIdx.dir = tdir;
    assign load_io.full = (|full) | redirect_next;
    assign head_n = head + commitBus.loadNum;
    assign tail_n = tail + load_io.eqNum;
    assign hdir_n = head[`LOAD_QUEUE_WIDTH-1] & ~head_n[`LOAD_QUEUE_WIDTH-1] ? ~hdir : hdir;
    
    always_ff @(posedge clk)begin
        redirect_next <= backendCtrl.redirect;
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            hdir <= 0;
            tdir <= 0;
        end
        else begin
            head <= head_n;
            hdir <= hdir_n;
            if(redirect_next)begin
                tail <= redirect_tail;
                tdir <= bank_tail_dir;
            end
            else if(~load_io.dis_stall)begin
                tail <= tail_n;
                tdir <= tail[`LOAD_QUEUE_WIDTH-1] & ~tail_n[`LOAD_QUEUE_WIDTH-1] ? ~tdir : tdir;
            end

        end
    end

// uncache
    assign laxi_io.ar_id = 0;
    always_comb begin
        if(uncache_arvalid[1])begin
            laxi_io.ar_addr = uncache_addr[1];
            laxi_io.ar_size = uncache_arsize[1];
        end
        else begin
            laxi_io.ar_addr = uncache_addr[0];
            laxi_io.ar_size = uncache_arsize[0];
        end
    end
    assign laxi_io.ar_len = 0;
    assign laxi_io.ar_burst = 0;
    assign laxi_io.ar_lock = 0;
    assign laxi_io.ar_cache = 0;
    assign laxi_io.ar_prot = 0;
    assign laxi_io.ar_qos = 0;
    assign laxi_io.ar_region = 0;
    assign laxi_io.ar_user = 0;

    assign laxi_io.ar_valid = |uncache_arvalid;
    assign laxi_io.r_ready = 1'b1;

// violation detect
    logic lq_violation_en;
    logic `N(`LOAD_QUEUE_WIDTH) lq_violation_idx;
    logic lq_vio_dir;
    RobIdx lq_vio_robIdx;
    FsqIdxInfo lq_vio_fsqInfo;
    logic `N(`LOAD_QUEUE_SIZE) head_mask;
    logic vio_bigger;
    
    MaskGen #(`LOAD_QUEUE_SIZE) decoder_head (head, head_mask);
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        LoopCompare #(`LOAD_QUEUE_WIDTH) cmp_overflow({tail, tdir}, io.write_violation[i].lqIdx, overflow[i]);
        logic `N(`LOAD_QUEUE_SIZE) store_mask;
        logic span;
        assign span = hdir ^ io.write_violation[i].lqIdx.dir;
        MaskGen #(`LOAD_QUEUE_SIZE) maskgen_store (io.write_violation[i].lqIdx.idx, store_mask);
        assign mask_vec_all[i] = ~({`LOAD_QUEUE_SIZE{span}} ^ (head_mask ^ store_mask));
    end
endgenerate
    `UNPARAM(STORE_PIPELINE, 2, "store violation")
    LoopCompare #(`ROB_WIDTH) cmp_vio_robIdx (vio_robIdx[1], vio_robIdx[0], vio_bigger);
    always_ff @(posedge clk)begin
        lq_violation_en <= |vio_en;
        lq_violation_idx <= vio_en[1] & vio_bigger | ~vio_en[0] ? vio_idx[1] : vio_idx[0];
        lq_vio_dir <= vio_en[1] & vio_bigger | ~vio_en[0] ? vio_datas[1].dir : vio_datas[0].dir;
        lq_vio_robIdx <= vio_en[1] & vio_bigger | ~vio_en[0] ? vio_robIdx[1] : vio_robIdx[0];
        lq_vio_fsqInfo <= vio_en[1] & vio_bigger | ~vio_en[0] ? vio_datas[1].fsqInfo : vio_datas[0].fsqInfo;
    end
    assign io.lq_violation.en = lq_violation_en;
    assign io.lq_violation.addr = 0;
    assign io.lq_violation.mask = 0;
    assign io.lq_violation.lqIdx.idx = lq_violation_idx;
    assign io.lq_violation.lqIdx.dir = lq_vio_dir;
    assign io.lq_violation.robIdx = lq_vio_robIdx;
    assign io.lq_violation.fsqInfo = lq_vio_fsqInfo;
endmodule

module LoadQueueBank #(
    parameter BANK_SIZE = 16,
    parameter BANK_WIDTH = $clog2(BANK_SIZE)
)(
    input logic clk,
    input logic rst,

    input logic dis_en,
    input logic dis_stall,
    input logic `N(BANK_WIDTH) dis_lq_idx,
    input RobIdx dis_rob_idx,

    input logic en,
    input logic `N(BANK_WIDTH) eqIdx,
    input LoadIssueData data,
    input logic miss_i,
    input logic uncache_i,
    input logic `N(`PADDR_SIZE) addr,
    input logic `N(`DCACHE_BITS) rdata,
    input logic `N(`DCACHE_BYTE) mask,
    input logic `N(`DCACHE_BYTE) rmask,

    input logic cache_en,
    input logic `N(BANK_WIDTH) cache_lqIdx,
    input logic `N(`DCACHE_BITS) cache_data,

    input logic redirect,
    input RobIdx redirectIdx,
    input logic fence_valid,

    input logic `N(`COMMIT_WIDTH) commit_en,
    input logic `ARRAY(`COMMIT_WIDTH, BANK_WIDTH) commit_idx,
    input RobIdx commitIdx,

    input logic wb_ready,
    output WBData int_wbData,
`ifdef RVF
    output WBData fp_wbData,
`endif

    output logic tail_valid,
    output logic tail_full,
    output logic `N(BANK_WIDTH) tail,

    output logic uncache_arvalid,
    output logic `N(2) uncache_arsize,
    output logic `N(`PADDR_SIZE) uncache_addr,
    input logic uncache_arready,
    input logic `N(`XLEN) uncache_rdata,
    input logic uncache_rvalid,
    output logic uncache_full,

    input ViolationData `N(`STORE_PIPELINE) write_violation,
    input logic `N(`STORE_PIPELINE) overflow,
    input logic `ARRAY(`STORE_PIPELINE, BANK_SIZE) mask_vec,
    output logic vio_en,
    output RobIdx vio_robIdx,
    output LoadVioData vio_data_o
);
    logic `N(BANK_SIZE) valid, miss, addrValid, dataValid, writeback, uncache;
    logic `N(BANK_SIZE) waiting_wb;
    logic `N(`DCACHE_BITS) load_data `N(BANK_SIZE);
    RobIdx redirect_robIdxs `N(BANK_SIZE);
    logic `N(BANK_WIDTH) head;
    logic `N(`LOAD_UNCACHE_WIDTH) uncache_idx `N(BANK_SIZE);

    logic `N(BANK_SIZE) dis_lq_idx_dec, dis_lq_valid;
    LoadQueueData writeData, wb_queue_data;
    LoadMaskData mask_data;
    logic `N(`DCACHE_BITS) refillData, expand_mask, refillDataCombine, refillDataShift;
    logic `N(`DCACHE_BYTE) refillMask;
    logic wb_valid, wb_valid_n;
    logic `N(`XLEN) wb_data;
    logic `N(BANK_WIDTH) wbIdx_pre, wbIdx;
    logic `ARRAY(`COMMIT_WIDTH, BANK_SIZE) commit_invalid;
    logic `N(BANK_SIZE) commit_invalid_combine;
    logic `N($clog2(`COMMIT_WIDTH)) commitNum;
    logic `N(`LOAD_UNCACHE_WIDTH) uncache_idx_o;
    logic `N(`XLEN) uncache_wb_data;
    logic uncache_wb_valid, uncache_wb_valid_n;

    logic redirect_n;
    logic `N(BANK_SIZE) bigger, walk_en, validStart, validEnd;
    logic `N(BANK_WIDTH) validSelect1, validSelect2, walk_tail, valid_select, valid_select_n;

    Decoder #(BANK_SIZE) decoder_lq_idx (dis_lq_idx, dis_lq_idx_dec);
    assign dis_lq_valid = {BANK_SIZE{dis_en & ~dis_stall}} & dis_lq_idx_dec;

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            valid <= 0;
            miss <= 0;
            addrValid <= 0;
            dataValid <= 0;
            writeback <= 0;
            uncache <= 0;
            head <= 0;
            uncache_idx <= '{default: 0};
        end
        else begin
            head <= head + commitNum;
            for(int i=0; i<BANK_SIZE; i++)begin
                valid[i] <= (valid[i] | dis_lq_valid[i]) &
                            ~(redirect & ~bigger[i]) &
                            ~commit_invalid_combine[i];
            end
            if(dis_en & ~dis_stall)begin
                addrValid[dis_lq_idx] <= 1'b0;
                dataValid[dis_lq_idx] <= 1'b0;
                uncache[dis_lq_idx] <= 1'b0;
            end
            if(en)begin
                addrValid[eqIdx] <= 1'b1;
                miss[eqIdx] <= miss_i;
                dataValid[eqIdx] <= ~miss_i & ~uncache_i;
                writeback[eqIdx] <= ~miss_i & ~uncache_i;
                uncache[eqIdx] <= uncache_i;
                uncache_idx[eqIdx] <= uncache_idx_o;
            end
            if(wb_valid & wb_ready)begin
                writeback[wbIdx] <= 1'b1;
            end
            if(cache_en)begin
                dataValid[cache_lqIdx] <= 1'b1;
            end
        end
    end


    assign waiting_wb = valid & miss & dataValid & ~writeback;
    PEncoder #(BANK_SIZE) pencoder_wb_idx (waiting_wb, wbIdx_pre);
    assign wbIdx = uncache_wb_valid ? head : wbIdx_pre;
    assign writeData.we = data.we;
`ifdef RVF
    assign writeData.frd_en = data.frd_en;
`endif
    assign writeData.rd = data.rd;
    assign writeData.robIdx = data.robIdx;
    MPRAM #(
        .WIDTH($bits(LoadQueueData)),
        .DEPTH(BANK_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) load_queue_data (
        .clk,
        .rst,
        .en(1'b1),
        .raddr(wbIdx),
        .rdata(wb_queue_data),
        .we(en),
        .waddr(eqIdx),
        .wdata(writeData),
        .ready()
    );

// wb
    assign refillMask = mask_data.mask;
    MaskExpand #(`DCACHE_BYTE) expand_refill_mask (refillMask, expand_mask);
    assign refillDataCombine = refillData & expand_mask | cache_data & ~expand_mask;
    RDataGen data_gen (mask_data.uext, mask_data.size, mask_data.offset, refillDataCombine, refillDataShift);
    MPRAM #(
        .WIDTH(`DCACHE_BITS + $bits(LoadMaskData)),
        .DEPTH(BANK_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .READ_LATENCY(0)
    ) load_data_mask_ram (
        .clk,
        .rst,
        .en(cache_en),
        .raddr(cache_lqIdx),
        .rdata({mask_data, refillData}),
        .we(en),
        .waddr(eqIdx),
        .wdata({data.uext, data.size, addr[`DCACHE_BYTE_WIDTH-1: 0], rmask, rdata}),
        .ready()
    );
    MPRAM #(
        .WIDTH(`DCACHE_BITS),
        .DEPTH(BANK_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) load_wb_data (
        .clk,
        .rst,
        .en(1'b1),
        .raddr(wbIdx),
        .rdata(wb_data),
        .we(cache_en),
        .waddr(cache_lqIdx),
        .wdata(refillDataShift),
        .ready()
    );

    assign wb_valid = ((|waiting_wb) | uncache_wb_valid) & ~redirect & ~redirect_n;
    always_ff @(posedge clk)begin
        wb_valid_n <= wb_valid & wb_ready;
        uncache_wb_valid_n <= uncache_wb_valid;
    end
`ifdef RVF
    assign fp_wbData.en = wb_valid_n & wb_queue_data.frd_en;
    assign fp_wbData.we = 1'b1;
    assign fp_wbData.robIdx = wb_queue_data.robIdx;
    assign fp_wbData.rd = wb_queue_data.rd;
    assign fp_wbData.res = uncache_wb_valid_n ? uncache_wb_data : wb_data;
    assign fp_wbData.exccode = `EXC_NONE;
    assign fp_wbData.irq_enable = ~uncache_wb_valid_n;
`endif
    assign int_wbData.en = wb_valid_n
`ifdef RVF
                            & ~wb_queue_data.frd_en
`endif
    ;

    assign int_wbData.we = wb_queue_data.we;
    assign int_wbData.robIdx = wb_queue_data.robIdx;
    assign int_wbData.rd = wb_queue_data.rd;
    assign int_wbData.res = uncache_wb_valid_n ? uncache_wb_data : wb_data;
    assign int_wbData.exccode = `EXC_NONE;
    assign int_wbData.irq_enable = ~uncache_wb_valid_n;

// redirect
    always_ff @(posedge clk)begin
        redirect_n <= redirect;
        if(dis_en & ~dis_stall)begin
            redirect_robIdxs[dis_lq_idx] <= dis_rob_idx;
        end
    end
    assign walk_en = valid & bigger;
generate
    for(genvar i=0; i<BANK_SIZE; i++)begin
        LoopCompare #(`ROB_WIDTH) cmp_bigger (redirect_robIdxs[i], redirectIdx, bigger[i]);
        logic `N(`LOAD_QUEUE_WIDTH) i_n, i_p;
        assign i_n = i + 1;
        assign i_p = i - 1;
        assign validStart[i] = walk_en[i] & ~walk_en[i_n]; // valid[i] == 1 && valid[i + 1] == 0
        assign validEnd[i] = walk_en[i] & ~walk_en[i_p];
    end
endgenerate
    Encoder #(BANK_SIZE) encoder_valid_start (validStart, validSelect1);
    Encoder #(BANK_SIZE) encoder_valid_end (validEnd, validSelect2);
    assign valid_select = validSelect1 == head ? validSelect2 : validSelect1;
    always_ff @(posedge clk)begin
        tail_valid <= |walk_en;
        tail_full <= &walk_en;
        tail <= valid_select + 1;
    end

// uncache
    `CONSTRAINT(DCACHE_BITS, `XLEN, "mix use two defines in many place")
    LoadUncacheBuffer uncache_buffer (
        .clk,
        .rst,
        .en(en & uncache_i),
        .redirect,
        .redirectIdx,
        .data,
        .uncache_valid(valid[head] & addrValid[head] & uncache[head]),
        .wb_en(wb_valid & wb_ready),
        .commit_valid(|commit_en),
        .commitIdx,
        .uncache_idx_i(uncache_idx[head]),
        .addr,
        .mask,
        .uncache_idx_o,
        .uncache_wb_valid,
        .uncache_wb_data,
        .uncache_arvalid,
        .uncache_arsize,
        .uncache_addr,
        .uncache_arready,
        .uncache_rdata,
        .uncache_rvalid,
        .fence_valid,
        .full(uncache_full)
    );

// commit
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        logic `N(BANK_SIZE) commit_idx_dec;
        Decoder #(BANK_SIZE) decoder_commit_idx (commit_idx[i], commit_idx_dec);
        assign commit_invalid[i] = {BANK_SIZE{commit_en[i]}} & commit_idx_dec; 
    end
    ParallelOR #(BANK_SIZE, `COMMIT_WIDTH) or_commit_invalid (commit_invalid, commit_invalid_combine);
    ParallelAdder #(1, `COMMIT_WIDTH) adder_commit_en (commit_en, commitNum);
endgenerate

// violation
    logic `ARRAY(`STORE_PIPELINE, BANK_SIZE) cmp_vec, valid_vec, violation_vec;
    logic `N(BANK_SIZE) vio_vec, vio_vec_n, vio_vec_redirect;

    RobIdx `N(BANK_SIZE) vio_robIdxs;

    LoadVioData `N(BANK_SIZE) vio_datas;
    logic `N(`PADDR_SIZE+`DCACHE_BYTE-`DCACHE_BYTE_WIDTH) addr_mask `N(BANK_SIZE);

    always_ff @(posedge clk)begin
        if(en)begin
            vio_robIdxs[eqIdx] <= data.robIdx;
            vio_datas[eqIdx] <= {data.lqIdx.dir, 
            eqIdx, data.fsqInfo};
            addr_mask[eqIdx] <= {addr[`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH], mask};
        end
    end

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<BANK_SIZE; j++)begin
            assign cmp_vec[i][j] = write_violation[i].en &
                    (write_violation[i].addr[`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH] ==
                    addr_mask[j][`PADDR_SIZE+`DCACHE_BYTE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BYTE]) &
                    (|(write_violation[i].mask & addr_mask[j][`DCACHE_BYTE-1: 0]));
            assign valid_vec[i][j] = ~overflow[i] & valid[j] & addrValid[j] & (~redirect | bigger[j]); 
        end
    end
endgenerate
    assign violation_vec = cmp_vec & mask_vec & valid_vec;
    ParallelOR #(BANK_SIZE, `STORE_PIPELINE) or_violation_vec(violation_vec, vio_vec);
    always_ff @(posedge clk)begin
        vio_vec_n <= vio_vec;
    end
generate
    for(genvar i=0; i<BANK_SIZE; i++)begin
        assign vio_vec_redirect[i] = vio_vec_n[i] & (~redirect | bigger[i]);
    end
endgenerate

    LoopOldestSelect #(BANK_SIZE, `ROB_WIDTH, $bits(LoadVioData)) select_vio (
        .en(vio_vec_redirect),
        .cmp(vio_robIdxs),
        .data_i(vio_datas),
        .en_o(vio_en),
        .cmp_o(vio_robIdx),
        .data_o(vio_data_o)
    );
endmodule

module LoadUncacheBuffer(
    input logic clk,
    input logic rst,
    input logic en,
    input logic redirect,
    input RobIdx redirectIdx,
    input RobIdx commitIdx,
    input LoadIssueData data,
    input logic uncache_valid,
    input logic wb_en,
    input logic commit_valid,
    input logic fence_valid,
    input logic `N(`LOAD_UNCACHE_WIDTH) uncache_idx_i,
    input logic `N(`PADDR_SIZE) addr,
    input logic `N(`DCACHE_BYTE) mask,
    output logic `N(`LOAD_UNCACHE_WIDTH) uncache_idx_o,
    output logic uncache_wb_valid,
    output logic `N(`DCACHE_BITS) uncache_wb_data,
    output logic uncache_arvalid,
    output logic `N(2) uncache_arsize,
    output logic `N(`PADDR_SIZE) uncache_addr,
    input logic uncache_arready,
    input logic `N(`XLEN) uncache_rdata,
    input logic uncache_rvalid,
    output logic full
);
    typedef struct packed {
        logic uext;
        logic `N(2) size;
        logic `N(`PADDR_SIZE) addr;
    } UncacheData;
    typedef enum { IDLE, LOOKUP, WRITEBACK, RETIRE } UncacheState;
    UncacheState uncacheState;
    logic `N(`LOAD_UNCACHE_SIZE) valid, free_en, busy_en;
    RobIdx redirect_robIdxs `N(`LOAD_UNCACHE_SIZE);
    RobIdx uncache_robIdx;
    logic `N(`LOAD_UNCACHE_WIDTH) freeIdx, busyIdx;
    UncacheData data_o, data_i;
    logic `N(`LOAD_UNCACHE_SIZE) bigger;
    logic `N(`XLEN) uncache_data;
    logic uncache_req;
    logic uncache_bigger;
    logic input_eq, input_en;
    logic full_pre;
    logic uncache_uext;
    logic input_cache;

    PSelector #(`LOAD_UNCACHE_SIZE) selector_free_en(~valid, free_en);
    Encoder #(`LOAD_UNCACHE_SIZE) encoder_free_idx(free_en, freeIdx);
    Decoder #(`LOAD_UNCACHE_SIZE) decoder_busy_idx(busyIdx, busy_en);
    assign uncache_idx_o = freeIdx;
    assign data_i.uext = data.uext;
    assign data_i.size = data.size;
    assign data_i.addr = addr;
    MPRAM #(
        .WIDTH($bits(UncacheData)),
        .DEPTH(`LOAD_UNCACHE_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1),
        .READ_LATENCY(0)
    ) data_ram (
        .clk,
        .rst,
        .en(1'b1),
        .raddr(uncache_idx_i),
        .rdata(data_o),
        .we(en & ~full_pre),
        .waddr(freeIdx),
        .wdata(data_i),
        .ready()
    );
    RDataGen uncache_data_gen (uncache_uext, uncache_arsize, 0, uncache_rdata, uncache_data);
    assign uncache_arvalid = uncache_req;
    assign input_eq = data.robIdx == commitIdx;
    assign input_en = input_eq & en;
    assign full_pre = &valid;
    assign full = full_pre & ~input_eq;
    assign uncache_wb_valid = uncacheState == WRITEBACK;

    always_ff @(posedge clk)begin
        if(en & ~full_pre)begin
            redirect_robIdxs[freeIdx] <= data.robIdx;
        end
    end
    LoopCompare #(`ROB_WIDTH) cmp_uncache_bigger (redirectIdx, uncache_robIdx, uncache_bigger);

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            uncacheState <= IDLE;
            uncache_req <= 0;
            uncache_wb_data <= 0;
            busyIdx <= 0;
            uncache_arsize <= 0;
            input_cache <= 0;
            uncache_addr <= 0;
            uncache_robIdx <= 0;
        end
        else if(redirect & uncache_bigger & (uncacheState != IDLE))begin
            uncacheState <= IDLE;
        end
        else begin
            case(uncacheState)
            IDLE:begin
                if(uncache_valid &
                (commitIdx == redirect_robIdxs[uncache_idx_i]) & ~fence_valid | input_en)begin
                    uncacheState <= LOOKUP;
                    uncache_req <= 1'b1;
                    busyIdx <= uncache_idx_i;
                    uncache_arsize <= input_en ? data.size : data_o.size;
                    uncache_addr <= input_en ? addr : data_o.addr;
                    uncache_uext <= input_en ? data.uext : data_o.uext;
                    uncache_robIdx <= input_en ? data.robIdx : redirect_robIdxs[uncache_idx_i];
                    input_cache <= input_en;
                end
            end
            LOOKUP:begin
                if(uncache_req & uncache_arready)begin
                    uncache_req <= 1'b0;
                end
                if(uncache_rvalid)begin
                    uncacheState <= WRITEBACK;
                    uncache_wb_data <= uncache_data;
                end
            end
            WRITEBACK:begin
                if(wb_en)begin
                    uncacheState <= RETIRE;
                end
            end
            RETIRE:begin
                if(commit_valid)begin
                    uncacheState <= IDLE;
                end
            end
            endcase
        end
    end


generate
    for(genvar i=0; i<`LOAD_UNCACHE_SIZE; i++)begin
        LoopCompare #(`ROB_WIDTH) cmp_bigger (redirect_robIdxs[i], redirectIdx, bigger[i]);
    end
endgenerate
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            valid <= 0;
        end
        else begin
            for(int i=0; i<`LOAD_UNCACHE_SIZE; i++)begin
                valid[i] <= (valid[i] | en & free_en[i]) &
                            ~(redirect & valid[i] & ~bigger[i]) &
                            ~(commit_valid & (uncacheState == RETIRE) & ~input_cache & busy_en[i]);
            end
        end
    end
endmodule