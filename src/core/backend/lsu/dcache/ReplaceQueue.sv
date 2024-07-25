`include "../../../../defines/defines.svh"

interface ReplaceQueueIO;
    logic en;
    logic refill_en;
    logic refill_dirty;
    logic `N(`DCACHE_TAG+`DCACHE_SET_WIDTH) addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    logic `N(`DCACHE_REPLACE_WIDTH) idx;
    logic full;

    logic `N(`PADDR_SIZE) waddr;
    logic whit;

    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx;

    modport queue (input en, refill_en, refill_dirty, addr, data, replace_idx, waddr, output idx, whit,  full);
    modport miss (input full, idx, output replace_idx);
endinterface

module ReplaceQueue(
    input logic clk,
    input logic rst,
    ReplaceQueueIO.queue io,
    DCacheAxi.replace w_axi_io
);
    localparam TRANSFER_BANK = `DCACHE_LINE / `DATA_BYTE;
    typedef struct packed {
        logic `N(`DCACHE_TAG+`DCACHE_SET_WIDTH) addr;
        logic `ARRAY(TRANSFER_BANK, `XLEN) data;
    } ReplaceEntry;

    ReplaceEntry entrys `N(`DCACHE_REPLACE_SIZE);
    logic `N(`DCACHE_REPLACE_SIZE) dataValid, dirty;
    logic `N(`DCACHE_REPLACE_WIDTH) bhead, tail, bhead_n, tail_n;
    logic bhdir, tdir;
    logic full;

    ReplaceEntry newEntry;

    assign full = (bhead == tail) & (bhdir ^ tdir);
    assign io.full = full;
    assign bhead_n = bhead + 1;
    assign tail_n = tail + 1;
    assign newEntry.addr = io.addr;
    assign newEntry.data = io.data;
    assign io.idx = tail;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            bhead <= 0;
            tail <= 0;
            bhdir <= 0;
            tdir <= 0;
            entrys <= '{default: 0};
            dataValid <= 0;
            dirty <= 0;
        end
        else begin
            if(io.en & ~full)begin
                tail <= tail_n;
                tdir <= tail[`DCACHE_REPLACE_WIDTH-1] & ~tail_n[`DCACHE_REPLACE_WIDTH-1] ? ~tdir : tdir;
            end

            if(io.refill_en)begin
                dataValid[io.replace_idx] <= 1'b1;
                dirty[io.replace_idx] <= io.refill_dirty;
                entrys[io.replace_idx] <= newEntry;
            end

            if(w_axi_io.sb.valid | dataValid[bhead] & ~dirty[bhead])begin
                bhead <= bhead_n;
                bhdir <= bhead[`DCACHE_REPLACE_WIDTH-1] & ~bhead_n[`DCACHE_REPLACE_WIDTH-1] ? ~bhdir : bhdir;
                dataValid[bhead] <= 1'b0;
                dirty[bhead] <= 1'b0;
            end
        end
    end

// write conflict detect
    logic `N(`DCACHE_REPLACE_SIZE) hit;
generate
    for(genvar i=0; i<`DCACHE_REPLACE_SIZE; i++)begin
        assign hit[i] = dataValid[i] & dirty[i] & (io.waddr`DCACHE_BLOCK_BUS == entrys[i].addr);
    end
    always_ff @(posedge clk)begin
        io.whit <= |hit;
    end
endgenerate

// axi
    logic aw_valid;
    logic `N($clog2(TRANSFER_BANK)) widx;
    logic wvalid;
    logic wlast;
    logic processValid;
    ReplaceEntry processEntry;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            aw_valid <= 1'b0;
            widx <= 0;
            wlast <= 0;
            wvalid <= 0;
            processValid <= 0;
            processEntry <= 0;
        end
        else begin
            if(!processValid && (bhead != tail || (bhdir ^ tdir)) && dataValid[bhead] && dirty[bhead])begin
                processValid <= 1'b1;
                aw_valid <= 1'b1;
                processEntry <= entrys[bhead];
            end

            if(w_axi_io.maw.valid & w_axi_io.saw.ready)begin
                aw_valid <= 1'b0;
                wvalid <= 1'b1;
            end

            if(w_axi_io.sb.valid)begin
                processValid <= 1'b0;
            end

            if(w_axi_io.mw.valid & w_axi_io.sw.ready)begin
                widx <= widx + 1;
                if(wlast)begin
                    wvalid <= 1'b0;
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
    assign w_axi_io.maw.addr = {processEntry.addr, {`DCACHE_LINE_WIDTH{1'b0}}};
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

    `LOG_ARRAY(T_DCACHE, dbg_data, newEntry.data, TRANSFER_BANK)
    `Log(DLog::Debug, T_DCACHE, io.refill_en & io.refill_dirty,
        $sformatf("dcache replace. [%h] %s", newEntry.addr << `DCACHE_LINE_WIDTH, dbg_data))
endmodule