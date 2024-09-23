`ifndef INTERFACES_SVH
`define INTERFACES_SVH
`include "bundles.svh"
`include "axi.svh"
`include "apb.svh"
`include "ace.svh"

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
    RasRedirectInfo rasInfo;

    modport ras (input request, ras_type, target, redirect, squash, squashInfo, update, updateInfo, output en, entry, rasInfo);
    modport control(input en, entry, rasInfo, output request, ras_type, target);

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
    FsqIdx abandonIdx;
    logic ready;
    FsqIdx fsqIdx;
    logic flush;
    logic stall;
    logic `N(`PREDICTION_WIDTH+1) shiftIdx;

    modport fsq (input ready, output en, stream, fsqIdx, abandon, abandonIdx, flush, stall, shiftIdx);
    modport cache (output ready, input en, stream,fsqIdx, abandon, abandonIdx, flush, stall, shiftIdx);
endinterface

interface FsqBackendIO;
    FetchStream `N(`FETCH_WIDTH) streams;
    logic `ARRAY(`FETCH_WIDTH, `FSQ_WIDTH) fsqIdx;
    logic `N(`FETCH_WIDTH) directions;
    logic `N(`VADDR_SIZE) exc_pc;

    BackendRedirectInfo redirect;
    BranchRedirectInfo redirectBr;
    CSRRedirectInfo redirectCsr;

`ifdef DIFFTEST
    FsqIdxInfo `N(`COMMIT_WIDTH) diff_fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, `VADDR_SIZE) diff_pc;
`endif
    
    modport fsq (input fsqIdx, redirect, redirectBr, redirectCsr, output streams, directions, exc_pc
`ifdef DIFFTEST
    ,input diff_fsqInfo,
    output diff_pc
`endif
    );
    modport backend (output fsqIdx, redirect, redirectBr, redirectCsr, input streams, directions, exc_pc
`ifdef DIFFTEST
    ,output diff_fsqInfo,
    input diff_pc
`endif
    );
endinterface

interface CachePreDecodeIO;
    logic `N(`BLOCK_INST_SIZE) en;
    logic `N(`BLOCK_INST_SIZE) exception;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) data;
    logic `N(`VADDR_SIZE) start_addr;
    FetchStream stream;
    FsqIdx fsqIdx;
    logic `N(`PREDICTION_WIDTH+1) shiftIdx;

    modport cache (output en, exception, start_addr, data, stream, fsqIdx, shiftIdx);
    modport pd (input en, exception, start_addr, data, stream, fsqIdx, shiftIdx);
endinterface

