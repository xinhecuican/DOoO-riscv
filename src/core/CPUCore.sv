
`include "../defines/defines.svh"

module CPUCore (
    input logic clk,
    input logic rst,
    AxiIO.master  mem_axi,
    AxiIO.master peri_axi,
    ClintIO.cpu clint_io
);

    CacheBus #(
        `PADDR_SIZE, `XLEN, 1, 1
    ) icache_io();
    CacheBus #(
        `PADDR_SIZE, `XLEN, 1, `DCACHE_WAY_WIDTH
    ) dcache_io();
    CacheBus #(
        `PADDR_SIZE, `XLEN, 1, 1
    ) ducache_io();
    CacheBus #(
        `PADDR_SIZE, `XLEN, 1, 1
    ) tlb_io();
    CacheBus #(
        `PADDR_SIZE, `XLEN, 2, 1
    ) master_io();
    SnoopIO #(
        `PADDR_SIZE, `XLEN, `L2MSHR_WIDTH
    ) dcache_snoop_io();
    typedef logic [`PADDR_SIZE-1: 0] addr_t;
    typedef logic [`XLEN-1: 0] data_t;
    typedef logic [$clog2(`L2MSHR_SIZE)-1: 0] snoop_ack_id_t;
    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_chan_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_chan_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_chan_t)
    `SNOOP_TYPEDEF_REQ_T(snoop_req_t, snoop_ac_chan_t, snoop_ack_id_t)
    `SNOOP_TYPEDEF_RESP_T(snoop_resp_t, snoop_cd_chan_t, snoop_cr_chan_t, snoop_ack_id_t)
    `SNOOP_TYPEDEF_REQ_T(mst_snoop_req_t, snoop_ac_chan_t, snoop_ack_id_t)
    `SNOOP_TYPEDEF_RESP_T(mst_snoop_resp_t, snoop_cd_chan_t, snoop_cr_chan_t, snoop_ack_id_t)
    snoop_req_t snoop_req;
    snoop_resp_t snoop_resp;
    mst_snoop_req_t mst_snoop_req;
    mst_snoop_resp_t mst_snoop_resp;
    `SNOOP_ASSIGN_FROM_REQ(dcache_snoop_io, snoop_req)
    `SNOOP_ASSIGN_TO_RESP(snoop_resp, dcache_snoop_io)
    `CACHE_ASSIGN_TO_AXI(mem_axi, master_io)
    `CACHE_ASSIGN_TO_AXI(peri_axi, ducache_io)
    assign mst_snoop_req = 0;

    IfuBackendIO ifu_backend_io();
    FsqBackendIO fsq_back_io();
    CommitBus commitBus();
    TlbL2IO itlb_io();
    TlbL2IO dtlb_io();
    CsrL2IO csr_l2_io();
    CsrTlbIO csr_itlb_io();
    FenceBus fenceBus();


    IFU ifu(.*, .axi_io(icache_io)
`ifdef EXT_FENCEI
    ,.fenceReq(fenceBus.inst_flush),
    .fenceEnd(fenceBus.inst_flush_end)
`endif
    );
    Backend backend(.*,
                    .commitBus_out(commitBus),
                    .axi_io(dcache_io),
                    .fenceBus_o(fenceBus));
    L2CacheWrapper #(
        snoop_req_t, snoop_resp_t, mst_snoop_req_t, mst_snoop_resp_t
    ) l2cache_wrapper (.*, .master_io(master_io.master));
    L2TLB l2_tlb(.*,
                .csr_io(csr_l2_io), 
                .flush(fsq_back_io.redirect.en), 
                .axi_io(tlb_io.masterr)
    );
endmodule
