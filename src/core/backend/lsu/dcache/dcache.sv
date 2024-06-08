`include "../../../../defines/defines.svh"

module DCache(
    input logic clk,
    input logic rst,
    DCacheLoadIO.dcache rio,
    DCacheStoreIO.dcache wio,
    DCacheAxi.cache axi_io
);

    DCacheWayIO way_io [`ICACHE_WAY-1: 0]();
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_SET_WIDTH) loadIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_LINE_WIDTH-2) loadOffset;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK) loadBankDecode;
    logic `N(`DCACHE_BANK) loadBank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_WAY) wayHit;
    logic `TENSOR(`DCACHE_WAY, `DCACHE_BANK, 32) rdata;

    logic `N(`DCACHE_BANK)  s2_loadBank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_WAY_WIDTH) hitWay_encode;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) rvaddr;

    logic wreq, wreq_n, wreq_n2;
    logic miss_req, miss_req_n;
    logic `N(`DCACHE_SET_WIDTH) widx;
    logic `ARRAY(`DCACHE_WAY, `DCACHE_TAG+1) wtagv;
    logic `N(`VADDR_SIZE) waddr, waddr_n;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata, wdata_n;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) wmask, wmask_n;
    logic `N(`DCACHE_WAY) w_wayhit;
    logic whit;
    logic `N(`DCACHE_WAY_WIDTH) w_wayIdx;
    logic replace_wb_en;
    logic `N(`LOAD_PIPELINE) write_valid;

    DCacheMissIO miss_io();
    ReplaceQueueIO replace_queue_io();
    ReplaceIO replace_io();
    DCacheMiss dcache_miss(.*, .io(miss_io), .r_axi_io(axi_io.miss));
    PLRU plru(.*, .io(replace_io));
    ReplaceQueue replace_queue(.*, .io(replace_queue_io), .w_axi_io(axi_io.replace));

// read
    logic `N(`LOAD_PIPELINE) r_req;
    logic req_bank_conflict;
