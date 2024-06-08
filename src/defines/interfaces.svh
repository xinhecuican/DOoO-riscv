`ifndef INTERFACES_SVH
`define INTERFACES_SVH
`include "bundles.svh"
`include "axi.svh"

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

    modport ubtb (input request, pc, fsqIdx, ghistIdx, fsqDir, history, redirect, squash, squashInfo, update, updateInfo, output result, meta);
endinterface

interface BpuTageIO(
    input BranchHistory history,
    input RedirectCtrl redirect,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic ready;
    logic `VADDR_BUS pc;
    logic `N(`SLOT_NUM) prediction;
    TageMeta meta;

    modport tage (input pc, history, redirect, update, updateInfo, output prediction, meta, ready);
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

    modport ras (input request, ras_type, target, redirect, squash, squashInfo, update, updateInfo, output en, entry, rasIdx);

endinterface

interface BpuFsqIO;
    PredictionResult prediction;
    logic `N(`FSQ_WIDTH) stream_idx;
    logic stream_dir;
    logic lastStage;
    logic `N(`FSQ_WIDTH) lastStageIdx;
    PredictionMeta lastStageMeta;
    logic en;
    logic redirect; // s2 redirect s1
    logic squash; // backend redirect
    SquashInfo squashInfo;
    logic stall;
    logic update;
    BranchUpdateInfo updateInfo;

    modport fsq (input en, prediction, redirect, lastStage, lastStageIdx, lastStageMeta, output stall, stream_idx, stream_dir, squash, squashInfo, update, updateInfo);
    modport bpu (output en, prediction, redirect, lastStage, lastStageIdx, lastStageMeta, input stall, stream_idx, stream_dir, squash, squashInfo, update, updateInfo);
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
    BranchRedirectInfo redirectBr;

`ifdef DIFFTEST
    FsqIdxInfo `N(`COMMIT_WIDTH) diff_fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, `VADDR_SIZE) diff_pc;
`endif
    
    modport fsq (input fsqIdx, redirect, output streams, directions
`ifdef DIFFTEST
    ,input diff_fsqInfo,
    output diff_pc
`endif
    );
    modport backend (output fsqIdx, redirect, input streams, directions
`ifdef DIFFTEST
    ,output diff_fsqInfo,
    input diff_pc
`endif
    );
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
    parameter READ_PORT = 1,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter ADDR_WIDTH = DEPTH <= 1 ? 1 : $clog2(DEPTH)
);
    logic `N(READ_PORT) hit_en;
    logic `ARRAY(READ_PORT, WAY_WIDTH) hit_way;
    logic `N(WAY_WIDTH) miss_way;
    logic `N(ADDR_WIDTH) miss_index;
    logic `ARRAY(READ_PORT, ADDR_WIDTH) hit_index;

    modport replace(input hit_en, hit_way, hit_index, miss_index, output miss_way);
endinterface

interface PreDecodeRedirect;
    logic en;
    logic `VADDR_BUS pc;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `VADDR_BUS redirect_addr;
    BranchType br_type;
    RasType ras_type;

    modport predecode(output en, fsqIdx, redirect_addr, pc, offset, br_type, ras_type);
    modport redirect(input en, fsqIdx, redirect_addr, pc, offset, br_type, ras_type);
endinterface

interface PreDecodeIBufferIO;
    logic `N(`BLOCK_INST_SIZE) en;
    logic `N($clog2(`BLOCK_INST_SIZE)+1) num;
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
    logic `N($clog2(`FETCH_WIDTH) + 1) validNum;

    modport rename(input robIdx, output validNum);
    modport rob(output robIdx, input validNum);
endinterface

interface RenameDisIO;
    OPBundle `N(`FETCH_WIDTH) op;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs1;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs2;
    logic `N(`FETCH_WIDTH) wen;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    RobIdx `N(`FETCH_WIDTH) robIdx;

    modport rename(output op, prs1, prs2, wen, prd, robIdx);
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

interface DisIssueIO #(
    parameter PORT_NUM = 4,
    parameter DATA_SIZE = 32
);
    logic `N(PORT_NUM) en;
    IssueStatusBundle `N(PORT_NUM) status;
    logic `ARRAY(PORT_NUM, DATA_SIZE) data;
    logic full;

    modport dis (output en, status, data, input full);
    modport issue(input en, status, data, output full);
endinterface

interface IssueRegfileIO #(
    parameter PORT_SIZE = 4
);
    logic `N(PORT_SIZE) en;
    logic `ARRAY(PORT_SIZE, `PREG_WIDTH) preg;

    // 1 stage
    logic `ARRAY(PORT_SIZE, `XLEN) data;

    modport issue(output en, preg, input data);
    modport regfile(input en, preg, output data);
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

    modport exu (input en, rs1_data, rs2_data, bundle, streams, directions, br_type, ras_type, output valid);
    modport issue (output en, rs1_data, rs2_data, bundle, streams, directions, br_type, ras_type, input valid);
endinterface

interface IssueAluIO;
    logic en;
    logic valid; // fu valid
    logic `N(`XLEN) rs1_data;
    logic `N(`XLEN) rs2_data;
    IntIssueBundle bundle;
    FetchStream stream;
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
    FetchStream streams;
    logic direction;

    modport branch (input en, rs1_data, rs2_data, bundle, streams, direction);
endinterface

interface WriteBackBus;
    logic `N(`WB_SIZE) en;
    logic `N(`WB_SIZE) we;
    RobIdx `N(`WB_SIZE) robIdx;
    logic `ARRAY(`WB_SIZE, `PREG_WIDTH) rd;
    logic `ARRAY(`WB_SIZE, `XLEN) res;

    modport wb (output en, we, robIdx, rd, res);
endinterface

interface CommitBus;
    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    FsqIdxInfo `N(`COMMIT_WIDTH) fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, 5) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;
    logic `N($clog2(`COMMIT_WIDTH) + 1) wenum;

    logic `N($clog2(`COMMIT_WIDTH)+1) loadNum;
    logic `N($clog2(`COMMIT_WIDTH)+1) storeNum;

    modport rob(output en, we, fsqInfo, vrd, prd, num, wenum, loadNum, storeNum);
    modport in(input en, we, fsqInfo, vrd, prd, num, wenum);
    modport mem(input loadNum, storeNum);
endinterface

interface CommitWalk;
    logic walk;
    logic walkStart;
    RobIdx walkIdx;

    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;
    logic `N($clog2(`COMMIT_WIDTH) + 1) weNum;
    logic `ARRAY(`COMMIT_WIDTH, 5) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;

    modport rob (output walk, walkStart, walkIdx, en, we, vrd, prd, num, weNum);
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

interface BackendRedirectIO;
    BackendRedirectInfo branchRedirect;
    BackendRedirectInfo memRedirect;
    BranchRedirectInfo branchInfo;

    BackendRedirectInfo out;
    BranchRedirectInfo branchOut;

    modport redirect(input branchRedirect, memRedirect, branchInfo, output out, branchOut);
endinterface

interface DCacheLoadIO;
    logic `N(`LOAD_PIPELINE) req;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) vaddr;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) lqIdx;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) ptag;

    logic `N(`LOAD_PIPELINE) hit;
    logic `N(`LOAD_PIPELINE) conflict;
    logic `N(`LOAD_PIPELINE) full;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) rdata;

    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lq_en;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lqData;
    logic `ARRAY(`LOAD_REFILL_SIZE, `LOAD_QUEUE_WIDTH) lqIdx_o;

    modport dcache (input req, vaddr, lqIdx, ptag, output hit, rdata, conflict, full, lq_en, lqData, lqIdx_o);
    modport queue (input lq_en, lqData, lqIdx_o);
endinterface

interface DCacheStoreIO;
    logic req;
    logic `N(`STORE_COMMIT_WIDTH) scIdx;
    logic `N(`VADDR_SIZE) paddr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) mask;

    logic valid;
    logic success;
    logic conflict;
    logic `N(`STORE_COMMIT_WIDTH) conflictIdx;

    modport dcache (input req, scIdx, paddr, data, mask, output valid, success, conflict, conflictIdx);
    modport buffer (output req, scIdx, paddr, data, mask, input valid, success, conflict, conflictIdx);
endinterface

interface LoadForwardIO;
    LoadFwdData `N(`LOAD_PIPELINE) fwdData;
    logic `N(`DCACHE_BYTE) mask;
    logic `N(`DCACHE_BITS) data;

    modport queue(input fwdData, output mask, data);
endinterface

interface StoreCommitIO;
    logic `N(`STORE_PIPELINE) en;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE-2) addr;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) mask;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BITS) data;

    logic  conflict;

    modport queue (output en, addr, mask, data, input conflict);
    modport buffer (input en, addr, mask, data, output conflict);
endinterface

interface DCacheAxi;
    AxiMAR mar;
    AxiSAR sar;
    AxiMR mr;
    AxiSR sr;
    AxiMAW maw;
    AxiSAW saw;
    AxiMW mw;
    AxiSW sw;
    AxiMB mb;
    AxiSB sb;

    modport cache(output mar, mr, maw, mw, mb, input sar, sr, saw, sw, sb);
    modport replace(output maw, mw, mb, input saw, sw, sb);
    modport miss(output mar, mr, input sar, sr);
    modport axi(input mar, mr, maw, mw, mb, output sar, sr, saw, sw, sb);
endinterface

`ifdef DIFFTEST
interface DiffRAT;
    logic `ARRAY(5, `PREG_WIDTH) map_reg;

    modport rat (output map_reg);
    modport regfile (input map_reg);
endinterface

`endif


`endif