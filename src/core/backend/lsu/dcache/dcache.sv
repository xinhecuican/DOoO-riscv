`include "../../../../defines/defines.svh"

module DCache(
    input logic clk,
    input logic rst,
    DCacheLoadIO.dcache rio,
    DCacheStoreIO.dcache wio,
`ifdef RVA
    DCacheAmoIO.dcache amo_io,
`endif
    CacheBus.master axi_io,
    NativeSnoopIO.master snoop_io,
    input BackendCtrl backendCtrl
);

    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_SET_WIDTH) loadIdx;
    logic `ARRAY(`LOAD_PIPELINE+1, `DCACHE_SET_WIDTH) tagvIdx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_LINE_WIDTH-2) loadOffset;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK) loadBankDecode;
    logic `N(`DCACHE_BANK) loadBank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_WAY) wayHit;
    logic `TENSOR(`DCACHE_WAY, `DCACHE_BANK, 32) rdata;

    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK_WIDTH)  s2_loadBank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_WAY_WIDTH) hitWay_encode;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) rvaddr;

    logic wreq, wreq_n, wreq_n2, cache_wreq;
    logic `N(`DCACHE_WAY) cache_wway;
    logic miss_req, miss_req_n;
    logic `N(`DCACHE_SET_WIDTH) widx;
    logic `ARRAY(`DCACHE_WAY, `DCACHE_TAG+1) wtagv;
    logic `N(`PADDR_SIZE) waddr, waddr_n;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata, wdata_n;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) wmask, wmask_n;
    logic `N(`DCACHE_WAY) w_wayhit;
    logic whit;
    logic `N(`DCACHE_WAY_WIDTH) w_wayIdx, missWay_encode;
    logic `N(`LOAD_PIPELINE) write_valid;

    logic refill_en_n;
    logic `N(`DCACHE_WAY) refill_way;
    logic `N(`DCACHE_WAY_WIDTH) refill_way_n;
    logic `N(`PADDR_SIZE) refill_addr_n;
    logic `N(`DCACHE_BLOCK_SIZE) replace_addr;

    logic snoop_req;
    logic `N(`PADDR_SIZE) snoop_addr;
    logic `N(`DCACHE_WAY) way_dirty;

`ifdef RVA
    logic amo_req, islr, issc, amo_req_n;
    logic `N(`PADDR_SIZE) amo_addr;
    logic `N(`DCACHE_BYTE) amo_mask;
    logic `N(`DCACHE_BANK) amo_en, amo_bank, amo_bank_n;
    logic `N(`XLEN) amo_data;
    logic `N(`AMOOP_WIDTH) amoop;
    logic `N(`DCACHE_BITS) amo_rdata, amo_res, amo_wdata;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) amo_wmask;
    logic `N(`DCACHE_WAY) amo_wway;

    logic reservation_set;
    logic `N(`PADDR_SIZE-`DCACHE_BYTE) reservation_addr;
    logic `N(`DCACHE_BYTE) reservation_mask;
    logic sc_match;
`endif


    DCacheMissIO miss_io();
    ReplaceQueueIO replace_queue_io();
    CacheBus #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, `DCACHE_WAY_WIDTH
    ) dcache_axi_io();
    ReplaceIO #(
        .DEPTH(`DCACHE_SET),
        .WAY_NUM(`DCACHE_WAY),
        .READ_PORT(`LOAD_PIPELINE)
    ) replace_io();
    DCacheMiss dcache_miss(.*, .io(miss_io), .r_axi_io(dcache_axi_io.masterr));
    PLRU #(
        .DEPTH(`DCACHE_SET),
        .WAY_NUM(`DCACHE_WAY),
        .READ_PORT(`LOAD_PIPELINE)
    ) plru(.*);
    ReplaceQueue replace_queue(.*, .io(replace_queue_io), .w_axi_io(dcache_axi_io.masterw));
    `CACHE_ASSIGN_REQ_INTF(axi_io, dcache_axi_io)
    `CACHE_ASSIGN_RESP_INTF(dcache_axi_io, axi_io)

// read
    logic `N(`LOAD_PIPELINE) r_req, r_req_s3;
    logic req_bank_conflict;
    logic `N(`LOAD_PIPELINE) req_cancel;
    `UNPARAM(LOAD_PIPELINE, 2, "detect req bank conflict")
    assign req_bank_conflict = (rio.req[0] & rio.req[1] & (rio.vaddr[0]`DCACHE_BANK_BUS == rio.vaddr[1]`DCACHE_BANK_BUS));
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign loadIdx[i] = rio.vaddr[i]`DCACHE_SET_BUS;
        assign loadOffset[i] = rio.vaddr[i][`DCACHE_LINE_WIDTH-1: `DCACHE_BYTE_WIDTH];
        Decoder #(`DCACHE_BANK) decoder_offset (loadOffset[i], loadBankDecode[i]);
    end
endgenerate
    ParallelOR #(.WIDTH(`DCACHE_BANK), .DEPTH(`LOAD_PIPELINE)) or_bank(loadBankDecode, loadBank);

    logic `N(`LOAD_PIPELINE+1) tagv_en;
    logic `N(`DCACHE_WAY) tagv_we;
    logic `TENSOR(`LOAD_PIPELINE+1, `DCACHE_WAY, `DCACHE_TAG+1) tagv;
    logic `TENSOR(`DCACHE_BANK, `DCACHE_WAY, `DCACHE_BYTE) data_we;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_SET_WIDTH) data_index;
    logic `N(`DCACHE_SET_WIDTH) refillIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refillData;
    logic `TENSOR(`DCACHE_BANK, `DCACHE_WAY, `DCACHE_BITS) data_rdata;
    logic `N(`DCACHE_WAY) dirty_we, dirty_wdata;

