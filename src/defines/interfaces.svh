`ifndef INTERFACES_SVH
`define INTERFACES_SVH
`include "bundles.svh"
`include "bus/axi.svh"
`include "bus/apb.svh"
`include "bus/ace.svh"
`include "bus/mem.svh"
`include "debug.svh"

interface BpuBtbIO#(
    parameter TAG_SIZE=1
)(
    input RedirectCtrl redirect,
    input logic squash,
    input SquashInfo squashInfo,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic request;
    logic `VADDR_BUS pc;
    BTBUpdateInfo entry;
    logic `N(TAG_SIZE) tag;

    modport btb (output entry, tag, input request, pc, redirect, squash, squashInfo, update, updateInfo);
endinterface

interface BpuUBtbIO(
    input RedirectCtrl redirect,
    input BranchHistory history,
    input logic squash,
    input logic update,
    input SquashInfo squashInfo,
    input BranchUpdateInfo updateInfo
);
    logic `VADDR_BUS pc;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic fsqDir;
    PredictionResult result;
    UBTBMeta meta;

    modport ubtb (input pc, fsqIdx, fsqDir, history, redirect, squash, squashInfo, update, updateInfo, output result, meta);
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
    logic `N(`SLOT_NUM) use_tage;
    logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) provider_ctr;
    TageMeta meta;

    modport tage (input pc, history, redirect, update, updateInfo, output prediction, use_tage, provider_ctr, meta, ready);
endinterface

interface BpuSCIO(
    input BranchHistory history,
    input RedirectCtrl redirect,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic `VADDR_BUS pc;
    SCMeta meta;
    logic `N(`SLOT_NUM) use_tage;
    logic `ARRAY(`SLOT_NUM, `TAGE_CTR_SIZE) tage_ctrs;
    logic `N(`SLOT_NUM) tage_prediction;
    logic `N(`SLOT_NUM) prediction;

    modport sc (input pc, history, redirect, update, updateInfo, use_tage, tage_ctrs, tage_prediction, 
                output prediction, meta);
endinterface //BpuSCIO

interface BpuITTAGEIO(
    input BranchHistory history,
    input RedirectCtrl redirect,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic `VADDR_BUS pc;
    ITTageMeta meta; 
    logic `VADDR_BUS target;
`ifdef FEAT_ITTAGE_REGION
    logic last_stage_ind;
    logic `N(`ITTAGE_REGION_WIDTH) region_idx;
    logic `N(`ITTAGE_REGION_TAG) update_tag;
    logic `N(`ITTAGE_REGION_WIDTH) update_region_idx;
`endif

    modport ittage(input pc, history, redirect, update, updateInfo, output meta, target
`ifdef FEAT_ITTAGE_REGION
    , input update_tag, region_idx, last_stage_ind, output update_region_idx
`endif
    );
endinterface //BpuITTAGEIO()

interface BpuRASIO(
    input RedirectCtrl redirect,
    input logic squash,
    input SquashInfo squashInfo,
    input logic update,
    input BranchUpdateInfo updateInfo
);
    logic request;
    BranchType br_type;
    logic en;
    logic `VADDR_BUS target;
    RasEntry entry;
    RasRedirectInfo rasInfo;
    RasRedirectInfo linfo; // lookup
`ifdef T_DEBUG
    logic lastStage;
    logic `N(`FSQ_WIDTH) lastStageIdx;
`endif

    modport ras (input request, br_type, target, redirect, squash, squashInfo, update, updateInfo, linfo, output en, entry, rasInfo
`ifdef T_DEBUG
    , input lastStage, lastStageIdx
`endif
    );


endinterface

interface BpuFsqIO;
    PredictionResult prediction;
    logic `N(`FSQ_WIDTH) stream_idx;
    logic stream_dir;
    logic lastStage;
    logic `N(`FSQ_WIDTH) lastStageIdx;
    PredictionMeta lastStageMeta;
    PredictionResult lastStagePred;
    logic en;
    logic redirect; // s2 redirect s1
    logic squash; // backend redirect
    SquashInfo squashInfo;
    logic stall;
    logic update;
    BranchUpdateInfo updateInfo;
    logic `N(`VADDR_SIZE) ras_addr; // last stage

