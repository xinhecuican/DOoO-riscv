`include "../../../../defines/defines.svh"

module DCache(
    input logic clk,
    input logic rst,
    DCacheLoadIO.dcache rio,
    DCacheStoreIO.dcache wio,
    DCacheAxi.cache axi_io,
    PTWRequest.cache ptw_io,
    BackendCtrl backendCtrl
);

    DCacheWayIO way_io [`ICACHE_WAY-1: 0]();
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_SET_WIDTH) loadIdx, tagvIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_LINE_WIDTH-2) loadOffset;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK) loadBankDecode;
    logic `N(`DCACHE_BANK) loadBank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_WAY) wayHit;
    logic `TENSOR(`DCACHE_WAY, `DCACHE_BANK, 32) rdata;

    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK_WIDTH)  s2_loadBank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_WAY_WIDTH) hitWay_encode;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) rvaddr;

    logic wreq, wreq_n, wreq_n2;
    logic miss_req, miss_req_n;
    logic `N(`DCACHE_SET_WIDTH) widx;
    logic `ARRAY(`DCACHE_WAY, `DCACHE_TAG+1) wtagv;
    logic `N(`PADDR_SIZE) waddr, waddr_n;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata, wdata_n;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) wmask, wmask_n;
    logic `N(`DCACHE_WAY) w_wayhit;
    logic whit;
    logic `N(`DCACHE_WAY_WIDTH) w_wayIdx;
    logic `N(`LOAD_PIPELINE) write_valid;

    logic refill_en_n;
    logic `N(`DCACHE_WAY_WIDTH) refill_way_n;
    logic `N(`PADDR_SIZE) refill_addr_n;
    logic `N(`DCACHE_BLOCK_SIZE) replace_addr;

    logic ptw_req, ptw_req_n;
    logic `N(`PADDR_SIZE) ptw_addr;

    DCacheMissIO miss_io();
    ReplaceQueueIO replace_queue_io();
    DCacheAxi dcache_axi_io();
    ReplaceIO #(
        .DEPTH(`DCACHE_SET),
        .WAY_NUM(`DCACHE_WAY),
        .READ_PORT(`LOAD_PIPELINE)
    ) replace_io();
    DCacheMiss dcache_miss(.*, .io(miss_io), .r_axi_io(dcache_axi_io.miss));
    PLRU #(
        .DEPTH(`DCACHE_SET),
        .WAY_NUM(`DCACHE_WAY),
        .READ_PORT(`LOAD_PIPELINE)
    ) plru(.*);
    ReplaceQueue replace_queue(.*, .io(replace_queue_io), .w_axi_io(dcache_axi_io.replace));
    assign axi_io.mar = dcache_axi_io.mar;
    assign axi_io.maw = dcache_axi_io.maw;
    assign axi_io.mw = dcache_axi_io.mw;
    assign axi_io.ar_valid = dcache_axi_io.ar_valid;
    assign axi_io.aw_valid = dcache_axi_io.aw_valid;
    assign axi_io.w_valid = dcache_axi_io.w_valid;
    assign axi_io.r_ready = dcache_axi_io.r_ready;
    assign axi_io.b_ready = dcache_axi_io.b_ready;
    assign dcache_axi_io.sr = axi_io.sr;
    assign dcache_axi_io.sb = axi_io.sb;
    assign dcache_axi_io.ar_ready = axi_io.ar_ready;
    assign dcache_axi_io.aw_ready = axi_io.aw_ready;
    assign dcache_axi_io.w_ready = axi_io.w_ready;
    assign dcache_axi_io.r_valid = axi_io.r_valid;
    assign dcache_axi_io.b_valid = axi_io.b_valid;

// read
    logic `N(`LOAD_PIPELINE) r_req, r_req_s3;
    logic req_bank_conflict;
    logic `N(`LOAD_PIPELINE) req_cancel;
