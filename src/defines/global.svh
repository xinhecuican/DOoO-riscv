`ifndef GLOBAL_SVH
`define GLOBAL_SVH
`include "arch.svh"

`define N(n) [(n)-1: 0]
`define ARRAY(height, width) [(height-1): 0][(width-1): 0]
`define TENSOR(x1, x2, x3) [x1-1: 0][x2-1: 0][x3-1: 0]

`define RST 1'b1
`ifdef RV32I
`define XLEN 32
`define MXL 32
`endif
`define DATA_BYTE (`XLEN / 8)
`define DATA_BUS `N(`XLEN)
`define VADDR_SIZE `XLEN
`define VADDR_BUS [(`VADDR_SIZE)-1: 0]
`define PADDR_SIZE `XLEN
`define PADDR_BUS [(`PADDR_SIZE)-1: 0]
`define IALIGN 32

`define RESET_PC `VADDR_SIZE'h80000000

// BranchPrediction
`define PREDICT_STAGE 2
`define BLOCK_SIZE 32 // max bytes for an instruction block/fetch stream
`define BLOCK_INST_SIZE (`BLOCK_SIZE / 4)
`define BLOCK_WIDTH $clog2(`BLOCK_SIZE)
`define BLOCK_INST_WIDTH $clog2(`BLOCK_INST_SIZE)
`define PREDICTION_WIDTH $clog2(`BLOCK_INST_SIZE)
`define SLOT_NUM 2

`define GHIST_SIZE 256
`define GHIST_WIDTH $clog2(`GHIST_SIZE)
`define PHIST_SIZE 32 // path hist

`define JAL_OFFSET 12
`define JALR_OFFSET 20

`define UBTB_SIZE 64
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
`define TAGE_BASE_WIDTH $clog2(`TAGE_BASE_SIZE)
`define TAGE_BASE_CTR 2
`define TAGE_ALT_CTR 7
parameter [8: 0] tage_hist_length `N(`TAGE_BANK) = {9'd8, 9'd13, 9'd32, 9'd119};
parameter [12: 0] tage_set_size `N(`TAGE_BANK) = {13'd2048, 13'd2048, 13'd2048, 13'd2048};
`define TAGE_SET_WIDTH 12
typedef enum logic [1: 0] {
    DIRECT,
    CONDITION,
    INDIRECT,
    CALL
} BranchType;

typedef enum logic [1: 0] { 
    TAR_NONE,
    TAR_OV,
    TAR_UN
} TargetState;

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

// icache
`define ICACHE_ID 4'b0
`define ICACHE_SET 64
`define ICACHE_WAY 8
`define ICACHE_LINE 64
`define ICACHE_BANK (`ICACHE_LINE / 4)
`define ICACHE_BANK_WIDTH $clog2(`ICACHE_BANK)
`define ICACHE_WAY_WIDTH $clog2(`ICACHE_WAY)
`define ICACHE_SET_WIDTH $clog2(`ICACHE_SET)
`define ICACHE_LINE_WIDTH $clog2(`ICACHE_LINE)
`define ICACHE_TAG (`VADDR_SIZE-`ICACHE_SET_WIDTH-`ICACHE_LINE_WIDTH)
`define ICACHE_TAG_BUS [`VADDR_SIZE-1: `ICACHE_SET_WIDTH+`ICACHE_LINE_WIDTH]
`define ICACHE_SET_BUS [`ICACHE_SET_WIDTH+`ICACHE_LINE_WIDTH-1: `ICACHE_LINE_WIDTH]

// InstBuffer
`define IBUF_SIZE 32
`define IBUF_BANK_NUM 8
`define IBUF_BANK_SIZE (`IBUF_SIZE / `IBUF_BANK_NUM)
`define IBUF_BANK_WIDTH $clog2(`IBUF_BANK_SIZE)

`define FETCH_WIDTH 4
`define FETCH_WIDTH_LOG $clog2(`FETCH_WIDTH)
`define DEC_IMM_WIDTH 20

// rename
`define PREG_SIZE 128
`define PREG_WIDTH $clog2(`PREG_SIZE)
`define FREELIST_DEPTH ((`PREG_SIZE-32))

// rob
`define ROB_SIZE 128
`define ROB_WIDTH $clog2(`ROB_SIZE)
`define COMMIT_WIDTH 4

// regfile
`define REGFILE_READ_PORT (`ALU_SIZE * 2 + `LOAD_PIPELINE + `STORE_PIPELINE * 2)
`define REGFILE_WRITE_PORT `WB_SIZE

// dispatch
`define INT_DIS_SIZE 16
`define INT_DIS_PORT 4
`define LOAD_DIS_SIZE 8
`define STORE_DIS_SIZE 8
`define LOAD_DIS_PORT 2
`define STORE_DIS_PORT 2
`define CSR_DIS_SIZE 8
`define CSR_DIS_PORT 1
`define BUSYTABLE_PORT (`INT_DIS_PORT * 2 + `LOAD_DIS_PORT + `STORE_DIS_PORT * 2)

