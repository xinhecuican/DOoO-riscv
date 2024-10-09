`include "../../defines/defines.svh"

module IFU (
    input logic clk,
    input logic rst,
    AxiIO.masterr axi_io,
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

    logic predictor_rst, fsq_rst, icache_rst, decoder_rst, buf_rst;
    SyncRst rst_predictor(clk, rst, predictor_rst);
    SyncRst rst_fsq(clk, rst, fsq_rst);
    SyncRst rst_icache(clk, rst, icache_rst);
    SyncRst rst_decoder(clk, rst, decoder_rst);
    SyncRst rst_buf(clk, rst, buf_rst);

    assign ifu_backend_io.fetchBundle = fetchBundle;
    assign frontendCtrl.redirect = fsq_back_io.redirect.en;
    BranchPredictor branch_predictor(.*, .rst(predictor_rst));
    FSQ fsq(.*, .rst(fsq_rst));
    ICache icache(.*, .rst(icache_rst));
    PreDecode predecode(.*, .rst(decoder_rst));
    InstBuffer instBuffer(.*,
                          .rst(buf_rst),
                          .full(frontendCtrl.ibuf_full),
                          .stall(ifu_backend_io.stall));
endmodule
