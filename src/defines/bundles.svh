`ifndef BUNDLES_SVH
`define BUNDLES_SVH
`include "global.svh"
`include "opcode.svh"
`include "csr_defines.svh"

`define LOOP_PTR_DEFINE(NAME, WIDTH) \
typedef struct packed { \
    logic [WIDTH-1: 0] idx; \
    logic dir; \
} NAME;

typedef struct packed {
    logic en;
    logic carry;
`ifdef RVC
    logic rvc;
`endif
    logic `N(`PREDICTION_WIDTH) offset;
    logic `N(`JAL_OFFSET) target;
    TargetState tar_state;
} BranchSlot;

typedef struct packed {
    logic en;
    logic carry;
`ifdef RVC
    logic rvc;
`endif
    BranchType br_type;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `N(`JALR_OFFSET) target;
    TargetState tar_state;
} TailSlot;

`define BTB_ENTRY_GEN(tag_size) \
typedef struct packed { \
    logic `N(``tag_size``) tag; \
    logic en; \
    BranchSlot `N(`SLOT_NUM-1) slots; \
    TailSlot tailSlot; \
    logic `N(`PREDICTION_WIDTH) fthAddr; \
`ifdef RVC \
    logic fth_rvc; \
`endif \
} BTBEntry;

typedef struct packed {
    logic en;
    BranchSlot `N(`SLOT_NUM-1) slots;
    TailSlot tailSlot;
    logic `N(`PREDICTION_WIDTH) fthAddr;
`ifdef RVC
    logic fth_rvc;
`endif
} BTBUpdateInfo;

typedef struct packed {
    logic `N(`TAGE_TAG_SIZE) tag;
    logic `N(`TAGE_U_SIZE) u;
    logic `N(`TAGE_CTR_SIZE) ctr;
} TageEntry;

typedef struct packed {
    logic `N(`ITTAGE_TAG_SIZE) tag;
    logic `N(`ITTAGE_U_SIZE) u;
    logic `N(`ITTAGE_CTR_SIZE) ctr;
    logic `N(`ITTAGE_OFFSET) offset;
} ITTageEntry;

`LOOP_PTR_DEFINE(RasIdx, `RAS_WIDTH)
`LOOP_PTR_DEFINE(RasInflightIdx, `RAS_INFLIGHT_WIDTH)

typedef struct packed {
    logic `ARRAY(`TAGE_BANK, `SLOT_NUM * `TAGE_CTR_SIZE) tage_ctrs;
    logic `ARRAY(`TAGE_BANK, `SLOT_NUM * `TAGE_U_SIZE) u;
    logic `ARRAY(`SLOT_NUM, `TAGE_BASE_CTR) base_ctr;
    logic `ARRAY(`SLOT_NUM, `TAGE_BANK) provider;
    logic `N(`SLOT_NUM) predTaken;
    logic `N(`SLOT_NUM) tagePred;
} TageMeta;

typedef struct packed {
    logic `N(`ITTAGE_CTR_SIZE) ctr;
    logic `ARRAY(`ITTAGE_BANK, `ITTAGE_U_SIZE) u;
    logic `N(`ITTAGE_BANK) provider;
`ifdef FEAT_ITTAGE_REGION
    logic `N(`ITTAGE_REGION) region;
`endif
    logic `N(`ITTAGE_OFFSET) offset;
    logic `N(`ITTAGE_OFFSET) alt_offset;
} ITTageMeta;

typedef struct packed {
    logic `ARRAY(`SLOT_NUM, 2) ctr;
} UBTBMeta;

typedef struct packed {
    logic `TENSOR(`SC_TABLE_NUM, `SLOT_NUM, `SC_CTR_SIZE) ctr;
    logic `ARRAY(`SLOT_NUM, `SC_THRESH_CTR) thresh_ctr;
    logic `N(`SLOT_NUM) predTaken;
    logic `N(`SLOT_NUM) thresh_update;
} SCMeta;

typedef struct packed {
    TageMeta tage;
    UBTBMeta ubtb;
`ifdef FEAT_SC
    SCMeta sc;
`endif
    ITTageMeta ittage;
} PredictionMeta;

typedef struct packed {
    logic taken;
`ifdef RVC
    logic rvc;
`endif
    logic `VADDR_BUS start_addr;
    logic `VADDR_BUS target;
    logic `N(`PREDICTION_WIDTH) size;
} FetchStream;

