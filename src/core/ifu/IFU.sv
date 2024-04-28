`include "../../defines/defines.svh"

module IFU (
    input logic clk,
    input logic rst,
    ICacheAxi.cache axi_io
);
    BpuFsqIO bpu_fsq_io;
    FsqCacheIO fsq_cache_io;
    CachePreDecodeIO cache_pd_io;
    PreDecodeRedirect pd_redirect;
    PreDecodeIBufferIO pd_ibuffer_io;

    BranchPredictor branch_predictor(.*);
    FSQ fsq(.*);
    ICache icache(.*);
    PreDecode predecode(.*);
    InstBuffer instBuffer(.*);
endmodule
