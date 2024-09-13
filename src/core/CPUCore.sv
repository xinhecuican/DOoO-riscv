
`include "../defines/defines.svh"

module CPUCore (
    input logic clk,
    input logic rst,
    input logic ext_irq,
    AxiIO.master axi,
    ClintIO.cpu clint_io
);

    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, 1
    ) icache_io();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, 1
    ) dcache_io();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, 1
    ) ducache_io();
    IfuBackendIO ifu_backend_io();
    FsqBackendIO fsq_back_io();
    CommitBus commitBus();
    TlbL2IO itlb_io();
    TlbL2IO dtlb_io();
    CsrL2IO csr_l2_io();
    PTWRequest ptw_request();
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
    AxiInterface axi_interface(.*);
    L2TLB l2_tlb(.*, .csr_io(csr_l2_io), .flush(fsq_back_io.redirect.en));
endmodule
