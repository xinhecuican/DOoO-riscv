`ifndef BUNDLES_SVH
`define BUNDLES_SVH
`include "global.svh"
`include "opcode.svh"

typedef struct packed {
    logic en;
    logic carry;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `N(`JAL_OFFSET) target;
} BranchSlot;

typedef struct packed {
    logic en;
    logic carry;
    BranchType br_type;
    RasType ras_type;
    logic `N(`PREDICTION_WIDTH) offset;
    logic `N(`JALR_OFFSET) target;
} TailSlot;

typedef struct packed {
    logic en;
    logic `N(`BTB_TAG_SIZE) tag;
    BranchSlot `N(`SLOT_NUM-1) slots;
    TailSlot tailSlot;
    logic `N(`PREDICTION_WIDTH) fthAddr;
} BTBEntry;

typedef struct packed {
    logic `N(`TAGE_TAG_SIZE) tag;
    logic `N(`TAGE_U_SIZE) u;
    logic `N(`TAGE_CTR_SIZE) ctr;
} TageEntry;

typedef struct packed {
    logic `ARRAY(`TAGE_BANK, `SLOT_NUM) table_hits;
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
    logic `N(`GHIST_WIDTH) ghistIdx;
    TageFoldHistory tage_history;
    logic `N(`RAS_WIDTH) rasIdx;
    logic `N(`RAS_CTR_SIZE) ras_ctr;
} RedirectInfo;

typedef struct packed {
    logic `N(`GHIST_SIZE) ghist;
    logic `N(`PHIST_SIZE) phist;
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
    RedirectInfo redirect_info;
} PredictionResult;

typedef struct packed {
    logic branch;
    logic direct;
    BranchType branch_type;
    RasType ras_type;
    logic `VADDR_BUS target;
} PreDecodeBundle;

typedef struct {
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
    BTBEntry btbEntry;
    PredictionMeta meta;
} BranchUpdateInfo;

typedef struct packed {
    logic `N(`FSQ_WIDTH) idx;
    logic `N(`PREDICTION_WIDTH) offset;
} FsqIdxInfo;

typedef struct packed {
    logic `N(`FETCH_WIDTH) en;
    FsqIdxInfo `N(`FETCH_WIDTH) fsqInfo;
    logic `ARRAY(`FETCH_WIDTH, 32) inst;
} FetchBundle;

typedef struct packed {
    logic intv; // int valid
    logic memv;
    logic branchv;
    logic sext;
    logic we;
    logic immv;
    logic `N(`INTOP_WIDTH) intop;
    logic `N(`MEMOP_WIDTH) memop;
    logic `N(`BRANCHOP_WIDTH) branchop;
    logic [4: 0] rs1, rs2, rd;
    logic `N(`XLEN) imm;
} DecodeInfo;

typedef struct packed {
    logic en;
    FsqIdxInfo fsqInfo;
    DecodeInfo di;
} OPBundle;

typedef struct packed {
    logic rs1v, rs2v;
    logic `N(`PREG_WIDTH) rs1, rs2;
} IssueStatusBundle;

typedef struct packed {
    logic intv;
    logic branchv;
    logic sext;
    logic immv;
    logic `N(`INTOP_WIDTH) intop;
    logic `N(`BRANCHOP_WIDTH) branchop;
    logic `N(`ROB_WIDTH) robIdx;
    logic `N(`PREG_WIDTH) rd;
    logic `N(`XLEN) imm;
    FsqIdxInfo fsqInfo;
} IntIssueBundle;

typedef struct packed {
    logic en;
    logic taken;
    FsqIdxInfo fsqInfo;
    logic `N(`VADDR_SIZE) target;
    BranchType br_type;
    RasType ras_type;
} BackendRedirectInfo;

typedef struct packed {
    logic direction;
    logic error;
    logic `N(`VADDR_SIZE) target;
    RasType ras_type;
    BranchType br_type;
} BranchUnitRes;

typedef struct packed {
    logic en;
    FsqIdxInfo fsqInfo;
    BranchUnitRes res;
} AluBranchBundle;

typedef struct packed {
    logic en;
    logic `N(`ROB_WIDTH) robIdx;
    FsqIdxInfo fsqInfo;
    logic `N(`PREG_WIDTH) rd;
    logic `N(`XLEN) res;
} WBData;

typedef struct packed {
    logic en;
    FsqIdxInfo fsqInfo;
    logic `N(`PREG_WIDTH) vrd;
    logic `N(`PREG_WIDTH) prd;
} CommitData;
`endif