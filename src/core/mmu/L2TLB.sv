`include "../../defines/defines.svh"

module L2TLB(
    input logic clk,
    input logic rst,
    input logic flush,
    TlbL2IO.l2 itlb_io,
    TlbL2IO.l2 dtlb_io,
    CsrL2IO.tlb csr_io,
    AxiIO.masterr axi_io,
    FenceBus.l2tlb fenceBus
);
    TLBCacheIO tlbCache_io();
    CachePTWIO cache_ptw_io();
    PTWL2IO ptw_io();
    FenceBus fenceBus_i();
    logic cache_flush, ptw_flush;
    logic fence, fence_end;
    logic dtlb_ready, itlb_ready;

    logic cache_rst, ptw_rst;
    SyncRst rst_cache (clk, rst, cache_rst);
    SyncRst rst_ptw (clk, rst, ptw_rst);

    Arbiter #(2, `VADDR_SIZE+$bits(TLBInfo)) arbiter_l1tlb (
        .valid({dtlb_io.req, itlb_io.req}),
        .data({{dtlb_io.info, dtlb_io.req_addr}, {itlb_io.info, itlb_io.req_addr}}),
        .ready({dtlb_ready, itlb_ready}),
        .valid_o(tlbCache_io.req),
        .data_o({tlbCache_io.info, tlbCache_io.req_addr})
    );
    TLBCache tlb_cache (.*, .rst(cache_rst), .io(tlbCache_io), .fenceBus(fenceBus_i.mmu));
    PTW ptw(.*, .rst(ptw_rst), .flush(ptw_flush), .fence_flush(fenceBus.mmu_flush[2]));

    assign dtlb_io.ready = dtlb_ready & ~fence;
    assign itlb_io.ready = itlb_ready & ~fence;
    assign fenceBus_i.mmu_flush = fenceBus.mmu_flush;
    assign fenceBus_i.mmu_flush_all = fenceBus.mmu_flush_all;
    assign fenceBus_i.vma_vaddr = fenceBus.vma_vaddr;
    assign fenceBus_i.vma_asid = fenceBus.vma_asid;
    assign fenceBus.mmu_flush_end = fence_end;
    always_ff @(posedge clk)begin
        cache_flush <= flush;
        ptw_flush <= flush;
        if(fenceBus.mmu_flush[2])begin
            fence <= 1'b1;
        end
        if(fence_end)begin
            fence <= 1'b0;
        end
    end
    assign tlbCache_io.flush = cache_flush | fenceBus.mmu_flush[2];


    logic `N(2) iready, dready;
    Arbiter #(2, `VADDR_SIZE+$bits(TLBInfo)+$bits(PTEEntry)+4) arbiter_itlb (
        .valid({tlbCache_io.hit & (tlbCache_io.info_o.source == 2'b00), ptw_io.valid & (ptw_io.info.source == 2'b00)}),
        .data({{tlbCache_io.wpn, tlbCache_io.exception, tlbCache_io.error, tlbCache_io.hit_addr, tlbCache_io.hit_entry, tlbCache_io.info_o}, 
              {ptw_io.wpn, ptw_io.exception, 1'b0, ptw_io.waddr, ptw_io.entry, ptw_io.info}}),
        .ready(iready),
        .valid_o(itlb_io.dataValid),
        .data_o({itlb_io.wpn, itlb_io.exception, itlb_io.error, itlb_io.waddr, itlb_io.entry, itlb_io.info_o})
    );
    Arbiter #(2, `VADDR_SIZE+$bits(TLBInfo)+$bits(PTEEntry)+4) arbiter_dtlb (
        .valid({tlbCache_io.hit & (tlbCache_io.info_o.source != 2'b00), ptw_io.valid & (ptw_io.info.source != 2'b00)}),
        .data({{tlbCache_io.wpn, tlbCache_io.exception, tlbCache_io.error, tlbCache_io.hit_addr, tlbCache_io.hit_entry, tlbCache_io.info_o}, 
              {ptw_io.wpn, ptw_io.exception, 1'b0, ptw_io.waddr, ptw_io.entry, ptw_io.info}}),
        .ready(dready),
        .valid_o(dtlb_io.dataValid),
        .data_o({dtlb_io.wpn, dtlb_io.exception, dtlb_io.error, dtlb_io.waddr, dtlb_io.entry, dtlb_io.info_o})
    );

    assign ptw_io.ready = ~tlbCache_io.hit;
endmodule