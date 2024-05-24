`include "../../../defines/defines.svh"

module ALU(
    input logic clk,
    input logic rst,
    IssueAluIO.alu io,
    input logic valid,
    output WBData wbData,
    output BranchUnitRes branchRes
);
    logic `N(`XLEN) result, branchResult;
    ALUModel model(
        .immv(io.bundle.immv),
        .sext(io.bundle.sext),
        .imm(io.bundle.imm),
        .rs1_data(io.rs1_data),
        .rs2_data(io.rs2_data),
        .op(io.bundle.op),
        .result(result)
    );
    BranchModel branchModel(
        .immv(io.bundle.immv),
        .sext(io.bundle.sext),
        .imm(io.bundle.imm),
        .rs1_data(io.rs1_data),
        .rs2_data(io.rs2_data),
        .op(io.bundle.op),
        .stream(io.stream),
        .offset(io.bundle.fsqInfo.offset),
        .br_type(io.br_type),
        .ras_type(io.ras_type),
        .BranchUnitRes(branchRes),
        .result(branchResult)
    );
    assign wbData.en = io.en & valid & ~(backendCtrl.redirect &
            ((backendCtrl.redirectIdx.dir ^ io.bundle.robIdx.dir) ^ (io.bundle.robIdx.idx < bankendCtrl.redirectIdx.idx)));
    assign wbData.fsqInfo = io.bundle.fsqInfo;
    assign wbData.robIdx = io.bundle.robIdx;
    assign wbData.rd = io.bundle.rd;
    assign wbDataq.res = io.intv ? result : branchResult;

    assign io.valid = valid;
endmodule

module BranchModel(
    input logic immv,
    input logic sext,
    input logic `N(`XLEN) imm,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`BRANCHOP_WIDTH) op,
    input FetchStream stream,
    input logic `N(`PREDICTION_WIDTH) offset,
    input BranchType br_type,
    input RasType ras_type,
    output BranchUnitRes branchRes,
    output logic `N(`XLEN) result
);
    logic cmp, scmp, cmp_result;
    logic equal;
    assign cmp = rs1_data < rs2_data;
    assign equal = rs1_data == rs2_data;
    always_comb begin
        case({rs1_data[`XLEN-1], rs2_data[`XLEN-1]})
        2'b00: scmp = cmp;
        2'b01: scmp = 1;
        2'b10: scmp = 0;
        2'b11: scmp = ~cmp;
        endcase
    end
    assign cmp_result = sext ? scmp : cmp;

    always_comb begin
        case(op)
        `BRANCH_BEQ: begin
            branchRes.direction = equal;
        end
        `BRANCH_BNE: begin
            branchRes.direction = ~equal;
        end
        `BRANCH_BLT: begin
            branchRes.direction = cmp_result;
        end
        `BRANCH_BGE: begin
            branchRes.direction = ~cmp_result;
        end
        default: branchRes.direction = 0;
        endcase
    end

    logic `N(`VADDR_SIZE) jalr_target;
    assign jalr_target = rs1_data + imm;
    assign branchRes.target = jalr_target;
    logic `N(`PREDICTION_WIDTH+1) addrOffset;
    assign addrOffset = offset + 1;
    assign result = {stream.start_addr[`VADDR_SIZE-1: 2] + addrOffset, 2'b00};

    // predict error
    // cal stream taken offset
    logic streamHit, branchError, indirectError;
    assign streamHit = stream.size == offset;
    assign branchError = streamHit ? stream.taken ^ branchRes.direction : branchRes.direction;
    assign indirectError = stream.target != jalr_target;
    assign branchRes.error = op == `BRANCH_JALR ? indirectError :
                        op != `BRANCH_JAL ? branchError : 0;
    assign branchRes.br_type = br_type;
    assign branchRes.ras_type = ras_type;
endmodule

module ALUModel(
    input logic immv,
    input logic sext,
    input logic `N(`XLEN) imm,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic `N(`INTOP_WIDTH) op,
    output logic `N(`XLEN) result
);
    logic `N(`XLEN) data1, data2;
    logic `N(`XLEN) add_result;
    logic cmp, scmp;

    assign data1 = rs1_data;
    assign data2 = immv ? imm : rs2_data;
    assign add_result = data1 + data2;
    assign cmp = data1 < data2;
    always_comb begin
        case({data2[`XLEN-1], data1[`XLEN-1]})
        2'b00: scmp = cmp;
        2'b01: scmp = 1;
        2'b10: scmp = 0;
        2'b11: scmp = ~cmp;
        endcase
    end

    always_comb begin
        case(op)
        `INT_ADD: begin
            result = add_result;
        end
        `INT_LUI: begin
            result = imm;
        end
        `INT_SLT: begin
            // A   B   s u
            // 001 111 0 1
            // 010 001 1 1
            // 100 111 1 0
            // 101 110 0 1
            // 100 011 1 0
            if(sext)begin
                result = scmp;
            end
            else begin
                result = cmp;
            end
        end
        `INT_XOR: begin
            result = data1 ^ data2;
        end
        `INT_AND: begin
            result = data1 & data2;
        end
        `INT_SL: begin
            result = data1 << data2[$clog2(`XLEN)-1: 0];
        end
        `INT_SRL: begin
            result = data1 >> data2[$clog2(`XLEN)-1: 0];
        end
        `INT_SRA: begin
            // TODO: remove $signed
            result = $signed(data1) >> data2[$clog2(`XLEN)-1: 0];
        end
        default: result = 0;
        endcase
    end
endmodule