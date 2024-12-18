`include "../../../defines/defines.svh"

module DecodeUnit(
    input logic [31: 0] inst,
    input logic iam,
    input logic ipf,
    output DecodeInfo info
);
    logic [4: 0] op;
    logic [2: 0] funct3;
    logic [6: 0] funct7;
    logic [4: 0] rd;

    assign op = inst[6: 2];
    assign funct3 = inst[14: 12];
    assign funct7 = inst[31: 25];

    logic funct7_0, funct7_32, funct7_4, funct7_2, funct7_1, funct7_8, funct7_12, funct7_44,
    funct7_16, funct7_20, funct7_80, funct7_96, funct7_104, funct7_112, funct7_120;
    logic rs2_0, rs2_1, rs2_2, rs2_5;
    logic funct3_0, funct3_1, funct3_2, funct3_3, funct3_4, funct3_5, funct3_6, funct3_7;
    logic ebreak_all;
    assign funct7_0 = ~funct7[6] & ~funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_1 = ~funct7[6] & ~funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & funct7[0];
    assign funct7_2 = ~funct7[6] & ~funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & funct7[1] & ~funct7[0];
    assign funct7_4 = ~funct7[6] & ~funct7[5] & ~funct7[4] & ~funct7[3] & funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_8 = ~funct7[6] & ~funct7[5] & ~funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_12 = ~funct7[6] & ~funct7[5] & ~funct7[4] & funct7[3] & funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_16 = ~funct7[6] & ~funct7[5] & funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_20 = ~funct7[6] & ~funct7[5] & funct7[4] & ~funct7[3] & funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_32 = ~funct7[6] & funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_44 = ~funct7[6] & funct7[5] & ~funct7[4] & funct7[3] & funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_80 = funct7[6] & ~funct7[5] & funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_96 = funct7[6] & funct7[5] & ~funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_104 = funct7[6] & funct7[5] & ~funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_112 = funct7[6] & funct7[5] & funct7[4] & ~funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct7_120 = funct7[6] & funct7[5] & funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0];
    assign funct3_0 = ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign funct3_1 = ~funct3[2] & ~funct3[1] & funct3[0];
    assign funct3_2 = ~funct3[2] & funct3[1] & ~funct3[0];
    assign funct3_3 = ~funct3[2] & funct3[1] & funct3[0];
    assign funct3_4 = funct3[2] & ~funct3[1] & ~funct3[0];
    assign funct3_5 = funct3[2] & ~funct3[1] & funct3[0];
    assign funct3_6 = funct3[2] & funct3[1] & ~funct3[0];
    assign funct3_7 = funct3[2] & funct3[1] & funct3[0];
    assign rs2_0 = ~inst[24] & ~inst[23] & ~inst[22] & ~inst[21] & ~inst[20];
    assign rs2_1 = ~inst[24] & ~inst[23] & ~inst[22] & ~inst[21] & inst[20];
    assign rs2_2 = ~inst[24] & ~inst[23] & ~inst[22] & inst[21] & ~inst[20];
    assign rs2_5 = ~inst[24] & ~inst[23] & inst[22] & ~inst[21] & inst[20];

    logic lui, auipc, jal, jalr, branch, load, store, miscmem, opimm, opreg, opsystem, unknown;
    assign lui = ~op[4] & op[3] & op[2] & ~op[1] & op[0] & inst[1] & inst[0];
    assign auipc = ~op[4] & ~op[3] & op[2] & ~op[1] & op[0] & inst[1] & inst[0];
    assign jal = op[4] & op[3] & ~op[2] & op[1] & op[0] & inst[1] & inst[0];
    assign jalr = op[4] & op[3] & ~op[2] & ~op[1] & op[0] & inst[1] & inst[0];
    assign branch = op[4] & op[3] & ~op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign load = ~op[4] & ~op[3] & ~op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign store = ~op[4] & op[3] & ~op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign miscmem = ~op[4] & ~op[3] & ~op[2] & op[1] & op[0] & inst[1] & inst[0];
    assign opimm = ~op[4] & ~op[3] & op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign opreg = ~op[4] & op[3] & op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign opsystem = op[4] & op[3] & op[2] & ~op[0] & ~op[0] & inst[1] & inst[0];

`ifdef RVC
    logic `N(16) cinst;
    logic `N(3) crd, crs1, crs2, cfunct3;
    logic `N(5) full_rd, full_rs2;
    logic `N(6) cfunct6;
    assign cinst = inst[15: 0];
    assign crd = cinst[4: 2];
    assign full_rd = cinst[11: 7];
    assign full_rs2 = cinst[6: 2];
    assign crs2 = cinst[4: 2];
    assign crs1 = cinst[9: 7];
    assign cfunct3 = cinst[15: 13];
    assign cfunct6 = cinst[15: 10];

    logic `N(6) cadd_imm, cadd16_imm;
    logic `N(11) cjal_imm;
    logic `N(8) cbranch_imm;
    logic `N(5) cmem_imm;
    logic `N(8) caddi4_imm;
    logic `N(6) clwsp_imm, cswsp_imm;
    assign cadd_imm = {cinst[12], cinst[6: 2]};
    assign cadd16_imm = {cinst[12], cinst[4: 3], cinst[5], cinst[2], cinst[6]};
    assign caddi4_imm = {cinst[10: 7], cinst[12: 11], cinst[5], cinst[6]};
    assign cjal_imm = {cinst[12], cinst[8], cinst[10: 9], cinst[6], cinst[7], cinst[2], cinst[11], cinst[5: 3]};
    assign cbranch_imm = {cinst[12], cinst[6: 5], cinst[2], cinst[11: 10], cinst[4: 3]};
    assign cmem_imm = {cinst[5], cinst[12: 10], cinst[6]};
    assign clwsp_imm = {cinst[3: 2], cinst[12], cinst[6: 4]};
    assign cswsp_imm = {cinst[8: 7], cinst[12: 9]};


    logic cfunct3_0, cfunct3_1, cfunct3_2, cfunct3_3, cfunct3_4, cfunct3_5, cfunct3_6, cfunct3_7;
    logic sign0, sign1, sign2;
    logic full_rd_2, full_rd_0;
    logic full_rs2_0;
    logic cfunct6_35;
    logic cadd_imm_0;
    assign cfunct3_0 = ~cfunct3[2] & ~cfunct3[1] & ~cfunct3[0];
    assign cfunct3_1 = ~cfunct3[2] & ~cfunct3[1] & cfunct3[0];
    assign cfunct3_2 = ~cfunct3[2] & cfunct3[1] & ~cfunct3[0];
    assign cfunct3_3 = ~cfunct3[2] & cfunct3[1] & cfunct3[0];
    assign cfunct3_4 = cfunct3[2] & ~cfunct3[1] & ~cfunct3[0];
    assign cfunct3_5 = cfunct3[2] & ~cfunct3[1] & cfunct3[0];
    assign cfunct3_6 = cfunct3[2] & cfunct3[1] & ~cfunct3[0];
    assign cfunct3_7 = cfunct3[2] & cfunct3[1] & cfunct3[0];
    assign sign0 = ~cinst[1] & ~cinst[0];
    assign sign1 = ~cinst[1] & cinst[0];
    assign sign2 = cinst[1] & ~cinst[0];
    assign full_rd_0 = ~full_rd[4] & ~full_rd[3] & ~full_rd[2] & ~full_rd[1] & ~full_rd[0];
    assign full_rd_2 = ~full_rd[4] & ~full_rd[3] & ~full_rd[2] & full_rd[1] & ~full_rd[0];
    assign full_rs2_0 = ~full_rs2[4] & ~full_rs2[3] & ~full_rs2[2] & ~full_rs2[1] & ~full_rs2[0];
    assign cfunct6_35 = cfunct6[5] & ~cfunct6[4] & ~cfunct6[3] & ~cfunct6[2] & cfunct6[1] & cfunct6[0];
    assign cadd_imm_0 = ~cadd_imm[5] & ~cadd_imm[4] & ~cadd_imm[3] & ~cadd_imm[2] & ~cadd_imm[1] & ~cadd_imm[0];

    logic clw, csw, caddi, cjal, cli, caddisp, clui, csrli, csrai, candi, cslli;
    logic csub, cxor, cor, cand, cj, cbeqz, cbnez, clwsp, cjr, cmv, cebreak;
    logic cjalr, cadd, cswsp, caddi4spn;
    logic cvalid;
    assign caddi4spn = sign0 & cfunct3_0;
    assign clw = sign0 & cfunct3_2;
    assign csw = sign0 & cfunct3_6;
    assign caddi = sign1 & cfunct3_0; // caddi and cnop
    assign cjal = sign1 & cfunct3_1;
    assign cli = sign1 & cfunct3_2;
    assign caddisp = sign1 & cfunct3_3 & full_rd_2 & ~cadd_imm_0;
    assign clui = sign1 & cfunct3_3 & ~full_rd_2 & ~cadd_imm_0;
    assign csrli = sign1 & cfunct3_4 & ~cinst[11] & ~cinst[10];
    assign csrai = sign1 & cfunct3_4 & ~cinst[11] & cinst[10];
    assign candi = sign1 & cfunct3_4 & cinst[11] & ~cinst[10];
    assign csub = sign1 & cfunct6_35 & ~cinst[6] & ~cinst[5];
    assign cxor = sign1 & cfunct6_35 & ~cinst[6] & cinst[5];
    assign cor = sign1 & cfunct6_35 & cinst[6] & ~cinst[5];
    assign cand = sign1 & cfunct6_35 & cinst[6] & cinst[5];
    assign cj = sign1 & cfunct3_5;
    assign cbeqz = sign1 & cfunct3_6;
    assign cbnez = sign1 & cfunct3_7;
    assign cslli = sign2 & cfunct3_0;
    assign clwsp = sign2 & cfunct3_2 & ~full_rd_0;
    assign cjr = sign2 & cfunct3_4 & ~cinst[12] & ~full_rd_0 & full_rs2_0;
    assign cmv = sign2 & cfunct3_4 & ~cinst[12] & ~full_rd_0 & ~full_rs2_0;
    assign cebreak = sign2 & cfunct3_4 & cinst[12] & full_rd_0 & full_rs2_0;
    assign cjalr = sign2 & cfunct3_4 & cinst[12] & ~full_rd_0 & full_rs2_0;
    assign cadd = sign2 & cfunct3_4 & cinst[12] & ~full_rs2_0;
    assign cswsp = sign2 & cfunct3_6;
    
    logic `N(5) cexp_rs1, cexp_rd;
    assign cexp_rs1 = {2'b01, crs1};
    assign cexp_rd = {2'b01, crd};

    logic `N(5) crs1_o, crs2_o, crd_o;
    logic `N(`DEC_IMM_WIDTH) cimm;

