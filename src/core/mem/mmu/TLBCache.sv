`include "../../../defines/defines.svh"

interface TLBCacheIO;
    logic req;
    TLBInfo info;
    logic `VADDR_BUS req_addr;
    logic flush;

    logic hit;
    logic error;
    logic exception;
    TLBInfo info_o;
    PTEEntry hit_entry;
    logic `N(`VADDR_SIZE) hit_addr;
    logic `N(`TLB_PN) wpn;

    modport cache (input req, info, req_addr, flush,
                   output hit, error, exception, info_o, hit_entry, hit_addr, wpn);
endinterface

module TLBCache(
    input logic clk,
    input logic rst,
    TLBCacheIO.cache io,
    CsrL2IO.tlb csr_io,
    CachePTWIO.cache cache_ptw_io,
    FenceBus.mmu fenceBus,
    output logic fence_end
);

    typedef struct packed {
        logic req;
        logic error;
        logic `N(`VADDR_SIZE) vaddr;
        TLBInfo info;
    } RequestBuffer;
    RequestBuffer req_buf;

    CachePTWIO ptw_page_io();
    assign ptw_page_io.full = cache_ptw_io.full;
    assign ptw_page_io.refill_req = cache_ptw_io.refill_req;
    assign ptw_page_io.refill_pn = cache_ptw_io.refill_pn;
    assign ptw_page_io.refill_addr = cache_ptw_io.refill_addr;
    assign ptw_page_io.refill_data = cache_ptw_io.refill_data;
    TLBPageIO #(`TLB_P0_BANK, `TLB_P0_BANK) pn0_io();
    logic pn0_fence_end, pn0_fence_valid, pn0_fence_end_n;
    TLBPage #(
        .PN(0),
        .WAY_NUM(`TLB_P0_WAY),
        .META_WIDTH(`TLB_P0_BANK),
        .DEPTH(`TLB_P0_SET),
        .BANK(`TLB_P0_BANK)
    ) page_pn0 (.*, .page_io(pn0_io), .cache_io(io), .fence_finish(pn0_fence_end), .fence_valid(pn0_fence_valid));

    TLBPageIO #(`TLB_P1_BANK, `TLB_P1_BANK) pn1_io();
    TLBPage #(
        .PN(1),
        .WAY_NUM(`TLB_P1_WAY),
        .META_WIDTH(`TLB_P1_BANK),
        .DEPTH(`TLB_P1_SET),
        .BANK(`TLB_P1_BANK)
    ) page_pn1 (.*, .page_io(pn1_io), .cache_io(io), .fence_finish(), .fence_valid()); 

`ifdef SV39
    TLBPageIO #(`TLB_P2_BANK, `TLB_P2_BANK) pn2_io();
    TLBPage #(
        .PN(2),
        .WAY_NUM(`TLB_P2_WAY),
        .META_WIDTH(`TLB_P2_BANK),
        .DEPTH(`TLB_P2_SET),
        .BANK(`TLB_P2_BANK)
    ) page_pn2 (.*, .page_io(pn2_io), .cache_io(io), .fence_finish(), .fence_valid()); 
`endif

    assign fence_end = pn0_fence_end;
    always_ff @(posedge clk)begin
        req_buf.req <= io.req & ~io.flush;
        req_buf.vaddr <= io.req_addr;
        req_buf.info <= io.info;
        req_buf.error <= cache_ptw_io.refill_req;
        pn0_fence_end_n <= pn0_fence_end;
    end

    logic `N(`TLB_PN) hit, hit_first, leaf, exception, valid;
    PTEEntry pn1_entry, pn0_entry;
    assign pn1_entry = pn1_io.entry;
    assign pn0_entry = pn0_io.entry;
    assign hit[1] = pn1_io.hit;
    assign hit[0] = pn0_io.hit;
    assign leaf[1] = pn1_entry.x | pn1_entry.w | pn1_entry.r;
    assign leaf[0] = pn0_entry.x | pn0_entry.w | pn0_entry.r;
