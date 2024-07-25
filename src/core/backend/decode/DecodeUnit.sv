`include "../../../defines/defines.svh"

module DecodeUnit(
    input logic [31: 0] inst,
    input logic iam,
    input logic ipf,
    /* verilator lint_off UNOPTFLAT */
    output DecodeInfo info
);
    logic [4: 0] op;
    logic [2: 0] funct3;
    logic [6: 0] funct7;
    logic [4: 0] rd;

    assign op = inst[6: 2];
    assign funct3 = inst[14: 12];
    assign funct7 = inst[31: 25];

    logic lui, auipc, jal, jalr, branch, load, store, miscmem, opimm, opreg, opsystem, unknown;
    assign lui = ~op[4] & op[3] & op[2] & ~op[1] & op[0];
    assign auipc = ~op[4] & ~op[3] & op[2] & ~op[1] & op[0];
    assign jal = op[4] & op[3] & ~op[2] & op[1] & op[0];
    assign jalr = op[4] & op[3] & ~op[2] & ~op[1] & op[0];
    assign branch = op[4] & op[3] & ~op[2] & ~op[1] & ~op[0];
    assign load = ~op[4] & ~op[3] & ~op[2] & ~op[1] & ~op[0];
    assign store = ~op[4] & op[3] & ~op[2] & ~op[1] & ~op[0];
    assign miscmem = ~op[4] & ~op[3] & ~op[2] & op[1] & op[0];
    assign opimm = ~op[4] & ~op[3] & op[2] & ~op[1] & ~op[0];
    assign opreg = ~op[4] & op[3] & op[2] & ~op[1] & ~op[0];
    assign opsystem = op[4] & op[3] & op[2] & ~op[0] & ~op[0];

    logic beq, bne, blt, bge, bltu, bgeu;
    assign beq = branch & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign bne = branch & ~funct3[2] & ~funct3[1] & funct3[0];
    assign blt = branch & funct3[2] & ~funct3[1] & ~funct3[0];
    assign bge = branch & funct3[2] & ~funct3[1] & funct3[0];
    assign bltu = branch & funct3[2] & funct3[1] & ~funct3[0];
    assign bgeu = branch & (&funct3);

    assign info.branchop[2] = jal | jalr;
    assign info.branchop[1] = blt | bge | bgeu | bltu;
    assign info.branchop[0] = jalr | bne | bge | bgeu;

    logic funct7_0, funct7_5, funct7_1, rs2_0, rs2_1, rs2_2, funct3_0;
    assign funct7_0 = ~funct7[6] & ~funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_1 = ~funct7[6] & ~funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & funct7[0];
    assign funct7_5 = ~funct7[6] & funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct3_0 = ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign rs2_0 = ~inst[24] & ~inst[23] & ~inst[22] & ~inst[21] & ~inst[20];
    assign rs2_1 = ~inst[24] & ~inst[23] & ~inst[22] & ~inst[21] & inst[20];
    assign rs2_2 = ~inst[24] & ~inst[23] & ~inst[22] & inst[21] & ~inst[20];

    // TODO: implement fence, current pass to int, no effect
    logic fence;
    assign fence = miscmem & ~funct3[2] & ~funct3[1] & ~funct3[0];

    logic lb, lh, lw, lbu, lhu, sb, sh, sw;
    assign lb = load & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign lh = load & ~funct3[2] & ~funct3[1] & funct3[0];
    assign lw = load & ~funct3[2] & funct3[1] & ~funct3[0];
    assign lbu = load & funct3[2] & ~funct3[1] & ~funct3[0];
    assign lhu = load & funct3[2] & ~funct3[1] & funct3[0];
    assign sb = store & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign sh = store & ~funct3[2] & ~funct3[1] & funct3[0];
    assign sw = store & ~funct3[2] & funct3[1] & ~funct3[0];

    assign info.memop[3] = store;
    assign info.memop[2] = sh;
    assign info.memop[1] = lw | sw;
    assign info.memop[0] = lh | lhu;

    logic addi, slti, sltiu, xori, ori, andi, slli, srli, srai;
    assign addi = opimm & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign slti = opimm & ~funct3[2] & funct3[1] & ~funct3[0];
    assign sltiu = opimm & ~funct3[2] & funct3[1] & funct3[0];
    assign xori = opimm & funct3[2] & ~funct3[1] & ~funct3[0];
    assign ori = opimm & funct3[2] & funct3[1] & ~funct3[0];
    assign andi = opimm & (&funct3);
    assign slli = opimm & ~funct3[2] & ~funct3[1] & funct3[0] & funct7_0;
    assign srli = opimm & funct3[2] & ~funct3[1] & funct3[0] & funct7_0;
    assign srai = opimm & funct3[2] & ~funct3[1] & funct3[0] & funct7_5;

    logic add, sub, sll, slt, sltu, _xor, srl, sra, _or, _and;
    assign add = opreg & ~funct3[2] & ~funct3[1] & ~funct3[0] & funct7_0;
    assign sub = opreg & ~funct3[2] & ~funct3[1] & ~funct3[0] & funct7_5;
    assign sll = opreg & ~funct3[2] & ~funct3[1] & funct3[0] & funct7_0;
    assign slt = opreg & ~funct3[2] & funct3[1] & ~funct3[0] & funct7_0;
    assign sltu = opreg & ~funct3[2] & funct3[1] & funct3[0] & funct7_0;
    assign _xor = opreg & funct3[2] & ~funct3[1] & ~funct3[0] & funct7_0;
    assign srl = opreg & funct3[2] & ~funct3[1] & funct3[0] & funct7_0;
    assign sra = opreg & funct3[2] & ~funct3[1] & funct3[0] & funct7_5;
    assign _or = opreg & funct3[2] & funct3[1] & ~funct3[0] & funct7_0;
    assign _and = opreg & (&funct3) & funct7_0;

`ifdef DIFFTEST
    logic custom0;
    logic sim_trap;
    assign custom0 = ~op[4] & ~op[3] & ~op[2] & op[1] & ~op[0];
    assign sim_trap = custom0 & funct3_0;
    assign info.sim_trap = sim_trap;