generate
    /* UNPARAM */
    assign req_bank_conflict = (rio.req[0] & rio.req[1] & (rio.vaddr[0]`DCACHE_BANK_BUS == rio.vaddr[1]`DCACHE_BANK_BUS));
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign loadIdx[i] = rio.vaddr`DCACHE_SET_BUS;
        assign loadOffset[i] = rio.vaddr[`DCACHE_LINE_WIDTH-1: 2];
        Decoder #(`DCACHE_BANK) decoder_offset (loadOffset[i], loadBankDecode[i]);
    end
    ParallelOR #(.WIDTH(`DCACHE_BANK), .DEPTH(`LOAD_PIPELINE)) or_bank(loadBankDecode, loadBank);

    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        DCacheWay way(
            .clk(clk),
            .rst(rst),
            .io(way_io[i])
        );
        assign way_io[i].tagv_en = rio.req;
        assign way_io[i].tagv_index = loadIdx;
        assign way_io[i].en = loadBank;
        for(genvar j=0; j<`DCACHE_BANK; j++)begin
            /* UNPARAM */
            assign way_io[i].index[j] = replace_wb_en ? waddr_n`DCACHE_SET_BUS :
                                        {`DCACHE_SET_WIDTH{loadBankDecode[0][j] & rio.req[0]}} & loadIdx[0] |
                                        {`DCACHE_SET_WIDTH{loadBankDecode[1][j] & rio.req[1] & ~req_bank_conflict}} & loadIdx[1];
        end
        assign rdata[i] = way_io[i].data;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_WAY; j++)begin
            assign wayHit[i][j] = way_io[j].tagv[i][0] & (way_io[j].tagv[i][`DCACHE_TAG: 1] == rio.ptag[i]);
        end
        Encoder #(`DCACHE_BANK) encoder_hit_way (wayHit[i], hitWay_encode[i]);
        always_ff @(posedge clk)begin
            r_req[i] <= rio.req[i];
            rvaddr[i] <= rio.vaddr[i];
            rio.rdata[i] <= rdata[hitWay_encode[i]][s2_loadBank[i]];
        end
        assign rio.hit[i] = |wayHit[i];
    end
endgenerate
    // load conflict detect
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign write_valid[i] = replace_wb_en | wreq_n & whit & (|wmask[rio.vaddr`DCACHE_BANK_BUS]);
    end
endgenerate
    /* UNPARAM */
    always_ff @(posedge clk)begin
        rio.conflict[0] <= write_valid;
        rio.conflict[1] <= write_valid | req_bank_conflict;
    end
    assign rio.full = miss_io.rfull;

    assign miss_io.ren = r_req & ~rio.hit;
    assign miss_io.lqIdx = rio.lqIdx;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign miss_io.raddr[i] = {rio.ptag, rvaddr[11: 0]};
    end
endgenerate
    assign rio.lq_en = miss_io.lq_en;
    assign rio.lqData = miss_io.lqData;
    assign rio.lqIdx_o = miss_io.lqIdx_o;

// write
    assign wreq = wio.req | miss_io.req;
    assign waddr = miss_io.req ? miss_io.req_addr : wio.paddr;
    assign wdata = wio.data;
    assign wmask = wio.mask;
    assign widx = miss_io.req ? miss_io.req_addr`DCACHE_SET_BUS : waddr`DCACHE_SET_BUS;

    assign wio.valid = ~miss_io.req;

generate
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        assign way_io[i].tagv_en[`LOAD_PIPELINE] = wreq;
        assign way_io[i].tagv_index[`LOAD_PIPELINE] = widx;
        assign way_io[i].dirty_en = miss_io.req;
        assign way_io[i].dirty_index = miss_io.req_addr`DCACHE_SET_BUS;
        
        assign wtagv[i] = way_io[i].tagv[`LOAD_PIPELINE];
        assign w_wayhit[i] = wtagv[i][0] & (wtagv[i][`DCACHE_TAG: 1] == waddr_n`DCACHE_TAG_BUS);
    end
endgenerate
    logic `N(`DCACHE_WAY) way_dirty;
    logic `N(`STORE_COMMIT_WIDTH) scIdx_n;
    always_ff @(posedge clk)begin
        wreq_n <= wio.req & ~miss_io.req;
        miss_req_n <= miss_io.req;
        waddr_n <= waddr;
        wdata_n <= wdata;
        wmask_n <= wmask_n;
        scIdx_n <= wio.scIdx;
    end
    // write miss
    assign whit = |w_wayhit;
    Encoder #(`DCACHE_WAY) encoder_way (w_wayhit, w_wayIdx);
    assign miss_io.wen = ~whit & wreq_n;
    assign miss_io.waddr = waddr_n;
    assign miss_io.wdata = wdata_n;
    assign miss_io.wmask = wmask_n;
    assign miss_io.req_success = miss_req_n & ~replace_queue_io.full;
    assign miss_io.write_ready = ~way_dirty[replace_io.miss_way];
    assign miss_io.replaceWay = replace_io.miss_way;
    assign wio.conflict = miss_io.wfull;
    assign wio.success = wreq_n2 & ~miss_io.wfull;
    always_ff @(posedge clk)begin
        wreq_n2 <= wreq_n;
        wio.conflictIdx <= scIdx_n;
    end

    assign replace_wb_en = miss_req_n & way_dirty[replace_io.miss_way];
    logic `N(`DCACHE_WAY_WIDTH) wayIdx;
    always_ff @(posedge clk)begin
        replace_queue_io.en <= replace_wb_en;
        replace_queue_io.addr <= waddr_n;
        wayIdx <= replace_io.miss_way;
    end
    assign replace_queue_io.data = rdata[wayIdx];

    // write hit
generate
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        for(genvar j=0; j<`DCACHE_BANK; j++)begin
            assign way_io[i].we[j] = {`DCACHE_BYTE{wreq_n & w_wayhit[i]}} & wmask_n[j] |
                                     {`DCACHE_BYTE{miss_io.refill_valid & miss_io.refill_en & miss_io.refillWay[i]}};
        end
        assign way_io[i].windex = waddr_n`DCACHE_SET_BUS | 
                                  {`DCACHE_SET_WIDTH{miss_io.refill_valid}} & miss_io.refillAddr`DCACHE_SET_BUS;
        assign way_io[i].wdata = wdata_n |
                                 {`DCACHE_BANK*`DCACHE_BITS{miss_io.refill_valid}} & miss_io.refillData;
        assign way_dirty[i] = way_io[i].dirty;

        assign way_io[i].dirty_we = wreq_n & w_wayhit[i] | miss_io.refill_valid & miss_io.refill_en & miss_io.refillWay[i];
        assign way_io[i].dirty_windex = waddr_n`DCACHE_SET_BUS | 
                                        {`DCACHE_SET_WIDTH{miss_io.refill_valid}} & miss_io.refillAddr`DCACHE_SET_BUS;
        assign way_io[i].dirty_wdata = wreq_n & w_wayhit[i];

        assign way_io[i].tagv_we = miss_io.refill_valid & miss_io.refill_en;
        assign way_io[i].tagv_windex = miss_io.refillAddr`DCACHE_SET_BUS;
        assign way_io[i].tagv_wdata = {miss_io.refillAddr`DCACHE_TAG_BUS, 1'b1};
    end
endgenerate
    // refill
    assign miss_io.refill_valid = ~(wreq_n & (|(w_wayhit & miss_io.refillWay))) & ~miss_io.req;

endmodule