generate
    
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign tagv_en[i] = rio.req[i];
        assign tagvIdx[i] = miss_io.refill_en & miss_io.refill_valid ? miss_io.refillAddr`DCACHE_SET_BUS :
                            loadIdx[i];
    end
    assign tagv_en[`LOAD_PIPELINE] = wreq | miss_io.refill_en;
    assign tagvIdx[`LOAD_PIPELINE] = wreq ? widx : miss_io.refillAddr`DCACHE_SET_BUS;
    assign tagv_we = {`DCACHE_WAY{miss_io.refill_valid & miss_io.refill_en}} & refill_way;
    for(genvar i=0; i<`DCACHE_BANK; i++)begin
        for(genvar j=0; j<`DCACHE_WAY; j++)begin
            assign data_we[i][j] = {`DCACHE_BYTE{cache_wreq & cache_wway[j]}} & wmask_n[i] |
                                   {`DCACHE_BYTE{miss_io.refill_valid & miss_io.refill_en & refill_way[j]}};
            assign rdata[j][i] = data_rdata[i][j];
        end
        assign data_index[i] = snoop_req ? snoop_addr`DCACHE_SET_BUS : 
                               |data_we[i] ? refillIdx : 
`ifdef RVA
                               amo_en[i] ? amo_io.paddr`DCACHE_SET_BUS :
`endif
                               {`DCACHE_SET_WIDTH{loadBankDecode[0][i] & rio.req[0] & ~req_cancel[0]}} & loadIdx[0] |
                            {`DCACHE_SET_WIDTH{loadBankDecode[1][i] & rio.req[1] & ~req_cancel[1]}} & loadIdx[1];
    end
endgenerate

    assign refillIdx = cache_wreq & (|cache_wway) ? waddr_n`DCACHE_SET_BUS :
                                                miss_io.refillAddr`DCACHE_SET_BUS;
    assign refillData = cache_wreq & (|cache_wway) ? wdata_n : miss_io.refillData;
    assign dirty_we = {`DCACHE_WAY{cache_wreq}} & cache_wway | 
                      {`DCACHE_WAY{miss_io.refill_valid & miss_io.refill_en}} & refill_way;
    assign dirty_wdata = ({`DCACHE_WAY{cache_wreq}} & cache_wway) |
                         ({`DCACHE_WAY{miss_io.refill_valid & miss_io.refill_en & miss_io.refill_dirty}} & refill_way);

    DCacheData cache_data (
        .clk,
        .rst,
        .tagv_en,
        .tagv_we,
        .tagv_index(tagvIdx),
        .tagv_wdata({miss_io.refillAddr`DCACHE_TAG_BUS, 1'b1}),
        .tagv,
`ifdef RVA
        .en((loadBank | amo_en | {`DCACHE_BANK{miss_io.refill_en | snoop_req}})),
