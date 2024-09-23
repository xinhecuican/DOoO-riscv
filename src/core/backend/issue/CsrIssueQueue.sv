`include "../../../defines/defines.svh"

module CsrIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_csr_io,
    IssueRegIO.issue csr_reg_io,
    IssueWakeupIO.issue csr_wakeup_io,
    IssueCSRIO.issue issue_csr_io,
    CommitBus.csr commitBus,
    input BackendCtrl backendCtrl,
    FenceBus.csr fenceBus,
    output logic `N(32) trapInst,
    output FenceReq fence_req
);

    typedef struct {
        logic we;
        logic `N(`PREG_WIDTH) rs1;
        logic `N(`PREG_WIDTH) rs2;
        logic `N(`PREG_WIDTH) rd;
        RobIdx robIdx;
    } StatusEntry;

    typedef enum  { IDLE, WRITING } State;

    StatusEntry status_ram `N(`CSR_ISSUE_SIZE);
    State state;
    logic select_en, wakeup_en;
    logic wakeup_older;
    logic `N(`CSR_ISSUE_WIDTH) head, tail, head_n, tail_n;
    logic hdir, tdir;
    logic `N(`CSR_ISSUE_SIZE) dirTable;
    logic full;
    logic enqueue;
    CsrIssueBundle rdata;
    IssueStatusBundle status;
    StatusEntry statush, status_n;
    RobIdx writeRobIdx;
    logic `ARRAY(2, `XLEN) csr_rdata;

    assign full = head == tail && (hdir ^ tdir);
    assign dis_csr_io.full = full;
    assign enqueue = dis_csr_io.en & ~full & ~backendCtrl.redirect;
    assign head_n = head + 1;
    assign tail_n = tail + 1;
    assign status = dis_csr_io.status;
    assign statush = status_ram[head];
    assign select_en = (head != tail || (hdir ^ tdir)) &&
                        state == IDLE &&
                        statush.robIdx == commitBus.robIdx &&
                        !backendCtrl.redirect;
    always_ff @(posedge clk)begin
        wakeup_en <= select_en & csr_wakeup_io.ready & csr_reg_io.ready;
        status_n <= statush;
    end
    LoopCompare #(`ROB_WIDTH) cmp_wakeup_older (writeRobIdx, backendCtrl.redirectIdx,  wakeup_older);

    assign csr_reg_io.en = select_en;
    assign csr_reg_io.preg = {statush.rs2, statush.rs1};
    assign csr_wakeup_io.en = select_en & csr_reg_io.ready;
    assign csr_wakeup_io.we = statush.we;
    assign csr_wakeup_io.rd = statush.rd;

    always_ff @(posedge clk)begin
        issue_csr_io.en <= wakeup_en & (~backendCtrl.redirect | wakeup_older);
        issue_csr_io.bundle <= rdata;
        issue_csr_io.status.we <=  status_n.we;
        issue_csr_io.status.rd <= status_n.rd;
        issue_csr_io.status.robIdx <= status_n.robIdx;
        if(issue_csr_io.en)begin
            csr_rdata <= csr_reg_io.data;
        end
    end
    assign issue_csr_io.rdata = csr_reg_io.data[0];

    MPREG #(
        .WIDTH($bits(CsrIssueBundle)),
        .DEPTH(`CSR_ISSUE_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .raddr(head),
        .rdata(rdata),
        .we(enqueue),
        .waddr(tail),
        .wdata(dis_csr_io.data),
        .ready()
    );

// redirect
    logic `N(`CSR_ISSUE_SIZE) redirect_en, head_mask, tail_mask;
    logic `N(`CSR_ISSUE_SIZE) bigger, valid, validStart, validEnd;
    logic `N(`CSR_ISSUE_WIDTH) validSelect1, validSelect2, validSelect, validSelect_n;
    MaskGen #(`CSR_ISSUE_SIZE) mask_gen_head(head, head_mask);
    MaskGen #(`CSR_ISSUE_SIZE) mask_gen_tail(tail, tail_mask);
    assign redirect_en = hdir ^ tdir ? ~(head_mask ^ tail_mask) : head_mask ^ tail_mask;
    assign valid = bigger & redirect_en;
generate
    for(genvar i=0; i<`CSR_ISSUE_SIZE; i++)begin
        LoopCompare #(`ROB_WIDTH) cmp_bigger (status_ram[i].robIdx, backendCtrl.redirectIdx, bigger[i]);
        logic `N(`CSR_ISSUE_WIDTH) i_n, i_p;
        assign i_n = i + 1;
        assign i_p = i - 1;
        assign validStart[i] = valid[i] & ~valid[i_n];
        assign validEnd[i] = valid[i] & ~valid[i_p];
    end
endgenerate
    Encoder #(`CSR_ISSUE_SIZE) encoder1 (validStart, validSelect1);
    Encoder #(`CSR_ISSUE_SIZE) encoder2 (validEnd, validSelect2);
    assign validSelect = validSelect1 == head ? validSelect2 : validSelect1;
    assign validSelect_n = validSelect + 1;

    always_ff @(posedge clk)begin
        if(enqueue)begin
            status_ram[tail].we <= status.we;
            status_ram[tail].rs1 <= status.rs1;
            status_ram[tail].rs2 <= status.rs2;
            status_ram[tail].robIdx <= status.robIdx;
            status_ram[tail].rd <= status.rd;
        end
    end

    function logic detectFence(input CsrIssueBundle bundle);
                // sfence.vma, fence, fence.i
        return bundle.csrop[3] |
                // mstatus, mpp need fence, usually sfence.vma followed with w satp
               (~bundle.csrop[3] &
               ((bundle.csrid == `CSRID_mstatus) | (bundle.csrid == `CSRID_sstatus) |
                (bundle.csrid[11: 0] >= `CSRID_pmpcfg && bundle.csrid[11: 0] < 12'h3f0)));
    endfunction

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            writeRobIdx <= 0;
            head <= 0;
            hdir <= 0;
            trapInst <= 0;
            fence_req <= 0;
        end
        else if(backendCtrl.redirect & ~(|valid))begin
            state <= IDLE;
            fence_req.req <= 1'b0;
        end
        else begin
            if(wakeup_en)begin
                trapInst <= rdata.inst;
                fence_req.robIdx <= writeRobIdx;
                fence_req.req <= detectFence(rdata);
            end
            case(state)
            IDLE:begin
                if(select_en & csr_wakeup_io.ready & csr_reg_io.ready)begin
                    state <= WRITING;
                    writeRobIdx <= statush.robIdx;
                end
            end
            WRITING:begin
                if(writeRobIdx != commitBus.robIdx)begin
                    state <= IDLE;
                    head <= head_n;
                    hdir <= head[`CSR_ISSUE_WIDTH-1] & ~head_n[`CSR_ISSUE_WIDTH-1] ? ~hdir : hdir;
                    fence_req.req <= 1'b0;
                end
            end
            endcase
        end
    end

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            tail <= 0;
            tdir <= 0;
            dirTable <= 0;
        end
        else begin
            if(backendCtrl.redirect & ~(&valid))begin
                tail <= |valid ? validSelect_n : head;
                tdir <= |valid ? (validSelect[`CSR_ISSUE_WIDTH-1] & ~validSelect_n[`CSR_ISSUE_WIDTH-1] ?
                        ~dirTable[validSelect] : dirTable[validSelect]) : hdir;
            end
            else if(enqueue)begin
                tail <= tail_n;
                tdir <= tail[`CSR_ISSUE_WIDTH-1] & ~tail_n[`CSR_ISSUE_WIDTH-1] ? ~tdir : tdir;
                dirTable[tail] <= tdir;
            end
        end
    end

// fence
    typedef struct packed {
        logic sfence_vma;
        logic fence;
        logic csr;
`ifdef EXT_FENCEI
        logic fencei;
`endif
    } FenceType;
    logic sfence_vma, vma_clear_all, fence, fencei;
    FsqIdxInfo fence_fsqInfo;
    logic `N(`PREDICTION_WIDTH+1) fsq_offset_n;
    RobIdx preRobIdx;
    FenceType fence_type;

    assign fsq_offset_n = commitBus.fsqInfo[0].offset + 1;
    assign fence_fsqInfo.idx = commitBus.fsqInfo[0].idx + fsq_offset_n[`PREDICTION_WIDTH];
    assign fence_fsqInfo.offset = fsq_offset_n[`PREDICTION_WIDTH-1: 0];
    assign vma_clear_all = csr_rdata[0][`VADDR_SIZE-1: 0] == 0;

    LoopSub #(`ROB_WIDTH, 1) sub_rob_idx (1'b1, commitBus.robIdx, preRobIdx);


    always_ff @(posedge clk)begin
        if(wakeup_en)begin
            fence_type.sfence_vma <= rdata.csrop == `CSR_SFENCE;
            fence_type.csr <= ~rdata.csrop[3];
            fence_type.fence <= rdata.csrop == `CSR_FENCE;
`ifdef EXT_FENCEI
            fence_type.fencei <= rdata.csrop == `CSR_FENCEI;
`endif
        end
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            fenceBus.store_flush <= 1'b0;
            fenceBus.inst_flush <= 1'b0;
            sfence_vma <= 1'b0;
            fence <= 1'b0;
`ifdef EXT_FENCEI
            fencei <= 1'b0;
`endif
            fenceBus.fence_end <= 1'b0;
            fenceBus.preRobIdx <= 0;
            fenceBus.robIdx <= 0;
            fenceBus.fsqInfo <= 0;
            fenceBus.mmu_flush <= 0;
        end
        else begin
            if(commitBus.fence_valid)begin
                fenceBus.preRobIdx <= preRobIdx;
                fenceBus.robIdx <= commitBus.robIdx;
                fenceBus.fsqInfo <= fence_fsqInfo;
            end
            if(commitBus.fence_valid & (fence_type.sfence_vma | fence_type.fence))begin
                fenceBus.store_flush <= 1'b1;
            end
            if(commitBus.fence_valid & fence_type.sfence_vma)begin
                sfence_vma <= 1'b1;
            end
            if(commitBus.fence_valid & fence_type.fence)begin
                fence <= 1'b1;
            end
`ifdef EXT_FENCEI
            if(commitBus.fence_valid & fence_type.fencei)begin
                fencei <= 1'b1;
            end
            fenceBus.inst_flush <= commitBus.fence_valid & fence_type.fencei;
            if(fencei & fenceBus.inst_flush_end)begin
                fencei <= 1'b0;
            end
`endif
            if(fenceBus.store_flush & fenceBus.store_flush_end)begin
                fenceBus.store_flush <= 1'b0;
            end
            if(sfence_vma & fenceBus.store_flush_end)begin
                sfence_vma <= 1'b0;
            end
            if(fence & fenceBus.store_flush_end)begin
                fence <= 1'b0;
            end

            fenceBus.mmu_flush <= {3{sfence_vma & fenceBus.store_flush_end}};
            fenceBus.fence_end <= fenceBus.mmu_flush_end |
                                  (commitBus.fence_valid & fence_type.csr) |
                                  (fence & fenceBus.store_flush_end)
`ifdef EXT_FENCEI
                                  | fenceBus.inst_flush_end;
`endif
;
        end
    end
    
generate
    for(genvar i=0; i<3; i++)begin
        always_ff @(posedge clk)begin
            if(commitBus.fence_valid & fence_type.sfence_vma)begin
                fenceBus.mmu_flush_all[i] <= vma_clear_all;
                fenceBus.vma_vaddr[i] <= csr_rdata[0][`VADDR_SIZE-1: 0];
                fenceBus.vma_asid[i] <= csr_rdata[1][`TLB_ASID-1: 0];
            end
        end
    end
endgenerate
endmodule