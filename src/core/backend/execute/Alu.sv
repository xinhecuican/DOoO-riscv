`include "../../../defines/defines.svh"

module ALU(
    input logic clk,
    input logic rst,
    IssueAluIO.alu io,
    input BackendCtrl backendCtrl,
    input logic valid,
    output WBData wbData,
    output BranchUnitRes branchRes
);
    logic `N(`XLEN) result, branchResult;
    ALUModel model(
        .immv(io.bundle.immv),
        .uext(io.bundle.uext),
`ifdef RV64I
        .word(io.bundle.word),
`ifdef RVB
        .srcword(io.bundle.srcword),
`endif
`endif
        .imm(io.bundle.imm),
        .rs1_data(io.rs1_data),
        .rs2_data(io.rs2_data),
        .op(io.bundle.intop),
        .vaddr(io.vaddr),
        .offset(io.bundle.fsqInfo.offset),
        .result(result)
    );
    BranchModel branchModel(
        .immv(io.bundle.immv),
        .uext(io.bundle.uext),
`ifdef RVC
        .rvc(io.bundle.rvc),
`endif
        .imm(io.bundle.imm),
        .rs1_data(io.rs1_data),
        .rs2_data(io.rs2_data),
        .op(io.bundle.branchop),
        .stream(io.stream),
        .vaddr(io.vaddr),
        .offset(io.bundle.fsqInfo.offset),
        .br_type(io.br_type),
        .branchRes(branchRes),
        .result(branchResult)
    );
    assign wbData.en = io.en & valid;
    assign wbData.we = io.status.we;
    assign wbData.robIdx = io.status.robIdx;
    assign wbData.rd = io.status.rd;
    assign wbData.res = io.bundle.intv ? result : branchResult;
    assign wbData.exccode = `EXC_NONE;
    assign wbData.irq_enable = 1;

    assign io.valid = valid;
endmodule

module BranchModel(
    input logic immv,
    input logic uext,
`ifdef RVC
    input logic rvc,
`endif
    input logic `N(`DEC_IMM_WIDTH) imm,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`BRANCHOP_WIDTH) op,
    input FetchStream stream,
    input logic `N(`VADDR_SIZE) vaddr,
    input logic `N(`PREDICTION_WIDTH) offset,
    input BranchType br_type,
    output BranchUnitRes branchRes,
    output logic `N(`XLEN) result
);
    logic `N(`XLEN) s_imm;
    logic `N(`VADDR_SIZE) jalr_imm;
    logic cmp, scmp, cmp_result;
    logic equal;
    logic dir;
    assign cmp = rs1_data < rs2_data;
    assign equal = rs1_data == rs2_data;
    always_comb begin
        case({rs1_data[`XLEN-1], rs2_data[`XLEN-1]})
        2'b00: scmp = cmp;
        2'b01: scmp = 0;
        2'b10: scmp = 1;
        2'b11: scmp = cmp;
        endcase
    end
    assign cmp_result = uext ? cmp : scmp;

    always_comb begin
        case(op)
        `BRANCH_BEQ: begin
            dir = equal;
        end
        `BRANCH_BNE: begin
            dir = ~equal;
        end
        `BRANCH_BLT: begin
            dir = cmp_result;
        end
        `BRANCH_BGE: begin
            dir = ~cmp_result;
        end
        default: dir = 0;
        endcase
    end

    logic `N(`VADDR_SIZE) jalr_target, br_target;
    assign s_imm = {{`XLEN-13{imm[12]}}, imm[12: 1], 1'b0};
    assign jalr_imm = {{`XLEN-12{imm[19]}}, imm[19: 8]};
    `CRITICAL(jalr_target, branchRedirect)
    KSA #(`VADDR_SIZE) ksa_jalr(rs1_data[`VADDR_SIZE-1: 0], jalr_imm, jalr_target);
    assign br_target = vaddr + s_imm;
    assign branchRes.target = op == `BRANCH_JALR ? {jalr_target[`VADDR_SIZE-1: 1], 1'b0} : 
                              dir ? br_target : result;

    logic `N(`VADDR_SIZE) result_addr;
`ifdef RVC
    assign result_addr = vaddr + {~rvc, rvc, 1'b0};
`else
    assign result_addr = vaddr + 4;
`endif
    assign result = {{`XLEN-`VADDR_SIZE{result_addr[`VADDR_SIZE-1]}}, result_addr};

    // predict error
    // cal stream taken offset
    logic streamHit, branchError, indirectError;
    assign streamHit = stream.size == offset;
    assign branchError = streamHit ? stream.taken ^ dir | (stream.taken & (stream.target != br_target)) : dir;
    assign indirectError = ~streamHit | (stream.target != jalr_target);
    assign branchRes.direction = (op == `BRANCH_JALR) | dir;
    assign branchRes.error = op == `BRANCH_JALR ? indirectError :
                        op != `BRANCH_JAL ? branchError : 0;
    assign branchRes.br_type = br_type;
`ifdef RVC
    assign branchRes.rvc = rvc;
`endif
endmodule

module ALUModel(
    input logic immv,
    input logic uext,
`ifdef RV64I
    input logic word,
`ifdef RVB
    input logic srcword,
`endif
`endif
    input logic `N(`DEC_IMM_WIDTH) imm,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`INTOP_WIDTH) op,
    input logic `N(`VADDR_SIZE) vaddr,
    input logic `N(`PREDICTION_WIDTH) offset,
    output logic `N(`XLEN) result
);
    logic `N(`XLEN) lui_imm, s_imm;
    assign lui_imm = {{`XLEN-32{imm[19]}}, imm[19: 0], 12'b0};
    assign s_imm = {{`XLEN-12{imm[19]}}, imm[19: 8]};

    logic `N(`XLEN) data1, data2, cmp_data;
    logic `N(`XLEN) add_result;
    logic cmp, scmp;

    assign data1 = 