`else
        .en((loadBank | {`DCACHE_BANK{miss_io.refill_en | snoop_req}})),
`endif
        .we(data_we),
        .index(data_index),
        .wdata(refillData),
        .data(data_rdata),
        .dirty_en(miss_io.refill_en),
        .dirty_index(miss_io.refillAddr`DCACHE_SET_BUS),
        .dirty(way_dirty),
        .dirty_we,
        .dirty_windex(refillIdx),
        .dirty_wdata
    );
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_WAY; j++)begin
            assign wayHit[i][j] = tagv[i][j][0] & (tagv[i][j][`DCACHE_TAG: 1] == rio.ptag[i]);
        end
        Encoder #(`DCACHE_WAY) encoder_hit_way (wayHit[i], hitWay_encode[i]);
        always_ff @(posedge clk)begin
            s2_loadBank[i] <= loadOffset[i];
            rvaddr[i] <= rio.vaddr[i];
            rio.rdata[i] <= rdata[hitWay_encode[i]][s2_loadBank[i]];
            r_req[i] <= rio.req[i] & ~write_valid[i] & ~rio.req_cancel[i] & ~req_cancel[i];
        end
        assign rio.hit[i] = |wayHit[i];

        logic `N(`DCACHE_BYTE) load_wmask;
        assign load_wmask = wmask_n[loadOffset[i]];
        assign write_valid[i] = miss_io.refill_en & ~(cache_wreq & (|w_wayhit)) & ~wio.req |
                                snoop_req |
                                cache_wreq & (|w_wayhit) & (|load_wmask)
`ifdef RVA
                                | amo_en[loadOffset[i]]
`endif
                                ;
    end
endgenerate

    LoadIdx `N(`LOAD_PIPELINE) lqIdx;
    RobIdx `N(`LOAD_PIPELINE) robIdx;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) miss_addr, rpaddr;
    logic `N(`LOAD_PIPELINE) rhit;
    logic `N(`LOAD_PIPELINE) load_refill_conflict;
    logic `N(`LOAD_PIPELINE) load_refill_reply;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign req_cancel[i] = req_bank_conflict & ~rio.oldest[i];
        assign rpaddr[i] = {rio.ptag[i], rvaddr[i][11: 0]};
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
            miss_addr[i] <= {rio.ptag[i], rvaddr[i][11: 0]};
            load_refill_conflict[i] <= miss_io.refill_en & miss_io.refill_valid &
                                       ({rio.ptag[i], rvaddr[i]`DCACHE_SET_BUS} == miss_io.refillAddr`DCACHE_BLOCK_BUS);
        end
        load_refill_reply <= r_req_s3 & ~rio.req_cancel_s3 & load_refill_conflict;
    end
    assign rio.full = miss_io.rfull | load_refill_reply;

    assign miss_io.ren = r_req_s3 & ~rhit & ~rio.req_cancel_s3 & ~load_refill_conflict;
    assign miss_io.lqIdx = lqIdx;
    assign miss_io.robIdx = robIdx;
    assign miss_io.raddr = miss_addr;
    assign miss_io.raddr_pre = rpaddr;
    
    logic replace_hit;
    logic `N(`DCACHE_WAY_WIDTH) replace_hit_way;
    logic `N(`DCACHE_SET_WIDTH) replace_idx;
    logic `N(`DCACHE_SET_WIDTH) miss_req_addr;
    always_ff @(posedge clk)begin
        `UNPARAM(LOAD_PIPELINE, 2, "replace reuse hit port")
        miss_req_addr <= miss_io.req_addr`DCACHE_SET_BUS;
        replace_io.hit_en[0] <= r_req_s3[0] & rio.hit[0] | cache_wreq;
        replace_io.hit_en[1] <= r_req_s3[1] & rio.hit[1] | miss_req_n & miss_io.req_success;
        replace_io.hit_way[0] <= cache_wreq ? cache_wway : wayHit[0];
        replace_io.hit_way[1] <= miss_req_n & miss_io.req_success ? replace_io.miss_way : wayHit[1];
        replace_io.hit_index[0] <= cache_wreq ? waddr_n`DCACHE_SET_BUS : miss_io.raddr[0]`DCACHE_SET_BUS;
        replace_io.hit_index[1] <= miss_req_n & miss_io.req_success ? miss_req_addr : miss_io.raddr[1]`DCACHE_SET_BUS;
    end

    assign rio.lq_en = miss_io.lq_en;
    assign rio.lqData = miss_io.lqData;
    assign rio.lqIdx_o = miss_io.lqIdx_o;

// write
    logic write_invalid;
`ifdef RVA
    assign wreq = (wio.req | replace_queue_io.snoop_en | amo_io.req) & ~amo_req;
    assign waddr = replace_queue_io.snoop_en ? replace_queue_io.snoop_addr : 
                   wio.req ? wio.paddr : amo_io.paddr;