`endif

    assign info.intop[4] = 1'b0;
    assign info.intop[3] = slli | srli | srai | sll | srl | sra | auipc | sub;
    assign info.intop[2] = xori | ori | andi | _xor | _or | _and | auipc | sub;
    assign info.intop[1] = slti | sltiu | slt | sltu | ori | _or | fence;
    assign info.intop[0] = lui | andi | _and | srl | srli | fence | sub | sra | srai;

    logic ecall, ebreak, mret, sret;
    assign ecall = opsystem & funct3_0 & funct7_0 & rs2_0;
    assign ebreak = opsystem & funct3_0 & funct7_0 & rs2_1;
    assign mret = opsystem & funct3_0 & ~funct7[6] & ~funct7[5] & funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0] & rs2_2;
    assign sret = opsystem & funct3_0 & ~funct7[6] & ~funct7[5] & ~funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0] & rs2_2;

    logic csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci, csr;
    assign csr = csrrw | csrrs | csrrc | csrrwi | csrrsi | csrrci;
    assign csrrw = opsystem & ~funct3[2] & ~funct3[1] & funct3[0];
    assign csrrs = opsystem & ~funct3[2] & funct3[1] & ~funct3[0];
    assign csrrc = opsystem & ~funct3[2] & funct3[1] & funct3[0];
    assign csrrwi = opsystem & funct3[2] & ~funct3[1] & funct3[0];
    assign csrrsi = opsystem & funct3[2] & funct3[1] & ~funct3[0];
    assign csrrci = opsystem & funct3[2] & funct3[1] & funct3[0];
    assign info.csrop[2] = csrrwi | csrrsi | csrrci;
    assign info.csrop[1] = csrrs | csrrc | csrrsi | csrrci;
    assign info.csrop[0] = csrrw | csrrc | csrrwi | csrrci;
    assign info.csrid = inst[31: 20];

`ifdef EXT_M
    logic mult, mul, mulh, mulhsu, mulhu, div, divu, rem ,remu;
    assign mult = opreg & funct7_1;
    assign mul = mult & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign mulh = mult & ~funct3[2] & ~funct3[1] & funct3[0];
    assign mulhsu = mult & ~funct3[2] & funct3[1] & ~funct3[0];
    assign mulhu = mult & ~funct3[2] & funct3[1] & funct3[0];
    assign div = mult & funct3[2] & ~funct3[1] & ~funct3[0];
    assign divu = mult & funct3[2] & ~funct3[1] & funct3[0];
    assign rem = mult & funct3[2] & funct3[1] & ~funct3[0];
    assign remu = mult & funct3[2] & funct3[1] & funct3[0];
    assign info.multop = funct3;
