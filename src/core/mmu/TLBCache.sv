`include "../../defines/defines.svh"

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
    logic `N(2) wpn;

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
    logic pn0_fence_end;
    TLBPage #(
        .PN(0),
        .WAY_NUM(1),
        .META_WIDTH(`TLB_P0_BANK),
        .DEPTH(`TLB_P0_SET),
        .BANK(`TLB_P0_BANK)
    ) page_pn0 (.*, .page_io(pn0_io), .cache_io(io), .fence_finish(pn0_fence_end));

    TLBPageIO #(`TLB_P1_BANK, `TLB_P1_BANK) pn1_io();
    TLBPage #(
        .PN(1),
        .WAY_NUM(1),
        .META_WIDTH(`TLB_P1_BANK),
        .DEPTH(`TLB_P1_SET),
        .BANK(`TLB_P1_BANK)
    ) page_pn1 (.*, .page_io(pn1_io), .cache_io(io), .fence_finish()); 

    assign fence_end = pn0_fence_end;
    always_ff @(posedge clk)begin
        req_buf.req <= io.req & ~io.flush;
        req_buf.vaddr <= io.req_addr;
        req_buf.info <= io.info;
        req_buf.error <= cache_ptw_io.refill_req;
    end

    logic `N(`TLB_PN) hit, hit_first, leaf, exception, valid;
    PTEEntry pn1_entry, pn0_entry;
    assign pn1_entry = pn1_io.entry;
    assign pn0_entry = pn0_io.entry;
    assign hit[1] = pn1_io.hit;
    assign hit[0] = pn0_io.hit;
    assign leaf[1] = pn1_entry.x | pn1_entry.w | pn1_entry.r;
    assign leaf[0] = pn0_entry.x | pn0_entry.w | pn0_entry.r;
    assign valid = hit & leaf;
    PRSelector #(`TLB_PN) select_hit (hit, hit_first);

    logic pn1_exception;
    TLBExcDetect exc_detect0 (pn0_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, exception[0]);
    TLBExcDetect exc_detect1 (pn1_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, pn1_exception);
    assign exception[1] = pn1_exception | (leaf[1] & pn1_io.meta);

    logic `ARRAY(`TLB_PN, `PADDR_SIZE) paddr;
    PAddrGen gen_paddr0(pn0_entry, req_buf.vaddr, paddr[0]);
    PAddrGen gen_paddr1(pn1_entry, req_buf.vaddr, paddr[1]);

    always_ff @(posedge clk)begin
        io.hit <= req_buf.req & ((|(hit_first & (leaf | exception))) | cache_ptw_io.full | req_buf.error) & ~io.flush;
        io.exception <= |(hit_first & exception);
        io.error <= (~(|(hit_first & (leaf | exception)))) & cache_ptw_io.full | req_buf.error;
        io.hit_entry <= valid[0] ? pn0_io.entry : pn1_io.entry;
        io.hit_addr <= req_buf.vaddr;
        io.info_o <= req_buf.info;
        io.wpn <= hit_first[1] ? 2'b01 : 2'b00;

        cache_ptw_io.req <= req_buf.req & (~(|(hit_first & (leaf | exception)))) & ~cache_ptw_io.full & ~io.flush;
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
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) wdata;

    modport page (output hit, meta, entry, input we, waddr, wdata);
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
    parameter INFO_WIDTH=TAG_WIDTH+1+META_WIDTH
)(
    input logic clk,
    input logic rst,
    TLBCacheIO.cache cache_io,
    TLBPageIO.page page_io,
    CachePTWIO.page ptw_page_io,
    FenceBus.mmu fenceBus,
    output logic fence_finish
);
    TLBWayIO #(
        .TAG_WIDTH(INFO_WIDTH),
        .DEPTH(DEPTH),
        .BANK(BANK)
    ) way_io `N(WAY_NUM) ();

    typedef enum  { IDLE, FENCE, FENCE_ALL, FENCE_END } FenceState;
    FenceState fenceState;
    logic fenceReq, fenceWe;
    logic `N(ADDR_WIDTH) fenceIdx;
    logic req_n;
    logic `N(`TLB_P0_TAG) tag;
    logic `N(BANK_WIDTH) offset;
    logic `ARRAY(WAY_NUM, BANK * `PTE_BITS) rdata;
    logic `ARRAY(WAY_NUM, INFO_WIDTH) rtag;
    logic `N(BANK) unaligned;
