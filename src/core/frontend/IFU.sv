`include "../../defines/defines.svh"

module IFU (
    input logic clk,
    input logic rst,
    CacheBus.masterr axi_io,
    IfuBackendIO.ifu ifu_backend_io,
    FsqBackendIO.fsq fsq_back_io,
    CommitBus.in commitBus,
    TlbL2IO.tlb itlb_io,
    CsrTlbIO.tlb csr_itlb_io,
    FenceBus.mmu fenceBus
`ifdef EXT_FENCEI
    ,input logic fenceReq,
    output logic fenceEnd
`endif
);
    BpuFsqIO bpu_fsq_io();
    FsqCacheIO fsq_cache_io();
    CachePreDecodeIO cache_pd_io();
    PreDecodeRedirect pd_redirect();
    PreDecodeIBufferIO pd_ibuffer_io();
    FetchBundle fetchBundle;
    FrontendCtrl frontendCtrl;

    assign ifu_backend_io.fetchBundle = fetchBundle;
    assign frontendCtrl.redirect = fsq_back_io.redirect.en;
    assign frontendCtrl.redirect_mem = ~fsq_back_io.redirectBr.en & ~fsq_back_io.redirectCsr.en;
    assign frontendCtrl.redirectInfo = fsq_back_io.redirect.fsqInfo;
    BranchPredictor branch_predictor(.*);
    FSQ fsq(.*);
    ICache icache(.*);
    PreDecode predecode(.*
`ifdef FEAT_MEMPRED
                , .ssit_en(ifu_backend_io.ssit_en),
                .ssit_raddr(ifu_backend_io.ssit_raddr),
                .ssit_ridx(ifu_backend_io.ssit_rdata)
`endif
    );
    InstBuffer instBuffer(.*,
                          .full(frontendCtrl.ibuf_full),
                          .stall(ifu_backend_io.stall));
endmodule