`ifdef FEAT_ITTAGE_REGION
    logic `N(`ITTAGE_REGION_TAG) ittage_tag;
    logic `N(`ITTAGE_REGION_WIDTH) ittage_idx;
`endif

    modport fsq (input en, prediction, redirect, lastStage, lastStageIdx, lastStageMeta, lastStagePred, ras_addr,
                output stall, stream_idx, stream_dir, squash, squashInfo, update, updateInfo
`ifdef FEAT_ITTAGE_REGION
    , input ittage_idx, output ittage_tag
`endif            
    );
    modport bpu (output en, prediction, redirect, lastStage, lastStageIdx, lastStageMeta, lastStagePred, ras_addr,
                input stall, stream_idx, stream_dir, squash, squashInfo, update, updateInfo
`ifdef FEAT_ITTAGE_REGION
    , output ittage_idx, input ittage_tag
`endif
                );
endinterface

interface FsqCacheIO;
    FetchStream stream;
    logic en;
    logic abandon; // cancel request at idle and lookup state
    FsqIdx abandonIdx;
    logic ready;
    FsqIdx fsqIdx;
    logic flush;
    logic stall;
    logic `N(`PREDICTION_WIDTH) shiftOffset;
`ifdef RVC
    logic `N(`PREDICTION_WIDTH) shiftIdx;
`endif

    modport fsq (input ready, output en, stream, fsqIdx, abandon, abandonIdx, flush, stall, shiftOffset
`ifdef RVC
    , shiftIdx
`endif
    );
    modport cache (output ready, input en, stream,fsqIdx, abandon, abandonIdx, flush, stall, shiftOffset
`ifdef RVC
    , shiftIdx
`endif
    );
endinterface

interface FsqBackendIO;
    FetchStream `N(`ALU_SIZE) streams;
    logic `ARRAY(`ALU_SIZE, `FSQ_WIDTH) fsqIdx;
    logic `N(`VADDR_SIZE) exc_pc;
    logic `N(`PREDICTION_WIDTH+1) commitStreamSize;

    BackendRedirectInfo redirect;
    BranchRedirectInfo redirectBr;
    CSRRedirectInfo redirectCsr;

`ifdef DIFFTEST
    FsqIdxInfo `N(`COMMIT_WIDTH) diff_fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, `VADDR_SIZE) diff_pc;
`endif
    
    modport fsq (input fsqIdx, redirect, redirectBr, redirectCsr, output streams, exc_pc, commitStreamSize
`ifdef DIFFTEST
    ,input diff_fsqInfo, output diff_pc
`endif
    );
    modport backend (output fsqIdx, redirect, redirectBr, redirectCsr, input streams, exc_pc, commitStreamSize
`ifdef DIFFTEST
    ,output diff_fsqInfo, input diff_pc
`endif
    );
endinterface

interface CachePreDecodeIO;
    logic `N(`BLOCK_INST_SIZE) en;
    logic `N(`BLOCK_INST_SIZE) exception;
`ifdef RVC
    logic `ARRAY(`BLOCK_INST_SIZE+1, `INST_BITS) data;
`else
    logic `ARRAY(`BLOCK_INST_SIZE, `INST_BITS) data;
`endif
    logic `N(`VADDR_SIZE) start_addr;
    FetchStream stream;
    FsqIdx fsqIdx;
    logic `N(`PREDICTION_WIDTH) shiftOffset;
`ifdef RVC
    logic `N(`PREDICTION_WIDTH) shiftIdx;
`endif

    modport cache (output en, exception, start_addr, data, stream, fsqIdx, shiftOffset
`ifdef RVC
    , shiftIdx
`endif
    );
    modport pd (input en, exception, start_addr, data, stream, fsqIdx, shiftOffset
`ifdef RVC
    , shiftIdx
`endif
    );
endinterface

interface ReplaceIO #(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter READ_PORT = 1,
    parameter WAY_WIDTH = WAY_NUM > 1 ? $clog2(WAY_NUM) : 1,
    parameter ADDR_WIDTH = DEPTH > 1 ? $clog2(DEPTH) : 1
);
    logic `N(READ_PORT) hit_en;
    logic `N(READ_PORT) hit_invalid;
    logic `ARRAY(READ_PORT, WAY_NUM) hit_way;
    logic `N(WAY_NUM) miss_way;
    logic `N(ADDR_WIDTH) miss_index;
    logic `ARRAY(READ_PORT, ADDR_WIDTH) hit_index;

    modport replace(input hit_en, hit_invalid, hit_way, hit_index, miss_index, output miss_way);
endinterface

interface ReplaceD1IO #(
    parameter WAY_NUM = 4,
    parameter READ_PORT = 1,
    parameter WAY_WIDTH = $clog2(WAY_NUM)
);
    logic `N(READ_PORT) hit_en;
    logic `ARRAY(READ_PORT, WAY_WIDTH) hit_way;
    logic `N(WAY_WIDTH) miss_way;

    modport replace(input hit_en, hit_way, output miss_way);
endinterface

interface PreDecodeRedirect;
    logic en;
    logic exc_en;
    logic entry_error;
    logic direct;
    FsqIdx fsqIdx;
    FetchStream stream;
    BranchType br_type;
    logic `N(`PREDICTION_WIDTH) size;
    logic `N(`PREDICTION_WIDTH) last_offset;
    logic `N(`FSQ_WIDTH) fsqIdx_pre;
    logic `N(`VADDR_SIZE) ras_addr;

    modport predecode(output en, exc_en, entry_error, direct, fsqIdx, stream, size, last_offset, br_type, fsqIdx_pre, input ras_addr);
    modport redirect(input en, exc_en, entry_error, direct, fsqIdx, stream, size, last_offset, br_type, fsqIdx_pre, output ras_addr);