`ifdef SV39
    PTEEntry pn2_entry;
    assign pn2_entry = pn2_io.entry;
    assign hit[2] = pn2_io.hit;
    assign leaf[2] = pn2_entry.x | pn2_entry.w | pn2_entry.r;
`endif
    assign valid = hit & leaf;
    PRSelector #(`TLB_PN) select_hit (hit, hit_first);

    logic pn1_exception;
    TLBExcDetect exc_detect0 (pn0_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, exception[0]);
    TLBExcDetect exc_detect1 (pn1_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, pn1_exception);
    assign exception[1] = pn1_exception | (leaf[1] & pn1_io.meta);
`ifdef SV39
    logic pn2_exception;
    TLBExcDetect exc_detect2 (pn2_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, pn2_exception);
    assign exception[2] = pn2_exception | (leaf[2] & pn2_io.meta);
`endif

    logic `ARRAY(`TLB_PN, `PADDR_SIZE) paddr;
    PAddrGen gen_paddr0(pn0_entry, req_buf.vaddr, paddr[0]);
    PAddrGen #(1) gen_paddr1(pn1_entry, req_buf.vaddr, paddr[1]);
`ifdef SV39
    PAddrGen #(2) gen_paddr2(pn2_entry, req_buf.vaddr, paddr[2]);
`endif

    logic hit_before;
    logic ptw_req_before, error_before;
    assign io.hit = (hit_before | ptw_req_before & cache_ptw_io.full) & ~io.flush;
    assign io.error = error_before | ptw_req_before & cache_ptw_io.full;
    assign cache_ptw_io.req = ptw_req_before & ~cache_ptw_io.full & 
                              ~pn0_fence_valid & ~pn0_fence_end & ~pn0_fence_end_n;
    always_ff @(posedge clk)begin
        hit_before <= req_buf.req & ((|(hit_first & (leaf | exception))) | req_buf.error) & ~io.flush;
        ptw_req_before <= req_buf.req & (~(|(hit_first & (leaf | exception)))) & ~req_buf.error & ~io.flush;
        error_before <= req_buf.error;
        io.exception <= |(hit_first & exception);

        io.hit_addr <= req_buf.vaddr;
        io.info_o <= req_buf.info;
`ifdef SV39
        io.hit_entry <= valid[0] ? pn0_io.entry :
                        valid[1] ? pn1_io.entry : pn2_io.entry;
        io.wpn <= hit_first[2] ? 3'b011 : hit_first[1] ? 3'b001 : 3'b000;
`else
        io.hit_entry <= valid[0] ? pn0_io.entry : pn1_io.entry;
        io.wpn <= hit_first[1] ? 2'b01 : 2'b00;
`endif
        cache_ptw_io.info <= req_buf.info;
        cache_ptw_io.vaddr <= req_buf.vaddr;
        cache_ptw_io.valid <= hit_first;
        cache_ptw_io.paddr <= paddr;
    end
    assign cache_ptw_io.refill_ready = 1'b1;

endmodule

