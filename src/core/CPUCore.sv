
`include "../defines/defines.svh"

module CPUCore (
    input logic clk,
    input logic rst,

    AxiIO.master axi
);

    ICacheAxi icache_io();
    DCacheAxi dcache_io();
    IfuBackendIO ifu_backend_io();
    FsqBackendIO fsq_back_io();
    CommitBus commitBus();
    TlbL2IO itlb_io();
    TlbL2IO dtlb_io();
    CsrL2IO csr_l2_io();
    PTWRequest ptw_request();
    CsrTlbIO csr_itlb_io();

    IFU ifu(.*, .axi_io(icache_io));
    Backend backend(.*,
                    .commitBus_out(commitBus),
                    .axi_io(dcache_io));
    AxiInterface axi_interface(.*);
    L2TLB l2_tlb(.*, .csr_io(csr_l2_io), .flush(fsq_back_io.redirect.en));
endmodule