endinterface

interface PreDecodeIBufferIO;
    logic `N(`BLOCK_INST_SIZE) en;
    logic `N(`BLOCK_INST_SIZE) ipf;
    logic `N($clog2(`BLOCK_INST_SIZE)+1) num;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) inst;
    logic `ARRAY(`BLOCK_INST_SIZE, `PREDICTION_WIDTH) offset;
    logic iam; // for exception, instruction address misaligned
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`PREDICTION_WIDTH) shiftIdx;
    logic `N(`VADDR_SIZE) start_addr;

    modport predecode(output en, ipf, num, inst, offset, iam, fsqIdx, shiftIdx, start_addr);
    modport instbuffer(input en, ipf, num, inst, offset, iam, fsqIdx, shiftIdx, start_addr);
endinterface

interface IfuBackendIO;
    FetchBundle fetchBundle;
    logic stall;
`ifdef FEAT_MEMPRED
    logic ssit_en;
    logic `ARRAY(2, `FSQ_WIDTH) ssit_raddr;
    logic `ARRAY(2, `SSIT_WIDTH) ssit_rdata;
`endif

    modport ifu(output fetchBundle, input stall
`ifdef FEAT_MEMPRED
            , input ssit_en, ssit_raddr, output ssit_rdata
`endif
    );
    modport backend(input fetchBundle, output stall
`ifdef FEAT_MEMPRED
            , output ssit_en, ssit_raddr, input ssit_rdata
`endif
    );
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
`ifdef RVF
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs3;
    logic `N(`FETCH_WIDTH) fp_wen;
`endif
    logic `N(`FETCH_WIDTH) int_wen;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) old_prd;
    RobIdx `N(`FETCH_WIDTH) robIdx;

    modport rename(output op, prs1, prs2, int_wen, prd, old_prd, robIdx
`ifdef RVF
    , prs3, fp_wen
`endif
    );
    modport dis(input op, prs1, prs2, int_wen, prd, robIdx
`ifdef RVF
    , prs3, fp_wen
`endif
    );
    modport rob(input op, prd, old_prd, robIdx);
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

interface DisCsrIO;
    logic en;
    logic `N(`PREG_WIDTH) rs1;
    CsrIssueBundle bundle;
    logic full;

    modport dis (output en, rs1, bundle, input full);
    modport issue(input en, rs1, bundle, output full);
endinterface

interface IssueRegIO #(
    parameter BANK_SIZE = 4,
    parameter PORT_SIZE = 4
);
    logic `N(BANK_SIZE) en;
    logic `ARRAY(PORT_SIZE, `PREG_WIDTH) preg;

    logic `N(BANK_SIZE) ready;
    logic `ARRAY(PORT_SIZE, `XLEN) data;
    modport issue(output en, preg, input ready, data);
    modport regfile(input en, preg, output ready, data);
endinterface

interface IssueWakeupIO #(
    parameter BANK_SIZE = 4
);
    logic `N(BANK_SIZE) en;
    logic `N(BANK_SIZE) we;
    logic `ARRAY(BANK_SIZE, `PREG_WIDTH) rd;

    logic `N(BANK_SIZE) ready;

    modport issue(output en, we, rd, input ready);
    modport wakeup(input en, we, rd, output ready);
endinterface

interface IntIssueExuIO;
    logic `N(`ALU_SIZE) en;
    logic `N(`ALU_SIZE) valid; // fu valid
    logic `ARRAY(`ALU_SIZE, `XLEN) rs1_data;
    logic `ARRAY(`ALU_SIZE, `XLEN) rs2_data;
    ExStatusBundle `N(`ALU_SIZE) status;
    IntIssueBundle `N(`ALU_SIZE) bundle;
    FetchStream `N(`ALU_SIZE) streams;
    logic `ARRAY(`ALU_SIZE, `VADDR_SIZE) vaddrs;

    modport exu (input en, rs1_data, rs2_data, status, bundle, streams, vaddrs, output valid);
    modport issue (output en, rs1_data, rs2_data, status, bundle, streams, vaddrs, input valid);
endinterface

interface IssueAluIO;
    logic en;
    logic valid; // fu valid
    logic `N(`XLEN) rs1_data;
    logic `N(`XLEN) rs2_data;
    ExStatusBundle status;
    IntIssueBundle bundle;
    FetchStream stream;
    logic `N(`VADDR_SIZE) vaddr;
    BranchType br_type;

    modport alu (input en, rs1_data, rs2_data, status, bundle, stream, vaddr, br_type, output valid);
endinterface

interface IssueCSRIO;
    logic en;
    logic `N(`XLEN) rdata;
    ExStatusBundle status;
    CsrIssueBundle bundle;

    modport issue(output en, rdata, status, bundle);
    modport csr (input en, rdata, status, bundle);
endinterface

interface IssueMultIO;
    logic `N(`MULT_SIZE) en;
    logic `ARRAY(`MULT_SIZE, `XLEN) rs1_data;
    logic `ARRAY(`MULT_SIZE, `XLEN) rs2_data;
    ExStatusBundle `N(`MULT_SIZE) status;
    MultIssueBundle `N(`MULT_SIZE) bundle;
    logic div_ready;
    logic div_end;

    modport issue(output en, rs1_data, rs2_data, status, bundle, input div_ready, div_end);
    modport mult (input en, rs1_data, rs2_data, status, bundle, output div_ready, div_end);
