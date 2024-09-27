`ifndef BUNDLES_SVH
`define BUNDLES_SVH
`include "global.svh"
`include "opcode.svh"
`include "csr_defines.svh"

typedef struct packed {
    logic en;
    logic carry;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `N(`JAL_OFFSET) target;
    TargetState tar_state;
} BranchSlot;

typedef struct packed {
    logic en;
    logic carry;
    BranchType br_type;
    RasType ras_type;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `N(`JALR_OFFSET) target;
    TargetState tar_state;
} TailSlot;

typedef struct packed {
    logic `N(`BTB_TAG_SIZE) tag;
    logic en;
    BranchSlot `N(`SLOT_NUM-1) slots;
    TailSlot tailSlot;
    logic `N(`PREDICTION_WIDTH) fthAddr;
} BTBEntry;

typedef struct packed {
    logic en;
    BranchSlot `N(`SLOT_NUM-1) slots;
    TailSlot tailSlot;
    logic `N(`PREDICTION_WIDTH) fthAddr;
} BTBUpdateInfo;

typedef struct packed {
    logic `N(`TAGE_TAG_SIZE) tag;
    logic `N(`TAGE_U_SIZE) u;
    logic `N(`TAGE_CTR_SIZE) ctr;
} TageEntry;

typedef struct packed {
    logic `ARRAY(`TAGE_BANK, `SLOT_NUM * `TAGE_CTR_SIZE) tage_ctrs;
    logic `ARRAY(`TAGE_BANK, `SLOT_NUM * `TAGE_U_SIZE) u;
    logic `ARRAY(`TAGE_BASE_CTR, `SLOT_NUM) base_ctr;
    logic `ARRAY(`SLOT_NUM, `TAGE_BANK) provider;
    logic `N(`SLOT_NUM) predTaken;
    logic `N(`SLOT_NUM) altPred;
} TageMeta;

typedef struct packed {
    logic `ARRAY(`SLOT_NUM, 2) ctr;
} UBTBMeta;

typedef struct packed {
    TageMeta tage;
    UBTBMeta ubtb;
} PredictionMeta;

typedef struct packed {
    logic taken;
    BranchType branch_type;
    RasType ras_type;
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
    logic `N(`RAS_WIDTH) rasTop;
    logic `N(`RAS_WIDTH) rasBottom;
    logic ras_tdir;
    logic ras_bdir;
} RasRedirectInfo;

typedef struct packed {
    logic `N(`GHIST_WIDTH) ghistIdx;
    TageFoldHistory tage_history;
    RasRedirectInfo rasInfo;
    // logic `N(`RAS_CTR_SIZE) ras_ctr;
} RedirectInfo;

typedef struct packed {
    logic `N(`GHIST_WIDTH) ghistIdx;
    // logic `N(`GHIST_SIZE) ghist;
    // logic `N(`PHIST_SIZE) phist;
    TageFoldHistory tage_history;
} BranchHistory;

typedef struct packed {
    logic en;
    FetchStream stream;
    BTBEntry btbEntry;
    logic `N(`PREDICT_STAGE-1) redirect;
    logic `N(2) cond_num;
    logic `N(`SLOT_NUM) cond_valid;
    logic `N(`SLOT_NUM) predTaken;
    logic taken;
    logic `N(`FSQ_WIDTH) stream_idx;
    logic stream_dir;
    RedirectInfo redirect_info;
} PredictionResult;

typedef struct packed {
    logic branch;
    logic direct;
    BranchType br_type;
    RasType ras_type;
    logic `VADDR_BUS target;
} PreDecodeBundle;

typedef struct packed {
    logic tage_ready;
    logic s2_redirect;
    // logic s3_redirect;
    logic flush;
    logic stall;
} RedirectCtrl;

typedef struct packed {
    logic `N(2) condNum;
    logic taken; // last branch is taken
} CondPredInfo;

typedef struct packed {
    logic `VADDR_BUS start_addr;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `VADDR_BUS target_pc;
    RedirectInfo redirectInfo;
    CondPredInfo predInfo;
    BranchType br_type;
    RasType ras_type;
} SquashInfo;

typedef struct packed {
    logic taken;
    logic `N(`SLOT_NUM) realTaken;
    logic `N(`SLOT_NUM) allocSlot;
    logic `VADDR_BUS start_addr;
    logic `VADDR_BUS target_pc;
    RedirectInfo redirectInfo;
    BTBUpdateInfo btbEntry;
    PredictionMeta meta;
} BranchUpdateInfo;

typedef struct packed {
    logic `N(`FSQ_WIDTH) idx;
    logic `N(`PREDICTION_WIDTH) offset;
} FsqIdxInfo;

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
} FetchBundle;

typedef struct packed {
    logic intv; // int valid
    logic memv;
    logic branchv;
    logic csrv;
`ifdef RVM
    logic multv;
`endif
    logic [11: 0] csrid;
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
} OPBundle;

typedef struct packed {
    logic `N(`ROB_WIDTH) idx;
    logic dir;
} RobIdx;

typedef struct packed {
    logic we;
    logic `N(`PREG_WIDTH) rs1, rs2;
    logic `N(`PREG_WIDTH) rd;
    RobIdx robIdx;
} DisStatusBundle;

typedef struct packed {
    logic rs1v, rs2v;
    logic we;
    logic `N(`PREG_WIDTH) rs1, rs2;
    logic `N(`PREG_WIDTH) rd;
    RobIdx robIdx;
} IssueStatusBundle;

typedef struct packed {
    logic intv;
    logic branchv;
    logic uext;
    logic immv;
    logic `N(`INTOP_WIDTH) intop;
    logic `N(`BRANCHOP_WIDTH) branchop;
    logic `N(`DEC_IMM_WIDTH) imm;
    BranchType br_type;
    RasType ras_type;
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
    logic uext;
    logic `N(`MEMOP_WIDTH) memop;
    logic `N(12) imm;
    LoadIdx lqIdx;
    StoreIdx sqIdx;
    FsqIdxInfo fsqInfo;
} MemIssueBundle;

typedef struct packed {
    logic `N(`CSROP_WIDTH) csrop;
    logic `N(5) imm;
    logic `N(12) csrid;
    logic `N(32) inst; // illigal inst
    logic exc_valid;
    logic `N(`EXC_WIDTH) exccode;
    FsqIdxInfo fsqInfo;
} CsrIssueBundle;

typedef struct packed {
    logic `N(`MULTOP_WIDTH) multop;
} MultIssueBundle;

typedef struct packed {
    logic we;
    logic `N(`PREG_WIDTH) rd;
    RobIdx robIdx;
} ExStatusBundle;

typedef struct packed {
    logic en;
    FsqIdxInfo fsqInfo;
    RobIdx robIdx;
} BackendRedirectInfo;

typedef struct packed {
    logic en;
    logic taken;
    logic `N(`VADDR_SIZE) target;
    BranchType br_type;
    RasType ras_type;
} BranchRedirectInfo;

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
    logic `N(`VADDR_SIZE) target;
    RasType ras_type;
    BranchType br_type;
} BranchUnitRes;

