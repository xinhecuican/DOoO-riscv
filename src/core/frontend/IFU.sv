`include "../../defines/defines.svh"

module IFU (
    input logic clk,
    input logic rst,
    ICacheAxi.cache axi_io,
    IfuBackendIO.ifu ifu_backend_io,
    FsqBackendIO.fsq fsq_back_io,
    CommitBus.in commitBus,
    TlbL2IO.tlb itlb_io,
    CsrTlbIO.tlb csr_itlb_io
);
    BpuFsqIO bpu_fsq_io();
    FsqCacheIO fsq_cache_io();
    CachePreDecodeIO cache_pd_io();
    PreDecodeRedirect pd_redirect();
    PreDecodeIBufferIO pd_ibuffer_io();
    FetchBundle fetchBundle;
    FrontendCtrl frontendCtrl();

    assign ifu_backend_io.fetchBundle = fetchBundle;
    assign frontendCtrl.redirect = fsq_back_io.redirect.en;
    BranchPredictor branch_predictor(.*);
    FSQ fsq(.*);
    ICache icache(.*);
    PreDecode predecode(.*);
    InstBuffer instBuffer(.*,
                          .full(frontendCtrl.ibuf_full),
                          .stall(ifu_backend_io.stall));
endmodule