endinterface

interface IssueFMiscIO;
    logic `N(`FMISC_SIZE) en;
    logic `ARRAY(`FMISC_SIZE, `XLEN) rs1_data;
    logic `ARRAY(`FMISC_SIZE, `XLEN) rs2_data;
    ExStatusBundle `N(`FMISC_SIZE) status;
    FMiscIssueBundle `N(`FMISC_SIZE) bundle;
    logic `N(`FMISC_SIZE) stall;

    modport issue (output en, rs1_data, rs2_data, status, bundle, input stall);
    modport fmisc (input en, rs1_data, rs2_data, status, bundle, output stall);
endinterface

interface IssueFMAIO;
    logic `N(`FMA_SIZE) en;
    logic `ARRAY(`FMA_SIZE, `XLEN) rs1_data;
    logic `ARRAY(`FMA_SIZE, `XLEN) rs2_data;
    logic `ARRAY(`FMA_SIZE, `XLEN) rs3_data;
    ExStatusBundle `N(`FMA_SIZE) status;
    FMAIssueBundle `N(`FMA_SIZE) bundle;

    modport issue (output en, rs1_data, rs2_data, rs3_data, status, bundle);
    modport fma (input en, rs1_data, rs2_data, rs3_data, status, bundle);
endinterface

interface IssueFDivIO;
    logic `N(`FDIV_SIZE) en;
    logic `ARRAY(`FDIV_SIZE, `XLEN) rs1_data;
    logic `ARRAY(`FDIV_SIZE, `XLEN) rs2_data;
    ExStatusBundle `N(`FDIV_SIZE) status;
    FDivIssueBundle `N(`FDIV_SIZE) bundle;
    logic `N(`FDIV_SIZE) done;

    modport issue (output en, rs1_data, rs2_data, status, bundle, input done);
    modport fdiv (input en, rs1_data, rs2_data, status, bundle, output done);
endinterface


interface WriteBackIO#(
    parameter FU_SIZE = 4
);
    WBData `N(FU_SIZE) datas;
    logic `N(FU_SIZE) valid;

    modport wb (input datas, output valid);
    modport fu (output datas, input valid);
endinterface

interface WakeupBus #(
    parameter PORT_NUM=4
);
    logic `N(PORT_NUM) en;
    logic `N(PORT_NUM) we;
    logic `ARRAY(PORT_NUM, `PREG_WIDTH) rd;

    modport out(output en, we, rd);
    modport in(input en, we, rd);
endinterface

interface WriteBackBus #(
    parameter PORT_NUM=4
);
    logic `N(PORT_NUM) en;
    logic `N(PORT_NUM) we;
    RobIdx `N(PORT_NUM) robIdx;
    logic `ARRAY(PORT_NUM, `PREG_WIDTH) rd;
    logic `ARRAY(PORT_NUM, `XLEN) res;
    logic `ARRAY(PORT_NUM, `EXC_WIDTH) exccode;
    logic `N(PORT_NUM) irq_enable;

    modport out(output en, we, robIdx, rd, res, exccode, irq_enable);
    modport in(input en, we, robIdx, rd, res, exccode, irq_enable);
endinterface

interface CommitBus;
    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    logic `N(`COMMIT_WIDTH) fp_we;
`ifdef RVC
    logic `N(`COMMIT_WIDTH) rvc;
`endif
    logic `N(`COMMIT_WIDTH) excValid;
    logic fence_valid;
    FsqIdxInfo `N(`COMMIT_WIDTH) fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, 5) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;

    logic `N($clog2(`COMMIT_WIDTH)+1) loadNum;
    logic `N($clog2(`COMMIT_WIDTH)+1) storeNum;
    RobIdx robIdx;

    modport rob(output en, we, excValid, fence_valid, fsqInfo, vrd, prd, num, loadNum, storeNum, robIdx, output fp_we
`ifdef RVC
    , output rvc
`endif
    );
    modport in(input en, we, excValid, fsqInfo, vrd, prd, num, input fp_we
`ifdef RVC
    , input rvc
`endif
    );
    modport mem(input loadNum, storeNum, robIdx, fence_valid);
    modport csr(input robIdx, fsqInfo, fence_valid, en
`ifdef RVC
    , input rvc
`endif
    );
endinterface

interface BackendRedirectIO;
    BackendRedirectInfo branchRedirect;
    BackendRedirectInfo memRedirect;
`ifdef FEAT_MEMPRED
    logic mem_raw;
    FsqIdxInfo wfsqInfo;
`endif
    BranchRedirectInfo branchInfo;
    RobIdx memRedirectIdx;

    BackendRedirectInfo out;
    BranchRedirectInfo branchOut;
    CSRRedirectInfo csrOut;

    modport redirect(input branchRedirect, memRedirect, memRedirectIdx, branchInfo, output out, branchOut, csrOut);
    modport mem(output memRedirect, memRedirectIdx
`ifdef FEAT_MEMPRED
                , mem_raw, wfsqInfo
`endif
    );
endinterface

interface RobRedirectIO;
    logic fence;
    BackendRedirectInfo csrRedirect;

    modport rob (output csrRedirect, fence);
    modport redirect (input csrRedirect, fence);
endinterface

interface DCacheLoadIO;
    logic `N(`LOAD_PIPELINE) req;
    logic `N(`LOAD_PIPELINE) oldest;
    logic `N(`LOAD_PIPELINE) req_cancel;
    logic `N(`LOAD_PIPELINE) req_cancel_s2;
    logic `N(`LOAD_PIPELINE) req_cancel_s3;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) vaddr;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_QUEUE_WIDTH) lqIdx;
    RobIdx `N(`LOAD_PIPELINE) robIdx;
    logic `ARRAY(`LOAD_PIPELINE, `TLB_TAG) ptag;

    logic `N(`LOAD_PIPELINE) hit;
    logic `N(`LOAD_PIPELINE) conflict;
    logic `N(`LOAD_PIPELINE) full;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) rdata;

    logic `N(`LOAD_REFILL_SIZE) lq_en;
    logic `ARRAY(`LOAD_REFILL_SIZE, `DCACHE_BITS) lqData;
    logic `ARRAY(`LOAD_REFILL_SIZE, `LOAD_QUEUE_WIDTH) lqIdx_o;

    modport dcache (input req, oldest, vaddr, lqIdx, ptag, req_cancel, req_cancel_s2, req_cancel_s3, robIdx, output hit, rdata, conflict, full, lq_en, lqData, lqIdx_o);
    modport queue (input lq_en, lqData, lqIdx_o);
endinterface

interface DCacheStoreIO;
    logic req;
    logic `N(`STORE_COMMIT_WIDTH) scIdx;
    logic `N(`PADDR_SIZE) paddr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) mask;

    logic valid;
    logic success;
    logic conflict;
    logic `N(`STORE_COMMIT_WIDTH) conflictIdx;
    logic refill;
    logic `N(`STORE_COMMIT_WIDTH) refillIdx;

    modport dcache (input req, scIdx, paddr, data, mask, output valid, success, conflict, conflictIdx, refill, refillIdx);
    modport buffer (output req, scIdx, paddr, data, mask, input valid, success, conflict, conflictIdx, refill, refillIdx);
endinterface

interface DCacheAmoIO;
    logic req;
    logic `N(`PADDR_SIZE) paddr;
    logic `N(`DCACHE_BYTE) mask;
    logic `N(`XLEN) data;
    logic `N(`AMOOP_WIDTH) op;
`ifdef RV64I
    logic word;
`endif

    logic ready;
    logic success;
    logic `N(`DCACHE_BITS) rdata;
    logic refill;

    modport dcache (input req, paddr, data, op, mask, output ready, success, rdata, refill
`ifdef RV64I
                    ,input word
`endif
    );
    modport buffer (output req, paddr, data, op, mask, input ready, success, rdata, refill
`ifdef RV64I
                    ,output word
`endif
    );
endinterface

interface StoreSetIO;
    logic `N(`FETCH_WIDTH) en;
    logic `ARRAY(`FETCH_WIDTH, `SSIT_WIDTH) raddr;
    SSITEntry `N(`FETCH_WIDTH) ssit_entrys;
    logic ssit_we;
    logic `ARRAY(2, `SSIT_WIDTH) ssit_widx;

    logic `ARRAY(`LOAD_PIPELINE, `LFST_WIDTH) lfst_raddr;
    logic `N(`LOAD_PIPELINE) lfst_en;
    RobIdx `N(`LOAD_PIPELINE) lfst_idx;

    logic `N(`FETCH_WIDTH) lfst_we;
    logic `ARRAY(`FETCH_WIDTH, `LFST_WIDTH) lfst_waddr;
    RobIdx `N(`FETCH_WIDTH) lfst_widx;
    logic `N(`STORE_PIPELINE) lfst_finish;
    logic `ARRAY(`STORE_PIPELINE, `LFST_WIDTH) lfst_finish_waddr;
    RobIdx `N(`STORE_PIPELINE) lfst_finish_idx;

    modport ss(input en, raddr, lfst_raddr, lfst_we, lfst_waddr, lfst_widx, ssit_we, ssit_widx,
                input lfst_finish, lfst_finish_waddr, lfst_finish_idx,
                output ssit_entrys, lfst_en, lfst_idx);
    modport rename(output en, raddr);
    modport dis(input ssit_entrys, output lfst_raddr, lfst_we, lfst_waddr, lfst_widx);
    modport lsu(input lfst_en, lfst_idx, output lfst_finish, lfst_finish_waddr, lfst_finish_idx);
endinterface

interface LoadForwardIO;
    LoadFwdData `N(`LOAD_PIPELINE) fwdData;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) mask;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) data;

    modport queue(input fwdData, output mask, data);