// issue
`define INT_ISSUE_SIZE 32
`define ALU_SIZE 4
`define LOAD_ISSUE_BANK_SIZE 8
`define LOAD_ISSUE_BANK_WIDTH $clog2(`LOAD_ISSUE_BANK_SIZE)
`define LOAD_ISSUE_BANK_NUM `LOAD_DIS_PORT
`define STORE_ISSUE_BANK_SIZE 8
`define STORE_ISSUE_BANK_NUM `STORE_DIS_PORT
`define CSR_ISSUE_SIZE 4
`define CSR_ISSUE_WIDTH $clog2(`CSR_ISSUE_SIZE)

// lsu
`define LOAD_QUEUE_SIZE 32
`define LOAD_QUEUE_WIDTH $clog2(`LOAD_QUEUE_SIZE)
`define LOAD_PIPELINE 2
`define STORE_QUEUE_SIZE 32
`define STORE_QUEUE_WIDTH $clog2(`STORE_QUEUE_SIZE)
`define STORE_PIPELINE 2
`define STORE_COMMIT_SIZE 8
`define STORE_COMMIT_WIDTH $clog2(`STORE_COMMIT_SIZE)
`define STORE_COUNTER_WIDTH 8
`define LSU_SIZE `LOAD_PIPELINE
`define LOAD_REFILL_SIZE 2

// wb
`define WAKEUP_SIZE (`ALU_SIZE+`LSU_SIZE)
`define WB_SIZE (`ALU_SIZE+`LSU_SIZE)

// dcache
`define DCACHE_ID 4'b1
`define DCACHE_SET 64
`define DCACHE_WAY 8
`define DCACHE_LINE 64
`define DCACHE_BYTE 4 // bank byte
`define DCACHE_BYTE_WIDTH $clog2(`DCACHE_BYTE)
`define DCACHE_BITS (`DCACHE_BYTE * 8)
`define DCACHE_BANK (`DCACHE_LINE / `DCACHE_BYTE)
`define DCACHE_BANK_WIDTH $clog2(`DCACHE_BANK)
`define DCACHE_WAY_WIDTH $clog2(`DCACHE_WAY)
`define DCACHE_SET_WIDTH $clog2(`DCACHE_SET)
`define DCACHE_LINE_WIDTH $clog2(`DCACHE_LINE)
`define DCACHE_BYTE_WIDTH $clog2(`DCACHE_BYTE)
`define DCACHE_TAG (`VADDR_SIZE-`DCACHE_SET_WIDTH-`DCACHE_LINE_WIDTH)
`define DCACHE_TAG_BUS [`VADDR_SIZE-1: `DCACHE_SET_WIDTH+`DCACHE_LINE_WIDTH]
`define DCACHE_SET_BUS [`DCACHE_SET_WIDTH+`DCACHE_LINE_WIDTH-1: `DCACHE_LINE_WIDTH]
`define DCACHE_BANK_BUS [`DCACHE_BANK_WIDTH+1: `DCACHE_BYTE_WIDTH]
`define DCACHE_BLOCK_SIZE (`VADDR_SIZE-`DCACHE_BYTE_WIDTH-`DCACHE_BANK_WIDTH)
`define DCACHE_BLOCK_BUS [`VADDR_SIZE-1: `DCACHE_BANK_WIDTH+`DCACHE_BYTE_WIDTH]

`define DCACHE_MISS_SIZE 16
`define DCACHE_MSHR_SIZE 16
`define DCACHE_MISS_WIDTH $clog2(`DCACHE_MISS_SIZE)
`define DCACHE_MSHR_WIDTH $clog2(`DCACHE_MSHR_SIZE)
`define DCACHE_REPLACE_SIZE 4
`define DCACHE_REPLACE_WIDTH $clog2(`DCACHE_REPLACE_SIZE)

// mmu
`define TLB_OFFSET 12
`define TLB_TAG (`VADDR_SIZE-`TLB_OFFSET)
`define TLB_TAG_BUS [`VADDR_SIZE-1: `TLB_OFFSET]

// exccode
`define EXC_WIDTH 5
`define EXC_NONE        `EXC_WIDTH'b11111
`define EXCI_SSI        `EXC_WIDTH'd1 // supervisor soft interrupt
`define EXCI_MSI        `EXC_WIDTH'd3 // machine soft interrupt
`define EXCI_STIMER     `EXC_WIDTH'd5
`define EXCI_MTIMER     `EXC_WIDTH'd7
`define EXCI_SEXT       `EXC_WIDTH'd9
`define EXCI_MEXT       `EXC_WIDTH'd11
`define EXCI_COUNTEROV  `EXC_WIDTH'd13
`define EXC_IAM         `EXC_WIDTH'd0 // inst address misaligned
`define EXC_IAF         `EXC_WIDTH'd1 // inst access fault
`define EXC_II          `EXC_WIDTH'd2 // illegal inst
`define EXC_BP          `EXC_WIDTH'd3 // breakpoint
`define EXC_LAM         `EXC_WIDTH'd4 // load address misaligned
`define EXC_LAF         `EXC_WIDTH'd5 // load address fault
`define EXC_SAM         `EXC_WIDTH'd6 // store address misaligned
`define EXC_SAF         `EXC_WIDTH'd7 // store address misaligned
`define EXC_ECU         `EXC_WIDTH'd8 // environment call from U-mode
`define EXC_ECS         `EXC_WIDTH'd9 // environment call from S-mode
`define EXC_ECM         `EXC_WIDTH'd11 // environment call from M-mode
`define EXC_IPF         `EXC_WIDTH'd12 // inst page fault
`define EXC_LPF         `EXC_WIDTH'd13 // load page fault
`define EXC_SPF         `EXC_WIDTH'd15 // store page fault
`define EXC_DT          `EXC_WIDTH'd16 // double trap
`define EXC_SC          `EXC_WIDTH'd18 // software check
`define EXC_HE          `EXC_WIDTH'd19 // hardware error
`define EXC_SRET        `EXC_WIDTH'd25 // user defined.sret 
`define EXC_MRET        `EXC_WIDTH'd27 // user defined.mret
`define EXC_EC          `EXC_WIDTH'd28 // user defined.environment call

`endif