typedef struct packed {
    logic `VADDR_BUS pc;
    // logic `N(`RAS_CTR_SIZE) ctr;
} RasEntry;

typedef struct packed {
    logic `ARRAY(`TAGE_BANK, `TAGE_SET_WIDTH) fold_idx;
    logic `ARRAY(`TAGE_BANK, `TAGE_TAG_COMPRESS1) fold_tag1;
    logic `ARRAY(`TAGE_BANK, `TAGE_TAG_COMPRESS2) fold_tag2;
} TageFoldHistory;

typedef struct packed {
    RasInflightIdx rasTop;
    RasInflightIdx listTop;
    logic `N(`RAS_WIDTH) inflightTop;
    logic topInvalid;
} RasRedirectInfo;

typedef struct packed {
    logic `N(`GHIST_WIDTH) ghistIdx;
    TageFoldHistory tage_history;
    RasRedirectInfo rasInfo;
    logic `N(`SC_GHIST_WIDTH) sc_ghist;
`ifdef IMLI_VALID
    logic `N(`SC_IMLI_WIDTH) imli;
`endif
    // logic `N(`RAS_CTR_SIZE) ras_ctr;
} RedirectInfo;

typedef struct packed {
    logic `N(`GHIST_WIDTH) ghistIdx;
    // logic `N(`GHIST_SIZE) ghist;
    // logic `N(`PHIST_SIZE) phist;
    logic `N(`SC_GHIST_WIDTH) sc_ghist;
`ifdef IMLI_VALID
    logic `N(`SC_IMLI_WIDTH) imli;
`endif
    TageFoldHistory tage_history;
} BranchHistory;