generate
    /* UNPARAM */
    assign req_bank_conflict = (rio.req[0] & rio.req[1] & (rio.vaddr[0]`DCACHE_BANK_BUS == rio.vaddr[1]`DCACHE_BANK_BUS));
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign loadIdx[i] = rio.vaddr[i]`DCACHE_SET_BUS;
        assign loadOffset[i] = rio.vaddr[i][`DCACHE_LINE_WIDTH-1: `DCACHE_BYTE_WIDTH];
        assign tagvIdx[i] = ptw_io.req ? ptw_io.paddr`DCACHE_SET_BUS :
                            loadIdx[i];
        Decoder #(`DCACHE_BANK) decoder_offset (loadOffset[i], loadBankDecode[i]);
    end
    ParallelOR #(.WIDTH(`DCACHE_BANK), .DEPTH(`LOAD_PIPELINE)) or_bank(loadBankDecode, loadBank);

    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        DCacheWay way(
            .clk(clk),
            .rst(rst),
            .io(way_io[i])
        );
        for(genvar j=0; j<`LOAD_PIPELINE; j++)begin
            assign way_io[i].tagv_en[j] = rio.req[j] | ptw_io.req;
            assign way_io[i].tagv_index[j] = tagvIdx[j];
        end
        assign way_io[i].en = loadBank | {`DCACHE_BANK{miss_io.refill_en | ptw_io.req}};
        for(genvar j=0; j<`DCACHE_BANK; j++)begin
            /* UNPARAM */
            assign way_io[i].index[j] = ptw_io.req ? ptw_io.paddr`DCACHE_SET_BUS :
                                        {`DCACHE_SET_WIDTH{loadBankDecode[0][j] & rio.req[0] & ~req_cancel[0]}} & loadIdx[0] |
                                        {`DCACHE_SET_WIDTH{loadBankDecode[1][j] & rio.req[1] & ~req_cancel[1]}} & loadIdx[1];
        end
        assign rdata[i] = way_io[i].data;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_WAY; j++)begin
            logic `N(`DCACHE_TAG+1) tagv;
            assign tagv = way_io[j].tagv[i * (`DCACHE_TAG+1)+: (`DCACHE_TAG+1)];
            assign wayHit[i][j] = tagv[0] & (tagv[`DCACHE_TAG: 1] == rio.ptag[i]);
        end
        Encoder #(`DCACHE_WAY) encoder_hit_way (wayHit[i], hitWay_encode[i]);
        always_ff @(posedge clk)begin
            s2_loadBank[i] <= loadOffset[i];
            rvaddr[i] <= rio.vaddr[i];
            rio.rdata[i] <= rdata[hitWay_encode[i]][s2_loadBank[i]];
            r_req[i] <= rio.req[i] & ~write_valid[i] & ~rio.req_cancel[i] & ~req_cancel[i];
        end
        assign rio.hit[i] = |wayHit[i];
    end
endgenerate
    // load conflict detect
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign write_valid[i] = miss_io.refill_en |
                                ptw_io.req |
                                wreq_n & whit & (|wmask_n[rio.vaddr[i]`DCACHE_BANK_BUS]);
    end
endgenerate

    LoadIdx `N(`LOAD_PIPELINE) lqIdx;
    RobIdx `N(`LOAD_PIPELINE) robIdx;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) miss_addr;
    logic `N(`LOAD_PIPELINE) rhit;
    logic `N(`LOAD_PIPELINE) load_refill_conflict;
    logic `N(`LOAD_PIPELINE) load_refill_reply;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign req_cancel[i] = req_bank_conflict & ~rio.oldest[i];
        always_ff @(posedge clk)begin
            rio.conflict[i] <= write_valid[i] | req_cancel[i];
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        r_req_s3 <= r_req & ~rio.req_cancel_s2;
        lqIdx <= rio.lqIdx;
        robIdx <= rio.robIdx;
        rhit <= rio.hit;
        for(int i=0; i<`LOAD_PIPELINE; i++)begin
            miss_addr[i] <= ptw_req ? ptw_addr : {rio.ptag[i], rvaddr[i][11: 0]};
            load_refill_conflict[i] <= miss_io.refill_en & miss_io.refill_valid &
                                       ({rio.ptag[i], rvaddr[i]`DCACHE_SET_BUS} == miss_io.refillAddr`DCACHE_BLOCK_BUS);
        end
        load_refill_reply <= r_req_s3 & ~rio.req_cancel_s3 & load_refill_conflict;
    end
    assign rio.full = miss_io.rfull | load_refill_reply;

    assign miss_io.ren = r_req_s3 & ~rhit & ~rio.req_cancel_s3 & ~load_refill_conflict | ptw_req_n;
    assign miss_io.lqIdx = lqIdx;
    assign miss_io.robIdx = robIdx;
    assign miss_io.raddr = miss_addr;
    
    logic replace_hit;
    logic `N(`DCACHE_WAY_WIDTH) replace_hit_way;
    logic `N(`DCACHE_SET_WIDTH) replace_idx;
    always_ff @(posedge clk)begin
        `UNPARAM
        replace_io.hit_en[0] <= r_req_s3[0] & rio.hit[0] | wreq_n;
        replace_io.hit_en[1] <= r_req_s3[1] & rio.hit[1] | refill_en_n;
        replace_io.hit_way[0] <= wreq_n ? w_wayIdx : hitWay_encode[0];
        replace_io.hit_way[1] <= refill_en_n ? refill_way_n : hitWay_encode[1];
        replace_io.hit_index[0] <= wreq_n ? waddr_n`DCACHE_SET_BUS : miss_io.raddr[0]`DCACHE_SET_BUS;
        replace_io.hit_index[1] <= refill_en_n ? refill_addr_n`DCACHE_SET_BUS : miss_io.raddr[1]`DCACHE_SET_BUS;
    end

    assign rio.lq_en = miss_io.lq_en;
    assign rio.lqData = miss_io.lqData;
    assign rio.lqIdx_o = miss_io.lqIdx_o;

// write
    logic write_invalid;
    assign wreq = wio.req;
    assign waddr = wio.paddr;
    assign wdata = wio.data;
    assign wmask = wio.mask;
    assign widx = waddr`DCACHE_SET_BUS;
    
    assign replace_io.miss_index = miss_io.req_addr`DCACHE_SET_BUS;
    assign wio.valid = 1'b1;

generate
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        assign way_io[i].tagv_en[`LOAD_PIPELINE] = wreq | miss_io.refill_en;
        assign wtagv[i] = way_io[i].tagv[`LOAD_PIPELINE*(`DCACHE_TAG+1)+: (`DCACHE_TAG+1)];
        assign w_wayhit[i] = wtagv[i][0] & (wtagv[i][`DCACHE_TAG: 1] == waddr_n`DCACHE_TAG_BUS);
    end
endgenerate
    logic `N(`DCACHE_WAY) way_dirty;
    logic `N(`STORE_COMMIT_WIDTH) scIdx_n;
    always_ff @(posedge clk)begin
        wreq_n <= wio.req;
        miss_req_n <= miss_io.req;
        waddr_n <= waddr;
        wdata_n <= wdata;
        wmask_n <= wmask;
        scIdx_n <= wio.scIdx;
        // write_invalid <= miss_req_n && (waddr_n`DCACHE_BLOCK_BUS == waddr`DCACHE_BLOCK_BUS);
    end

    // 如果该项在replace queue中，那么它不能在miss queue中, 避免miss queue先写入导致错误
    logic refill_write_conflict;
    logic replace_conflict, replace_conflict_n;
    assign replace_queue_io.waddr = wio.paddr;
    always_ff @(posedge clk)begin
        refill_write_conflict <= replace_queue_io.refill_en & replace_queue_io.refill_dirty &
                                 (wio.paddr`DCACHE_BLOCK_BUS == replace_addr);
        replace_conflict_n <= replace_conflict & wreq_n & ~whit;
    end
    assign replace_conflict = refill_write_conflict | replace_queue_io.whit;

    // write miss
    assign whit = (|w_wayhit);
    Encoder #(`DCACHE_WAY) encoder_way (w_wayhit, w_wayIdx);
    assign miss_io.wen = ~whit & wreq_n & ~replace_conflict;
    assign miss_io.waddr = waddr_n;
    assign miss_io.wdata = wdata_n;
    assign miss_io.wmask = wmask_n;
    assign miss_io.req_success = miss_io.req & ~replace_queue_io.full;
    assign miss_io.replaceWay = replace_io.miss_way;
    assign miss_io.scIdx = scIdx_n;
    assign wio.conflict = miss_io.wfull | replace_conflict_n;
    assign wio.success = wreq_n2;
    assign replace_queue_io.en = miss_io.req;
    always_ff @(posedge clk)begin
        wreq_n2 <= wreq_n & whit;
        wio.conflictIdx <= scIdx_n;
    end

    // write hit
    logic `N(`DCACHE_WAY) refill_way;
    Decoder #(`DCACHE_WAY) decoder_refill_way (miss_io.refillWay, refill_way);
generate
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        logic `N(`DCACHE_SET_WIDTH) refillIdx;
        logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refillData;
        assign refillIdx = wreq_n & w_wayhit[i] ? waddr_n`DCACHE_SET_BUS :
                                                  miss_io.refillAddr`DCACHE_SET_BUS;
        assign refillData = wreq_n & w_wayhit[i] ? wdata_n : miss_io.refillData;
        for(genvar j=0; j<`DCACHE_BANK; j++)begin
            assign way_io[i].we[j] = {`DCACHE_BYTE{wreq_n & w_wayhit[i]}} & wmask_n[j] |
                                     {`DCACHE_BYTE{miss_io.refill_valid & miss_io.refill_en & refill_way[i]}};
            assign way_io[i].windex[j] = refillIdx;
        end
        assign way_io[i].wdata = refillData;
        assign way_dirty[i] = way_io[i].dirty;

        assign way_io[i].dirty_we = wreq_n & w_wayhit[i] | miss_io.refill_valid & miss_io.refill_en & refill_way[i];
        assign way_io[i].dirty_windex = refillIdx;
        assign way_io[i].dirty_wdata = (wreq_n & w_wayhit[i]) |
                                       (miss_io.refill_valid & miss_io.refill_en & refill_way[i] & miss_io.refill_dirty);
        assign way_io[i].dirty_en = miss_io.refill_en;
        assign way_io[i].dirty_index = miss_io.refillAddr`DCACHE_SET_BUS;

        assign way_io[i].tagv_we = miss_io.refill_valid & miss_io.refill_en & refill_way[i];
        assign way_io[i].tagv_windex =  wreq ? widx : miss_io.refillAddr`DCACHE_SET_BUS;
        assign way_io[i].tagv_wdata = {miss_io.refillAddr`DCACHE_TAG_BUS, 1'b1};
    end
endgenerate
    // refill
    assign miss_io.refill_valid = ~(wreq_n & (|(w_wayhit & refill_way))) & ~wio.req;
    always_ff @(posedge clk)begin
        wio.refill <= miss_io.refill_en & miss_io.refill_valid & miss_io.refill_dirty;
        wio.refillIdx <= miss_io.refill_scIdx;
    end

    // replace enqueue
    assign replace_addr = {wtagv[refill_way_n][`DCACHE_TAG: 1], refill_addr_n`DCACHE_SET_BUS};
    always_ff @(posedge clk)begin
        refill_en_n <= miss_io.refill_en & miss_io.refill_valid;
        refill_way_n <= miss_io.refillWay;
        refill_addr_n <= miss_io.refillAddr;
    end
    assign replace_queue_io.refill_en = refill_en_n;
    assign replace_queue_io.refill_dirty = wtagv[refill_way_n][0] & way_dirty[refill_way_n];
    assign replace_queue_io.addr = replace_addr;
    assign replace_queue_io.data = rdata[refill_way_n];

// ptw
    logic `N(`DCACHE_TAG) ptw_tag;
    logic `N(`DCACHE_WAY) ptw_way_hit;
    logic `N(`DCACHE_WAY_WIDTH) ptw_hit_way;

    always_ff @(posedge clk)begin
        ptw_tag <= ptw_io.paddr`DCACHE_TAG_BUS;
        ptw_req <= ptw_io.req;
        ptw_req_n <= ptw_req;
    end

    assign miss_io.ptw_req = ptw_req_n;

generate
    for(genvar j=0; j<`DCACHE_WAY; j++)begin
        assign ptw_way_hit[j] = way_io[j].tagv[0] & (way_io[j].tagv[`DCACHE_TAG: 1] == ptw_tag);
    end
endgenerate
    Encoder #(`DCACHE_WAY) encoder_ptw_hit (ptw_way_hit, ptw_hit_way);
    assign ptw_io.ready = 1'b1;
    assign ptw_io.full = ptw_req_n & miss_io.rfull[0];
    always_ff @(posedge clk)begin
        ptw_io.data_valid <= miss_io.ptw_refill | (ptw_req & (|ptw_way_hit));
        ptw_io.rdata <= miss_io.ptw_refill ? miss_io.ptw_refill_data : rdata[ptw_hit_way];
    end

`ifdef DIFFTEST

    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) dbg_wmask, dbg_wdatan;
    MaskExpand #(`DCACHE_BANK * `DCACHE_BYTE) mask_expand_dbg_wmask (wmask_n, dbg_wmask);
    assign dbg_wdatan = wdata_n & dbg_wmask;
    `LOG_ARRAY(T_DCACHE, dbg_refillData, miss_io.refillData, `DCACHE_BANK)
    `LOG_ARRAY(T_DCACHE, dbg_wdata, dbg_wdatan, `DCACHE_BANK)
    `Log(DLog::Debug, T_DCACHE, miss_io.refill_en & miss_io.refill_valid,
        $sformatf("dcache refill. [%8h %d %b] %s", miss_io.refillAddr, miss_io.refillWay, miss_io.refill_dirty, dbg_refillData))
    `Log(DLog::Debug, T_DCACHE, wreq_n & whit,
        $sformatf("dcache write. [%h %d] %s", waddr_n, w_wayIdx, dbg_wdata))
`endif
endmodule