`else
    assign wreq = wio.req | replace_queue_io.snoop_en;
    assign waddr = replace_queue_io.snoop_en ? replace_queue_io.snoop_addr : wio.paddr;
`endif
    assign wdata = wio.data;
    assign wmask = wio.mask;
    assign widx = waddr`DCACHE_SET_BUS;
    
    assign replace_io.miss_index = miss_io.req_addr`DCACHE_SET_BUS;
`ifdef RVA
    assign wio.valid = ~replace_queue_io.snoop_en & ~amo_req;
`else
    assign wio.valid = ~replace_queue_io.snoop_en;
`endif

generate
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        assign wtagv[i] = tagv[`LOAD_PIPELINE][i];
        assign w_wayhit[i] = wtagv[i][0] & (wtagv[i][`DCACHE_TAG: 1] == waddr_n`DCACHE_TAG_BUS);
    end
endgenerate
    logic `N(`STORE_COMMIT_WIDTH) scIdx_n;
    always_ff @(posedge clk)begin
        wreq_n <= wio.req & ~replace_queue_io.snoop_en & ~amo_req;
        miss_req_n <= miss_io.req;
        waddr_n <= waddr;
`ifdef RVA
        if(amo_req)begin
            wdata_n <= {`DCACHE_BANK{amo_wdata}};
            wmask_n <= amo_wmask;
        end
        else begin
`endif
        wdata_n <= wdata;
        wmask_n <= wmask;
`ifdef RVA
        end
`endif
        scIdx_n <= wio.scIdx;
        // write_invalid <= miss_req_n && (waddr_n`DCACHE_BLOCK_BUS == waddr`DCACHE_BLOCK_BUS);
    end
`ifdef RVA
    assign cache_wreq = wreq_n & whit | amo_req_n;
    assign cache_wway = amo_req_n ? amo_wway : w_wayhit;
`else
    assign cache_wreq = wreq_n & whit;
    assign cache_wbank = w_wayhit;
`endif

    // 如果该项在replace queue中，那么需要等它写回miss queue才能进行读取
    assign replace_queue_io.waddr = miss_io.req_addr;

    // write miss
    assign whit = (|w_wayhit);
    Encoder #(`DCACHE_WAY) encoder_way (w_wayhit, w_wayIdx);
    Encoder #(`DCACHE_WAY) encoder_miss_way (replace_io.miss_way, missWay_encode);
    assign miss_io.wen = ~whit & wreq_n;
    assign miss_io.waddr = waddr_n;
    assign miss_io.waddr_pre = waddr;
    assign miss_io.wdata = wdata_n;
    assign miss_io.wmask = wmask_n;
    assign miss_io.req_success = ~snoop_req & miss_req_n & 
                                 ~replace_queue_io.full & ~replace_queue_io.whit;
    assign miss_io.replaceWay = missWay_encode;
    assign miss_io.scIdx = scIdx_n;
    assign wio.conflict = miss_io.wfull;
    assign wio.success = wreq_n2;
    assign replace_queue_io.en = miss_io.req;
    always_ff @(posedge clk)begin
        wreq_n2 <= wreq_n & whit;
        wio.conflictIdx <= scIdx_n;
    end

    // write hit
    Decoder #(`DCACHE_WAY) decoder_refill_way (miss_io.refillWay, refill_way);

    // refill
    assign miss_io.refill_valid = ~(cache_wreq & (|cache_wway)) & ~wio.req & ~snoop_req & ~replace_queue_io.snoop_en
