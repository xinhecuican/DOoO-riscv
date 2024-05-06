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
    logic table_hits;
    logic `N($clog2(`TAGE_BANK)) provider;
} TageMeta;

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
    logic [`SLOT_NUM-1: 0] cond_history;
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
    logic `VADDR_BUS squash_pc;
    logic `VADDR_BUS target_pc;
    RedirectInfo redirectInfo;
    BTBEntry btbEntry;
} SquashInfo;

typedef struct packed {
    logic `N(`FETCH_WIDTH) en;
    logic `ARRAY(`FETCH_WIDTH, `FSQ_WIDTH) fsqIdx;
    logic `ARRAY(`FETCH_WIDTH, 32) inst;
} FetchBundle;

typedef struct packed {
    logic intv; // int valid
    logic memv;
    logic branchv;
    logic sext;
    logic we;
    logic `N(`INTOP_WIDTH) intop;
    logic `N(`MEMOP_WIDTH) memop;
    logic `N(`BRANCHOP_WIDTH) branchop;
    logic [4: 0] rs1, rs2, rd;
    logic `N(`XLEN) imm;
} DecodeInfo;

typedef struct packed {
    logic en;
    logic `N(`FSQ_WIDTH) fsqIdx;
    DecodeInfo di;
} OPBundle;
`endif