generate
    if(WAY_NUM > 1)begin
        always_comb begin
            $display("tlb page replace unimpl");
        end
    end
    for(genvar j=0; j<BANK; j++)begin
        PTEEntry entry;
        assign entry = ptw_page_io.refill_data[j];
        if(PN == 1)begin
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
        assign way_io[i].we = ptw_page_io.refill_req & ptw_page_io.refill_pn[PN];
        assign way_io[i].tag_we = ptw_page_io.refill_req & ptw_page_io.refill_pn[PN] | fenceWe;
        assign way_io[i].wdata = ptw_page_io.refill_data;
        assign way_io[i].wtag = fenceWe ? {INFO_WIDTH{1'b0}} : {1'b1, unaligned, ptw_page_io.refill_addr`TLB_VPN_TBUS(PN, DEPTH, BANK)};
    end
endgenerate

    always_ff @(posedge clk)begin
        tag <= cache_io.req_addr`TLB_VPN_TBUS(PN, DEPTH, BANK);
        offset <= cache_io.req_addr[`TLB_VPN_BASE(PN)+BANK_WIDTH-1: `TLB_VPN_BASE(PN)];
        req_n <= cache_io.req & ~cache_io.flush;
    end

    logic `N(WAY_NUM) tag_hits;
    logic `ARRAY(BANK, `PTE_BITS) way_data;
    logic `ARRAY(BANK, META_WIDTH/BANK) meta;
generate
    for(genvar i=0; i<WAY_NUM; i++)begin
        assign tag_hits[i] = way_io[i].tag[INFO_WIDTH-1] & (way_io[i].tag[TAG_WIDTH-1: 0] == tag);
    end
    
    assign page_io.hit = req_n & (|tag_hits);
    if(WAY_NUM > 1)begin
        logic `N($clog2(WAY_NUM)) hit_way;
        PEncoder #(WAY_NUM) encoder_hit_idx (tag_hits, hit_way);
        assign way_data = rdata[hit_way];
        assign page_io.entry = way_data[offset];
        assign meta = rtag[hit_way][INFO_WIDTH-2: TAG_WIDTH];
        assign page_io.meta = meta[offset];
    end
    else begin
        assign way_data = rdata;
        assign page_io.entry = way_data[offset];
        assign meta = rtag[0][INFO_WIDTH-2: TAG_WIDTH];
        assign page_io.meta = meta[offset];
    end
endgenerate


    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            fenceState <= IDLE;
            fenceReq <= 0;
            fenceWe <= 0;
            fenceIdx <= 0;
            fence_finish <= 0;
        end
        else begin
            case(fenceState)
            IDLE: begin
                if(fenceBus.mmu_flush[2])begin
                    if(fenceBus.mmu_flush_all[2])begin
                        fenceIdx <= 0;
                        fenceWe <= 1'b1;
                        fenceState <= FENCE_ALL;
                    end
                    else begin
                        fenceIdx <= fenceBus.vma_vaddr[2]`TLB_VPN_IBUS(PN, DEPTH, BANK);
                        fenceReq <= 1'b1;
                        fenceState <= FENCE;
                    end
                end
            end
            FENCE: begin
                fenceWe <= tag_hits;
                fenceState <= FENCE_END;
            end
            FENCE_ALL: begin
                fenceIdx <= fenceIdx + 1;
                if(fenceIdx == {{ADDR_WIDTH-1{1'b1}}, 1'b0})begin
                    fenceState <= FENCE_END;
                end
            end
            FENCE_END:begin
                fenceWe <= 0;
                fenceReq <= 0;
                fenceState <= IDLE;
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
        .en(io.tag_en),
        .we(io.tag_we),
        .addr(io.idx),
        .wdata(io.wtag),
        .rdata(io.tag),
        .ready()
    );

generate
    for(genvar i=0; i<BANK; i++)begin
        SPRAM #(
            .WIDTH(`PTE_BITS),
            .DEPTH(DEPTH),
            .READ_LATENCY(1)
        ) data_ram (
            .clk(clk),
            .rst(rst),
            .en(io.en),
            .we(io.we),
            .addr(io.idx),
            .wdata(io.wdata[i]),
            .rdata(io.rdata[i]),
            .ready()
        );
    end
endgenerate
endmodule

module PAddrGen #(
    parameter PN=0,
    parameter LEAF=0
)(
    input PTEEntry entry,
    input `VADDR_BUS vaddr,
    output `PADDR_BUS paddr
);
`define PPN_ASSIGN(i) \
    if(PN >= i)begin \
        assign ppn.ppn``i = entry.ppn.ppn``i; \
    end \
    else begin \
        assign ppn.ppn``i = vpn.vpn[i]; \
    end \


generate
    if(PN == 0)begin
        assign paddr = {entry.ppn, vaddr[`TLB_OFFSET-1: 0]};
    end
    else begin
        VPNAddr vpn;
        assign vpn = vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
        PPNAddr ppn;
        `PPN_ASSIGN(0)
        `PPN_ASSIGN(1)
        // for(genvar i=0; i<`TLB_PN; i++)begin
        //     `PPN_ASSIGN(i)
        // end
        logic leaf;
        if(LEAF == 0)begin
            assign leaf = entry.r | entry.w | entry.x;
        end
        else begin
            assign leaf = 1'b1;
        end
        assign paddr = leaf ? {ppn, vaddr[`TLB_OFFSET-1: 0]} :
                       {entry.ppn, {`TLB_OFFSET-`TLB_VPN-2{1'b0}}, vpn[PN-1], 2'b00};
    end
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
                      (leaf & ~((entry.r & r) |
                              (entry.x & (x | (r & mxr))) |
                              (entry.w & w))) |
                      (leaf & (((mode_i == 2'b01) & ~sum & entry.u) |
                      ((mode_i == 2'b00) & ~entry.u) |
                      (~entry.a | (w & ~entry.d))));
endmodule