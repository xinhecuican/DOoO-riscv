`include "../../../defines/defines.svh"

interface StoreQueueIO;
    logic `N(`STORE_PIPELINE) en;
    logic `N(`STORE_PIPELINE) uncache;
    StoreIssueData `N(`STORE_PIPELINE) data;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE) paddr;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) mask;
    StoreIdx sqIdx;
    RobIdx wb_robIdx;
    logic wb_req;
    logic wb_valid;
`ifdef FEAT_MEMPRED
    SSITEntry wb_ssitEntry;
`endif

    modport queue(input en, uncache, data, paddr, mask, output sqIdx, wb_req, wb_valid, wb_robIdx
`ifdef FEAT_MEMPRED
    , wb_ssitEntry
`endif
    );
endinterface

module StoreQueue(
    input logic clk,
    input logic rst,
`ifdef RVF
    input logic `ARRAY(`STORE_PIPELINE*2, `XLEN) store_data,
`else
    input logic `ARRAY(`STORE_PIPELINE, `XLEN) store_data,
`endif
    StoreQueueIO.queue io,
    StoreUnitIO.queue issue_queue_io,
    StoreCommitIO.queue queue_commit_io,
    LoadForwardIO.queue loadFwd,
    CommitBus.mem commitBus,
    input BackendCtrl backendCtrl,
    CacheBus.masterw saxi_io,
    input logic fence_valid,
    output logic commit_empty,
    output logic `N(`LOAD_PIPELINE) fwd_data_invalid
);
    logic `N(`STORE_QUEUE_WIDTH) head, tail, head_n, tail_n, commitHead, storeHead, storeHead_n, commitHead_n;
    logic hdir, tdir, hdir_n, chdir;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_WIDTH) addr_eqIdx, data_eqIdx;
    logic `N($clog2(`STORE_DIS_PORT)+1) disNum;
    logic `N($clog2(`STORE_PIPELINE)+1) commitNum, commitNum_n;
    logic `ARRAY(`STORE_DIS_PORT, `STORE_QUEUE_WIDTH) disWIdx;
    logic `ARRAY(`STORE_DIS_PORT, `STORE_QUEUE_SIZE) disWIdx_dec, dis_wvalid;
    logic `N(`STORE_QUEUE_SIZE) dis_wvalid_combine;
    logic `ARRAY(`COMMIT_WIDTH, `STORE_QUEUE_WIDTH) commitIdx;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_WIDTH) headCommitIdx;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_SIZE) headCommit_dec, headCommitValid;
    logic `N(`STORE_QUEUE_SIZE) commitValid_combine;

    StoreIdx redirectIdx;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_WIDTH) redirectRobIdx;
    StoreIdx `N(`STORE_PIPELINE) redirectSqIdx;
    logic `N(`STORE_QUEUE_SIZE) head_n_mask, redirect_mask;
    logic `N(`STORE_QUEUE_SIZE) bigger, walk_en, validStart, validEnd;
    logic `N(`STORE_QUEUE_WIDTH) validSelect1, validSelect2, walk_tail, valid_select, valid_select_n;
    logic walk_valid, walk_dir;
    logic walk_full;
    logic `ARRAY(`STORE_PIPELINE, `XLEN) storeData;
    logic `N(`STORE_PIPELINE) full;
    logic `N(`STORE_PIPELINE) store_commit_en_n;

    typedef enum { IDLE, LOOKUP, WRITEBACK, RETIRE } UncacheState;
    UncacheState uncacheState;
    logic `N(`PADDR_SIZE) uncache_addr;
    logic `N(`DCACHE_BYTE_WIDTH+1) uncache_size, uncache_size_pre;
    logic `N(`DCACHE_BYTE_WIDTH) uncache_offset;
    logic `N(`DCACHE_BITS) uncache_data, uncache_wb_data;
    logic `N(`STORE_QUEUE_WIDTH) uncache_head;
    logic `N(`DCACHE_BYTE) uncache_strb;
    logic uncache_req, uncache_wreq;
    RobIdx uncache_robIdx;
