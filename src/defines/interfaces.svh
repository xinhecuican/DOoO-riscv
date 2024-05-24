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
    input SquashInfo squashInfo,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic request;
    logic `VADDR_BUS pc;
    BTBEntry entry;

    modport btb (output entry, input request, pc, redirect, squash, squashInfo, update, updateInfo);
endinterface

interface BpuUBtbIO(
    input RedirectCtrl redirect,
    input BranchHistory history,
    input logic squash,
    input logic update,
    input SquashInfo squashInfo,
    input BranchUpdateInfo updateInfo
);
    logic request;
    logic `VADDR_BUS pc;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic fsqDir;
    logic `N(`GHIST_WIDTH) ghistIdx;
    PredictionResult result;
    UBTBMeta meta;

    modport ubtb (input request, pc, fsqIdx, fsqDir, history, redirect, squash, squashInfo, update, updateInfo, output result, meta);
endinterface

interface BpuTageIO(
    input BranchHistory history,
    input RedirectCtrl redirect,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic request;
    logic `VADDR_BUS pc;
    logic `N(`SLOT_NUM) prediction;
    TageMeta meta;

    modport tage (input request, pc, history, redirect, update, updateInfo, output prediction, meta);
endinterface

interface BpuRASIO(
    input RedirectCtrl redirect,
    input logic squash,
    input SquashInfo squashInfo,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic request;
    RasType ras_type;
    logic en;
    logic `VADDR_BUS target;
    RasEntry entry;
    logic `N(`RAS_WIDTH) rasIdx;

    modport ras (input request, ras_type, redirect, squash, squashInfo, update, updateInfo, output en, entry, rasIdx);

endinterface

interface BpuFsqIO;
    PredictionResult prediction;
    logic `N(`FSQ_WIDTH) stream_idx;
    logic stream_dir;
    logic lastStage;
    logic `N(`FSQ_WIDTH) lastStageIdx;
    PredictionResult lastStageMeta;
    logic en;
    logic redirect;
    RedirectInfo redirect_info;
    logic squash;
    SquashInfo squashInfo;
    logic stall;
    logic update;
    BranchUpdateInfo updateInfo;

    modport fsq (input en, prediction, redirect, redirect_info, squash, squashInfo, update, updateInfo, lastStage, lastStageIdx, lastStageMeta, output stall, stream_idx, stream_dir);
    modport bpu (output en, prediction, redirect, redirect_info, squash, squashInfo, update, updateInfo, lastStage, lastStageIdx, lastStageMeta, input stall, stream_idx, stream_dir);
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