endinterface

interface StoreCommitIO;
    logic `N(`STORE_PIPELINE) en;
    logic `N(`STORE_PIPELINE) uncache;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE-`DCACHE_BYTE_WIDTH) addr;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) mask;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BITS) data;

    logic  conflict;

    modport queue (output en, addr, mask, data, uncache, input conflict);
    modport buffer (input en, addr, mask, data, uncache, output conflict);
endinterface

interface ITLBCacheIO;
    logic `N(2) req;
    logic `ARRAY(2, `VADDR_SIZE) vaddr;
    logic flush;
    logic ready;

    logic miss;
    logic `N(2) exception;
    logic `ARRAY(2, `PADDR_SIZE) paddr;

    modport tlb(input req, vaddr, flush, ready, output miss, exception, paddr);
    modport cache(output req, vaddr, flush, ready, input miss, exception, paddr);
endinterface

interface DTLBLsuIO;
    logic flush;

    logic `N(`LOAD_PIPELINE) lreq;
    logic `N(`LOAD_PIPELINE) lreq_s2;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) lidx;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) laddr;
    logic `ARRAY(`LOAD_PIPELINE, $bits(VPNAddr)) lsel_tag;
    logic `TENSOR(`LOAD_PIPELINE, `TLB_PN, 2) lsel;
    
    logic `N(`LOAD_PIPELINE) lmiss;
    logic `N(`LOAD_PIPELINE) lexception;
    logic `N(`LOAD_PIPELINE) lcancel;
    logic `N(`LOAD_PIPELINE) luncache;
    logic `ARRAY(`LOAD_PIPELINE, `PADDR_SIZE) lpaddr;

    logic `N(`LOAD_PIPELINE) lwb;
    logic `N(`LOAD_PIPELINE) lwb_exception;
    logic `N(`LOAD_PIPELINE) lwb_error;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) lwb_idx;

    logic `N(`STORE_PIPELINE) sreq;
    logic `N(`STORE_PIPELINE) sreq_s2;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sidx;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) saddr;
    logic `ARRAY(`STORE_PIPELINE, $bits(VPNAddr)) ssel_tag;
    logic `TENSOR(`STORE_PIPELINE, `TLB_PN, 2) ssel;

    logic `N(`STORE_PIPELINE) smiss;
    logic `N(`STORE_PIPELINE) sexception;
    logic `N(`STORE_PIPELINE) scancel;
    logic `N(`STORE_PIPELINE) suncache;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE) spaddr;

    logic `N(`STORE_PIPELINE) swb;
    logic `N(`STORE_PIPELINE) swb_exception;
    logic `N(`STORE_PIPELINE) swb_error;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) swb_idx;