interface ReplaceIO #(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter READ_PORT = 1,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter ADDR_WIDTH = $clog2(DEPTH)
);
    logic `N(READ_PORT) hit_en;
    logic `ARRAY(READ_PORT, WAY_NUM) hit_way;
    logic `N(WAY_NUM) miss_way;
    logic `N(ADDR_WIDTH) miss_index;
    logic `ARRAY(READ_PORT, ADDR_WIDTH) hit_index;

    modport replace(input hit_en, hit_way, hit_index, miss_index, output miss_way);
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
    logic direct;
    RasType ras_type;
    FsqIdx fsqIdx;
    FetchStream stream;

    modport predecode(output en, exc_en, direct, ras_type, fsqIdx, stream);
    modport redirect(input en, exc_en, direct, ras_type, fsqIdx, stream);
endinterface

interface PreDecodeIBufferIO;
    logic `N(`BLOCK_INST_SIZE) en;
    logic `N(`BLOCK_INST_SIZE) ipf;
    logic `N($clog2(`BLOCK_INST_SIZE)+1) num;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) inst;
    logic iam; // for exception, instruction address misaligned
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`PREDICTION_WIDTH+1) shiftIdx;

    modport predecode(output en, ipf, num, inst, iam, fsqIdx, shiftIdx);
    modport instbuffer(input en, ipf, num, inst, iam, fsqIdx, shiftIdx);
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
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) old_prd;
    RobIdx `N(`FETCH_WIDTH) robIdx;

    modport rename(output op, prs1, prs2, wen, prd, old_prd, robIdx);
    modport dis(input op, prs1, prs2, wen, prd, robIdx);
    modport rob(input op, prd, old_prd, robIdx);
endinterface

interface RegfileIO;
    logic `N(`REGFILE_READ_PORT) en;
    logic `ARRAY(`REGFILE_READ_PORT, `PREG_WIDTH) raddr;
    logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata;
    logic `N(`REGFILE_WRITE_PORT) we;
    logic `ARRAY(`REGFILE_WRITE_PORT, `PREG_WIDTH) waddr;
    logic `ARRAY(`REGFILE_WRITE_PORT, `XLEN) wdata;

    modport regfile (input raddr, waddr, wdata, en, we, output rdata);
    modport bypass  (input raddr, rdata);
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
    logic `N(`ALU_SIZE) directions; // fsq dir

    modport exu (input en, rs1_data, rs2_data, status, bundle, streams, directions, output valid);
    modport issue (output en, rs1_data, rs2_data, status, bundle, streams, directions, input valid);
endinterface

interface IssueAluIO;
    logic en;
    logic valid; // fu valid
    logic `N(`XLEN) rs1_data;
    logic `N(`XLEN) rs2_data;
    ExStatusBundle status;
    IntIssueBundle bundle;
    FetchStream stream;
    logic direction;
    RasType ras_type;
    BranchType br_type;

    modport alu (input en, rs1_data, rs2_data, status, bundle, stream, direction, ras_type, br_type, output valid);
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

interface WriteBackIO#(
    parameter FU_SIZE = 4
);
    WBData `N(FU_SIZE) datas;
    logic `N(FU_SIZE) valid;

    modport wb (input datas, output valid);
    modport fu (output datas, input valid);
endinterface

interface CommitBus;
    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    logic fence_valid;
    FsqIdxInfo `N(`COMMIT_WIDTH) fsqInfo;
    logic `ARRAY(`COMMIT_WIDTH, 5) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;
    logic `N($clog2(`COMMIT_WIDTH) + 1) wenum;

    logic `N($clog2(`COMMIT_WIDTH)+1) loadNum;
    logic `N($clog2(`COMMIT_WIDTH)+1) storeNum;
    RobIdx robIdx;

    modport rob(output en, we, fence_valid, fsqInfo, vrd, prd, num, wenum, loadNum, storeNum
    , robIdx
);
    modport in(input en, we, fsqInfo, vrd, prd, num, wenum);
    modport mem(input loadNum, storeNum, robIdx);
    modport csr(input robIdx, fsqInfo, fence_valid, en);
endinterface

interface BackendRedirectIO;
    BackendRedirectInfo branchRedirect;
    BackendRedirectInfo memRedirect;
    BranchRedirectInfo branchInfo;
    RobIdx memRedirectIdx;

    BackendRedirectInfo out;
    BranchRedirectInfo branchOut;
    CSRRedirectInfo csrOut;

    modport redirect(input branchRedirect, memRedirect, memRedirectIdx, branchInfo, output out, branchOut, csrOut);
    modport mem(output memRedirect, memRedirectIdx);
endinterface

interface RobRedirectIO;
    logic fence;
    BackendRedirectInfo csrRedirect;
    CSRRedirectInfo csrInfo;

    modport rob (output csrRedirect, csrInfo, fence);
    modport redirect (input csrRedirect, csrInfo, fence);
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

    logic miss;
    logic `N(2) exception;
    logic `ARRAY(2, `PADDR_SIZE) paddr;

    modport tlb(input req, vaddr, flush, output miss, exception, paddr);
    modport cache(output req, vaddr, flush, input miss, exception, paddr);
endinterface

interface DTLBLsuIO;
    logic flush;

    logic `N(`LOAD_PIPELINE) lreq;
    logic `N(`LOAD_PIPELINE) lreq_cancel;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) lidx;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) laddr;
    
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
    logic `N(`STORE_PIPELINE) sreq_cancel;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sidx;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) saddr;

    logic `N(`STORE_PIPELINE) smiss;
    logic `N(`STORE_PIPELINE) sexception;
    logic `N(`STORE_PIPELINE) scancel;
    logic `N(`STORE_PIPELINE) suncache;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE) spaddr;

    logic `N(`STORE_PIPELINE) swb;
    logic `N(`STORE_PIPELINE) swb_exception;
    logic `N(`STORE_PIPELINE) swb_error;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) swb_idx;

    modport tlb(input flush, lreq, lidx, laddr, sreq, sidx, saddr,  lreq_cancel, sreq_cancel,
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
    logic `VADDR_BUS req_addr;
    TLBInfo info;

    logic ready;
    logic dataValid;
    logic error;
    logic exception;
    TLBInfo info_o;
    PTEEntry entry;
    logic `N(2) wpn;
    logic `N(`VADDR_SIZE) waddr;

    modport tlb(output req, req_addr, info, input ready, dataValid, error, exception, info_o, entry, wpn, waddr);
    modport l2 (input req, req_addr, info, output ready, dataValid, error, exception, info_o, entry, wpn, waddr);
