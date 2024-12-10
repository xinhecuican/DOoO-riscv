`include "../../defines/defines.svh"

module ROB(
    input logic clk,
    input logic rst,
    input FenceReq fence_req,
    input BackendRedirectInfo backendRedirect,
    input CSRIrqInfo irqInfo,
    input logic `N(`VADDR_SIZE) exc_pc,
    input StoreWBData `N(`STORE_PIPELINE) storeWBData,
    RenameDisIO.rob dis_io,
    ROBRenameIO.rob rob_rename_io,
    RobRedirectIO.rob rob_redirect_io,
    input WriteBackBus int_wbBus,
`ifdef RVF
    input WriteBackBus fp_wbBus,
    RobFCsrIO.rob rob_fcsr_io,
`endif
    CommitBus.rob commitBus,
    output CommitWalk commitWalk,
    FenceBus.rob fenceBus,
    input BackendCtrl backendCtrl,
    output logic full

`ifdef DIFFTEST
    ,FsqBackendIO.backend fsq_back_io
`endif
);

    typedef struct packed {
        logic `N(`ROB_WIDTH+1) remainCount;
    } WalkInfo;

    typedef struct packed {
        logic we;
        logic mem;
        logic store;
`ifdef RVF
        logic fp_we;
        logic fflag_we;
`endif
`ifdef RVC
        logic rvc;
`endif
        FsqIdxInfo fsqInfo;
        logic `N(5) vrd;
        logic `N(`PREG_WIDTH) prd;
        logic `N(`PREG_WIDTH) old_prd;
`ifdef DIFFTEST
        logic sim_trap;
        logic [2: 0] trapCode;
`endif
    } RobData;

    localparam ROB_BANK_SIZE = `ROB_SIZE / `FETCH_WIDTH;
    WalkInfo walkInfo;
    logic walk_state;
    logic `N(`ROB_SIZE) wb; // set to 0 when commit, set to 1 when write back
