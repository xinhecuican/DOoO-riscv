`include "../../../defines/defines.svh"

module DecodeUnit(
    input logic [31: 0] inst,
    /* verilator lint_off UNOPTFLAT */
    output DecodeInfo info
);
    logic [4: 0] op;
    logic [2: 0] funct3;
    logic [5: 0] funct7;

    assign op = inst[6: 2];
    assign funct3 = inst[14: 12];
    assign funct7 = inst[31: 25];

    logic lui, auipc, jal, jalr, branch, load, store, opimm, opreg;
    assign lui = ~op[4] & op[3] & op[2] & ~op[1] & op[0];
    assign auipc = ~op[4] & ~op[3] & op[2] & ~op[1] & op[0];
    assign jal = op[4] & op[3] & ~op[2] & op[1] & op[0];
    assign jalr = op[4] & op[3] & ~op[2] & ~op[1] & op[0];
    assign branch = op[4] & op[3] & ~op[2] & ~op[1] & ~op[0];
    assign load = ~op[4] & ~op[3] & ~op[2] & ~op[1] & ~op[0];
    assign store = ~op[4] & op[3] & ~op[2] & ~op[1] & ~op[0];
    assign opimm = ~op[4] & ~op[3] & op[2] & ~op[1] & ~op[0];
    assign opreg = ~op[4] & op[3] & op[2] & ~op[1] & ~op[0];

    assign info.intv = lui | opimm | opreg;
    assign info.branchv = branch | jal | jalr;
    assign info.memv = load | store;
    assign info.rs1 = {5{jalr | branch | load | store | opimm | opreg}} & inst[19: 15];
    assign info.rs2 = {5{branch | store | opreg}} & inst[24: 20];
    assign info.rd = {5{lui | jalr | jal | load | opimm | opreg}} & inst[11: 7];
    assign info.we = info.rd != 0;

    logic beq, bne, blt, bge, bltu, bgeu;
    assign beq = branch & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign bne = branch & ~funct3[2] & ~funct3[1] & funct3[0];
    assign blt = branch & funct3[2] & ~funct3[1] & ~funct3[0];
    assign bge = branch & funct3[2] & ~funct3[1] & funct3[0];
    assign bltu = branch & funct3[2] & funct3[1] & ~funct3[0];
    assign bgeu = branch & (|funct3);

    assign info.branchop[2] = jal | jalr;
    assign info.branchop[1] = blt | bge;
    assign info.branchop[0] = jalr | bne | bge;


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
    assign info.memop[2] = lbu | lhu;
    assign info.memop[1] = lw | sw;
    assign info.memop[0] = lh | lhu | sh;

    logic addi, slti, sltiu, xori, ori, andi, slli, srli, srai;
    assign addi = opimm & ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign slti = opimm & ~funct3[2] & funct3[1] & ~funct3[0];
    assign sltiu = opimm & ~funct3[2] & funct3[1] & funct3[0];
    assign xori = opimm & funct3[2] & ~funct3[1] & ~funct3[0];
    assign ori = opimm & funct3[2] & funct3[1] & ~funct3[0];
    assign andi = opimm & (|funct3);
    assign slli = opimm & ~funct3[2] & ~funct3[1] & funct3[0];
    assign srli = opimm & funct3[2] & ~funct3[1] & funct3[0] & ~funct7[5];
    assign srai = opimm & funct3[2] & ~funct3[1] & funct3[0] & funct7[5];

    logic add, sub, sll, slt, sltu, _xor, srl, sra, _or, _and;
    assign add = opreg & ~funct3[2] & ~funct3[1] & ~funct3[0] & ~funct7[5];
    assign sub = opreg & ~funct3[2] & ~funct3[1] & ~funct3[0] & funct7[5];
    assign sll = opreg & ~funct3[2] & ~funct3[1] & funct3[0];
    assign slt = opreg & ~funct3[2] & funct3[1] & ~funct3[0];
    assign sltu = opreg & ~funct3[2] & funct3[1] & funct3[0];
    assign _xor = opreg & funct3[2] & ~funct3[1] & ~funct3[0];
    assign srl = opreg & funct3[2] & ~funct3[1] & funct3[0] & ~funct7[5];
    assign sra = opreg & funct3[2] & ~funct3[1] & funct3[0] & funct7[5];
    assign _or = opreg & funct3[2] & funct3[1] & ~funct3[0];
    assign _and = opreg & (|funct3);

    assign info.intop[4] = 1'b0;
    assign info.intop[3] = slli | srli | srai | sll | srl | sra;
    assign info.intop[2] = xori | ori | andi | _xor | _or | _and;
    assign info.intop[1] = slti | sltiu | slt | sltu | ori | _or | sra | srai;
    assign info.intop[0] = lui | andi | _and | srl | srli;

    assign info.sext = blt | bge | lb | lh | lw | slti | slt;
    logic [11: 0] imm;
    logic `N(`XLEN) lui_imm;
    logic `N(`XLEN) jal_imm;
    logic `N(`XLEN) branch_imm;
    logic `N(`XLEN) sext_imm;
    assign jal_imm = {{(`XLEN-21){inst[31]}}, inst[31], inst[19: 12], inst[20], inst[30: 21], 1'b0};
    assign lui_imm = {{`XLEN-20{inst[31]}}, inst[31: 12]};
    assign branch_imm = {{`XLEN-13{inst[31]}}, inst[31], inst[7], inst[30: 25], inst[11: 8], 1'b0};
    assign imm = inst[31: 20];
    assign sext_imm = {{`XLEN-12{inst[31]}}, imm};
    assign info.immv = lui | jal | beq | bne | blt | bge | slli | srai | srli | lb | lh | lw | addi | slti | xori | ori | andi | lbu | lhu | sltiu | jalr;
    assign info.imm = lui & lui_imm |
                      jal & jal_imm |
                      {beq | bne | blt | bge} & branch_imm |
                      {slli | srai | srli} & info.rs2 |
                      {lb | lh | lw | addi | slti | xori | ori | andi} & sext_imm |
                      {lbu | lhu | sltiu | jalr} & imm;

endmodule