endinterface

interface CsrL2IO;
    logic sum;
    logic mxr;
    logic `N(2) mode;
    PPNAddr ppn;

    modport csr (output sum, mxr, mode, ppn);
    modport tlb (input sum, mxr, mode, ppn);
endinterface

interface CachePTWIO;
    logic req;
    TLBInfo info;
    logic `N(`VADDR_SIZE) vaddr;
    logic `N(`TLB_PN) valid;
    logic `ARRAY(`TLB_PN, `PADDR_SIZE) paddr;
    logic full;

    logic refill_req;
    logic refill_ready;
    logic `N(`TLB_PN) refill_pn;
    logic `N(`VADDR_SIZE) refill_addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) refill_data;

    modport cache(output req, info, vaddr, valid, paddr, refill_ready, input full, refill_req, refill_pn, refill_addr, refill_data);
    modport page (input full, refill_req, refill_pn, refill_addr, refill_data);
    modport ptw (input req, info, vaddr, valid, paddr, refill_ready, output full, refill_req, refill_pn, refill_addr, refill_data);
endinterface

interface PTWRequest;
    logic req;
    logic `N(`PADDR_SIZE) paddr;

    logic ready;
    logic full;
    logic data_valid;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) rdata;
    
    modport ptw (output req, paddr, input ready, full, data_valid, rdata);
    modport cache (input req, paddr, output ready, full, data_valid, rdata);
endinterface

interface FenceBus;
    logic fence_end;
    logic store_flush;
    logic store_flush_end;

`ifdef EXT_FENCEI
    logic inst_flush;
    logic inst_flush_end;
`endif

    logic `N(3) mmu_flush;
    logic `N(3) mmu_flush_all;
    logic mmu_flush_end;
    logic `ARRAY(3, `VADDR_SIZE) vma_vaddr;
    logic `ARRAY(3, `TLB_ASID) vma_asid;

    RobIdx robIdx;
    RobIdx preRobIdx;
    FsqIdxInfo fsqInfo;

    modport csr (output mmu_flush, mmu_flush_all, vma_vaddr, vma_asid, store_flush, fence_end, robIdx, preRobIdx, fsqInfo, input store_flush_end, mmu_flush_end
`ifdef EXT_FENCEI
    , output inst_flush, input inst_flush_end
`endif
    );
    modport lsu (input mmu_flush, mmu_flush_all, vma_vaddr, vma_asid, store_flush, robIdx, preRobIdx, fsqInfo, fence_end, output store_flush_end);
    modport rob (input fence_end);
    modport mmu (input mmu_flush, mmu_flush_all, vma_vaddr, vma_asid);
    modport l2tlb (input mmu_flush, mmu_flush_all, vma_vaddr, vma_asid, output mmu_flush_end);
    modport backend (output mmu_flush, mmu_flush_all, vma_vaddr, vma_asid, input mmu_flush_end
`ifdef EXT_FENCEI
    , output inst_flush, input inst_flush_end
`endif
    );
`ifdef EXT_FENCEI
    modport ifu (input inst_flush_end, output inst_flush);
`endif
endinterface //SFenceBus

`ifdef DIFFTEST
interface DiffRAT;
    logic `ARRAY(32, `PREG_WIDTH) map_reg;

    modport rat (output map_reg);
    modport regfile (input map_reg);
endinterface

`endif


`endif