typedef struct packed {
    logic en;
    logic btb_hit;
    FetchStream stream;
    BranchType br_type;
    BTBUpdateInfo btbEntry;
    logic redirect;
    logic `N(2) cond_num;
    logic `N(`SLOT_NUM) cond_valid;
    logic `N(`SLOT_NUM) predTaken;
    logic taken;
    logic tail_taken;
    logic `N(`FSQ_WIDTH) stream_idx;
    logic stream_dir;
    RedirectInfo redirect_info;
} PredictionResult;

typedef struct packed {
`ifdef RVC
    logic rvc;
`endif
    logic branch;
    logic direct;
    logic jump;
    logic `VADDR_BUS target;
    BranchType br_type;
} PreDecodeBundle;

typedef struct packed {
    logic tage_ready;
    logic s2_redirect;
    logic s3_redirect;
    logic flush;
    logic stall;
} RedirectCtrl;

typedef struct packed {
    logic `N(2) condNum;
    logic taken; // last branch is taken
} CondPredInfo;

typedef struct packed {
`ifdef RVC
    logic rvc;
`endif
`ifdef DIFFTEST
    logic `N(`FSQ_WIDTH) squashIdx;
`endif
    logic squash_front;
    logic `VADDR_BUS start_addr;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `VADDR_BUS target_pc;
    RedirectInfo redirectInfo;
    CondPredInfo predInfo;
    BranchType br_type;
} SquashInfo;

typedef struct packed {
    logic `N(`FSQ_WIDTH) idx;
`ifdef RVC
    logic `N(`PREDICTION_WIDTH) size;
`endif
    logic `N(`PREDICTION_WIDTH) offset;
} FsqIdxInfo;

typedef struct packed {
    logic pred_error;
    FsqIdxInfo fsqInfo;
`ifdef RVC
    logic rvc;
`endif
    BranchType br_type;
} PredErrorInfo;

typedef struct packed {
    logic taken;
    logic tailTaken;
`ifdef DIFFTEST
    logic `N(`FSQ_WIDTH) fsqIdx;
`endif
    logic `N(`SLOT_NUM) realTaken;
    logic `N(`SLOT_NUM) allocSlot;
    logic `VADDR_BUS start_addr;
    logic `VADDR_BUS target_pc;
    RedirectInfo redirectInfo;
    logic btb_update;
    BTBUpdateInfo btbEntry;
    PredictionMeta meta;
    PredErrorInfo error_info;
} BranchUpdateInfo;

typedef struct packed {
    logic `N(`FSQ_WIDTH) idx;
    logic dir;
} FsqIdx;

typedef struct packed {
    logic `N(`FETCH_WIDTH) en;
    logic `N(`FETCH_WIDTH) iam;
    logic `N(`FETCH_WIDTH) ipf;
    FsqIdxInfo `N(`FETCH_WIDTH) fsqInfo;
    logic `ARRAY(`FETCH_WIDTH, 32) inst;
`ifdef FEAT_MEMPRED
    logic `ARRAY(`FETCH_WIDTH, `SSIT_WIDTH) ssit_idx;
`endif
} FetchBundle;

typedef struct packed {
    logic intv; // int valid
    logic memv;
    logic branchv;
    logic csrv;
`ifdef RVM
    logic multv;
`endif
`ifdef RVA
    logic amov;
`endif
    logic uext;
    logic we;
    logic immv;
    logic `N(`INTOP_WIDTH) intop;
    logic `N(`MEMOP_WIDTH) memop;
    logic `N(`BRANCHOP_WIDTH) branchop;
    logic `N(`CSROP_WIDTH) csrop;
`ifdef RVM
    logic `N(`MULTOP_WIDTH) multop;
`endif
`ifdef RVA
    logic `N(`AMOOP_WIDTH) amoop;
`endif
`ifdef RVF
    logic `N(`FLTOP_WIDTH) fltop;
    logic fmiscv;
    logic fcalv;
    logic flt_mem;
    logic fflag_we;
    logic [2: 0] rm;
    logic [4: 0] rs3;
    logic frs1_sel;
    logic frs2_sel;
    logic flt_we;
`endif
`ifdef RVC
    logic rvc;
`endif
`ifdef RV64I
    logic word;
`endif
`ifdef RVD
    logic db;
`endif
    logic [4: 0] rs1, rs2, rd;
    logic `N(`DEC_IMM_WIDTH) imm;
    logic `N(`EXC_WIDTH) exccode;
`ifdef DIFFTEST
    logic sim_trap;
`endif
} DecodeInfo;

typedef struct packed {
    logic en;
    FsqIdxInfo fsqInfo;
    DecodeInfo di;
    logic `N(32) inst;
`ifdef FEAT_MEMPRED
    logic `N(`SSIT_WIDTH) ssit_idx;
`endif
} OPBundle;

typedef struct packed {
    logic `N(`ROB_WIDTH) idx;
    logic dir;
} RobIdx;

typedef struct packed {
    logic frs1_sel, frs2_sel;
    logic `N(`PREG_WIDTH) rs3;
    logic `N(`PREG_WIDTH) rs1, rs2;
    logic `N(`PREG_WIDTH) rd;
    logic we;
    RobIdx robIdx;
} DisStatusBundle;

typedef struct packed {
    logic rs1v, rs2v;
    logic rs3v;
    logic frs1_sel, frs2_sel;
    logic `N(`PREG_WIDTH) rs3;
    logic `N(`PREG_WIDTH) rs1, rs2;
    logic `N(`PREG_WIDTH) rd;
    logic we;
    RobIdx robIdx;
} IssueStatusBundle;

typedef struct packed {
    logic intv;
    logic branchv;
    logic uext;
    logic immv;
`ifdef RVC
    logic rvc;
`endif
`ifdef RV64I
    logic word;
`endif
    logic `N(`INTOP_WIDTH) intop;
    logic `N(`BRANCHOP_WIDTH) branchop;
    logic `N(`DEC_IMM_WIDTH) imm;
    BranchType br_type;
    FsqIdxInfo fsqInfo;
} IntIssueBundle;

typedef struct packed {
    logic `N(`LOAD_QUEUE_WIDTH) idx;
    logic dir;
} LoadIdx;

typedef struct packed {
    logic `N(`STORE_QUEUE_WIDTH) idx;
    logic dir;
} StoreIdx;

typedef struct packed {
    logic en;
    logic `N(`LFST_WIDTH) idx;
} SSITEntry;

typedef struct packed {
    logic uext;
`ifdef RVF
    logic fp_en;
`endif
    logic `N(`MEMOP_WIDTH) memop;
    logic `N(12) imm;
    LoadIdx lqIdx;
    StoreIdx sqIdx;
    FsqIdxInfo fsqInfo;
`ifdef FEAT_MEMPRED
    SSITEntry ssitEntry;
`endif
} MemIssueBundle;

typedef struct packed {
    logic `N(`CSROP_WIDTH) csrop;
    logic `N(`DEC_IMM_WIDTH-3) imm;
    logic `N(32) inst; // illigal inst
    logic exc_valid;
    logic `N(`EXC_WIDTH) exccode;
    FsqIdxInfo fsqInfo;
} CsrIssueBundle;

typedef struct packed {
    logic `N(`MULTOP_WIDTH) multop;
`ifdef RV64I
    logic word;
`endif
} MultIssueBundle;

typedef struct packed {
    logic `N(`AMOOP_WIDTH) amoop;
`ifdef RV64I
    logic word;
`endif
} AmoIssueBundle;

typedef struct packed {
    logic `N(`FLTOP_WIDTH) fltop;
    logic flt_we;
    logic uext;
    logic [2: 0] rm;
`ifdef RV64I
    logic word;
`endif
`ifdef RVD
    logic db;
`endif
} FMiscIssueBundle;

typedef struct packed {
    logic `N(`FLTOP_WIDTH) fltop;
    logic `N(3) rm;
`ifdef RVD
    logic db;
`endif
} FMAIssueBundle;

typedef struct packed {
    logic div;
    logic [2: 0] rm;
`ifdef RVD
    logic db;
`endif
} FDivIssueBundle;

typedef struct packed {
    logic we;
    logic `N(`PREG_WIDTH) rd;
    RobIdx robIdx;
} ExStatusBundle;

typedef struct packed {
    logic en;
`ifdef RVC
    logic rvc;
`endif
    FsqIdxInfo fsqInfo;
    RobIdx robIdx;
} BackendRedirectInfo;

typedef struct packed {
    logic en;
    logic taken;
    logic `N(`VADDR_SIZE) target;
    BranchType br_type;
} BranchRedirectInfo;

typedef struct packed {
    logic en;
    logic irq;
    logic irq_deleg;
    logic `N(`EXC_WIDTH) exccode;
} RobRedirectInfo;

typedef struct packed {
    logic en;
    logic irq;
    logic irq_deleg;
    logic `N(`EXC_WIDTH) exccode;
    logic `N(`VADDR_SIZE) exc_pc;
} CSRRedirectInfo;

typedef struct packed {
    logic irq;
    logic deleg;
    logic `N(`EXC_WIDTH) exccode;
} CSRIrqInfo;

typedef struct packed {
    logic direction;
    logic error;
`ifdef RVC
    logic rvc;
`endif
    logic `N(`VADDR_SIZE) target;
    BranchType br_type;
} BranchUnitRes;

typedef struct packed {
    logic en;
    FsqIdxInfo fsqInfo;
    RobIdx robIdx;
    BranchUnitRes res;
} AluBranchBundle;

typedef struct packed {
    logic is_nan;
    logic is_signalling;
    logic is_inf;
    logic is_invalid;
    logic is_ov;
    logic sign;
} FMulInfo;

typedef struct packed {
    logic en;
    logic we;
    logic irq_enable;
    RobIdx robIdx;
    logic `N(`PREG_WIDTH) rd;
    logic `N(`EXC_WIDTH) exccode;
    logic `N(`XLEN) res;
} WBData;

typedef struct packed {
    logic we;
    logic uext;
`ifdef RVF
    logic frd_en;
`endif
    logic [1: 0] size;
    logic [11: 0] imm;
    logic `N(`PREG_WIDTH) rd;
    LoadIdx lqIdx;
    StoreIdx sqIdx;
    RobIdx robIdx;
    FsqIdxInfo fsqInfo;
} LoadIssueData;

typedef struct packed {
    logic uext;
    logic [1: 0] size;
    logic [11: 0] imm;
    StoreIdx sqIdx;
    LoadIdx lqIdx;
    RobIdx robIdx;
    FsqIdxInfo fsqInfo;
`ifdef FEAT_MEMPRED
    SSITEntry ssitEntry;
`endif
} StoreIssueData;

typedef struct packed {
    logic en;
    logic `N(`PADDR_SIZE) addr;
    logic `N(`DCACHE_BYTE) mask;
    LoadIdx lqIdx;
    RobIdx robIdx;
    FsqIdxInfo fsqInfo;
`ifdef FEAT_MEMPRED
    FsqIdxInfo wfsqInfo;
`endif
} ViolationData;

typedef struct packed {
    logic dir;
    logic `N($clog2(`LOAD_QUEUE_SIZE / `LOAD_PIPELINE)) idx;
    FsqIdxInfo fsqInfo;
} LoadVioData;

typedef struct packed {
    LoadVioData data;
`ifdef FEAT_MEMPRED
    logic `N($clog2(`STORE_PIPELINE)) wbank;
`endif
} SelectVioData;

typedef struct packed {
    logic en;
    StoreIdx sqIdx;
    logic `N(`TLB_OFFSET) vaddrOffset;
    logic `N(`TLB_TAG) ptag;
    logic `N(`DCACHE_BYTE) mask;
} LoadFwdData;

typedef struct packed {
    logic we;
`ifdef RVF
    logic frd_en;
`ifdef RV64I
    logic word;
`endif
`endif
    logic `N(`PREG_WIDTH) rd;
    RobIdx robIdx;
} LoadQueueData;

typedef struct packed {
    logic uext;
    logic [1: 0] size;
    logic `N(`DCACHE_BYTE_WIDTH) offset;
    logic `N(`DCACHE_BYTE) mask;
} LoadMaskData;

typedef struct packed {
    logic en;
    logic [1: 0] reason;
    logic `N(`LOAD_ISSUE_BANK_WIDTH) issue_idx;
} ReplyRequest;

typedef struct packed {
    logic en;
    RobIdx robIdx;
    logic `N(`EXC_WIDTH) exccode;
    logic irq_enable;
} StoreWBData;

typedef struct packed {
    logic `ARRAY(`TLB_PN, `TLB_VPN) vpn;
} VPNAddr;

typedef struct packed {
`ifdef SV39
    logic `N(`TLB_PPN2) ppn2;
`endif
    logic `N(`TLB_PPN1) ppn1;
    logic `N(`TLB_PPN0) ppn0;
} PPNAddr;

typedef struct packed {
    logic g;
    logic u;
    logic r;
    logic x;
    logic d;
    logic exc;
    logic uc;
    logic `N(`TLB_PN) size;
    logic `N(`TLB_ASID) asid;
    VPNAddr vpn;
    PPNAddr ppn;
} L1TLBEntry;

typedef struct packed {
`ifdef SV39
    logic n;
    logic `N(2) pbmt;
    logic `N(7) unuse;
`endif
    PPNAddr ppn;
    logic `N(2) rsw;
    logic d;
    logic a;
    logic g;
    logic u;
    logic x;
    logic w;
    logic r;
    logic v;
} PTEEntry;

typedef struct packed {
    logic `N(2) source; // 2'b00: icache, 2'b01: load, 2'b10: store
    logic `N(`TLB_IDX_SIZE) idx;
} TLBInfo;

typedef struct packed {
    logic dataValid;
    logic error;
    logic exception;
    TLBInfo info_o;
    PTEEntry entry;
    logic `N(2) wpn;
    logic `N(`VADDR_SIZE) waddr;
} L2TLBResponse;

typedef struct packed {
    logic req;
    RobIdx robIdx;
} FenceReq;

typedef struct packed {
    logic ibuf_full;
    logic redirect;
    logic redirect_mem;
    FsqIdxInfo redirectInfo;
} FrontendCtrl;

typedef struct packed {
    logic rename_full;
    logic dis_full;

    logic redirect;
    RobIdx redirectIdx;
} BackendCtrl;

typedef struct packed {
    logic walk;
    logic walkStart;

    logic `N(`WALK_WIDTH) en;
    logic `N(`WALK_WIDTH) we;
    logic `N(`WALK_WIDTH) fp_we;
    logic `N($clog2(`WALK_WIDTH) + 1) num;
    logic `ARRAY(`WALK_WIDTH, 5) vrd;
    logic `ARRAY(`WALK_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`WALK_WIDTH, `PREG_WIDTH) old_prd;
} CommitWalk;

typedef struct packed {
    logic owner;
    logic share;
    logic dirty;
} DirectoryState;

typedef struct packed {
    logic owned;
    logic share;
    logic dirty;
} DCacheMeta;

`ifdef DIFFTEST
typedef struct packed {
    logic en;
    RobIdx robIdx;
    logic `N(`PADDR_SIZE) paddr;
} DiffLoadData;
`endif

`endif