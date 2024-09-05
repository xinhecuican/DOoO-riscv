`ifndef OPCODE_SVH
`define OPCODE_SVH

`define INTOP_WIDTH 5
`define MEMOP_WIDTH 4
`define BRANCHOP_WIDTH 3
`define CSROP_WIDTH 4
`define MULTOP_WIDTH 4

// intop
`define INT_ADD     `INTOP_WIDTH'b00000
`define INT_SUB     `INTOP_WIDTH'b01101
`define INT_LUI     `INTOP_WIDTH'b00001
`define INT_SLT     `INTOP_WIDTH'b00010
`define INT_XOR     `INTOP_WIDTH'b00100
`define INT_OR      `INTOP_WIDTH'b00110
`define INT_AND     `INTOP_WIDTH'b00101
`define INT_SL      `INTOP_WIDTH'b01000
`define INT_SR      `INTOP_WIDTH'b01001
`define INT_AUIPC   `INTOP_WIDTH'b01100
`define INT_FENCE   `INTOP_WIDTH'b00011

// memop

`define MEM_LB      `MEMOP_WIDTH'b0000
`define MEM_LH      `MEMOP_WIDTH'b0001
`define MEM_LW      `MEMOP_WIDTH'b0010
`define MEM_SB      `MEMOP_WIDTH'b1000
`define MEM_SH      `MEMOP_WIDTH'b1100
`define MEM_SW      `MEMOP_WIDTH'b1010

// branchop

`define BRANCH_JAL  `BRANCHOP_WIDTH'b100
`define BRANCH_JALR `BRANCHOP_WIDTH'b101
`define BRANCH_BEQ  `BRANCHOP_WIDTH'b000
`define BRANCH_BNE  `BRANCHOP_WIDTH'b001
`define BRANCH_BLT  `BRANCHOP_WIDTH'b010
`define BRANCH_BGE  `BRANCHOP_WIDTH'b011

// csrop
`define CSR_RW      `CSROP_WIDTH'b0001
`define CSR_RS      `CSROP_WIDTH'b0010
`define CSR_RC      `CSROP_WIDTH'b0011
`define CSR_RWI     `CSROP_WIDTH'b0101
`define CSR_RSI     `CSROP_WIDTH'b0110
`define CSR_RCI     `CSROP_WIDTH'b0111
`define CSR_SFENCE  `CSROP_WIDTH'b1000

// multop
`define MULT_MUL       `MULTOP_WIDTH'b000
`define MULT_MULH      `MULTOP_WIDTH'b001
`define MULT_MULHSU    `MULTOP_WIDTH'b010
`define MULT_MULHU     `MULTOP_WIDTH'b011
`define MULT_DIV       `MULTOP_WIDTH'b100
`define MULT_DIVU      `MULTOP_WIDTH'b101
`define MULT_REM       `MULTOP_WIDTH'b110
`define MULT_REMU      `MULTOP_WIDTH'b111

// opcode

`define OPCODE_LUI      7'b0110111
`define OPCODE_AUIPC    7'b0010111
`define OPCODE_JAL      7'b1101111
`define OPCODE_JALR     7'b1100111
`define OPCODE_BRANCH   7'b1100011
`define OPCODE_LOAD     7'b0000011
`define OPCODE_STORE    7'b0100011
`define OPCODE_IMM      7'b0010011
`define OPCODE_OP       7'b0110011
`define OPCODE_FENCE    7'b0001111
`define OPCODE_SYSTEM   7'b1110011
`define OPCODE_CUSTOM0  7'b0001011

// funct3
`define FUNCT_BEQ   3'b000
`define FUNCT_BNE   3'b001
`define FUNCT_BLT   3'b100
`define FUNCT_BGE   3'b101
`define FUNCT_BLTU  3'b110
`define FUNCT_BGEU  3'b111

`define FUNCT_LB    3'b000
`define FUNCT_LH    3'b001
`define FUNCT_LW    3'b010
`define FUNCT_LBU   3'b100
`define FUNCT_LHU   3'b101
`define FUNCT_SB    3'b000
`define FUNCT_SH    3'b001
`define FUNCT_SW    3'b010

`define FUNCT_ADDI  3'b000
`define FUNCT_SLTI  3'b010
`define FUNCT_SLTIU 3'b011
`define FUNCT_XORI  3'b100
`define FUNCT_ORI   3'b110
`define FUNCT_ANDI  3'b111
`define FUNCT_SLLI 3'b001
`define FUNCT_SRLI 3'b101
`define FUNCT_SRAI 3'b101

`define FUNCT_ADD   3'b000
`define FUNCT_SUB   3'b000
`define FUNCT_SLL   3'b001
`define FUNCT_SLT   3'b010
`define FUNCT_SLTU  3'b011
`define FUNCT_XOR   3'b100
`define FUNCT_SRL   3'b101
`define FUNCT_SRA   3'b101
`define FUNCT_OR    3'b110
`define FUNCT_AND   3'b111

`define FUNCT_CSRRW     3'b001
`define FUNCT_CSRRS     3'b010
`define FUNCT_CSRRC     3'b011
`define FUNCT_CSRRWI    3'b101
`define FUNCT_CSRRSI    3'b110
`define FUNCT_CSRRCI    3'b111

`define FUNCT_SIMTRAP   3'b000

`define FUNCT_MUL       3'b000
`define FUNCT_MULH      3'b001
`define FUNCT_MULHSU    3'b010
`define FUNCT_MULHU     3'b011
`define FUNCT_DIV       3'b100
`define FUNCT_DIVU      3'b101
`define FUNCT_REM       3'b110
`define FUNCT_REMU      3'b111

// funct7
`define FUNCT7_SRLI 7'b0000000
`define FUNCT7_SRAI 7'b0100000
`define FUNCT7_ADD  7'b0000000
`define FUNCT7_SUB  7'b0100000
`define FUNCT7_SRL  7'b0000000
`define FUNCT7_SRA  7'b0100000
`define FUNCT7_MULT 7'b0000001
`define FUNCT7_SFENCE_VMA 7'b0001001

// funct12
`define FUNCT12_ECALL   12'b0000_0000_0000
`define FUNCT12_EBREAK  12'b0000_0000_0001
`define FUNCT12_MRET    12'b0011_0000_0010
`define FUNCT12_SRET    12'b0001_0000_0010
`define FUNCT12_URET    12'b0000_0000_0010

// simulation
`define GOOD_TRAP   32'h0000000b
`define BAD_TRAP    32'h0010000b
`endif
