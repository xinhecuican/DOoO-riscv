`include "../../../defines/defines.svh"

module CsrIssueQueue(
    input logic clk,
    input logic rst,
    DisCsrIO.issue dis_csr_io,
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
    logic `N(`CSR_ISSUE_WIDTH) head, tail, head_n, tail_n;
    logic hdir, tdir;
    logic `N(`CSR_ISSUE_SIZE) dirTable;
    logic full;
    logic enqueue;
    CsrIssueBundle rdata;

    assign full = head == tail && (hdir ^ tdir);
    assign enqueue = dis_csr_io.en & ~full & ~backendCtrl.redirect;
    assign head_n = head + 1;
    assign tail_n = tail + 1;
    assign select_en = (head != tail || (hdir ^ tdir)) &&
                        status_ram[head].robIdx == commitBus.robIdx;
    always_ff @(posedge clk)begin
        wakeup_en <= select_en & csr_wakeup_io.ready;
    end

    assign csr_wakeup_io.en = select_en;
    assign csr_wakeup_io.preg = status_ram[head].rs1;
    assign csr_wakeup_io.rd = status_ram[head].rd;

    always_ff @(posedge clk)begin
        issue_csr_io.en <= wakeup_en;
    end
    assign issue_csr_io.rdata = csr_wakeup_io.data;
    assign issue_csr_io.bundle = rdata;

    MPRAM #(
        .WIDTH($bits(CsrIssueBundle)),
        .DEPTH(`CSR_ISSUE_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(1)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .en(wakeup_en),
        .raddr(head),
        .rdata(rdata),
        .we(enqueue),
        .waddr(tail),
        .wdata(dis_csr_io.bundle)
    );

// redirect

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            hdir <= 0;
            tdir <= 0;
            dirTable <= 0;
        end
        else begin
            if(enqueue)begin
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