`endif

    assign unknown = ~beq & ~bne & ~blt & ~bge & ~bltu & ~bgeu & 
                     ~lb & ~lh & ~lw & ~lbu & ~lhu & ~sb & ~sh & ~sw & 
                     ~addi & ~slti & ~sltiu & ~xori & ~ori & ~andi & ~slli & ~srli & ~srai & 
                     ~add & ~sub & ~sll & ~slt & ~sltu & ~_xor & ~srl & ~sra & ~_or & ~_and &
                     ~csrrw & ~csrrs & ~csrrc & ~csrrwi & ~csrrsi & ~csrrci & ~ecall & ~ebreak &
                     ~fence & ~mret & ~sret &
                     ~(inst[0] & inst[1])
`ifdef DIFFTEST
                     & ~sim_trap
`endif
`ifdef EXT_M
                     & ~mult
`endif
                     ;


    assign info.uext = sltu | sltiu | lbu | lhu | bltu | bgeu | srl | srli;
    logic [11: 0] imm, store_imm;
    logic [19: 0] lui_imm;
    logic `N(`DEC_IMM_WIDTH) branch_imm;
    assign branch_imm = {inst[31], inst[7], inst[30: 25], inst[11: 8], 1'b0};
    assign imm = inst[31: 20];
    assign store_imm = {inst[31: 25], inst[11: 7]};
    assign lui_imm = inst[31: 12];

    assign info.immv = slli | srai | srli | addi | slti | xori | ori | andi | sltiu;
    assign info.imm = {`DEC_IMM_WIDTH{beq | bne | blt | bge | bgeu | bltu}} & branch_imm |
                      {`DEC_IMM_WIDTH{lui | auipc}} & lui_imm |
                      {`DEC_IMM_WIDTH{csrrw | csrrs | csrrc | csrrwi | csrrsi | csrrci
                      }} & inst[19: 15] |
                      {`DEC_IMM_WIDTH{store}} & store_imm |
                      {`DEC_IMM_WIDTH{load | opimm | fence | jalr
`ifdef DIFFTEST
                        | sim_trap
`endif
                      }} & imm;

    assign info.intv = lui | opimm | opreg | auipc | fence
`ifdef DIFFTEST
    | sim_trap
`endif
    ;
    assign info.branchv = branch | jal | jalr;
    assign info.memv = load | store;
    assign info.csrv = csr | ecall | ebreak | mret | sret | unknown | iam;
`ifdef EXT_M
    assign info.multv = mult;
`endif
    assign info.rs1 = {5{jalr | branch | load | store | opimm | opreg | csrrs | csrrc | csrrw}} & inst[19: 15];
    assign info.rs2 = {5{branch | store | opreg}} & inst[24: 20];
    assign rd = {5{lui | auipc | jalr | jal | load | opimm | opreg | csr}} & inst[11: 7];
    assign info.rd = rd;
    assign info.we = rd != 0;
    // exception from frontend and illegal inst
    // all of these exception are sent to csr issue queue due to it's simple structure
    assign info.exccode = unknown ? `EXC_II :
                          ipf ? `EXC_IPF :
                          iam ? `EXC_IAM :
                          ecall | ebreak | mret | sret ?
                               {`EXC_WIDTH{ecall}} & `EXC_EC | 
                               {`EXC_WIDTH{ebreak}} & `EXC_BP |
                               {`EXC_WIDTH{mret}} & `EXC_MRET |
                               {`EXC_WIDTH{sret}} & `EXC_SRET : `EXC_NONE;

endmodule