`ifdef RVA
    logic amo_req;
    logic `N(`VADDR_SIZE) amo_addr;
    logic amo_valid;
    logic amo_exception;
    logic amo_error;
    logic `N(`PADDR_SIZE) amo_paddr;
`endif
    modport tlb(input flush, lreq, lreq_s2, lidx, laddr, lsel, lsel_tag,
                sreq, sreq_s2, sidx, saddr, ssel, ssel_tag,
`ifdef RVA
                input amo_req, amo_addr,
                output amo_valid, amo_exception, amo_error, amo_paddr,
`endif
                output lmiss, luncache, lexception, lcancel, lpaddr, smiss, suncache, sexception, scancel, spaddr,
                lwb, lwb_exception, lwb_error, lwb_idx, swb, swb_exception, swb_error, swb_idx);
    modport lq (input lwb, lwb_exception, lwb_error, lwb_idx);
    modport sq (input swb, swb_exception, swb_error, swb_idx);
endinterface

interface CsrTlbIO;
    logic `N(`TLB_ASID) asid;
    logic sum;
    logic mxr;
    logic `N(2) mode;
    logic `N(`TLB_MODE) satp_mode;
    logic `ARRAY(`PMPCFG_SIZE, `MXL) pmpcfg;
    logic `ARRAY(`PMP_SIZE, `MXL) pmpaddr;

    modport csr (output asid, sum, mxr, mode, satp_mode, pmpcfg, pmpaddr);
    modport tlb (input asid, sum, mxr, mode, satp_mode, pmpcfg, pmpaddr);
endinterface

interface TlbL2IO;
    logic req;
    logic `N(`TLB_VPN_SIZE) req_addr;
    TLBInfo info;

    logic ready;
    logic dataValid;
    logic error;
    logic exception;
    logic exc_static;
    TLBInfo info_o;
    PTEEntry entry;
    logic `N(`TLB_PN) wpn;
    logic `N(`TLB_VPN_SIZE) waddr;

    modport tlb(output req, req_addr, info, input ready, dataValid, error, exception, exc_static, info_o, entry, wpn, waddr);
    modport l2 (input req, req_addr, info, output ready, dataValid, error, exception, exc_static, info_o, entry, wpn, waddr);
endinterface

interface CsrL2IO;
    logic sum;
    logic mxr;
    logic mprv;
    logic `N(2) mode;
    logic `N(2) mpp;
    logic `N(`TLB_ASID) asid;
    PPNAddr ppn;

    modport csr (output sum, mxr, mode, asid, ppn, mprv, mpp);
    modport tlb (input sum, mxr, mode, asid, ppn, mprv, mpp);
endinterface

interface CachePTWIO;
    logic req;
    TLBInfo info;
    logic `N(`TLB_VPN_SIZE) vaddr;
    logic `N(`TLB_PN) valid;
    logic `ARRAY(`TLB_PN, `PADDR_SIZE) paddr;
    logic full;

    logic refill_req;
    logic refill_ready;
    logic `N(`TLB_PN) refill_pn;
    logic `N(`TLB_VPN_SIZE) refill_addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refill_data;

    modport cache(output req, info, vaddr, valid, paddr, refill_ready, input full, refill_req, refill_pn, refill_addr, refill_data);
    modport page (input full, refill_req, refill_pn, refill_addr, refill_data);
    modport ptw (input req, info, vaddr, valid, paddr, refill_ready, output full, refill_req, refill_pn, refill_addr, refill_data);
endinterface

interface FenceBus;
    logic valid;
    logic fence_end;
    logic store_flush;
    logic store_flush_end;

`ifdef EXT_FENCEI
    logic inst_flush;
    logic inst_flush_end;
`endif

    logic `N(3) mmu_flush;
    logic `N(3) mmu_flush_all;
    logic `N(3) mmu_asid_all;
    logic mmu_flush_end;
    logic `ARRAY(3, `VADDR_SIZE) vma_vaddr;
    logic `ARRAY(3, `TLB_ASID) vma_asid;

    RobIdx robIdx;
    RobIdx preRobIdx;
    FsqIdxInfo fsqInfo;

    modport csr (output valid, mmu_flush, mmu_flush_all, mmu_asid_all, vma_vaddr, vma_asid, store_flush, fence_end, robIdx, preRobIdx, fsqInfo, input store_flush_end, mmu_flush_end
`ifdef EXT_FENCEI
    , output inst_flush, input inst_flush_end
`endif
    );
    modport lsu (input valid, mmu_flush, mmu_flush_all, mmu_asid_all, vma_vaddr, vma_asid, store_flush, robIdx, preRobIdx, fsqInfo, fence_end, output store_flush_end);
    modport rob (input fence_end, valid);
    modport dis (input valid);
    modport mmu (input mmu_flush, mmu_flush_all, mmu_asid_all, vma_vaddr, vma_asid);
    modport l2tlb (input mmu_flush, mmu_flush_all, mmu_asid_all, vma_vaddr, vma_asid, output mmu_flush_end);
    modport backend (output mmu_flush, mmu_flush_all, mmu_asid_all, vma_vaddr, vma_asid, input mmu_flush_end
`ifdef EXT_FENCEI
    , output inst_flush, input inst_flush_end
`endif
    );
`ifdef EXT_FENCEI
    modport ifu (input inst_flush_end, output inst_flush);
`endif
endinterface //SFenceBus

interface RobFCsrIO;
    logic valid;
    logic we;
    logic flag_we;
    logic [4: 0] flags;

    modport csr(output valid, input we, flag_we, flags);
    modport rob(input valid, output we, flag_we, flags);
endinterface

interface L2MSHRSlaveIO #(
    parameter SLAVE = 1,
    parameter LLC = 1,
    parameter WAY = 4,
    parameter SET = 64,
    parameter OFFSET = 32,
    parameter OFFSET_WIDTH = $clog2(OFFSET),
    parameter SLAVE_WIDTH = SLAVE > 1 ? $clog2(SLAVE) : 1,
    parameter SET_WIDTH = $clog2(SET),
    parameter WAY_WIDTH = $clog2(WAY),
    parameter TAG_WIDTH = `PADDR_SIZE - OFFSET_WIDTH - SET_WIDTH,
    parameter ENTRY_SIZE = TAG_WIDTH + 1 + (LLC ? 0 : 1) + SLAVE + SLAVE_WIDTH
);
    logic request;
    logic `N(`PADDR_SIZE) raddr;
    logic hit;
    logic `N(WAY_WIDTH) hit_way;
    logic share;
    logic owned;
    logic `N(SLAVE) slave;
    logic `N(SLAVE_WIDTH) owner;
    logic replace_hit;
    logic `N(WAY_WIDTH) replace_way;
    logic replace_owned;
    logic `N(TAG_WIDTH) replace_tag;

    logic we;
    logic wready;
    logic `N(SET_WIDTH) waddr;
    logic `N(WAY_WIDTH) wway;
    logic `N(ENTRY_SIZE) wdata;

    modport mshr (output request, raddr, we, waddr, wway, wdata, input hit, hit_way, share, owned, slave, owner, replace_hit, replace_way, replace_owned, replace_tag, wready);
    modport slaver (input request, raddr, we, waddr, wway, wdata, output hit, hit_way, share, owned, slave, owner, replace_hit, replace_way, replace_owned, replace_tag, wready);
endinterface

interface L2MSHRDirIO #(
    parameter WAY = 4,
    parameter OFFSET = 32,
    parameter SET = 64,
    parameter WAY_WIDTH = $clog2(WAY),
    parameter OFFSET_WIDTH = $clog2(OFFSET),
    parameter SET_WIDTH = $clog2(SET),
    parameter TAG_WIDTH = `PADDR_SIZE - OFFSET_WIDTH - SET_WIDTH
);
    logic request;
    logic `N(`PADDR_SIZE) raddr;
    logic hit;
    DirectoryState hit_state;
    logic `N(WAY_WIDTH) hit_way;
    logic `N(TAG_WIDTH+1) replace_tagv;
    logic `N(WAY_WIDTH) replace_way;
    DirectoryState replace_state;

    logic we;
    logic wready;
    logic `N(SET_WIDTH) waddr;
    logic `N(WAY_WIDTH) wway;
    logic `N(TAG_WIDTH+1+$bits(DirectoryState)) wdata;

    modport mshr (output request, raddr, we, waddr, wway, wdata, input hit, hit_way, hit_state, replace_tagv, replace_way, replace_state, wready);
    modport dir (input request, raddr, we, waddr, wway, wdata, output hit, hit_way, hit_state, replace_tagv, replace_way, replace_state, wready);
endinterface

interface L2MSHRDataIO #(
    parameter MSHR_SIZE = 4,
    parameter DATA_BANK = 1,
    parameter SET_SIZE = 64,
    parameter WAY_NUM = 4,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter MSHR_WIDTH = $clog2(MSHR_SIZE),
    parameter SET_WIDTH = $clog2(SET_SIZE / DATA_BANK)
);
    logic `N(DATA_BANK) req;
    logic `ARRAY(DATA_BANK, WAY_WIDTH) rway;
    logic `N(DATA_BANK) ready;
    logic `ARRAY(DATA_BANK, MSHR_WIDTH) mshr_idx;
    logic `ARRAY(DATA_BANK, SET_WIDTH) raddr;
    logic `N(DATA_BANK) rvalid;
    logic `ARRAY(DATA_BANK, MSHR_WIDTH) mshr_idx_o;
    logic `TENSOR(DATA_BANK, `DCACHE_BANK, `DCACHE_BITS) rdata;

    logic `N(DATA_BANK) we;
    logic `ARRAY(DATA_BANK, WAY_WIDTH) wway;
    logic `ARRAY(DATA_BANK, MSHR_WIDTH) wmshr_idx;
    logic `ARRAY(DATA_BANK, SET_WIDTH) waddr;
    logic `N(DATA_BANK) wvalid;
    logic `ARRAY(DATA_BANK, MSHR_WIDTH) wmshr_idx_o;
    logic `TENSOR(DATA_BANK, `DCACHE_BANK, `DCACHE_BITS) wdata;

    modport mshr(output req, rway, mshr_idx, raddr, input ready, rvalid, mshr_idx_o, rdata,
                output we, wway, wmshr_idx, waddr, wdata, input wvalid, wmshr_idx_o);
    modport data(input req, rway, mshr_idx, raddr, output ready, rvalid, mshr_idx_o, rdata,
                input we, wway, wmshr_idx, waddr, wdata, output wvalid, wmshr_idx_o);
endinterface

`ifdef DIFFTEST
interface DiffRAT;
    logic `ARRAY(32, `PREG_WIDTH) map_reg;

    modport rat (output map_reg);
    modport regfile (input map_reg);
endinterface

`endif


`endif