`ifdef FEAT_MEMPRED
    SSITEntry `N(`STORE_QUEUE_SIZE) ssitEntrys;
    SSITEntry uncache_ssitEntry;
`endif

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign addr_eqIdx[i] = io.data[i].sqIdx.idx;
        assign data_eqIdx[i] = issue_queue_io.data_sqIdx[i].idx;
        assign headCommitIdx[i] = head + i;
        Decoder #(`STORE_QUEUE_SIZE) decoder_head_commit (headCommitIdx[i], headCommit_dec[i]);
        assign headCommitValid[i] = {`STORE_QUEUE_SIZE{store_commit_en_n[i] & ~queue_commit_io.conflict}} & headCommit_dec[i];
        logic `N(`XLEN) reg_data;
`ifdef RVF
        assign reg_data = issue_queue_io.data_fp_sel[i] ? store_data[`STORE_PIPELINE+i] : store_data[i];
`else
        assign reg_data = store_data[i];
`endif
        StoreDataGen gen_store_data(issue_queue_io.data_size[i], reg_data, storeData[i]);
    end
    for(genvar i=0; i<`STORE_DIS_PORT; i++)begin
        assign disWIdx[i] = tail + i;
        Decoder #(`STORE_QUEUE_SIZE) decoder_dis_widx (disWIdx[i], disWIdx_dec[i]);
        assign dis_wvalid[i] = {`STORE_QUEUE_SIZE{issue_queue_io.dis_en[i] & ~issue_queue_io.dis_stall}} & disWIdx_dec[i];
        assign full[i] = issue_queue_io.dis_en[i] & ((issue_queue_io.dis_sq_idx[i].idx == head) & (issue_queue_io.dis_sq_idx[i].dir ^ hdir));
    end
    ParallelOR #(`STORE_QUEUE_SIZE, `STORE_DIS_PORT) or_wvalid (dis_wvalid, dis_wvalid_combine);
    ParallelOR #(`STORE_QUEUE_SIZE, `STORE_PIPELINE) or_commit (headCommitValid, commitValid_combine);
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitIdx[i] = commitHead + i;
    end
endgenerate

    ParallelAdder #(1, `STORE_DIS_PORT) adder_dis_num (issue_queue_io.dis_en, disNum);
    ParallelAdder #(1, `STORE_PIPELINE) addr_commit_num (queue_commit_io.en, commitNum);
    assign io.sqIdx.idx = tail;
    assign io.sqIdx.dir = tdir;
    assign issue_queue_io.full = (|full) | backendCtrl.redirect;
    assign head_n = queue_commit_io.conflict ? head : head + commitNum_n;
    assign storeHead_n = queue_commit_io.conflict ? storeHead : storeHead + commitNum;
    assign commitHead_n = commitHead + commitBus.storeNum;
    assign tail_n = tail + disNum;
    assign hdir_n = head[`STORE_QUEUE_WIDTH-1] & ~head_n[`STORE_QUEUE_WIDTH-1] ? ~hdir : hdir;
    assign commit_empty = {hdir, head} == {chdir, commitHead};
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            storeHead <= 0;
            commitHead <= 0;
            hdir <= 0;
            tdir <= 0;
            chdir <= 0;
        end
        else begin
            head <= head_n;
            storeHead <= storeHead_n;
            hdir <= hdir_n;
            if(backendCtrl.redirect)begin
                tail <= walk_valid ? walk_tail: head_n;
                tdir <= walk_valid ? walk_dir : hdir_n;
            end
            else if(~issue_queue_io.dis_stall)begin
                tail <= tail_n;
                tdir <= tail[`STORE_QUEUE_WIDTH-1] & ~tail_n[`STORE_QUEUE_WIDTH-1] ? ~tdir : tdir;
            end

            commitHead <= commitHead + commitBus.storeNum;
            chdir <= commitHead[`STORE_QUEUE_WIDTH-1] & ~commitHead_n[`STORE_QUEUE_WIDTH-1] ? ~chdir : chdir;
        end
    end

    logic `N(`STORE_QUEUE_SIZE) valid, addrValid, dataValid, commited, uncache;

    logic `N(`PADDR_SIZE+`DCACHE_BYTE-`DCACHE_BYTE_WIDTH) addr_mask `N(`STORE_QUEUE_SIZE);
    logic `N(`STORE_QUEUE_SIZE) data_dir;
    logic `ARRAY(`STORE_QUEUE_SIZE, `DCACHE_BITS) data;
    logic `N(`COMMIT_WIDTH+1) commitMask;
    MaskGen #(`COMMIT_WIDTH+1) mask_gen_commit (commitBus.storeNum, commitMask);

    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            addr_mask <= '{default: 0};
            valid <= 0;
            addrValid <= 0;
            dataValid <= 0;
            commited <= 0;
            uncache <= 0;
        end
        else begin
            for(int i=0; i<`STORE_DIS_PORT; i++)begin
                if(issue_queue_io.dis_en[i] & ~issue_queue_io.dis_stall)begin
                    addrValid[disWIdx[i]] <= 1'b0;
                    dataValid[disWIdx[i]] <= 1'b0;
                    commited[disWIdx[i]] <= 1'b0;
                    uncache[disWIdx[i]] <= 0;
                end
            end
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                if(io.en[i])begin
                    addr_mask[addr_eqIdx[i]] <= {io.paddr[i][`PADDR_SIZE-1: `DCACHE_BYTE_WIDTH], io.mask[i]};
                    addrValid[addr_eqIdx[i]] <= 1'b1;
                    data_dir[addr_eqIdx[i]] <= io.data[i].sqIdx.dir;
                    uncache[addr_eqIdx[i]] <= io.uncache[i];
`ifdef FEAT_MEMPRED
                    ssitEntrys[addr_eqIdx[i]] <= io.data[i].ssitEntry;
`endif
                end
                if(issue_queue_io.data_en[i])begin
                    dataValid[data_eqIdx[i]] <= 1'b1;
                    data[data_eqIdx[i]] <= storeData[i];
                end
            end
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(commitMask[i])begin
                    commited[commitIdx[i]] <= 1'b1;
                end
            end

            for(int i=0; i<`STORE_QUEUE_SIZE; i++)begin
                valid[i] <= (valid[i] & ~(backendCtrl.redirect & ~walk_en[i]) | 
                            dis_wvalid_combine[i]) & 
                            ~commitValid_combine[i];
            end
        end
    end