`ifdef RV64I
`ifdef RVB
                    srcword ? {32'b0, rs1_data[31: 0]} :
`endif
`endif
                    rs1_data;
    assign data2 = immv ? s_imm : rs2_data;

    assign cmp_data = immv ? s_imm : rs2_data;
    logic `N(`XLEN) add_src1, add_src2;
    logic add_cin, add_cout;
    always_comb begin
        case(op)
        `INT_SUB, `INT_SLT
`ifdef ZBB
        , `INT_MAX, `INT_MIN
`endif
        : begin
            add_src2 = ~data2;
            add_cin = 1'b1;
        end
        default: begin
            add_src2 = data2;
            add_cin = 1'b0;
        end
        endcase
    end
    always_comb begin
        case(op)
`ifdef ZBA
        `INT_SHADD: begin
            case(imm[2:1])
            2'b01: add_src1 = {data1[`XLEN-2:0], 1'b0};
            2'b10: add_src1 = {data1[`XLEN-3:0], 2'b0};
            2'b11: add_src1 = {data1[`XLEN-4:0], 3'b0};
            default: add_src1 = data1;
            endcase
        end
`endif
        default: add_src1 = data1;
        endcase
    end
    assign {add_cout, add_result} = add_src1 + add_src2 + add_cin;
    assign scmp = (data1[`XLEN-1] & ~data2[`XLEN-1])
                    | ((data1[`XLEN-1] ~^ data2[`XLEN-1]) & add_result[`XLEN-1]);
    assign cmp = ~add_cout;


    logic padding;
    logic `N($clog2(`XLEN)) sramt, slamt, shamt;
    logic `N(`XLEN) sr_data, shift_data, sl_data;
`ifdef ZBB
    logic `N($clog2(`XLEN)) shift_remain;
`ifdef RV64I
    assign shift_remain = {~word, word, 5'b0} - {data2[$clog2(`XLEN)-1] & ~word, data2[$clog2(`XLEN)-2: 0]};
`else
    assign shift_remain = 6'b100000 - data2[$clog2(`XLEN)-1:0];
`endif
`endif

    always_comb begin
        padding = rs1_data[`XLEN-1] & ~uext;
        shamt = data2[$clog2(`XLEN)-1: 0];
        shift_data = data1;
`ifdef RV64I
        padding = word ? rs1_data[31] & ~uext : padding;
        shamt = {data2[$clog2(`XLEN)-1] & ~word, data2[$clog2(`XLEN)-2: 0]};
        shift_data = word ? {{32{data1[31] & ~uext}}, data1[31: 0]} : data1;
`endif
        sramt = shamt;
        slamt = shamt;
`ifdef ZBB
        if (op == `INT_ROL) sramt = shift_remain;
        if (op == `INT_ROR) slamt = shift_remain;
`endif
    end
    assign sl_data = data1 << slamt;
    ShiftModel shift_model (padding, shift_data, sramt, sr_data);

    logic `N(`VADDR_SIZE) auipc_addr;
    assign auipc_addr = vaddr + lui_imm;

    logic `N(`XLEN) xor_result;
    assign xor_result = data1 ^ data2;