interface TLBPageIO #(
    parameter META_WIDTH=16,
    parameter BANK=16
);
    logic hit;
    // 判断是否为非对齐的超级页
    logic `N(META_WIDTH/BANK) meta;
    logic `N(`PTE_BITS) entry;

    logic we;
    logic `N(`VADDR_SIZE) waddr;
    logic `N(`TLB_ASID) wasid;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata;

    modport page (output hit, meta, entry, input we, waddr, wdata, wasid);
endinterface

module TLBPage #(
    parameter PN=0,
    parameter WAY_NUM=1,
    parameter META_WIDTH=4,
    parameter DEPTH=64,
    parameter BANK=16,
    parameter ADDR_WIDTH=$clog2(DEPTH),
    parameter BANK_WIDTH=$clog2(BANK),
    parameter TAG_WIDTH=`TLB_VPN * (`TLB_PN - PN) -ADDR_WIDTH - BANK_WIDTH,
    parameter INFO_WIDTH=TAG_WIDTH+1+META_WIDTH+`TLB_ASID
)(
    input logic clk,
    input logic rst,
    CsrL2IO.tlb csr_io,
    TLBCacheIO.cache cache_io,
    TLBPageIO.page page_io,
    CachePTWIO.page ptw_page_io,
    FenceBus.mmu fenceBus,
    output logic fence_valid,
    output logic fence_finish
);
    typedef struct packed {
        logic en;
        logic `N(TAG_WIDTH) tag;
        logic `N(`TLB_ASID) asid;
        logic `N(META_WIDTH) meta;
    } InfoData;

    TLBWayIO #(
        .TAG_WIDTH(INFO_WIDTH),
        .DEPTH(DEPTH),
        .BANK(BANK)
    ) way_io `N(WAY_NUM) ();
    ReplaceIO #(DEPTH, WAY_NUM) replace_io();
    PLRU #(DEPTH, WAY_NUM) plru(.*);

    typedef enum  { IDLE, FENCE, FENCE_ALL, FENCE_END } FenceState;
    FenceState fenceState;
    logic fenceReq, fenceWe, fenceReq_n;
    logic `N(ADDR_WIDTH) fenceIdx;
    logic `N(WAY_NUM) fence_way;
    logic `N(TAG_WIDTH) fence_tag;
    logic `N(`TLB_ASID) fence_asid;
    logic fence_asid_all;
    logic req_n;
    logic `N(TAG_WIDTH) tag;
    logic `N(BANK_WIDTH) offset;
    logic `ARRAY(WAY_NUM, BANK * `PTE_BITS) rdata;
    InfoData `N(WAY_NUM) rtag;
    InfoData wtag;
    logic `N(BANK) unaligned;

    assign replace_io.hit_en = ptw_page_io.refill_req & ptw_page_io.refill_pn[PN];
    assign replace_io.hit_invalid = 0;
    assign replace_io.hit_way = replace_io.miss_way;
    assign replace_io.hit_index = ptw_page_io.refill_addr`TLB_VPN_IBUS(PN, DEPTH, BANK);
    assign replace_io.miss_index = ptw_page_io.refill_addr`TLB_VPN_IBUS(PN, DEPTH, BANK);
generate
    for(genvar j=0; j<BANK; j++)begin
        PTEEntry entry;
        assign entry = ptw_page_io.refill_data[j];
        if(PN == 2)begin
            assign unaligned[j] = (entry.ppn.ppn1 != 0) || (entry.ppn.ppn0 != 0);
        end
        else if(PN == 1)begin
            assign unaligned[j] = entry.ppn.ppn0 != 0;
        end
        else begin
            assign unaligned[j] = 0;
        end
    end
    for(genvar i=0; i<WAY_NUM; i++)begin
        TLBWay #(
            .TAG_WIDTH(INFO_WIDTH),
            .DEPTH(DEPTH),
            .BANK(BANK)
        ) way(
            .*,
            .io(way_io[i])
        );

        assign way_io[i].tag_en = cache_io.req | fenceReq;
        assign way_io[i].en = cache_io.req | fenceReq;

        assign way_io[i].idx = fenceReq | fenceWe ? fenceIdx : 
                               ptw_page_io.refill_req ? ptw_page_io.refill_addr`TLB_VPN_IBUS(PN, DEPTH, BANK) : 
                                              cache_io.req_addr`TLB_VPN_IBUS(PN, DEPTH, BANK);
        assign rdata[i] = way_io[i].rdata;
        assign rtag[i] = way_io[i].tag;
        assign way_io[i].we = ptw_page_io.refill_req & ptw_page_io.refill_pn[PN] & replace_io.miss_way[i] & ~(fenceReq | fenceWe);
        assign way_io[i].tag_we = ptw_page_io.refill_req & ptw_page_io.refill_pn[PN] & replace_io.miss_way[i] & ~fenceReq | fenceWe & fence_way[i];
        assign way_io[i].wdata = ptw_page_io.refill_data;
        assign way_io[i].wtag = fenceWe ? {INFO_WIDTH{1'b0}} : wtag;
    end
    assign wtag.en = 1'b1;
    assign wtag.meta = unaligned;
    assign wtag.tag = ptw_page_io.refill_addr`TLB_VPN_TBUS(PN, DEPTH, BANK);
    assign wtag.asid = csr_io.asid;
endgenerate

    always_ff @(posedge clk)begin
        tag <= fenceReq ? fence_tag : cache_io.req_addr`TLB_VPN_TBUS(PN, DEPTH, BANK);
        offset <= cache_io.req_addr[`TLB_VPN_BASE(PN)+BANK_WIDTH-1: `TLB_VPN_BASE(PN)];
        req_n <= cache_io.req & ~cache_io.flush;
    end

    logic `N(WAY_NUM) tag_hits;
    logic `ARRAY(BANK, `PTE_BITS) way_data;
    logic `ARRAY(BANK, META_WIDTH/BANK) meta;
    logic `N(`TLB_ASID) lookup_asid;
    assign lookup_asid = fenceReq_n ? fence_asid : csr_io.asid;
generate
    for(genvar i=0; i<WAY_NUM; i++)begin
        assign tag_hits[i] = rtag[i].en & (rtag[i].tag == tag) &
                            ((rtag[i].asid == lookup_asid) | fenceReq_n & fence_asid_all);
    end
    
    assign page_io.hit = req_n & (|tag_hits);
    if(WAY_NUM > 1)begin
        logic `N($clog2(WAY_NUM)) hit_way;
        PEncoder #(WAY_NUM) encoder_hit_idx (tag_hits, hit_way);
        assign way_data = rdata[hit_way];
        assign page_io.entry = way_data[offset];
        assign meta = rtag[hit_way].meta;
        assign page_io.meta = meta[offset];
    end
    else begin
        assign way_data = rdata;
        assign page_io.entry = way_data[offset];
        assign meta = rtag[0].meta;
        assign page_io.meta = meta[offset];
    end
endgenerate

    always_ff @(posedge clk)begin
        fenceReq_n <= fenceReq;
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            fenceState <= IDLE;
            fenceReq <= 0;
            fenceWe <= 0;
            fenceIdx <= 0;
            fence_valid <= 0;
            fence_finish <= 0;
            fence_way <= 0;
            fence_tag <= 0;
            fence_asid <= 0;
            fence_asid_all <= 0;
        end
        else begin
            case(fenceState)
            IDLE: begin
                if(fenceBus.mmu_flush[2])begin
                    if(fenceBus.mmu_flush_all[2])begin
                        fenceIdx <= 0;
                        fenceWe <= 1'b1;
                        fence_way <= {WAY_NUM{1'b1}};
                        fenceState <= FENCE_ALL;
                    end
                    else begin
                        fenceIdx <= fenceBus.vma_vaddr[2]`TLB_VPN_IBUS(PN, DEPTH, BANK);
                        fenceReq <= 1'b1;
                        fenceState <= FENCE;
                        fence_tag <= fenceBus.vma_vaddr[2]`TLB_VPN_TBUS(PN, DEPTH, BANK);
                        fence_asid <= fenceBus.vma_asid[2];
                        fence_asid_all <= fenceBus.mmu_asid_all[2];
                    end
                    fence_valid <= 1'b1;
                end
            end
            FENCE: begin
                fenceReq <= 1'b0;
                if(fenceReq_n)begin
                    fenceWe <= |tag_hits;
                    fence_way <= tag_hits;
                    fenceState <= FENCE_END;
                end
            end
            FENCE_ALL: begin
                fenceIdx <= fenceIdx + 1;
                if(fenceIdx == {{ADDR_WIDTH-1{1'b1}}, 1'b0})begin
                    fenceState <= FENCE_END;
                end
            end
            FENCE_END:begin
                fenceWe <= 0;
                fenceState <= IDLE;
                fence_valid <= 1'b0;
            end
            endcase
            fence_finish <= fenceState == FENCE_END;
        end
    end
endmodule

interface TLBWayIO #(
    parameter TAG_WIDTH=4,
    parameter DEPTH=64,
    parameter BANK=16,
    parameter ADDR_WIDTH=$clog2(DEPTH)
);
    logic tag_en;
    logic tag_we;
    logic `N(TAG_WIDTH) tag;
    logic `N(TAG_WIDTH) wtag;
    logic  en;
    logic  we;
    logic `N(ADDR_WIDTH) idx;
    logic `ARRAY(BANK, `PTE_BITS) wdata;
    logic `ARRAY(BANK, `PTE_BITS) rdata;

    modport way (input tag_en, tag_we, idx, wtag, en, we, wdata, output tag, rdata);
