`include "../../../defines/defines.svh"

module CsrIssueQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_csr_io,
    IssueWakeupIO.issue csr_wakeup_io,
    IssueCSRIO.issue issue_csr_io,
    CommitBus.csr commitBus,
    BackendCtrl backendCtrl
);

    typedef struct {
        logic `N(`PREG_WIDTH) rs1;
        logic `N(`PREG_WIDTH) rd;
        RobIdx robIdx;
    } StatusEntry;

    StatusEntry status_ram `N(`CSR_ISSUE_SIZE);
    logic select_en, wakeup_en;
    RobIdx wakeup_robIdx, wakeup_out;
    logic wakeup_older;
    logic `N(`CSR_ISSUE_WIDTH) head, tail, head_n, tail_n;
    logic hdir, tdir;
    logic `N(`CSR_ISSUE_SIZE) dirTable;
    logic full;
    logic enqueue;
    CsrIssueBundle rdata, rdata_n;
    CsrIssueBundle bundle;
    IssueStatusBundle status;

    assign full = head == tail && (hdir ^ tdir);
    assign dis_csr_io.full = full;
    assign enqueue = dis_csr_io.en & ~full & ~backendCtrl.redirect;
    assign head_n = head + 1;
    assign tail_n = tail + 1;
    assign bundle = dis_csr_io.data;
    assign status = dis_csr_io.status;
    assign select_en = (head != tail || (hdir ^ tdir)) &&
                        status_ram[head].robIdx == commitBus.robIdx &&
                        !backendCtrl.redirect;
    always_ff @(posedge clk)begin
        wakeup_en <= select_en & csr_wakeup_io.ready;
        wakeup_robIdx <= status_ram[head].robIdx;
    end
    LoopCompare #(`ROB_WIDTH) cmp_wakeup_older (wakeup_robIdx, backendCtrl.redirectIdx,  wakeup_older, wakeup_out);

    assign csr_wakeup_io.en = select_en;
    assign csr_wakeup_io.preg = status_ram[head].rs1;
    assign csr_wakeup_io.rd = status_ram[head].rd;

    always_ff @(posedge clk)begin
        issue_csr_io.en <= wakeup_en & (~backendCtrl.redirect | wakeup_older);
        rdata_n <= rdata;
    end
    assign issue_csr_io.rdata = csr_wakeup_io.data;
    assign issue_csr_io.bundle = rdata_n;

    MPRAM #(
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
        RobIdx out;
        LoopCompare #(`ROB_WIDTH) cmp_bigger (status_ram[i].robIdx, backendCtrl.redirectIdx, bigger[i], out);
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
            status_ram[tail].rs1 <= status.rs1;
            status_ram[tail].robIdx <= status.robIdx;
            status_ram[tail].rd <= bundle.rd;
        end
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