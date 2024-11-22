`include "../../defines/defines.svh"

module RAS(
    input logic clk,
    input logic rst,
    BpuRASIO.ras ras_io
);
    logic `N(`RAS_WIDTH) top, top_p1, top_n1;
    logic `N(`RAS_WIDTH) bottom, bottom_n1, redirect_bottom_n1;
    logic `N(`RAS_WIDTH) redirect_p1, redirect_n1;
    logic bdir, tdir, bdir_n, rbdir_n;
    logic `N(`RAS_WIDTH) waddr;
    RasEntry entry, updateEntry;
    RasType squashType;
    RasRedirectInfo r;
    logic we;
    logic full, empty, redirect_full, redirect_empty;
    logic `VADDR_BUS squash_target;

    assign top_p1 = top - 1;
    assign top_n1 = top + 1;
    assign redirect_p1 = r.rasTop - 1;
    assign redirect_n1 = r.rasTop + 1;
    LoopAdder #(`RAS_WIDTH, 1) adder_bottom(1'b1, {bottom, bdir}, {bottom_n1, bdir_n});
    LoopAdder #(`RAS_WIDTH, 1) adder_rbottom(1'b1, {r.rasBottom, r.ras_bdir}, {redirect_bottom_n1, rbdir_n});
    assign full = (bdir ^ tdir) & (top == bottom);
    assign empty = (bdir == tdir) & (top == bottom);
    assign r = ras_io.squashInfo.redirectInfo.rasInfo;
    assign redirect_full = (r.ras_bdir ^ r.ras_tdir) & (r.rasTop == r.rasBottom);
    assign redirect_empty = (r.ras_bdir == r.ras_tdir) & (r.rasTop == r.rasBottom);
    assign waddr = ras_io.squash && squashType == POP_PUSH ? r.rasTop - 1 :
                   ras_io.squash ? r.rasTop :
                   ras_io.ras_type == POP_PUSH ? top_p1 : top;
    assign squash_target = ras_io.squashInfo.start_addr + {ras_io.squashInfo.offset, {`INST_OFFSET{1'b0}}} + 
`ifdef RVC
    {~ras_io.squashInfo.rvc, ras_io.squashInfo.rvc, 1'b0}
`else
    4
`endif
;
    assign updateEntry.pc = ras_io.squash ? squash_target : ras_io.target;
    assign squashType = ras_io.squashInfo.ras_type;
    assign we = ~ras_io.squash & ras_io.request & ras_io.ras_type[1] | 
                ras_io.squash & squashType[1];
    assign ras_io.en = ~empty;
    assign ras_io.rasInfo.rasTop = top;
    assign ras_io.rasInfo.ras_tdir = tdir;
    assign ras_io.rasInfo.rasBottom = bottom;
    assign ras_io.rasInfo.ras_bdir = bdir;
    assign ras_io.entry = entry;
    SDPRAM #(
        .WIDTH($bits(RasEntry)),
        .DEPTH(`RAS_SIZE)
    ) ras (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .we(we),
        .addr0(waddr),
        .addr1(top_p1),
        .wdata(updateEntry),
        .rdata1(entry),
        .ready()
    );

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            top <= 0;
            bottom <= 0;
            bdir <= 0;
            tdir <= 0;
        end
        else begin
            if(ras_io.squash)begin
                if(squashType == POP && !redirect_empty)begin
                    top <= r.rasTop - 1;
                    tdir <= redirect_p1[`RAS_WIDTH-1] & ~r.rasTop[`RAS_WIDTH-1] ? ~r.ras_tdir : r.ras_bdir;
                end
                else if(ras_io.ras_type == PUSH)begin
                    top <= r.rasTop + 1;
                    tdir <= r.rasTop[`RAS_WIDTH-1] & ~redirect_n1[`RAS_WIDTH-1] ? ~r.ras_tdir : r.ras_bdir;
                end
                else begin
                    top <= r.rasTop;
                    tdir <= r.ras_tdir;
                end
                if(ras_io.ras_type == PUSH && redirect_full)begin
                    bottom <= redirect_bottom_n1;
                    bdir <= rbdir_n;
                end
                else begin
                    bottom <= r.rasBottom;
                    bdir <= r.ras_bdir;
                end
            end
            else if(ras_io.en)begin
                if(ras_io.ras_type == POP && !empty)begin
                    top <= top_p1;
                    tdir <= top_p1[`RAS_WIDTH-1] & ~top[`RAS_WIDTH-1] ? ~tdir : tdir;
                end
                else if(ras_io.ras_type == PUSH)begin
                    top <= top_n1;
                    tdir <= top[`RAS_WIDTH-1] & ~top_n1[`RAS_WIDTH-1] ? ~tdir : tdir;
                    if(full)begin
                        bottom <= bottom_n1;
                        bdir <= bdir_n;
                    end
                end
            end
        end
    end

    `Log(DLog::Debug, T_RAS, ~ras_io.squash & ras_io.request & ras_io.ras_type != NONE,
        $sformatf("ras lookup. %d %d %b %b %h %h", top, bottom, tdir, bdir, ras_io.target, ras_io.ras_type))
    `Log(DLog::Debug, T_RAS, ras_io.squash & squashType != NONE,
        $sformatf("ras squash. %h %h", squash_target, squashType))

endmodule