// redirect
    MaskGen #(`STORE_QUEUE_SIZE) mask_gen_redirect (walk_tail, redirect_mask);
    MaskGen #(`STORE_QUEUE_SIZE) mask_gen_head (head_n, head_n_mask);


    RobIdx redirect_robIdxs `N(`STORE_QUEUE_SIZE);
    always_ff @(posedge clk) begin
        for(int i=0; i<`STORE_PIPELINE; i++)begin
            if(issue_queue_io.dis_en[i] & ~issue_queue_io.dis_stall)begin
                redirect_robIdxs[issue_queue_io.dis_sq_idx[i].idx] <= issue_queue_io.dis_rob_idx[i];
            end
        end
    end
generate
    for(genvar i=0; i<`STORE_QUEUE_SIZE; i++)begin
        LoopCompare #(`ROB_WIDTH) cmp_bigger (redirect_robIdxs[i], backendCtrl.redirectIdx, bigger[i]);
        logic `N(`STORE_QUEUE_WIDTH) i_n, i_p;
        assign i_n = i + 1;
        assign i_p = i - 1;
        assign validStart[i] = walk_en[i] & ~walk_en[i_n]; // valid[i] == 1 && valid[i + 1] == 0
        assign validEnd[i] = walk_en[i] & ~walk_en[i_p];
    end
endgenerate
    Encoder #(`STORE_QUEUE_SIZE) encoder1 (validStart, validSelect1);
    Encoder #(`STORE_QUEUE_SIZE) encoder2 (validEnd, validSelect2);
    assign valid_select = validSelect1 == head ? validSelect2 : validSelect1;
    assign walk_en = valid & (bigger | commited);
    assign valid_select_n = valid_select + 1;
    assign walk_full = &walk_en;
    assign walk_valid = |walk_en;
    assign walk_tail = walk_full ? tail : valid_select_n;
    assign walk_dir = walk_full || (valid_select_n <= tail) ? tdir : ~tdir;

// uncache
    assign saxi_io.aw_id = 0;
    assign saxi_io.aw_addr = uncache_addr;
    assign saxi_io.aw_len = 0;
    assign saxi_io.aw_size = uncache_size;
    assign saxi_io.aw_burst = 0;
    assign saxi_io.aw_user = 0;
    assign saxi_io.aw_snoop = `ACEOP_WRITE_UNIQUE;
    assign saxi_io.w_data = uncache_data;
    assign saxi_io.w_strb = uncache_strb;
    assign saxi_io.w_last = 1'b1;
    assign saxi_io.w_user = 0;

    assign saxi_io.aw_valid = uncache_req;
    assign saxi_io.w_valid = uncache_wreq;
    assign saxi_io.b_ready = 1'b1;

    assign io.wb_req = uncacheState == WRITEBACK;
    assign io.wb_robIdx = uncache_robIdx;
`ifdef FEAT_MEMPRED
    assign io.wb_ssitEntry = uncache_ssitEntry;
