`ifndef INTERFACES_SVH
`define INTERFACES_SVH
`include "bundles.svh"
`include "axi.svh"

interface core_icache_if;
    logic ready; // cache can receive req
    logic req;
    logic valid; // data valid
    logic `N(`FETCH_WIDTH_LOG) req_size;
    logic `N(`VADDR_SIZE) addr;
    logic `N(`FETCH_WIDTH) rdata_valid;
    logic `ARRAY(`FETCH_WIDTH, `XLEN) rdata;

    modport cache (input req, req_size, addr, output ready, valid, rdata_valid, rdata);
    modport core (output req, req_size, addr, input ready, valid, rdata_valid, rdata);
    modport data (input ready, valid, rdata_valid, rdata);
endinterface //CoreCacheItf

interface core_dcache_if;
    logic ready;
    logic req;
    logic wr;
    logic `N(2) req_size;
    logic `N(`VADDR_SIZE) addr;
    logic `ARRAY(`FETCH_WIDTH, `XLEN) rdata;
    logic `ARRAY(`FETCH_WIDTH, `XLEN) wdata;

    modport cache (input req, wr, req_size, addr, wdata, output ready, rdata);
    modport core (output req, wr, req_size, addr, wdata, output ready, rdata);
endinterface //core_dcache_if

interface BpuBtbIO(
    input RedirectCtrl redirect,
    input logic squash,
    input SquashInfo squashInfo
);
    logic request;
    logic `VADDR_BUS pc;
    BTBEntry entry;

    modport btb (output entry, input request, pc, redirect, squash, squashInfo);
endinterface

interface BpuUBtbIO(
    input RedirectCtrl redirect,
    input BranchHistory history,
    input logic squash,
    input SquashInfo squashInfo
);
    logic request;
    logic `VADDR_BUS pc;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`GHIST_WIDTH) ghistIdx;
    PredictionResult result;

    modport ubtb (input request, pc, fsqIdx, history, redirect, squash, squashInfo, output result);
endinterface

interface BpuTageIO(
    input BranchHistory history,
    input RedirectCtrl redirect
);
    logic request;
    logic `VADDR_BUS pc;
    logic `N(`SLOT_NUM) prediction;
    TageMeta meta;

    modport tage (input request, pc, history, redirect, output prediction, meta);
endinterface

interface BpuRASIO(
    input RedirectCtrl redirect,
    input logic squash,
    input SquashInfo squashInfo
);
    logic request;
    RasType ras_type;
    logic en;
    logic `VADDR_BUS target;
    RasEntry entry;
    logic `N(`RAS_WIDTH) rasIdx;

    modport ras (input request, ras_type, redirect, squash, squashInfo, output en, entry, rasIdx);

endinterface

interface BpuFsqIO;
    PredictionResult prediction;
    logic `N(`FSQ_WIDTH) stream_idx;
    logic en;
    logic redirect;
    RedirectInfo redirect_info;
    logic squash;
    SquashInfo squashInfo;
    logic stall;

    modport fsq (input en, prediction, redirect, redirect_info, output stall, stream_idx);
    modport bpu (output en, prediction, redirect, redirect_info, input stall, stream_idx);
endinterface

interface FsqCacheIO;
    FetchStream stream;
    logic en;
    logic abandon; // cancel request at idle and lookup state
    logic `N(`FSQ_WIDTH) abandonIdx;
    logic ready;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic flush;
    logic stall;

    modport fsq (input ready, output en, stream, fsqIdx, abandon, abandonIdx, flush, stall);
    modport cache (output ready, input en, stream,fsqIdx, abandon, abandonIdx, flush, stall);
endinterface

interface CachePreDecodeIO;
    logic `N(`ICACHE_BANK) en;
    logic `ARRAY(`ICACHE_BANK, 32) data;
    FetchStream stream;
    logic `N(`FSQ_WIDTH) fsqIdx;

    modport cache (output en, data, stream, fsqIdx);
    modport pd (input en, data, stream, fsqIdx);
endinterface

interface ICacheAxi;
    AxiMAR mar;
    AxiSAR sar;
    AxiMR mr;
    AxiSR sr;

    modport cache(output mar, mr, input sar, sr);
    modport axi(input mar, mr, output sar, sr);
endinterface

interface ReplaceIO #(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter ADDR_WIDTH = $clog2(DEPTH)
);
    logic hit_en;
    logic miss_en;
    logic `N(WAY_WIDTH) hit_way;
    logic `N(WAY_WIDTH) miss_way;
    logic `N(ADDR_WIDTH) hit_index;
    logic `N(ADDR_WIDTH) miss_index;

    modport replace(input hit_en, miss_en, hit_way, hit_index, miss_index, output miss_way);
endinterface

interface PreDecodeRedirect;
    logic en;
    logic `VADDR_BUS pc;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `VADDR_BUS redirect_addr;
    BranchType branch_type;
    RasType ras_type;

    modport predecode(output en, fsqIdx, redirect_addr, pc, offset, branch_type, ras_type);
    modport redirect(input en, fsqIdx, redirect_addr, pc, offset, branch_type, ras_type);
endinterface

interface PreDecodeIBufferIO;
    logic `N(`ICACHE_BANK) en;
    logic `N($clog2(`ICACHE_BANK)) num;
    logic `ARRAY(`ICACHE_BANK, 32) inst;

    modport predecode(output en, num, inst);
    modport instbuffer(input en, num, inst);
endinterface

interface IBufferDecodeIO;
    logic `N(`FETCH_WIDTH) en;
    logic `ARRAY(`FETCH_WIDTH, 32) inst;

    modport instbuffer(output en, inst);
endinterface

`endif