endinterface

module TLBWay #(
    parameter TAG_WIDTH=4,
    parameter DEPTH=64,
    parameter BANK=16,
    parameter ADDR_WIDTH=$clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    TLBWayIO.way io
);
    SPRAM #(
        .WIDTH(TAG_WIDTH),
        .DEPTH(DEPTH),
        .READ_LATENCY(1)
    ) tag_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(1'b0),
        .en(io.tag_en),
        .we(io.tag_we),
        .addr(io.idx),
        .wdata(io.wtag),
        .rdata(io.tag),
        .ready()
    );

    SPRAM #(
        .WIDTH(`PTE_BITS * BANK),
        .DEPTH(DEPTH),
        .READ_LATENCY(1)
    ) data_ram (
        .clk(clk),
        .rst(rst),
        .rst_sync(1'b0),
        .en(io.en),
        .we(io.we),
        .addr(io.idx),
        .wdata(io.wdata),
        .rdata(io.rdata),
        .ready()
    );
endmodule

module PAddrGen #(
    parameter PN=0,
    parameter LEAF=0
)(
    input PTEEntry entry,
    input `VADDR_BUS vaddr,
    output `PADDR_BUS paddr
);
generate
    if(PN == 0)begin
        assign paddr = {entry.ppn, vaddr[`TLB_OFFSET-1: 0]};
    end
    else if(PN == 1)begin
        VPNAddr vpn;
        assign vpn = vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
        PPNAddr ppn;
        assign ppn.ppn0 = vpn.vpn[0];
        assign ppn.ppn1 = entry.ppn.ppn1;