`ifdef RVF
    logic cflw, cfsw, cflwsp, cfswsp;
    assign cflw = sign0 & cfunct3_3;
    assign cfsw = sign0 & cfunct3_7;
    assign cflwsp = sign2 & cfunct3_3;
    assign cfswsp = sign2 & cfunct3_7;
    assign crs1_o = {5{clw | csw | csrli | csrai | candi | csub | cxor | cor | cand | 
                    cbeqz | cbnez | cflw | cfsw}} & cexp_rs1 |
                    {5{caddi | cslli | cjr | cjalr | cadd}} & full_rd |
                    {5{caddi4spn | caddisp | clwsp | cswsp | cflwsp | cfswsp}} & 5'h2;

    assign crs2_o = {5{csw | csub | cxor | cor | cand | cfsw}} & cexp_rd |
                    {5{cmv | cadd | cswsp | cfswsp}} & full_rs2;

    assign crd_o = {5{caddi4spn | clw| cflw}} & cexp_rd |
                   {5{csrli | csrai | candi | csub | cxor | cor | cand}} & cexp_rs1 |
                   {5{caddi | cli | clui | cslli | clwsp | cmv | cadd | cflwsp}} & full_rd |
                   {5{cjal | cjalr}} & 5'h1 |
                   {5{caddisp}} & 5'h2;

    assign cimm = {2'b0, caddi4_imm & {8{caddi4spn}}, 10'b0} |
                  {5'b0, cmem_imm & {5{clw | csw | cflw | cfsw}}, 10'b0} |
                  {{{6{cadd_imm[5]}}, cadd_imm} & {12{caddi | cli | csrli | csrai | candi | cslli}}, 8'b0} |
                  {{{2{cadd16_imm[5]}}, cadd16_imm} & {8{caddisp}}, 12'b0} |
                  {{14{cadd_imm[5]}}, cadd_imm} & {20{clui}} |
                  {{{11{cbranch_imm[7]}}, cbranch_imm} & {19{cbeqz | cbnez}}, 1'b0} |
                  {2'b0, clwsp_imm & {8{clwsp | cflwsp}}, 10'b0} |
                  {2'b0, cswsp_imm & {8{cswsp | cfswsp}}, 10'b0};
`else
    assign crs1_o = {5{clw | csw | csrli | csrai | candi | csub | cxor | cor | cand | 
                    cbeqz | cbnez}} & cexp_rs1 |
                    {5{caddi | cslli | cjr | cjalr | cadd}} & full_rd |
                    {5{caddi4spn | caddisp | clwsp | cswsp}} & 5'h2;

    assign crs2_o = {5{csw | csub | cxor | cor | cand}} & cexp_rs2 |
                    {5{cmv | cadd | cswsp}} & full_rs2;

    assign crd_o = {5{caddi4spn | clw}} & cexp_rd |
                   {5{csrli | csrai | candi | csub | cxor | cor | cand}} & cexp_rs1 |
                   {5{caddi | cli | clui | cslli | clwsp | cmv | cadd}} & full_rd |
                   {5{cjal | cjalr}} & 5'h1 |
                   {5{caddisp}} & 5'h2;

    assign cimm = {2'b0, caddi4_imm & {8{caddi4spn}}, 10'b0} |
                  {5'b0, mem_imm & {5{clw | csw}}, 10'b0} |
                  {{{6{cadd_imm[5]}}, cadd_imm} & {12{caddi | cli | csrli | csrai | candi | cslli}}, 8'b0} |
                  {{{2{cadd16_imm[5]}}, cadd16_imm} & {8{caddisp}}, 12'b0} |
                  {{14{cadd_imm[5]}}, cadd_imm} & {20{clui}} |
                  {{12{cbranch_imm[7]}}, cbranch_imm} & {20{cbeqz | cbnez}} |
                  {2'b0, clwsp_imm & {8{clwsp}}, 10'b0} |
                  {2'b0, cswsp_imm & {8{cswsp}}, 10'b0};
`endif
    assign cvalid = caddi4spn | clw | csw | caddi | cjal | cli | caddisp | clui |
                    csrli | csrai | candi | csub | cxor | cor | cand | cj |
                    cbeqz | cbnez | cslli | clwsp | cjr | cmv | cebreak |
                    cjalr | cadd | cswsp
`ifdef RVF
                    | cflw | cflwsp | cfsw | cfswsp
`endif
                    ;
    assign info.rvc = ~(inst[1] & inst[0]);

`endif

    logic beq, bne, blt, bge, bltu, bgeu;
    assign beq = branch & funct3_0;
    assign bne = branch & funct3_1;
    assign blt = branch & funct3_4;
    assign bge = branch & funct3_5;
    assign bltu = branch & funct3_6;
    assign bgeu = branch & funct3_7;

`ifdef RVC
    assign info.branchop[2] = jal | jalr | cj | cjal | cjr | cjalr;
    assign info.branchop[1] = blt | bge | bgeu | bltu;
    assign info.branchop[0] = jalr | bne | bge | bgeu | cjr | cjalr | cbnez;
`else
    assign info.branchop[2] = jal | jalr;
    assign info.branchop[1] = blt | bge | bgeu | bltu;
    assign info.branchop[0] = jalr | bne | bge | bgeu;
`endif

    logic lb, lh, lw, lbu, lhu, sb, sh, sw;
    assign lb = load & funct3_0;
    assign lh = load & funct3_1;
    assign lw = load & funct3_2;
    assign lbu = load & funct3_4;
    assign lhu = load & funct3_5;
    assign sb = store & funct3_0;
    assign sh = store & funct3_1;
    assign sw = store & funct3_2;



    logic addi, slti, sltiu, xori, ori, andi, slli, srli, srai;
    assign addi = opimm & funct3_0;
    assign slti = opimm & funct3_2;
    assign sltiu = opimm & funct3_3;
    assign xori = opimm & funct3_4;
    assign ori = opimm & funct3_6;
    assign andi = opimm & funct3_7;
    assign slli = opimm & funct3_1 & funct7_0;
    assign srli = opimm & funct3_5 & funct7_0;
    assign srai = opimm & funct3_5 & funct7_32;

    logic add, sub, sll, slt, sltu, _xor, srl, sra, _or, _and;
    assign add = opreg & funct3_0 & funct7_0;
    assign sub = opreg & funct3_0 & funct7_32;
    assign sll = opreg & funct3_1 & funct7_0;
    assign slt = opreg & funct3_2 & funct7_0;
    assign sltu = opreg & funct3_3 & funct7_0;
    assign _xor = opreg & funct3_4 & funct7_0;
    assign srl = opreg & funct3_5 & funct7_0;
    assign sra = opreg & funct3_5 & funct7_32;
    assign _or = opreg & funct3_6 & funct7_0;
    assign _and = opreg & funct3_7 & funct7_0;

`ifdef DIFFTEST
    logic custom0;
    logic sim_trap;
    assign custom0 = ~op[4] & ~op[3] & ~op[2] & op[1] & ~op[0] & inst[1] & inst[0];
    assign sim_trap = custom0 & funct3_0;
    assign info.sim_trap = sim_trap;
`endif

    // TODO: impl wfi, current treat as nop
    logic fence, sfence_vma, wfi;
    assign fence = miscmem & funct3_0;
    assign sfence_vma = opsystem & ~funct7[6] & ~funct7[5] & ~funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & funct7[0];
    assign wfi = opsystem & funct3_0 & ~funct7[6] & ~funct7[5] & ~funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0] & rs2_5;
`ifdef EXT_FENCEI
    logic fencei;
    assign fencei = miscmem & funct3_1;
`endif

    logic ecall, ebreak, mret, sret;
    assign ecall = opsystem & funct3_0 & funct7_0 & rs2_0;
    assign ebreak = opsystem & funct3_0 & funct7_0 & rs2_1;
    assign mret = opsystem & funct3_0 & ~funct7[6] & ~funct7[5] & funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0] & rs2_2;
    assign sret = opsystem & funct3_0 & ~funct7[6] & ~funct7[5] & ~funct7[4] & funct7[3] & ~funct7[2] & ~funct7[1] & ~funct7[0] & rs2_2;

`ifdef RVC
    assign ebreak_all = ebreak | cebreak;
`else
    assign ebreak_all = ebreak;
`endif

    logic csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci, csr;
    assign csr = csrrw | csrrs | csrrc | csrrwi | csrrsi | csrrci;
    assign csrrw = opsystem & funct3_1;
    assign csrrs = opsystem & funct3_2;
    assign csrrc = opsystem & funct3_3;
    assign csrrwi = opsystem & funct3_5;
    assign csrrsi = opsystem & funct3_6;
    assign csrrci = opsystem & funct3_7;

`ifdef RVM
    logic mult, mul, mulh, mulhsu, mulhu, div, divu, rem ,remu;
    assign mult = opreg & funct7_1;
    assign mul = mult & funct3_0;
    assign mulh = mult & funct3_1;
    assign mulhsu = mult & funct3_2;
    assign mulhu = mult & funct3_3;
    assign div = mult & funct3_4;
    assign divu = mult & funct3_5;
    assign rem = mult & funct3_6;
    assign remu = mult & funct3_7;
    assign info.multop = funct3;
`endif

`ifdef RVA
    logic lr, sc, amoswap, amoadd, amoxor, amoand, amoor, amomin, amomax, amominu, amomaxu, amo;
    assign amo = ~op[4] & op[3] & ~op[2] & op[1] & op[0] & inst[1] & inst[0];
    assign lr = amo & funct3_2 & ~inst[31] & ~inst[30] & ~inst[29] & inst[28] & ~inst[27];
    assign sc = amo & funct3_2 & ~inst[31] & ~inst[30] & ~inst[29] & inst[28] & inst[27];
    assign amoswap = amo & funct3_2 & ~inst[31] & ~inst[30] & ~inst[29] & ~inst[28] & inst[27];
    assign amoadd = amo & funct3_2 & ~inst[31] & ~inst[30] & ~inst[29] & ~inst[28] & ~inst[27];
    assign amoxor = amo & funct3_2 & ~inst[31] & ~inst[30] & inst[29] & ~inst[28] & ~inst[27];
    assign amoand = amo & funct3_2 & ~inst[31] & inst[30] & inst[29] & ~inst[28] & ~inst[27];
    assign amoor = amo & funct3_2 & ~inst[31] & inst[30] & ~inst[29] & ~inst[28] & ~inst[27];
    assign amomin = amo & funct3_2 & inst[31] & ~inst[30] & ~inst[29] & ~inst[28] & ~inst[27];
    assign amomax = amo & funct3_2 & inst[31] & ~inst[30] & inst[29] & ~inst[28] & ~inst[27];
    assign amominu = amo & funct3_2 & inst[31] & inst[30] & ~inst[29] & ~inst[28] & ~inst[27];
    assign amomaxu = amo & funct3_2 & inst[31] & inst[30] & inst[29] & ~inst[28] & ~inst[27];

    assign info.amoop[3] = amomin | amomax | amominu | amomaxu;
    assign info.amoop[2] = amoadd | amoxor | amoand | amomaxu;
    assign info.amoop[1] = amoswap | amoxor | amoor | amominu;
    assign info.amoop[0] = sc | amoand | amoor | amomax;
`endif

`ifdef RVF
    logic flw, fsw, fmadd, fmsub, fnmsub, fnmadd, fadd, fsub, fmul, fdiv,
    fsqrt, fsgnj, fsgnjn, fsgnjx, fmin, fmax, fcvt, fcvtu, fmvx, feq, flt,
    fle, fclass, fcvts, fcvtsu, fmv;
    logic loadfp, storefp, fp, madd, msub, nmsub, nmadd;
    assign loadfp = ~op[4] & ~op[3] & ~op[2] & ~op[1] & op[0] & inst[1] & inst[0];
    assign storefp = ~op[4] & op[3] & ~op[2] & ~op[1] & op[0] & inst[1] & inst[0];
    assign fp = op[4] & ~op[3] & op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign madd = op[4] & ~op[3] & ~op[2] & ~op[1] & ~op[0] & inst[1] & inst[0];
    assign msub = op[4] & ~op[3] & ~op[2] & ~op[1] & op[0] & inst[1] & inst[0];
    assign nmadd = op[4] & ~op[3] & ~op[2] & op[1] & op[0] & inst[1] & inst[0];
    assign nmsub = op[4] & ~op[3] & ~op[2] & op[1] & ~op[0] & inst[1] & inst[0];
    
    assign flw = loadfp & funct3_2;
    assign fsw = storefp & funct3_2;
    assign fmadd = madd;
    assign fmsub = msub;
    assign fnmadd = nmadd;
    assign fnmsub = nmsub;
    assign fadd = fp & funct7_0;
    assign fsub = fp & funct7_4;
    assign fmul = fp & funct7_8;
    assign fdiv = fp & funct7_12;
    assign fsqrt = fp & funct7_44;
    assign fsgnj = fp & funct7_16 & funct3_0;
    assign fsgnjn = fp & funct7_16 & funct3_1;
    assign fsgnjx = fp & funct7_16 & funct3_2;
    assign fmin = fp & funct7_20 & funct3_0;
    assign fmax = fp & funct7_20 & funct3_1;
    assign fcvt = fp & funct7_96 & rs2_0;
    assign fcvtu = fp & funct7_96 & rs2_1;
    assign fmvx = fp & funct7_112 & funct3_0;
    assign feq = fp & funct7_80 & funct3_2;
    assign flt = fp & funct7_80 & funct3_1;
    assign fle = fp & funct7_80 & funct3_0;
    assign fclass = fp & funct7_112 & funct3_1;
    assign fcvts = fp & funct7_104 & rs2_0;
    assign fcvtsu = fp & funct7_104 & rs2_1;
    assign fmv = fp & funct7_120 & funct3_0;

    assign info.rm = funct3;
    assign info.flt_mem = loadfp | storefp
`ifdef RVC
    | cflw | cflwsp | cfsw | cfswsp
`endif
    ;
    assign info.flt_we = loadfp | fmadd | fmsub | fnmadd | fnmsub | fadd | fsub | fmul | fdiv |
                        fsqrt | fsgnj | fsgnjn | fsgnjx | fmin | fmax | fcvts | fcvtsu | fmv
`ifdef RVC
    | cflw | cflwsp
`endif
                        ;
    assign info.frs1_sel = fmadd | fmsub | fnmadd | fnmsub | fadd | fsub | fmul | fdiv |
                            fsqrt | fsgnj | fsgnjn | fsgnjx | fmin | fmax | fcvt | fcvtu |
                            fmvx | feq | flt | fle | fclass;
    assign info.frs2_sel = storefp | fmadd | fmsub | fnmadd | fnmsub | fadd | fsub | fmul | fdiv |
                           fsgnj | fsgnjn | fsgnjx | fmin | fmax | feq | flt | fle
`ifdef RVC
    | cfsw | cfswsp
`endif
                           ;
    assign info.fflag_we = fmadd | fmsub | fnmadd | fnmsub | fadd | fsub | fmul | fdiv |
                           fsqrt | fmin | fmax | fcvt | fcvtu | feq | flt | fle | fcvts | fcvtsu;
    assign info.fltop[4] = fmvx | feq | flt | fle | fclass | fcvts | fcvtsu | fmv;
    assign info.fltop[3] = fsqrt | fsgnj | fsgnjn | fsgnjx | fmin | fmax | fcvt | fcvtu | fclass | fcvts | fcvtsu;
    assign info.fltop[2] = fmadd | fmsub | fnmsub | fnmadd | fmin | fmax | fcvt | fcvtu | fle | fcvts | fcvtsu;
    assign info.fltop[1] = fmul | fdiv | fnmsub | fnmadd | fsgnjn | fsgnjx | fcvt | fcvtu | flt;
    assign info.fltop[0] = fsub | fdiv | fmsub | fnmadd | fsgnj | fsgnjx | fmax | feq ;
`endif

    assign unknown = ~beq & ~bne & ~blt & ~bge & ~bltu & ~bgeu & ~jal & ~jalr &
                     ~lb & ~lh & ~lw & ~lbu & ~lhu & ~sb & ~sh & ~sw & ~auipc & ~lui &
                     ~addi & ~slti & ~sltiu & ~xori & ~ori & ~andi & ~slli & ~srli & ~srai & 
                     ~add & ~sub & ~sll & ~slt & ~sltu & ~_xor & ~srl & ~sra & ~_or & ~_and &
                     ~csrrw & ~csrrs & ~csrrc & ~csrrwi & ~csrrsi & ~csrrci & ~ecall & ~ebreak &
                     ~fence & ~mret & ~sret & ~sfence_vma & ~wfi
`ifdef DIFFTEST
                     & ~sim_trap
`endif
`ifdef RVM
                     & ~mult
`endif
`ifdef RVA
                     & ~lr & ~sc & ~amoswap & ~amoadd & ~amoxor & ~amoand & ~amoor & ~amomin
                     & ~amomax & ~amominu & ~amomaxu
`endif
`ifdef RVF
                     & ~flw & ~fsw & ~fmadd & ~fmsub & ~fnmsub & ~fnmadd & ~fadd & ~fsub
                     & ~fmul & ~fdiv & ~fsqrt & ~fsgnj & ~fsgnjn & ~fsgnjx & ~fmin & ~fmax
                     & ~fcvt & ~fcvtu & ~fmvx & ~feq & ~flt & ~fle & ~fclass & ~fcvts
                     & ~fcvtsu & ~fmv
`endif
`ifdef RVC
                     & ~cvalid
`endif
`ifdef EXT_FENCEI
                     & ~fencei
`endif
                     ;

`ifdef RVC
    assign info.intop[4] = 1'b0;
    assign info.intop[3] = slli | srli | srai | sll | srl | sra | auipc | sub | csub | cslli | csrli | csrai;
    assign info.intop[2] = xori | ori | andi | _xor | _or | _and | auipc | sub | csub | cand | cor | candi | cxor;
    assign info.intop[1] = slti | sltiu | slt | sltu | ori | _or | cor | sub | csub;
    assign info.intop[0] = lui | andi | _and | srl | srli | sra | srai | cand | clui | csrli | csrai | candi;
`else
    assign info.intop[4] = 1'b0;
    assign info.intop[3] = slli | srli | srai | sll | srl | sra | auipc | sub;
    assign info.intop[2] = xori | ori | andi | _xor | _or | _and | auipc | sub;
    assign info.intop[1] = slti | sltiu | slt | sltu | ori | _or | sub;
    assign info.intop[0] = lui | andi | _and | srl | srli | sra | srai;
`endif

`ifdef RVC
`ifdef RVF
    assign info.memop[3] = store | fsw | csw | cfsw | cswsp | cfswsp;
    assign info.memop[2] = sw | fsw | csw | cfsw | cswsp | cfswsp;
    assign info.memop[1] = lw | flw | clw | clwsp | cflw | cflwsp;
    assign info.memop[0] = lh | lhu | sh;
`else
    assign info.memop[3] = store | csw | cswsp;
    assign info.memop[2] = sw | csw | cswsp;
    assign info.memop[1] = lw | clw | clwsp;
    assign info.memop[0] = lh | lhu | sh;
`endif
`else
`ifdef RVF
    assign info.memop[3] = store | fsw;
    assign info.memop[2] = sw | fsw;
    assign info.memop[1] = lw | flw;
    assign info.memop[0] = lh | lhu | sh;
`else
    assign info.memop[3] = store;
    assign info.memop[2] = sw;
    assign info.memop[1] = lw;
    assign info.memop[0] = lh | lhu | sh;
`endif
`endif


    assign info.csrop[3] = sfence_vma | fence
`ifdef EXT_FENCEI
    | fencei
`endif
    ;
    assign info.csrop[2] = csrrwi | csrrsi | csrrci | fence;
    assign info.csrop[1] = csrrs | csrrc | csrrsi | csrrci;
    assign info.csrop[0] = csrrw | csrrc | csrrwi | csrrci
`ifdef EXT_FENCEI
    | fencei
`endif
;

    assign info.uext = sltu | sltiu | lbu | lhu | bltu | bgeu | srl | srli
`ifdef RVF
                    | fcvtu | fcvtsu
`endif
`ifdef RVC
                    | csrli
`endif
    ;
    logic [`DEC_IMM_WIDTH-1: 0] store_imm;
    logic [`DEC_IMM_WIDTH-1: 0] lui_imm;
    logic `N(`DEC_IMM_WIDTH) branch_imm;
    assign branch_imm = {inst[31], inst[7], inst[30: 25], inst[11: 8], 1'b0};
    assign store_imm = {inst[31: 25], inst[11: 7], 8'b0};
    assign lui_imm = inst[31: 12];

    assign info.immv = slli | srai | srli | addi | slti | xori | ori | andi | sltiu
`ifdef RVC
    | cslli | csrai | csrli | caddi | caddi4spn | candi | caddisp | cli
`endif
    ;
    assign info.imm = beq | bne | blt | bge | bgeu | bltu ? branch_imm :
                      store
`ifdef RVF
                      | storefp 
`endif
                                ? store_imm : 
`ifdef RVC
                     ~(inst[1] & inst[0]) ? cimm :
`endif
                                lui_imm;

    assign info.intv = (lui | opimm |
                       add | sub | sll | slt | sltu | _xor | srl | sra | _or | _and |
                       auipc
`ifdef DIFFTEST
    | sim_trap
`endif
`ifdef RVC
    | caddi | cli | clui | csrli | csrai | candi | csub | cxor | cor | cand 
    | cslli | cadd | cmv | caddisp | caddi4spn
`endif
    ) & ~ipf & ~iam;
    assign info.branchv = (branch | jal | jalr
`ifdef RVC
    | cj | cjal | cbeqz | cbnez | cjr | cjalr
`endif
    ) & ~ipf & ~iam;
    assign info.memv = (load | store
`ifdef RVF
                        | loadfp | storefp
`endif
`ifdef RVC
            | clw | clwsp | csw | cswsp
`ifdef RVF
            | cflw | cflwsp | cfsw | cfswsp
`endif
`endif
    ) & ~ipf & ~iam;
    assign info.csrv = csr | ecall | ebreak_all | mret | sret | unknown | iam | sfence_vma | ipf | fence | wfi
`ifdef EXT_FENCEI
    | fencei
`endif
    ;
`ifdef RVM
    assign info.multv = mult & ~ipf & ~iam;
`endif
`ifdef RVA
    assign info.amov = amo & ~ipf & ~iam;
`endif
`ifdef RVF
    assign info.fmiscv = (fsgnj | fsgnjn | fsgnjx | fmvx | feq | flt | fle | fclass |
                           fcvt | fcvtu | fcvts | fcvtsu | fmv | fmin | fmax) & ~ipf & ~iam;
    assign info.fcalv = (fmadd | fnmadd | fmsub | fnmsub | fadd | fsub | fmul | fdiv |
                         fsqrt) & ~ipf & ~iam;
`endif


    assign info.rs1 = {5{jalr | branch | load | store | opimm | opreg | csrrs | csrrc | csrrw | sfence_vma
`ifdef RVA
    | amo
`endif
`ifdef RVF
    | fp | madd | msub | nmsub | nmadd | flw | fsw
`endif
    }} & inst[19: 15]
`ifdef RVC
    | {5{~(inst[1] & inst[0])}} & crs1_o
`endif
    ;


    assign info.rs2 = {5{branch | store | opreg | sfence_vma
`ifdef RVA
    | amo
`endif
`ifdef RVF
    |((fp | madd | msub | nmsub | nmadd | fsw) & ~fcvtsu & ~fcvtu)
`endif
    }} & inst[24: 20]
`ifdef RVC
    | {5{~(inst[1] & inst[0])}} & crs2_o
`endif
    ;

`ifdef RVF
    assign info.rs3 = {5{fmadd | fnmadd | fmsub | fnmsub}} & inst[31: 27];
`endif

    
    assign rd = {5{lui | auipc | jalr | jal | load | opimm | opreg | csr
`ifdef RVA
    | amo
`endif
`ifdef RVF
    | fp | madd | msub | nmsub | nmadd | flw
`endif
    }} & inst[11: 7]
`ifdef RVC
    | {5{~(inst[1] & inst[0])}} & crd_o
`endif
    ;


    assign info.rd = rd;
    assign info.we = rd != 0;
    // exception from frontend and illegal inst
    // all of these exception are sent to csr issue queue due to it's simple structure
    assign info.exccode = ipf ? `EXC_IPF :
                          iam ? `EXC_IAM :
                          unknown ? `EXC_II :
                          ecall | ebreak_all | mret | sret ?
                               {`EXC_WIDTH{ecall}} & `EXC_EC | 
                               {`EXC_WIDTH{ebreak_all}} & `EXC_BP |
                               {`EXC_WIDTH{mret}} & `EXC_MRET |
                               {`EXC_WIDTH{sret}} & `EXC_SRET : `EXC_NONE;

endmodule