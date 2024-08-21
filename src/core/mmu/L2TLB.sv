`include "../../defines/defines.svh"

module L2TLB(
    input logic clk,
    input logic rst,
    input logic flush,
    TlbL2IO.l2 itlb_io,
    TlbL2IO.l2 dtlb_io,
    CsrL2IO.tlb csr_io,
    PTWRequest.ptw ptw_request
);
    TLBCacheIO tlbCache_io();
    CachePTWIO cache_ptw_io();
    PTWL2IO ptw_io();
    logic cache_flush, ptw_flush;

    Arbiter #(2, `VADDR_SIZE+$bits(TLBInfo)) arbiter_l1tlb (
        .valid({dtlb_io.req, itlb_io.req}),
        .data({{dtlb_io.info, dtlb_io.req_addr}, {dtlb_io.info, itlb_io.req_addr}}),
        .ready({dtlb_io.ready, itlb_io.ready}),
        .valid_o(tlbCache_io.req),
        .data_o({tlbCache_io.info, tlbCache_io.req_addr})
    );
    TLBCache tlb_cache (.*, .io(tlbCache_io));
    PTW ptw(.*, .flush(ptw_flush));

    always_ff @(posedge clk)begin
        cache_flush <= flush;
        ptw_flush <= flush;
    end
    assign tlbCache_io.flush = cache_flush;


    logic `N(2) iready, dready;
    Arbiter #(2, `VADDR_SIZE+$bits(TLBInfo)+$bits(PTEEntry)+4) arbiter_itlb (
        .valid({tlbCache_io.hit & (tlbCache_io.info_o.source == 2'b00), ptw_io.valid & (ptw_io.info.source == 2'b00)}),
        .data({{tlbCache_io.wpn, tlbCache_io.exception, tlbCache_io.error, tlbCache_io.hit_addr, tlbCache_io.hit_entry, tlbCache_io.info_o}, 
              {ptw_io.wpn, ptw_io.exception, 1'b0, ptw_io.waddr, ptw_io.entry, ptw_io.info}}),
        .ready(iready),
        .valid_o(itlb_io.dataValid),
        .data_o({itlb_io.wpn, itlb_io.exception, itlb_io.error, itlb_io.waddr, itlb_io.entry, itlb_io.info_o})
    );
    Arbiter #(2, `PADDR_SIZE+$bits(TLBInfo)+$bits(PTEEntry)+3) arbiter_dtlb (
        .valid({tlbCache_io.hit & (tlbCache_io.info_o.source != 2'b00), ptw_io.valid & (ptw_io.info.source != 2'b00)}),
        .data({{tlbCache_io.wpn, tlbCache_io.exception, tlbCache_io.error, tlbCache_io.hit_addr, tlbCache_io.hit_entry, tlbCache_io.info_o}, 
              {ptw_io.wpn, ptw_io.exception, 1'b0, ptw_io.waddr, ptw_io.entry, ptw_io.info}}),
        .ready(dready),
        .valid_o(dtlb_io.dataValid),
        .data_o({dtlb_io.wpn, dtlb_io.exception, dtlb_io.error, dtlb_io.waddr, dtlb_io.entry, dtlb_io.info_o})
    );

    assign ptw_io.ready = ~tlbCache_io.hit;
endmodule