`ifdef ZBB
    logic `N(`XLEN) clz_data;
    logic `N($clog2(`XLEN)) clz_result, ctz_result;
    logic `N(`XLEN) cz_result;
    logic clz_empty, ctz_empty;
    assign clz_data = {rs1_data[`XLEN-1:32]
    `ifdef RV64I
     & {32{~word}}
     `endif
     , rs1_data[31:0]};
    lzc #(`XLEN, 1) clz_data1(data1, clz_result, clz_empty);
    lzc #(`XLEN) ctz_data1(data1, ctz_result, ctz_empty);
    always_comb begin
        case({imm[8], ctz_empty, clz_empty})
        3'b100: cz_result = ctz_result;
        3'b111, 3'b011: cz_result = 
                                    `ifdef RV64I
                                    word ? 'd32 : 'd64
                                    `else
                                    'd32
                                    `endif
                                    ;
        default: cz_result = {{`XLEN-$clog2(`XLEN){1'b0}}, (clz_result
                            `ifdef RV64I
                            - {word, 5'b0}
                            `endif
                            )};
        endcase
    end

    logic `N(`XLEN) cpop_result;
    logic `ARRAY(16, 3) add_rom;
    logic `ARRAY(`XLEN/4, 3) cpop_add_part;

    AdderROM #(4) cpop_adder_rom(add_rom);
generate
    for(genvar i=0; i<`XLEN; i+=4)begin
        assign cpop_add_part[i/4] = add_rom[rs1_data[i +: 4]];
    end
endgenerate
`ifdef RV64I
    logic `N(6) cpop_add_low, cpop_add_high;
    logic `N(7) cpop_add_result;
    ParallelAdder #(3, 8) parallel_adder_low (cpop_add_part[7:0], cpop_add_low);
    ParallelAdder #(3, 8) parallel_adder_high (cpop_add_part[15:8], cpop_add_high);
    assign cpop_add_result = cpop_add_low + cpop_add_high;
    assign cpop_result = word ? {57'b0, cpop_add_low} : {57'b0, cpop_add_result};
`else
    ParallelAdder #(3, 8) parallel_cpop_adder (cpop_add_part, cpop_result[5:0]);
    assign cpop_result[63:6] = 58'b0;
`endif

    logic `N(`XLEN) ro_result;

    always_comb begin
        ro_result = sl_data | sr_data;
`ifdef RV64I
        if(word) ro_result = {{32{ro_result[31]}}, ro_result[31:0]};
`endif
    end

    logic `N(`XLEN) orc_result;
generate
    for(genvar i=0; i<`XLEN; i+=8)begin
        assign orc_result[i +: 8] = {8{|rs1_data[i +: 8]}};
    end
endgenerate

    logic `N(`XLEN) rev8_result;
generate
    for(genvar i=0; i<`XLEN; i+=8)begin
        assign rev8_result[i +: 8] = rs1_data[`XLEN-1-i -: 8];
    end
endgenerate

`endif

`ifdef ZBS
    logic `N(`XLEN) index_dec;
    Decoder #(`XLEN) decoder_index (data2[$clog2(`XLEN)-1:0], index_dec);
`endif

    always_comb begin
        case(op)
        `INT_ADD, `INT_SUB, `INT_SHADD: begin
`ifdef RV64I
            result = word ? {{32{add_result[31]}}, add_result[31: 0]} : add_result;
`else
            result = add_result;
`endif
        end
        `INT_LUI: result = lui_imm;
        `INT_SLT: begin
            // A   B   s u
            // 001 111 0 1
            // 010 001 1 1
            // 100 111 1 0
            // 101 110 0 1
            // 100 011 1 0
            if(uext)begin
                result = cmp;
            end
            else begin
                result = scmp;
            end
        end
        `INT_OR: result = data1 | data2;
        `INT_XOR:  result = xor_result;
        `INT_AND: result = data1 & data2;
        `INT_SL: begin
`ifdef RV64I
            result = word ? {{32{sl_data[31]}}, sl_data[31: 0]} : sl_data;
`else
            result = sl_data;
`endif
        end
        `INT_SR: begin
`ifdef RV64I
            result = word ? {{32{sr_data[31]}}, sr_data[31: 0]} : sr_data;
`else
            result = sr_data;
`endif
        end
        `INT_AUIPC: result = {{`XLEN-`VADDR_SIZE{auipc_addr[`VADDR_SIZE-1]}}, auipc_addr};
`ifdef ZBB
        `INT_ORN: result = rs1_data | (~rs2_data);
        `INT_ANDN: result = rs1_data & (~rs2_data);
        `INT_XNOR: result = ~xor_result;
        `INT_ROL, `INT_ROR: result = ro_result;
        `INT_ORC: result = orc_result;
        `INT_REV8: result = rev8_result;
        `INT_CLZ: result = cz_result;
        `INT_CPOP: result = cpop_result;
        `INT_MAX: begin
            if (uext) begin
                result = cmp ? rs2_data : rs1_data;
            end
            else begin
                result = scmp ? rs2_data : rs1_data;
            end
        end
        `INT_MIN: begin
            if (uext) begin
                result = cmp ? rs1_data : rs2_data;
            end
            else begin
                result = scmp ? rs1_data : rs2_data;
            end
        end
        `INT_SEXT: begin
            if (~imm[8]) result = {{`XLEN-8{rs1_data[7]}}, rs1_data[7:0]};
            else result = {{`XLEN-16{rs1_data[15]}}, rs1_data[15:0]};
        end
        `INT_ZEXT: begin
            result = {{`XLEN-16{1'b0}}, rs1_data[15:0]};
        end
`endif
`ifdef ZBS
        `INT_BCLR: result = rs1_data & ~index_dec;
        `INT_BEXT: result = sr_data[0];
        `INT_BINV: result = rs1_data ^ index_dec;
        `INT_BSET: result = rs1_data | index_dec;
`endif
        default: result = 0;
        endcase
    end
endmodule

module ShiftModel(
    input logic padding,
    input logic `N(`XLEN) data,
    input logic `N($clog2(`XLEN)) shift,
    output logic `N(`XLEN) data_o
);
`define SHIFT_DEFINE(num) \
        num: data_o = {{num{padding}}, data[`XLEN-1: num]};\

    always_comb begin
        case(shift)
        0: data_o = data;
        `SHIFT_DEFINE(1)
        `SHIFT_DEFINE(2)
        `SHIFT_DEFINE(3)
        `SHIFT_DEFINE(4)
        `SHIFT_DEFINE(5)
        `SHIFT_DEFINE(6)
        `SHIFT_DEFINE(7)
        `SHIFT_DEFINE(8)
        `SHIFT_DEFINE(9)
        `SHIFT_DEFINE(10)
        `SHIFT_DEFINE(11)
        `SHIFT_DEFINE(12)
        `SHIFT_DEFINE(13)
        `SHIFT_DEFINE(14)
        `SHIFT_DEFINE(15)
        `SHIFT_DEFINE(16)
        `SHIFT_DEFINE(17)
        `SHIFT_DEFINE(18)
        `SHIFT_DEFINE(19)
        `SHIFT_DEFINE(20)
        `SHIFT_DEFINE(21)
        `SHIFT_DEFINE(22)
        `SHIFT_DEFINE(23)
        `SHIFT_DEFINE(24)
        `SHIFT_DEFINE(25)
        `SHIFT_DEFINE(26)
        `SHIFT_DEFINE(27)
        `SHIFT_DEFINE(28)
        `SHIFT_DEFINE(29)
        `SHIFT_DEFINE(30)
        `SHIFT_DEFINE(31)
`ifdef RV64I
        `SHIFT_DEFINE(32)
        `SHIFT_DEFINE(33)
        `SHIFT_DEFINE(34)
        `SHIFT_DEFINE(35)
        `SHIFT_DEFINE(36)
        `SHIFT_DEFINE(37)
        `SHIFT_DEFINE(38)
        `SHIFT_DEFINE(39)
        `SHIFT_DEFINE(40)
        `SHIFT_DEFINE(41)
        `SHIFT_DEFINE(42)
        `SHIFT_DEFINE(43)
        `SHIFT_DEFINE(44)
        `SHIFT_DEFINE(45)
        `SHIFT_DEFINE(46)
        `SHIFT_DEFINE(47)
        `SHIFT_DEFINE(48)
        `SHIFT_DEFINE(49)
        `SHIFT_DEFINE(50)
        `SHIFT_DEFINE(51)
        `SHIFT_DEFINE(52)
        `SHIFT_DEFINE(53)
        `SHIFT_DEFINE(54)
        `SHIFT_DEFINE(55)
        `SHIFT_DEFINE(56)
        `SHIFT_DEFINE(57)
        `SHIFT_DEFINE(58)
        `SHIFT_DEFINE(59)
        `SHIFT_DEFINE(60)
        `SHIFT_DEFINE(61)
        `SHIFT_DEFINE(62)
        `SHIFT_DEFINE(63)
`endif
        endcase
    end
endmodule