`ifdef RVA
    & ~amo_io.req
`endif
    ;
    always_ff @(posedge clk)begin
        wio.refill <= miss_io.refill_en & miss_io.refill_valid & miss_io.refill_dirty;
        wio.refillIdx <= miss_io.refill_scIdx;
    end

    // replace enqueue
    assign replace_addr = {wtagv[refill_way_n][`DCACHE_TAG: 1], refill_addr_n`DCACHE_SET_BUS};
    always_ff @(posedge clk)begin
        refill_en_n <= miss_io.refill_en & miss_io.refill_valid;
        refill_way_n <= snoop_req ? w_wayIdx : miss_io.refillWay;
        refill_addr_n <= miss_io.refillAddr;
    end
    assign replace_queue_io.refill_en = refill_en_n;
    assign replace_queue_io.refill_dirty = wtagv[refill_way_n][0] & way_dirty[refill_way_n];
    assign replace_queue_io.addr = replace_addr;
    assign replace_queue_io.data = rdata[refill_way_n];

    // BUG: rlast但是没有refill进dcache时snoop访问不到该项
    assign replace_queue_io.snoop_data = rdata[refill_way_n];
`ifdef RVA
    assign replace_queue_io.snoop_ready = ~amo_req;
`else
    assign replace_queue_io.snoop_ready = 1'b1;
`endif
    always_ff @(posedge clk)begin
        snoop_req <= replace_queue_io.snoop_en;
        snoop_addr <= replace_queue_io.snoop_addr;
    end

    // amo
`ifdef RVA
    // TODO: currently only one core, not implement lr/sc
    Decoder #(`DCACHE_BANK) decoder_amo_bank(amo_io.paddr`DCACHE_BANK_BUS, amo_bank);
    assign amo_en = {`DCACHE_BANK{amo_io.req}} & amo_bank;
    always_ff @(posedge clk)begin
        amo_req <= amo_io.req & ~wio.req & ~replace_queue_io.snoop_en;
        amo_addr <= amo_io.paddr;
        amo_mask <= amo_io.mask;
        amo_data <= amo_io.data;
        amo_bank_n <= amo_bank;
        amoop <= amo_io.op;
        islr <= amo_io.op == `AMO_LR;
        issc <= amo_io.op == `AMO_SC;
        sc_match <= reservation_set & (reservation_addr == amo_io.paddr[`PADDR_SIZE-1: `DCACHE_BYTE]) & (reservation_mask == amo_io.mask);
    end
    assign amo_rdata = rdata[w_wayIdx][amo_addr`DCACHE_BANK_BUS];

    assign amo_io.ready = ~wio.req & ~replace_queue_io.snoop_en;
    assign amo_io.success = amo_req & whit;
    assign amo_io.rdata = issc ? !sc_match : amo_rdata;
    assign miss_io.amo_en = amo_req & ~whit;
    assign amo_io.refill = miss_io.amo_refill;

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            reservation_set <= 0;
            reservation_addr <= 0;
            reservation_mask <= 0;
        end
        else begin
            if(amo_req & islr & whit)begin
                reservation_set <= 1'b1;
                reservation_addr <= amo_addr[`PADDR_SIZE-1: `DCACHE_BYTE];
                reservation_mask <= amo_mask;
            end

            if(amo_req & issc & whit)begin
                reservation_set <= 1'b0;
            end
        end
    end

    AmoALU amo_alu (amo_rdata, amo_data, amoop, amo_res);
    assign amo_wdata = issc & sc_match ? amo_data : amo_res;
generate
    for(genvar i=0; i<`DCACHE_BANK; i++)begin
        assign amo_wmask[i] = {`DCACHE_BYTE{~islr & (~issc | sc_match) & amo_bank_n[i]}} & amo_mask;
    end
endgenerate
    always_ff @(posedge clk)begin
        amo_req_n <= amo_req & whit & (~islr & (~issc | sc_match));
        amo_wway <= w_wayhit;
    end
`endif

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