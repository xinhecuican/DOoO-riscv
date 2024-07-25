`include "../../../defines/defines.svh"

module CsrIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_csr_io,
    IssueRegIO.issue csr_reg_io,
    IssueWakeupIO.issue csr_wakeup_io,
    IssueCSRIO.issue issue_csr_io,
    CommitBus.csr commitBus,
    BackendCtrl backendCtrl
);

    typedef struct {
        logic we;
        logic `N(`PREG_WIDTH) rs1;
        logic `N(`PREG_WIDTH) rd;
        RobIdx robIdx;
    } StatusEntry;

    StatusEntry status_ram `N(`CSR_ISSUE_SIZE);
    logic select_en, wakeup_en;
    logic wakeup_older;
    logic `N(`CSR_ISSUE_WIDTH) head, tail, head_n, tail_n;
    logic hdir, tdir;
    logic `N(`CSR_ISSUE_SIZE) dirTable;
    logic full;
    logic enqueue;
    CsrIssueBundle rdata, rdata_n;
    CsrIssueBundle bundle;
    IssueStatusBundle status;
    StatusEntry statush, status_n;

    assign full = head == tail && (hdir ^ tdir);
    assign dis_csr_io.full = full;
    assign enqueue = dis_csr_io.en & ~full & ~backendCtrl.redirect;
    assign head_n = head + 1;
    assign tail_n = tail + 1;
    assign bundle = dis_csr_io.data;
    assign status = dis_csr_io.status;
    assign statush = status_ram[head];
    assign select_en = (head != tail || (hdir ^ tdir)) &&
                        statush.robIdx == commitBus.robIdx &&
                        !backendCtrl.redirect;
    always_ff @(posedge clk)begin
        wakeup_en <= select_en & csr_wakeup_io.ready & csr_reg_io.ready;
        status_n <= statush;
    end
    LoopCompare #(`ROB_WIDTH) cmp_wakeup_older (status_n.robIdx, backendCtrl.redirectIdx,  wakeup_older);

    assign csr_reg_io.en = select_en;
    assign csr_reg_io.preg = statush.rs1;
    assign csr_wakeup_io.en = select_en & csr_reg_io.ready;
    assign csr_wakeup_io.we = statush.we;
    assign csr_wakeup_io.rd = statush.rd;

    always_ff @(posedge clk)begin
        issue_csr_io.en <= wakeup_en & (~backendCtrl.redirect | wakeup_older);
        issue_csr_io.bundle <= rdata;
        issue_csr_io.status.we <=  status_n.we;
        issue_csr_io.status.rd <= status_n.rd;
        issue_csr_io.status.robIdx <= status_n.robIdx;
    end
    assign issue_csr_io.rdata = csr_reg_io.data;

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
            status_ram[tail].robIdx <= status.robIdx;
            status_ram[tail].rd <= status.rd;
        end
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            hdir <= 0;
            tdir <= 0;
            dirTable <= 0;
        end
        else begin
            if(backendCtrl.redirect)begin
                tail <= |valid ? validSelect_n : head;
                tdir <= |valid ? (validSelect[`CSR_ISSUE_WIDTH-1] & ~validSelect_n[`CSR_ISSUE_WIDTH-1] ?
                        ~dirTable[validSelect] : dirTable[validSelect]) : hdir;
            end
            else if(enqueue)begin
                tail <= tail_n;
                tdir <= tail[`CSR_ISSUE_WIDTH-1] & ~tail_n[`CSR_ISSUE_WIDTH-1] ? ~tdir : tdir;
                dirTable[tail] <= tdir;
            end

            if(select_en & csr_wakeup_io.ready)begin
                head <= head_n;
                hdir <= head[`CSR_ISSUE_WIDTH-1] & ~head_n[`CSR_ISSUE_WIDTH-1] ? ~hdir : hdir;
            end
        end
    end
endmodule