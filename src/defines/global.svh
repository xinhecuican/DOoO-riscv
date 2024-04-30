`ifndef GLOBAL_SVH
`define GLOBAL_SVH
`define RV32I

`define N(n) [(n)-1: 0]
`define ARRAY(height, width) [(height-1): 0][(width-1): 0]

`define RST 1'b1
`ifdef RV32I
`define XLEN 32
`endif
`define DATA_BUS `N(`XLEN)
`define VADDR_SIZE `XLEN
`define VADDR_BUS [(`VADDR_SIZE)-1: 0]
`define PADDR_SIZE `XLEN
`define PADDR_BUS [(`PADDR_SIZE)-1: 0]
`define IALIGN 32

`define RESET_PC `XLEN'h0

// BranchPrediction
`define PREDICT_STAGE 3
`define BLOCK_SIZE 32 // max bytes for an instruction block/fetch stream
`define BLOCK_WIDTH $clog2(`BLOCK_SIZE)
`define PREDICTION_WIDTH $clog2(`BLOCK_SIZE/4)
`define SLOT_NUM 2

`define GHIST_SIZE 256
`define GHIST_WIDTH $clog2(`GHIST_SIZE)
`define PHIST_SIZE 32 // path hist

`define JAL_OFFSET 12
`define JALR_OFFSET 20

`define UBTB_SIZE 64
`define UBTB_TAG_SIZE 7
`define UBTB_WIDTH $clog2(`UBTB_SIZE)

`define BTB_TAG_SIZE 14
`define BTB_WAY 2
`define BTB_SET 256
`define BTB_SET_WIDTH $clog2(`BTB_SET)
`define BTB_TAG_BUS [`BTB_TAG_SIZE+$clog2(`BTB_WAY*`BTB_SET)-1: $clog2(`BTB_WAY*`BTB_SET)]

`define TAGE_TAG_SIZE 8
`define TAGE_U_SIZE 2
`define TAGE_CTR_SIZE 3
`define TAGE_BANK 4
`define TAGE_TAG_COMPRESS1 12
`define TAGE_TAG_COMPRESS2 10
`define TAGE_BASE_SIZE 4096
`define TAGE_BASE_CTR 2
parameter [8: 0] tage_hist_length `N(`TAGE_BANK) = {9'd8, 9'd13, 9'd32, 9'd119};
parameter [12: 0] tage_set_size `N(`TAGE_BANK) = {13'd4096, 13'd4096, 13'd4096, 13'd4096};
`define TAGE_SET_WIDTH 12
typedef enum logic [1: 0] { 
    DIRECT, 
    CONDITION, 
    INDIRECT, 
    CALL 
} BranchType;

`define RAS_SIZE 32
`define RAS_WIDTH $clog2(`RAS_SIZE)
`define RAS_CTR_SIZE 8
typedef enum logic [1: 0] { 
    NONE,
    POP,
    PUSH,
    POP_PUSH
} RasType;

`define FSQ_SIZE 32
`define FSQ_WIDTH $clog2(`FSQ_SIZE)

`define ICACHE_SET 256
`define ICACHE_WAY 4
`define ICACHE_LINE 32
`define ICACHE_BANK (`ICACHE_LINE / 4)
`define ICACHE_BANK_WIDTH $clog2(`ICACHE_BANK)
`define ICACHE_WAY_WIDTH $clog2(`ICACHE_WAY)
`define ICACHE_SET_WIDTH $clog2(`ICACHE_SET)
`define ICACHE_LINE_WIDTH $clog2(`ICACHE_LINE)
`define ICACHE_TAG (`VADDR_SIZE-`ICACHE_SET_WIDTH-`ICACHE_LINE_WIDTH)
`define ICACHE_TAG_BUS [`VADDR_SIZE-1: `ICACHE_SET_WIDTH+`ICACHE_LINE_WIDTH]
`define ICACHE_SET_BUS [`ICACHE_SET_WIDTH+`ICACHE_LINE_WIDTH-1: `ICACHE_LINE_WIDTH]

// InstBuffer
`define INST_BUFFER_SIZE 32
`define INST_BUFFER_BANK_NUM 8
`define INST_BUFFER_BANK_SIZE (`INST_BUFFER_SIZE / `INST_BUFFER_BANK_NUM)
`define INST_BUFFER_BANK_WIDTH $clog2(`INST_BUFFER_BANK_SIZE)

`define FETCH_WIDTH 4
`define FETCH_WIDTH_LOG $clog2(`FETCH_WIDTH)

`endif