typedef struct packed {
    logic en;
    logic fsqDir;
    FsqIdxInfo fsqInfo;
    RobIdx robIdx;
    BranchUnitRes res;
} AluBranchBundle;

typedef struct packed {
    logic en;
    logic we;
    RobIdx robIdx;
    logic `N(`PREG_WIDTH) rd;
    logic `N(`EXC_WIDTH) exccode;
    logic `N(`XLEN) res;
} WBData;

typedef struct packed {
    logic we;
    logic uext;
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
} StoreIssueData;

typedef struct packed {
    logic en;
    logic `N(`PADDR_SIZE) addr;
    logic `N(4) mask;
    LoadIdx lqIdx;
    RobIdx robIdx;
    FsqIdxInfo fsqInfo;
} ViolationData;

typedef struct packed {
    logic en;
    StoreIdx sqIdx;
    logic `N(`TLB_OFFSET) vaddrOffset;
    logic `N(`TLB_TAG) ptag;
} LoadFwdData;

typedef struct packed {
    logic dir;
    logic we;
    logic `N(`PREG_WIDTH) rd;
    RobIdx robIdx;
    FsqIdxInfo fsqInfo;
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
} StoreWBData;

typedef struct packed {
    logic `ARRAY(`TLB_PN, `TLB_VPN) vpn;
} VPNAddr;

typedef struct packed {
    logic `N(`TLB_PPN1) ppn1;
    logic `N(`TLB_PPN0) ppn0;
} PPNAddr;

typedef struct packed {
    logic g;
    logic u;
    logic r;
    logic x;
    logic exc;
    logic `N(2) size;
    // logic `N(`TLB_ASID) asid;
    VPNAddr vpn;
    PPNAddr ppn;
} L1TLBEntry;

typedef struct packed {
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

    logic `N(`COMMIT_WIDTH) en;
    logic `N(`COMMIT_WIDTH) we;
    logic `N($clog2(`COMMIT_WIDTH) + 1) num;
    logic `N($clog2(`COMMIT_WIDTH) + 1) weNum;
    logic `ARRAY(`COMMIT_WIDTH, 5) vrd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) old_prd;
} CommitWalk;

typedef struct packed {
    logic `N(`WAKEUP_SIZE) en;
    logic `N(`WAKEUP_SIZE) we;
    logic `ARRAY(`WAKEUP_SIZE, `PREG_WIDTH) rd;
} WakeupBus;

typedef struct packed {
    logic `N(`WB_SIZE) en;
    logic `N(`WB_SIZE) we;
    RobIdx `N(`WB_SIZE) robIdx;
    logic `ARRAY(`WB_SIZE, `PREG_WIDTH) rd;
    logic `ARRAY(`WB_SIZE, `XLEN) res;
    logic `ARRAY(`WB_SIZE, `EXC_WIDTH) exccode;
} WriteBackBus;

`define DIRECTORY_ENTRY_DEF(NUM_ENTRY)  \
typedef struct packed { \
    logic en; \
    CoherentState state; \
    logic `N($clog2(NUM_ENTRY+1)) owner; \
    logic `N(NUM_ENTRY) sharers; \
} DirectoryEntry;


`endif