`ifdef SV39
        assign ppn.ppn2 = entry.ppn.ppn2;
`endif

        logic leaf;
        if(LEAF == 0)begin
            assign leaf = entry.r | entry.w | entry.x;
        end
        else begin
            assign leaf = 1'b1;
        end
        assign paddr = leaf ? {ppn, vaddr[`TLB_OFFSET-1: 0]} :
                       {entry.ppn, vpn.vpn[0], {`PTE_WIDTH{1'b0}}};
    end
`ifdef SV39
    else if(PN == 2)begin
        VPNAddr vpn;
        assign vpn = vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
        PPNAddr ppn;
        assign ppn.ppn0 = vpn.vpn[0];
        assign ppn.ppn1 = vpn.vpn[1];
        assign ppn.ppn2 = entry.ppn.ppn2;

        logic leaf;
        if(LEAF == 0)begin
            assign leaf = entry.r | entry.w | entry.x;
        end
        else begin
            assign leaf = 1'b1;
        end
        assign paddr = leaf ? {ppn, vaddr[`TLB_OFFSET-1: 0]} :
                    {entry.ppn, vpn.vpn[1], {`PTE_WIDTH{1'b0}}};
    end
`endif
endgenerate
endmodule

module TLBExcDetect#(
    parameter IS_LEAF=0
)(
    input PTEEntry entry,
    input logic `N(2) source,
    input logic mxr,
    input logic sum,
    input logic mprv,
    input logic [1: 0] mpp,
    input logic [1: 0] mode,
    output logic exception
);
    logic leaf;
    logic r, w, x;
    logic [1: 0] mode_i;
    assign r = source[0];
    assign w = source[1];
    assign x = ~source[0] & ~source[1];
    assign mode_i = ~x & mprv ? mpp : mode;
generate
    if(IS_LEAF)begin
        assign leaf = 1'b1;
    end
    else begin
        assign leaf = entry.r | entry.w | entry.x;
    end
endgenerate
    assign exception = ~entry.v |
                      (~entry.r & entry.w) |
                      (|entry.rsw) |
                      (leaf & ~(((entry.r | entry.x & mxr) & r) |
                              (entry.x & x) |
                              (entry.w & w))) |
                      (leaf & (((mode_i == 2'b01) & ~sum & entry.u) |
                      ((mode_i == 2'b00) & ~entry.u) |
                      (~entry.a | (w & ~entry.d))));
endmodule