`ifdef RVF
    logic `N(`ROB_SIZE) fp_op;
    logic `N(`COMMIT_WIDTH) commit_fp;
`endif
    logic `N(`EXC_WIDTH) exccode `N(`ROB_SIZE);

    // some instructions take effect before commit(force insts)
    // eq. mmio load, csr rw, fence
    // so irq_enable is used to recognize these insts
    // these insts can commit even irq is high
    // other insts will cause intrrupt during commit
	// another way to handle intrrupt is intrrupt after commit
	// but the last committed inst can't be branch
	// and signal used to identify irq is sent to force insts
    logic `N(`ROB_SIZE) irq_enable;
    logic `N(`COMMIT_WIDTH) commitValid;
    logic `N($clog2(`COMMIT_WIDTH) + 1) commit_en_num;
    logic `N(`COMMIT_WIDTH) wbValid, commit_en_pre, commit_en_unexc, commit_en, commit_en_n;
    logic exc_exist;
    logic `N(`COMMIT_WIDTH) excValid, exc_en, exc_mask, exc_en_n;
    logic `N($clog2(`COMMIT_WIDTH)) excIdx;
    logic `ARRAY(`COMMIT_WIDTH, `EXC_WIDTH) rexccode;
    logic `N(`COMMIT_WIDTH) irq_valid;
    logic `N($clog2(`FETCH_WIDTH)) tail_shift;
    logic `N(`FETCH_WIDTH) data_we;
    logic `ARRAY(`FETCH_WIDTH, `FETCH_WIDTH) data_we_shift, shift_idx_decode, shift_idx_reverse;
    logic `ARRAY(`FETCH_WIDTH, `FETCH_WIDTH) shift_ridx_decode, shift_ridx_reverse;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`ROB_SIZE / `FETCH_WIDTH)) data_widx, data_ridx;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`ROB_SIZE)) dataWIdx;
    logic `ARRAY(`COMMIT_WIDTH, $clog2(`ROB_SIZE)) dataRIdx;
    logic `N(`FETCH_WIDTH) data_en;
    logic `N(`ROB_WIDTH) head, tail, tail_n, head_n;
    logic `N(`COMMIT_WIDTH) commit_we;
`ifdef RVF
    logic `N(`COMMIT_WIDTH) commit_fp_we;
`endif
    logic hdir, tdir; // tail direction
    logic `N(`ROB_WIDTH+1) remainCount, remainCount_n, validCount, validCount_n;

    logic `N(`FETCH_WIDTH) dis_en;
    logic `N(`FETCH_WIDTH * 2) dis_en_shift;
    localparam ROB_ADD_WIDTH = $clog2(`WALK_WIDTH) + 1; 
    logic `N(ROB_ADD_WIDTH) dis_validNum, addNum, subNum;
    logic `N(`FETCH_WIDTH) initReady;
    logic `N(`COMMIT_WIDTH) commit_store, commit_mem;

    logic `N(`ROB_WIDTH + 1) walk_remainCount_n, ext_tail, walk_remain_count;
    logic `N(`WALK_WIDTH) walk_en;
    logic `N($clog2(`WALK_WIDTH)+1) walk_num, walk_normal_num, redirect_num;
    logic skip_current, walk_skip, walk_skip_exist, walk_skip_redirect;
    RobIdx walk_robIdx;

    logic exc_exist_n;
    logic `N($clog2(`COMMIT_WIDTH)) excIdx_n;
    logic `N(`ROB_WIDTH) exc_robIdx;
    logic exc_dir;
    logic `N(`EXC_WIDTH) redirect_exccode;
    logic irq_n, irq_deleg_n;

    RobData `N(`FETCH_WIDTH) rob_wdata_pre, rob_wdata;
    RobData `N(`WALK_WIDTH) robData_pre, robData;
    `CONSTRAINT(COMMIT_WIDTH, `FETCH_WIDTH, "commit width and fetch width must be same")
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign rob_wdata_pre[i].we = dis_io.op[i].di.we;
`ifdef RVF
        assign rob_wdata_pre[i].fp_we = dis_io.op[i].di.flt_we;
        assign rob_wdata_pre[i].fflag_we = dis_io.op[i].di.fflag_we;
`endif
`ifdef RVC
        assign rob_wdata_pre[i].rvc = dis_io.op[i].di.rvc;
`endif
        assign rob_wdata_pre[i].mem = dis_io.op[i].di.memv;
        assign rob_wdata_pre[i].store = dis_io.op[i].di.memop[`MEMOP_WIDTH-1];
        assign rob_wdata_pre[i].fsqInfo = dis_io.op[i].fsqInfo;
        assign rob_wdata_pre[i].vrd = dis_io.op[i].di.rd;
        assign rob_wdata_pre[i].prd = dis_io.prd[i];
        assign rob_wdata_pre[i].old_prd = dis_io.old_prd[i];
`ifdef DIFFTEST
        assign rob_wdata_pre[i].sim_trap = dis_io.op[i].di.sim_trap;
        assign rob_wdata_pre[i].trapCode = dis_io.op[i].di.imm;
`endif

        logic `N($clog2(`FETCH_WIDTH)) shift_idx, shift_ridx, shift_widx_in, shift_ridx_in;
        assign shift_idx = dataWIdx[i][$clog2(`FETCH_WIDTH)-1: 0];
        assign shift_ridx = dataRIdx[i][$clog2(`FETCH_WIDTH)-1: 0];
        assign data_ridx[i] = dataRIdx[shift_ridx_in][`ROB_WIDTH-1: $clog2(`FETCH_WIDTH)];
        assign data_widx[i] = dataWIdx[shift_widx_in][`ROB_WIDTH-1: $clog2(`FETCH_WIDTH)];
        Decoder #(`FETCH_WIDTH) decoder_shift (shift_idx, shift_idx_decode[i]);
        Decoder #(`FETCH_WIDTH) decoder_shift_r (shift_ridx, shift_ridx_decode[i]);
        Encoder #(`FETCH_WIDTH) encoder_shift (shift_idx_reverse[i], shift_widx_in);
        Encoder #(`FETCH_WIDTH) encoder_shift_r (shift_ridx_reverse[i], shift_ridx_in);
        for(genvar j=0; j<`FETCH_WIDTH; j++)begin
            assign shift_idx_reverse[i][j] = shift_idx_decode[j][i];
            assign shift_ridx_reverse[i][j] = shift_ridx_decode[j][i];
        end
        assign data_we_shift[i] = shift_idx_decode[i] & {`FETCH_WIDTH{dis_en[i]}};
        logic `N($clog2(`FETCH_WIDTH*2)) shift_widx_global, shift_ridx_global;
        assign shift_widx_global = {1'b1, shift_idx};
        assign shift_ridx_global = {1'b0, shift_ridx};
        `SIG_N(robData_pre[shift_ridx_global], robData[i])
        `SIG_N(robData_pre[shift_widx_global], robData[`FETCH_WIDTH+i])
        assign rob_wdata[i] = rob_wdata_pre[shift_widx_in];
        MPRAM #(
            .WIDTH($bits(RobData)),
            .DEPTH(`ROB_SIZE / `FETCH_WIDTH),
            .READ_PORT(1),
            .WRITE_PORT(0),
            .RW_PORT(1),
            .READ_LATENCY(0),
            .RESET(1)
        ) rob_data_ram (
            .clk(clk),
            .rst(rst),
            .en(2'b11),
            .raddr(data_ridx[i]),
            .rdata({robData_pre[`FETCH_WIDTH+i], robData_pre[i]}),
            .we(data_we[i]),
            .waddr(data_widx[i]),
            .wdata(rob_wdata[i]),
            .ready(initReady[i])
        );
    end
    ParallelOR #(`FETCH_WIDTH, `FETCH_WIDTH) or_data_we (data_we_shift, data_we);
endgenerate


//enqueue
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign dis_en[i] = dis_io.op[i].en & ~backendCtrl.dis_full;
    end
    assign data_en = dis_en;
    ParallelAdder #(1, `FETCH_WIDTH) adder_dis_valid (dis_en, dis_validNum);
endgenerate

    logic wb_sfence;
    logic fence, fence_redirect;
    logic fence_end_n;
    `SIG_N(fenceBus.fence_end, fence_end_n)
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            fence <= 0;
            fence_redirect <= 0;
        end
        else begin
            if(wb_sfence & ~walk_state & ~exc_exist_n & ~exc_exist)begin
                fence <= 1'b1;
                fence_redirect <= 1'b1;
            end
            if(fenceBus.fence_end)begin
                fence_redirect <= 1'b0;
            end
            if(fence_end_n)begin
                fence <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            wb_sfence <= 0;
            commitBus.fence_valid <= 0;
        end
        else begin
            // en[0] is csr issue queue idx and it's in order
            if(int_wbBus.en[0] & fence_req.req & (int_wbBus.robIdx[0] == fence_req.robIdx) & ~fenceBus.valid)begin
                wb_sfence <= int_wbBus.en[0] & fence_req.req & (int_wbBus.robIdx[0] == fence_req.robIdx);
            end
            else if((|commit_en_n) | exc_exist_n)begin
                wb_sfence <= 1'b0;
            end
            commitBus.fence_valid <= wb_sfence & (commit_en[0]) & ~walk_state & ~exc_exist_n & ~exc_exist;
        end
    end

// commit
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign wbValid[i] = wb[dataRIdx[i]];
        // exception inst invalid
        assign commit_we[i] = robData[i].we & ~exc_en_n[i];
        assign commit_store[i] = robData[i].store;
        assign commit_mem[i] = robData[i].mem;
        assign rexccode[i] = exccode[dataRIdx[i]];
        assign irq_valid[i] = irq_enable[dataRIdx[i]];
`ifdef RVF
        assign commit_fp[i] = fp_op[dataRIdx[i]];
        assign excValid[i] = commit_fp[i] ? ~rob_fcsr_io.valid : ~(&rexccode[i]);
`else
        assign excValid[i] = ~(&rexccode[i]);
`endif
    end
    assign commit_en_num = validCount < `COMMIT_WIDTH ? validCount : `COMMIT_WIDTH;
    assign commitValid = (1 << commit_en_num) - 1;
    assign commit_en_pre = commitValid & wbValid;
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        if(i == 0)begin
            assign commit_en_unexc[i] = commit_en_pre[0] & ~fence;
        end
        else begin
            assign commit_en_unexc[i] = (&commit_en_pre[i: 0]) & ~fence & ~wb_sfence;
        end
    end
    assign exc_en = (excValid | ({`COMMIT_WIDTH{irqInfo.irq}} & irq_valid));
    assign exc_exist = |(commit_en_unexc & exc_en);
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        if(i == 0)begin
            assign exc_mask[i] = 1'b1;
        end
        else begin
            assign exc_mask[i] = ~(|exc_en[i-1: 0]);
        end
    end
    PREncoder #(`COMMIT_WIDTH) prencoder_exc_idx (exc_en, excIdx);
    assign commit_en = commit_en_unexc & exc_mask;
endgenerate

    logic `N($clog2(`COMMIT_WIDTH) + 1) commitNum, commitLoadNum, commitStoreNum;
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_num (commit_en, commitNum);

    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_load (commitBus.en & commit_mem & ~commit_store & ~exc_en_n, commitLoadNum);
    ParallelAdder #(.DEPTH(`COMMIT_WIDTH)) adder_commit_store (commitBus.en & commit_mem & commit_store & ~exc_en_n, commitStoreNum);
    assign commitBus.we = commit_we;
    assign commitBus.robIdx.idx = head;
    assign commitBus.robIdx.dir = hdir;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitBus.fsqInfo[i] = robData[i].fsqInfo;
        assign commitBus.vrd[i] = robData[i].vrd;
        assign commitBus.prd[i] = robData[i].prd;
`ifdef RVC
        assign commitBus.rvc[i] = robData[i].rvc;
`endif
`ifdef RVF
        assign commitBus.fp_we[i] = robData[i].fp_we;
`else
        assign commitBus.fp_we[i] = 0;
`endif
    end
    for(genvar i=0; i<`WALK_WIDTH; i++)begin
        assign commitWalk.vrd[i] = robData[i].vrd;
        assign commitWalk.prd[i] = robData[i].prd;
        assign commitWalk.old_prd[i] = robData[i].old_prd;
        assign commitWalk.we[i] = robData[i].we;
`ifdef RVF
        assign commitWalk.fp_we[i] = robData[i].fp_we;
`else
        assign commitWalk.fp_we[i] = 0;
`endif
    end


`ifdef RVF
    logic `N($clog2(`COMMIT_WIDTH)) fp_commit_idx, fp_commit_idx_n, fp_fflag_idx;
    logic `N(`COMMIT_WIDTH) fflag_we;
    logic fcsr_we;
    logic `ARRAY(`COMMIT_WIDTH, `EXC_WIDTH) rexccode_n;
    PEncoder #(`COMMIT_WIDTH) encoder_fp_commit_idx (commit_en & commit_fp, fp_commit_idx);
    PEncoder #(`COMMIT_WIDTH) encoder_fp_fflag_idx (commit_en_n & fflag_we, fp_fflag_idx);
    assign rob_fcsr_io.we = fcsr_we;
    assign rob_fcsr_io.flag_we = |(commit_en_n & fflag_we);
    assign rob_fcsr_io.flags = rexccode_n[fp_fflag_idx];
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign fflag_we[i] = robData[i].fflag_we;
    end
    always_ff @(posedge clk)begin
        fcsr_we <= (|(commit_en & commit_fp)) & rob_fcsr_io.valid & ~walk_state & ~exc_exist_n;
        rexccode_n <= rexccode;
    end
`endif

    always_ff @(posedge clk)begin
        exc_en_n <= exc_en;
        if(!walk_state && initReady[0] && !exc_exist_n)begin
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                commitBus.en[i] <= commit_en[i];
            end
            commitBus.num <= commitNum;
            commit_en_n <= commit_en;
            commitBus.excValid <= excValid;
        end
        else begin
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                commitBus.en[i] <= 0;
            end
            commitBus.num <= 0;
            commit_en_n <= 0;
            commitBus.excValid <= 0;
        end
        if(initReady[0])begin
            commitBus.loadNum <= commitLoadNum;
            commitBus.storeNum <= commitStoreNum;
        end
        else begin
            commitBus.loadNum <= 0;
            commitBus.storeNum <= 0;
        end
    end
endgenerate


// exception

    always_ff @(posedge clk)begin
        exc_exist_n <= exc_exist && !walk_state && initReady[0] & ~exc_exist_n;
        irq_n <= irqInfo.irq & irq_valid[excIdx];
        irq_deleg_n <= irqInfo.deleg;
        excIdx_n <= excIdx;
        exc_robIdx <= dataRIdx[excIdx];
        exc_dir <= head[`ROB_WIDTH-1] & ~dataRIdx[excIdx][`ROB_WIDTH-1] ? ~hdir : hdir;
`ifdef RVF
        redirect_exccode <= irqInfo.irq & irq_valid[excIdx] ? irqInfo.exccode : 
                            commit_fp[excIdx] ? `EXC_II : rexccode[excIdx]; 
`else
        redirect_exccode <= irqInfo.irq & irq_valid[excIdx] ? irqInfo.exccode : rexccode[excIdx];
`endif
    end
    assign rob_redirect_io.fence = fence_redirect;
    assign rob_redirect_io.csrRedirect.en = exc_exist_n;
`ifdef RVC
    assign rob_redirect_io.csrRedirect.rvc = robData[excIdx_n].rvc;
`endif
    assign rob_redirect_io.csrRedirect.fsqInfo = robData[excIdx_n].fsqInfo;
    assign rob_redirect_io.csrRedirect.robIdx.idx = exc_robIdx;
    assign rob_redirect_io.csrRedirect.robIdx.dir = exc_dir;
    assign rob_redirect_io.csrInfo.en = exc_exist_n;
    assign rob_redirect_io.csrInfo.irq = irq_n;
    assign rob_redirect_io.csrInfo.irq_deleg = irq_deleg_n;
    assign rob_redirect_io.csrInfo.exccode = redirect_exccode;
    assign rob_redirect_io.csrInfo.exc_pc = exc_pc;

// idx maintain
    always_comb begin
        if(walk_state)begin
            addNum = walk_skip;
            subNum = walk_num;
            head_n = head - addNum;
            tail_n = tail - subNum;
            remainCount_n = remainCount + subNum - addNum;
            validCount_n = validCount - subNum + addNum;
        end
        else begin
            addNum = {ROB_ADD_WIDTH{~exc_exist_n}} & commitNum;
            subNum = {ROB_ADD_WIDTH{~backendCtrl.rename_full & ~backendCtrl.dis_full & ~backendRedirect.en}} & rob_rename_io.validNum;
            tail_n = tail + subNum;
            head_n = head + addNum;
            remainCount_n = remainCount + addNum - subNum;
            validCount_n = validCount - addNum + subNum;
        end
    end

    assign full = remainCount < rob_rename_io.validNum;
    assign rob_rename_io.robIdx.idx = tail;
    assign rob_rename_io.robIdx.dir = tdir;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            wb <= '{default: 0};
            exccode <= '{default: 0};
            hdir <= 0;
            tdir <= 0;
            remainCount <= `ROB_SIZE;
            validCount <= 0;
`ifdef RVF
            fp_op <= 0;
`endif
        end
        else begin
            
            tail <= tail_n;
            remainCount <= remainCount_n;
            validCount <= validCount_n;
            if((~commitWalk.walk & tail[`ROB_WIDTH-1] & ~tail_n[`ROB_WIDTH-1]) |
               (commitWalk.walk & tail_n[`ROB_WIDTH-1] & ~tail[`ROB_WIDTH-1]))begin
                tdir <= ~tdir;
            end
            head <= head_n;
            if(~walk_state & head[`ROB_WIDTH-1] & ~head_n[`ROB_WIDTH-1] |
               walk_state & head_n[`ROB_WIDTH-1] & ~head[`ROB_WIDTH-1])begin
                hdir <= ~hdir;
            end
            for(int i=0; i<`WB_SIZE; i++)begin
                if(int_wbBus.en[i])begin
                    wb[int_wbBus.robIdx[i].idx] <= 1'b1;
                    exccode[int_wbBus.robIdx[i].idx] <= int_wbBus.exccode[i];
                    irq_enable[int_wbBus.robIdx[i].idx] <= int_wbBus.irq_enable[i];
                end
            end
`ifdef RVF
            for(int i=0; i<`FP_WB_SIZE; i++)begin
                if(fp_wbBus.en[i])begin
                    wb[fp_wbBus.robIdx[i].idx] <= 1'b1;
                    exccode[fp_wbBus.robIdx[i].idx] <= fp_wbBus.exccode[i];
                    irq_enable[fp_wbBus.robIdx[i].idx] <= fp_wbBus.irq_enable[i];
                end
            end
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if(dis_en[i])begin
                    fp_op[dataWIdx[i]] <= dis_io.op[i].di.fmiscv | dis_io.op[i].di.fcalv;
                end
            end
`endif
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                if(storeWBData[i].en)begin
                    wb[storeWBData[i].robIdx.idx] <= 1'b1;
                    exccode[storeWBData[i].robIdx.idx] <= storeWBData[i].exccode;
                    irq_enable[storeWBData[i].robIdx.idx] <= storeWBData[i].irq_enable;
                end
            end
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                if((rob_rename_io.validNum > i) & ~backendCtrl.dis_full & ~backendCtrl.rename_full)begin
                    wb[tail + i] <= 1'b0;
                end
            end
        end
    end

    // walk
    // 异常指令需要提交但是不能对寄存器堆产生影响
    assign skip_current = ~exc_exist_n;
    assign ext_tail = {tdir ^ backendRedirect.robIdx.dir, tail};
    assign walk_remainCount_n = ext_tail - backendRedirect.robIdx.idx - skip_current;
    assign walk_remain_count = backendRedirect.en ? walk_remainCount_n : walkInfo.remainCount;
    assign redirect_num = (|walk_remainCount_n[`ROB_WIDTH: $clog2(`WALK_WIDTH)]) ? `WALK_WIDTH : walk_remainCount_n;
    assign walk_normal_num =  (|walkInfo.remainCount[`ROB_WIDTH: $clog2(`WALK_WIDTH)]) ? `WALK_WIDTH : walkInfo.remainCount;
    assign walk_num = backendRedirect.en ? redirect_num : walk_normal_num;
    assign walk_en = backendRedirect.en ? (1 << redirect_num) - 1 : (1 << walk_normal_num) - 1;
    // TODO: dataWIdx改为rw port，walk使用widx，从而walk和commit同时进行
    logic `N(`WALK_WIDTH) commit_walk_en;
    logic walk;
    logic `N($clog2(`WALK_WIDTH) + 1) commit_walk_num;
    logic walk_start;
    assign commitWalk.en = commit_walk_en;
    assign commitWalk.walk = walk;
    assign commitWalk.num = commit_walk_num;
    assign commitWalk.walkStart = walk_start;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            walk_state <= 1'b0;
            walkInfo <= '{default: 0};
            commit_walk_en <= 0;
            walk <= 1'b0;
            commit_walk_num <= 0;
            walk_start <= 0;
            walk_skip <= 0;
            walk_skip_exist <= 0;
            walk_robIdx <= 0;
            walk_skip_redirect <= 0;
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                dataRIdx[i] <= i;
            end
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dataWIdx[i] <= i;
            end
        end
        else begin
            if(walk_state)begin
                if(walk_remain_count == 0)begin
                    walk <= 1'b0;
                    walk_state <= 1'b0;
                    commit_walk_en <= 0;
                    commit_walk_num <= 0;
                end
                walk_start <= 1'b0;
                walk_skip <= backendRedirect.en & ~walk_skip_exist & ~skip_current;
                commit_walk_en <= walk_en;
                commit_walk_num <= walk_num;
                walkInfo.remainCount <= walk_remain_count - walk_num;
            end
            else if(backendRedirect.en)begin
                walk_state <= 1'b1;
                walkInfo.remainCount <= walk_remainCount_n;
                walk <= 1'b1;
                walk_start <= 1'b1;
                walk_skip <= ~skip_current;
            end

            if(backendRedirect.en)begin
                walk_skip_exist <= walk_skip_exist | ~skip_current;
                walk_robIdx <= backendRedirect.robIdx.idx;
                walk_skip_redirect <= skip_current;
            end
            if(walk_state && walk_remain_count == 0) begin
                walk_skip_exist <= 1'b0;
            end

            if(walk_state && walk_remain_count == 0)begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= head + i;
                    dataWIdx[i] <= walk_robIdx + i + walk_skip_redirect;
                end
            end
            else if(walk_state)begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= dataRIdx[i] - walk_num;
                    dataWIdx[i] <= dataWIdx[i] - walk_num;
                end
            end
            else if(backendRedirect.en)begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= tail - i - 1;
                    dataWIdx[i] <= tail - i - `COMMIT_WIDTH - 1;
                end
            end
            else begin
                for(int i=0; i<`COMMIT_WIDTH; i++)begin
                    dataRIdx[i] <= dataRIdx[i] + commitNum;
                    dataWIdx[i] <= dataWIdx[i] + dis_validNum;
                end
            end

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
    logic `ARRAY(`COMMIT_WIDTH, `ROB_WIDTH) dataRIdxNext, diff_robIdx;
    always_ff @(posedge clk)begin
        pc <= fsq_back_io.diff_pc;
        diff_valid <= commitBus.en;
        diff_wen <= commitBus.we;
        diff_wdest <= commitBus.vrd;
        dataRIdxNext <= dataRIdx;
        diff_robIdx <= dataRIdxNext;
        for(int i=0; i<`FETCH_WIDTH; i++)begin
            if(data_en[i])begin
                insts[dataWIdx[i]] <= dis_io.op[i].inst;
            end
        end
        for(int i=0; i<`WB_SIZE; i++)begin
            if(int_wbBus.en[i])begin
                data[int_wbBus.robIdx[i].idx] <= int_wbBus.res[i];
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
            .robIdx({{32-`ROB_WIDTH{1'b0}}, diff_robIdx[i]}),
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
    logic trapValid;
    logic `N(`COMMIT_WIDTH) trapValids;
    logic `N($clog2(`COMMIT_WIDTH)) trapIdx;
    logic [7: 0] trapCode;

generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign trapValids[i] = commitBus.en[i] & robData[i].sim_trap;
    end
endgenerate
    PREncoder #(`COMMIT_WIDTH) encoder_trap_idx (trapValids, trapIdx);
    always_ff @(posedge clk)begin
        trapValid <= |trapValids;
        trapCode <= robData[trapIdx].trapCode;
    end

    DifftestTrapEvent difftest_trap_event (
        .clock(clk),
        .coreid(0),
        .valid(trapValid),
        .code(trapCode),
        .pc(pc[0]),
        .cycleCnt(cycleCnt),
        .instrCnt(instrCnt)
    );

    logic diff_irq;
    logic diff_exc_exist;
    logic `N(`EXC_WIDTH) diff_exccode, diff_cause;
    always_ff @(posedge clk)begin
        diff_irq <= irq_n;
        diff_exc_exist <= exc_exist_n;
        diff_exccode <= redirect_exccode;
    end
    assign diff_cause = diff_exc_exist & ~diff_irq &
        (diff_exccode == `EXC_IPF || diff_exccode == `EXC_LPF || diff_exccode == `EXC_SPF) ? diff_exccode : 0;

    DifftestArchEvent difftest_arch_event (
        .clock(clk),
        .coreid(0),
        .intrNO((diff_exc_exist & diff_irq ? diff_exccode : 0)),
        .cause(diff_cause),
        .exceptionPC(pc[0]),
        .exceptionInst(diff_insts[0])
    );

    logic `N($clog2(`COMMIT_WIDTH)+1) commitCnt;
    ParallelAdder #(1, `COMMIT_WIDTH) adder_commit (diff_valid, commitCnt);
    assign DLog::cycleCnt = cycleCnt;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            cycleCnt <= 0;
            instrCnt <= 0;
        end
        else begin
            cycleCnt <= cycleCnt + 1;
            instrCnt <= instrCnt + commitCnt;
        end
    end

    `Log(DLog::Debug, T_COMMIT, exc_exist_n,
        $sformatf("exception[%d %x] pc: %x", irq_n, redirect_exccode, exc_pc))
`endif
endmodule