`endif
    lzc #(`DCACHE_BYTE) lzc_uncache_offset (addr_mask[commitHead][`DCACHE_BYTE-1: 0], uncache_offset, );
    ParallelAdder #(1, `DCACHE_BYTE) adder_uncache_size (addr_mask[commitHead][`DCACHE_BYTE-1: 0], uncache_size_pre);

    RobIdx commitRobIdx;
    always_ff @(posedge clk)begin
        commitRobIdx <= commitBus.robIdx;
`ifdef FEAT_MEMPRED
        if(valid[commitHead] & uncache[commitHead] &
            (commitBus.robIdx == redirect_robIdxs[commitHead]) &
            ~fence_valid & ~backendCtrl.redirect)begin
            uncache_ssitEntry <= ssitEntrys[commitHead];
        end
`endif
    end

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            uncacheState <= IDLE;
            uncache_req <= 0;
            uncache_wreq <= 0;
            uncache_size <= 0;
            uncache_addr <= 0;
            uncache_head <= 0;
            uncache_strb <= 0;
            uncache_data <= 0;
            uncache_size <= 0;
            uncache_robIdx <= 0;
        end
        else begin
            case(uncacheState)
            IDLE:begin
                if(valid[commitHead] & uncache[commitHead] &
                (commitBus.robIdx == redirect_robIdxs[commitHead]) &
                ~fence_valid & ~backendCtrl.redirect)begin
                    uncacheState <= LOOKUP;
                    uncache_addr <= {addr_mask[commitHead][`PADDR_SIZE+`DCACHE_BYTE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BYTE], uncache_offset};
                    uncache_size <= uncache_size_pre;
                    uncache_head <= commitHead;
                    uncache_req <= 1'b1;
                    uncache_data <= data[commitHead];
                    uncache_strb <= addr_mask[commitHead][`DCACHE_BYTE-1: 0] >> uncache_offset;
                    uncache_robIdx <= commitBus.robIdx;
                end
            end
            LOOKUP:begin
                if(saxi_io.aw_valid & saxi_io.aw_ready)begin
                    uncache_req <= 1'b0;
                    uncache_wreq <= 1'b1;
                end
                if(saxi_io.w_valid & saxi_io.w_ready)begin
                    uncache_wreq <= 1'b0;
                end
                if(saxi_io.b_valid & saxi_io.b_ready)begin
                    uncacheState <= WRITEBACK;
                end
            end
            WRITEBACK:begin
                if(io.wb_valid)begin
                    uncacheState <= RETIRE;
                end
            end
            RETIRE:begin
                if(commitHead != uncache_head)begin
                    uncacheState <= IDLE;
                end
            end
            endcase
        end
    end

// write to commit
    logic `N(`STORE_PIPELINE) queue_commit_en_pre, queue_commit_en;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic `N(`STORE_QUEUE_WIDTH) queue_idx;
        assign queue_commit_en_pre[i] = valid[queue_idx] & addrValid[queue_idx] & dataValid[queue_idx] & commited[queue_idx];
        assign queue_commit_en[i] = &queue_commit_en_pre[i: 0];
        assign queue_idx = storeHead + i;
        assign queue_commit_io.en[i] = queue_commit_en[i];
        assign queue_commit_io.uncache[i] = uncache[queue_idx];
        assign queue_commit_io.addr[i] = addr_mask[queue_idx][`PADDR_SIZE+`DCACHE_BYTE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BYTE];
        assign queue_commit_io.mask[i] = addr_mask[queue_idx][`DCACHE_BYTE-1: 0];
        assign queue_commit_io.data[i] = data[queue_idx];
        always_ff @(posedge clk)begin
            if(~queue_commit_io.conflict)begin
                store_commit_en_n[i] <= queue_commit_io.en[i];
            end
        end
    end
    always_ff @(posedge clk)begin
        if(~queue_commit_io.conflict)begin
            commitNum_n <= commitNum;
        end
    end
endgenerate

// forward
    logic `N(`STORE_QUEUE_SIZE) head_mask, tail_mask, mask_vec;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_QUEUE_SIZE) valid_vec, offset_vec, fwd_offset_vec;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_QUEUE_SIZE) ptag_vec, forward_vec;
    logic [`LOAD_PIPELINE-1: 0][`STORE_QUEUE_SIZE-1: 0][`DCACHE_BYTE-1: 0] forward_mask;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) forward_mask_o, forward_data_valid_o;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) forward_data_o;
    logic `ARRAY(`LOAD_PIPELINE, `TLB_OFFSET-`DCACHE_BYTE_WIDTH) load_voffset;

    MaskGen #(`STORE_QUEUE_SIZE) maskgen_head (head, head_mask);
    MaskGen #(`STORE_QUEUE_SIZE) maskgen_tail (tail, tail_mask);
    assign mask_vec = {`STORE_QUEUE_SIZE{hdir ^ tdir}} ^ (head_mask ^ tail_mask);
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_QUEUE_SIZE; j++)begin
            // assign offset_vec[i][j] = loadFwd.fwdData[i].en &
                                    //   (loadFwd.fwdData[i].vaddrOffset[`TLB_OFFSET-1: `DCACHE_BYTE_WIDTH] == 
                                    //   addr_mask[j][`DCACHE_BYTE+`TLB_OFFSET-`DCACHE_BYTE_WIDTH-1: `DCACHE_BYTE]);
            assign offset_vec[i][j] = loadFwd.fwdData[i].en & valid[j];
        end
        logic `N(`STORE_QUEUE_SIZE) store_mask;
        MaskGen #(`STORE_QUEUE_SIZE) maskgen_store (loadFwd.fwdData[i].sqIdx.idx, store_mask);
        logic span, overflow_pre, overflow;
        assign span = hdir ^ loadFwd.fwdData[i].sqIdx.dir;
        LoopCompare #(`STORE_QUEUE_WIDTH) cmp_overflow({tail, tdir}, loadFwd.fwdData[i].sqIdx, overflow_pre);
        assign overflow = overflow_pre & (tail != loadFwd.fwdData[i].sqIdx.idx);
        assign valid_vec[i] = overflow ? mask_vec : {`STORE_QUEUE_SIZE{span}} ^ (head_mask ^ store_mask);
        always_ff @(posedge clk)begin
            load_voffset[i] <= loadFwd.fwdData[i].vaddrOffset[`TLB_OFFSET-1: `DCACHE_BYTE_WIDTH];
        end
    end

    always_ff @(posedge clk)begin
        fwd_offset_vec <= valid_vec & offset_vec;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_QUEUE_SIZE; j++)begin
            assign ptag_vec[i][j] = {loadFwd.fwdData[i].ptag, load_voffset[i]} == 
                                    addr_mask[j][`PADDR_SIZE+`DCACHE_BYTE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BYTE];
            assign forward_mask[i][j] = {`DCACHE_BYTE{forward_vec[i][j]}} & addr_mask[j][`DCACHE_BYTE-1: 0];
        end
        assign forward_vec[i] = ptag_vec[i] & fwd_offset_vec[i] & addrValid;
        ForwardSelect #(`STORE_QUEUE_SIZE) forward_select (
            .dir(data_dir),
            .mask(forward_mask[i]),
            .data(data),
            .dataValid(dataValid),
            .mask_o(forward_mask_o[i]),
            .data_o(forward_data_o[i]),
            .dataValid_o(forward_data_valid_o[i]),
            .dir_o()
        );
    end
    always_ff @(posedge clk)begin
        loadFwd.mask <= forward_mask_o;
        loadFwd.data <= forward_data_o;
        for(int i=0; i<`LOAD_PIPELINE; i++)begin
            // 当在该次读mask范围内的数据没准备好时
            fwd_data_invalid[i] <= ((forward_data_valid_o[i] & forward_mask_o[i]) != forward_mask_o[i]) &
                ~(((forward_data_valid_o[i] & forward_mask_o[i] & loadFwd.fwdData[i].mask)) == loadFwd.fwdData[i].mask);
        end
        
    end
    
`ifdef DIFFTEST
    `Log(DLog::Debug, T_DCACHE, saxi_io.w_valid & saxi_io.w_ready, 
        $sformatf("uncache write. [%x %d] %x", uncache_addr, uncache_size, uncache_data))
`endif
endgenerate
endmodule

module ForwardSelect #(
    parameter DEPTH = 32
)(
    input logic `N(DEPTH) dir,
    input logic `ARRAY(DEPTH, `DCACHE_BYTE) mask,
    input logic `ARRAY(DEPTH, `DCACHE_BITS) data,
    input logic `N(DEPTH) dataValid,
    output logic `N(`DCACHE_BYTE) dir_o,
    output logic `N(`DCACHE_BYTE) mask_o,
    output logic `N(`DCACHE_BITS) data_o,
    output logic `N(`DCACHE_BYTE) dataValid_o
);
generate
    if(DEPTH == 1)begin
        assign mask_o = mask;
        assign data_o = data;
        assign dir_o = {`DCACHE_BYTE{dir}};
    end
    else if(DEPTH == 2)begin
        // 0001 0011 dir = 0
        // 1 1 01
        // 0 1 10
        logic older;
        assign older = dir[1] ^ dir[0];
        for(genvar i=0; i<`DCACHE_BYTE; i++)begin
            logic bigger;
            assign bigger = (mask[0][i] & older) | ~mask[1][i];
            assign dir_o[i] = bigger ? dir[0] : dir[1];
            assign mask_o[i] = mask[0][i] | mask[1][i];
            assign data_o[(i+1)*8-1: i*8] = bigger ? data[0][(i+1)*8-1: i*8] : data[1][(i+1)*8-1: i*8];
            assign dataValid_o[i] = bigger ? dataValid[0] : dataValid[1];
        end
    end
    else begin
        logic `ARRAY(2, `DCACHE_BYTE) dir1;
        logic `ARRAY(2, `DCACHE_BYTE) mask1, dataValid1;
        logic `ARRAY(2, `DCACHE_BITS) data1;
        ForwardSelect #(DEPTH/2) select1 (
            .dir(dir[DEPTH/2-1: 0]),
            .mask(mask[DEPTH/2-1: 0]),
            .data(data[DEPTH/2-1: 0]),
            .dataValid(dataValid[DEPTH/2-1: 0]),
            .dir_o(dir1[0]),
            .mask_o(mask1[0]),
            .data_o(data1[0]),
            .dataValid_o(dataValid1[0])
        );
        localparam REMAIN = DEPTH-DEPTH/2;
        ForwardSelect #(REMAIN) select2 (
            .dir(dir[DEPTH-1: DEPTH/2]),
            .mask(mask[DEPTH-1: DEPTH/2]),
            .data(data[DEPTH-1: DEPTH/2]),
            .dataValid(dataValid[DEPTH-1: DEPTH/2]),
            .dir_o(dir1[1]),
            .mask_o(mask1[1]),
            .data_o(data1[1]),
            .dataValid_o(dataValid1[1])
        );
        for(genvar i=0; i<`DCACHE_BYTE; i++)begin
            logic bigger, older;
            assign older = dir1[1][i] ^ dir1[0][i];
            assign bigger = (mask1[0][i] & older) | ~mask1[1][i];
            assign dir_o[i] = bigger ? dir1[0][i] : dir1[1][i];
            assign mask_o[i] = mask1[0][i] | mask1[1][i];
            assign data_o[(i+1)*8-1: i*8] = bigger ? data1[0][(i+1)*8-1: i*8] : data1[1][(i+1)*8-1: i*8];
            assign dataValid_o[i] = bigger ? dataValid1[0][i] : dataValid1[1][i];
        end
    end
endgenerate

endmodule

module StoreDataGen(
    input logic [1: 0] size,
    input logic `N(`XLEN) data,
    output logic `N(`XLEN) data_o
);
    logic `ARRAY(`DCACHE_BYTE, 8) shift_data;
    assign shift_data = data;
    always_comb begin
        case(size)
        2'b00: data_o = {`DCACHE_BYTE{shift_data[0]}};
        2'b01: data_o = {`DCACHE_BYTE/2{shift_data[1: 0]}};
        2'b10: data_o = {`DCACHE_BYTE/4{shift_data[3: 0]}};
`ifdef RV64I
        2'b11: data_o = {`DCACHE_BYTE/8{shift_data[7: 0]}};
`else
        2'b11: data_o = 0;
`endif
        endcase
    end
endmodule