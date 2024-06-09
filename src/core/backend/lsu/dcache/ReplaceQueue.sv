`include "../../../../defines/defines.svh"

interface ReplaceQueueIO;
    logic en;
    logic `N(`DCACHE_MISS_WIDTH) missIdx;
    logic `N(`VADDR_SIZE) addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    logic full;

    logic wend;
    logic `N(`DCACHE_MISS_WIDTH) missIdx_o;

    modport queue (input en, missIdx, addr, data, output wend, missIdx_o, full);
    modport miss (input full, wend, missIdx_o, output missIdx);
endinterface

module ReplaceQueue(
    input logic clk,
    input logic rst,
    ReplaceQueueIO.queue io,
    DCacheAxi.replace w_axi_io
);
    localparam TRANSFER_BANK = `DCACHE_LINE / `DATA_BYTE;
    typedef struct packed {
        logic `N(`DCACHE_MISS_WIDTH) missIdx;
        logic `N(`VADDR_SIZE) addr;
        logic `ARRAY(TRANSFER_BANK, `XLEN) data;
    } ReplaceEntry;

    ReplaceEntry entrys `N(`DCACHE_REPLACE_SIZE);
    logic `N(`DCACHE_REPLACE_WIDTH) bhead, head, tail, head_n, bhead_n, tail_n;
    logic bhdir, hdir, tdir;
    logic full;

    ReplaceEntry newEntry;

    assign full = (bhead == tail) & (bhdir ^ tdir);
    assign io.full = full;
    assign bhead_n = bhead + 1;
    assign head_n = head + 1;
    assign tail_n = tail + 1;
    assign newEntry.missIdx = io.missIdx;
    assign newEntry.addr = io.addr;
    assign newEntry.data = io.data;
    assign io.wend = w_axi_io.sb.valid;
    assign io.missIdx_o = entrys[bhead].missIdx;
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            bhead <= 0;
            head <= 0;
            tail <= 0;
            bhdir <= 0;
            hdir <= 0;
            tdir <= 0;
            entrys <= '{default: 0};
        end
        else begin
            if(io.en & ~full)begin
                tail <= tail_n;
                tdir <= tail[`DCACHE_REPLACE_WIDTH-1] & ~tail_n[`DCACHE_REPLACE_WIDTH-1] ? ~tdir : tdir;
                entrys[tail] <= newEntry;
            end

            if(w_axi_io.mw.valid & w_axi_io.sw.ready & w_axi_io.mw.last)begin
                head <= head + 1;
                hdir <= head[`DCACHE_REPLACE_WIDTH-1] & ~head_n[`DCACHE_REPLACE_WIDTH-1] ? ~hdir : hdir;
            end

            if(w_axi_io.sb.valid)begin
                bhead <= bhead_n;
                bhdir <= bhead[`DCACHE_REPLACE_WIDTH-1] & ~bhead_n[`DCACHE_REPLACE_WIDTH-1] ? ~bhdir : bhdir;
            end
        end
    end

    logic aw_valid;
    logic `N($clog2(TRANSFER_BANK)) widx;
    logic wvalid;
    logic wlast;
    logic processValid;
    ReplaceEntry processEntry;

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            aw_valid <= 1'b0;
            widx <= 0;
            wlast <= 0;
            wvalid <= 0;
            processValid <= 0;
            processEntry <= 0;
        end
        else begin
            if(!processValid && (head != tail || (hdir ^ tdir)))begin
                processValid <= 1'b1;
                aw_valid <= 1'b1;
                processEntry <= entrys[head];
            end

            if(w_axi_io.maw.valid & w_axi_io.saw.ready)begin
                aw_valid <= 1'b0;
                wvalid <= 1'b1;
            end

            if(w_axi_io.mw.valid & w_axi_io.sw.ready)begin
                widx <= widx + 1;
                if(wlast)begin
                    wvalid <= 1'b0;
                    processValid <= 1'b0;
                end
                if(widx == TRANSFER_BANK - 2)begin
                    wlast <= 1'b1;
                end
                else begin
                    wlast <= 1'b0;
                end
            end
        end
    end

    assign w_axi_io.maw.valid = aw_valid;
    assign w_axi_io.maw.id = `DCACHE_ID;
    assign w_axi_io.maw.addr = entrys[head].addr;
    assign w_axi_io.maw.len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign w_axi_io.maw.size = $clog2(`DATA_BYTE);
    assign w_axi_io.maw.burst = 2'b01;
    assign w_axi_io.maw.lock = 2'b0;
    assign w_axi_io.maw.cache = 4'b0;
    assign w_axi_io.maw.prot = 0;

    assign w_axi_io.mw.data = processEntry.data[widx];
    assign w_axi_io.mw.wstrb = {`DATA_BYTE{1'b1}};
    assign w_axi_io.mw.last = wlast;
    assign w_axi_io.mw.valid = wvalid;
    assign w_axi_io.mw.user = 0;

    assign w_axi_io.mb.ready = 1'b1;
endmodule