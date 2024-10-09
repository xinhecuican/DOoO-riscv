
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
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, `DCACHE_WAY_WIDTH
    ) ducache_io();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH, 1
    ) tlb_io();
    NativeSnoopIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH+2
    ) dcache_snoop_io();
    IfuBackendIO ifu_backend_io();
    FsqBackendIO fsq_back_io();
    CommitBus commitBus();
    TlbL2IO itlb_io();
    TlbL2IO dtlb_io();
    CsrL2IO csr_l2_io();
    CsrTlbIO csr_itlb_io();
    FenceBus fenceBus();

    logic ifu_rst, mmu_rst, back_rst, axi_rst;
    SyncRst rst_ifu(clk, rst, ifu_rst);
    SyncRst rst_mmu(clk, rst, mmu_rst);
    SyncRst rst_back(clk, rst, back_rst);
    SyncRst rst_axi_s1(clk, rst, axi_rst);


    IFU ifu(.*, .rst(ifu_rst), .axi_io(icache_io)
`ifdef EXT_FENCEI
    ,.fenceReq(fenceBus.inst_flush),
    .fenceEnd(fenceBus.inst_flush_end)
`endif
    );
    Backend backend(.*,
                    .rst(back_rst),
                    .commitBus_out(commitBus),
                    .axi_io(dcache_io),
                    .fenceBus_o(fenceBus));
    AxiInterface axi_interface(.*, .rst(axi_rst));
    L2TLB l2_tlb(.*,
                .rst(mmu_rst),
                .csr_io(csr_l2_io), 
                .flush(fsq_back_io.redirect.en), 
                .axi_io(tlb_io.masterr)
    );
endmodule