interface FsqBackendIO;
    FetchStream `N(`ALU_SIZE) streams;
    logic `ARRAY(`ALU_SIZE, `FSQ_WIDTH) fsqIdx;
    logic `N(`ALU_SIZE) directions;

    BackendRedirectInfo redirect;
    
    modport fsq (input fsqIdx, redirect, output streams, directions);
    modport backend (output fsqIdx, redirect, input streams, directions);
endinterface

interface CachePreDecodeIO;
    logic `N(`BLOCK_INST_SIZE) en;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) data;
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
    logic `N(`BLOCK_INST_SIZE) en;
    logic `N($clog2(`BLOCK_INST_SIZE)) num;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) inst;
    logic `N(`FSQ_WIDTH) fsqIdx;

    modport predecode(output en, num, inst, fsqIdx);
    modport instbuffer(input en, num, inst, fsqIdx);
endinterface

interface IfuBackendIO;
    FetchBundle fetchBundle;
    logic stall;

    modport ifu(output fetchBundle, input stall);
    modport backend(input fetchBundle, output stall);
endinterface

interface DecodeRenameIO;
    OPBundle `N(`FETCH_WIDTH) op;

    modport decode(output op);
    modport rename(input op);
endinterface

interface ROBRenameIO;
    RobIdx robIdx;
    logic `N($clog2(`FETCH_WIDTH)) validNum;

    modport rename(input robIdx);
    modport rob(output robIdx);
endinterface

interface RenameDisIO;
    OPBundle `N(`FETCH_WIDTH) op;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs1;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs2;
    logic `N(`FETCH_WIDTH) wen;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    RobIdx `N(`FETCH_WIDTH) robIdx;

    modport rename(output op, prs1, prs2, prd, robIdx);
    modport dis(input op, prs1, prs2, wen, prd, robIdx);
    modport rob(input op, prd, robIdx);
endinterface

interface RegfileIO;
    logic `N(`REGFILE_READ_PORT) en;
    logic `ARRAY(`REGFILE_READ_PORT, `PREG_WIDTH) raddr;
    logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata;
    logic `N(`REGFILE_WRITE_PORT) we;
    logic `ARRAY(`REGFILE_WRITE_PORT, `PREG_WIDTH) waddr;
    logic `ARRAY(`REGFILE_WRITE_PORT, `XLEN) wdata;

    modport regfile (input raddr, waddr, wdata, en, we, output rdata);
endinterface

interface DisIntIssueIO;
    logic `N(`INT_DISPATCH_PORT) en;
    IssueStatusBundle `N(`INT_DISPATCH_PORT) status;
    IntIssueBundle `N(`INT_DISPATCH_PORT) data;
    logic full;

    modport dis (output en, status, data, input full);
    modport issue(input en, status, data, output full);
endinterface

interface IssueRegfileIO #(
    parameter PORT_SIZE = 4
);
    logic `N(PORT_SIZE) en;
    logic `ARRAY(PORT_SIZE, `PREG_WIDTH) rs1;
    logic `ARRAY(PORT_SIZE, `PREG_WIDTH) rs2;

    // 1 stage
    logic `ARRAY(PORT_SIZE, `XLEN) rs1_data;
    logic `ARRAY(PORT_SIZE, `XLEN) rs2_data;

    modport issue(output en, rs1, rs2, input rs1_data, rs2_data);
    modport regfile(input en, rs1, rs2, output rs1_data, rs2_data);
endinterface

interface IntIssueExuIO;
    logic `N(`ALU_SIZE) en;
    logic `N(`ALU_SIZE) valid; // fu valid
    logic `ARRAY(`ALU_SIZE, `XLEN) rs1_data;
    logic `ARRAY(`ALU_SIZE, `XLEN) rs2_data;
    IntIssueBundle `N(`ALU_SIZE) bundle;
    FetchStream `N(`ALU_SIZE) streams;
    logic `N(`ALU_SIZE) directions; // fsq dir
    BranchType `N(`ALU_SIZE) br_type;
    RasType `N(`ALU_SIZE) ras_type;

    modport exu (input en, rs1_data, rs2_data, bundle, streams, directions, output valid);
    modport issue (output en, rs1_data, rs2_data, bundle, streams, directions, input valid);
endinterface

interface IssueAluIO;
    logic en;
    logic valid; // fu valid
    logic `N(`XLEN) rs1_data;
    logic `N(`XLEN) rs2_data;
    IntIssueBundle bundle;
    FetchSteram stream;
    logic direction;
    RasType ras_type;
    BranchType br_type;

    modport alu (input en, rs1_data, rs2_data, bundle, stream, direction, ras_type, br_type, output valid);
endinterface

interface IssueBranchIO;
    logic en;
    logic `N(`XLEN) rs1_data;
    logic `N(`XLEN) rs2_data;
    IntIssueBundle bundle;
    FetchSteram streams;
    logic direction;

    modport branch (input en, rs1_data, rs2_data, bundle, streams, direction);
endinterface

interface WriteBackBus;
    WBData `N(`WB_SIZE) data;

    modport wb (output data);
    modport slave (input data);
endinterface

interface CommitBus;
    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    FsqIdxInfo `N(`COMMIT_WIDTH) fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;
    logic `N($clog2(`COMMIT_WIDTH) + 1) wenum;

    modport rob(output en, we, fsqInfo, vrd, prd, num, wenum);
endinterface

interface CommitWalk;
    logic walk;
    logic walkStart;
    RobIdx walkIdx;

    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;
    logic `N($clog2(`COMMIT_WIDTH) + 1) weNum;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;

    modport rob (output walk, walkStart, walkIdx, en, we, vrd, prd);
endinterface

interface FrontendCtrl;
    logic ibuf_full;
    logic redirect;
endinterface

interface BackendCtrl;
    logic rename_full;
    logic rob_full;
    logic dis_full;

    logic redirect;
    RobIdx redirectIdx;
endinterface
`endif