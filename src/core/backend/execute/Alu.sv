`include "../../../defines/defines.svh"

module ALU(
    input logic clk,
    input logic rst,
    IssueAluIO.alu issue_alu_io
);

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
    output logic predict,
    output logic pred_error,
    output logic `N(`VADDR_SIZE) target,
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
            predict = equal;
        end
        `BRANCH_BNE: begin
            predict = ~equal;
        end
        `BRANCH_BLT: begin
            predict = cmp_result;
        end
        `BRANCH_BGE: begin
            predict = ~cmp_result;
        end
        default: predict = 0;
        endcase
    end

    logic `N(`VADDR_SIZE) jalr_target;
    assign jalr_target = rs1_data + imm;
    assign target = jalr_target;
    logic `N(`PREDICTION_WIDTH+1) addrOffset;
    assign addrOffset = offset + 1;
    assign result = {stream.start_addr[`VADDR_SIZE-1: 2] + addrOffset, 2'b00};

    // predict error
    // cal stream taken offset
    logic streamHit, branchError, indirectError;
    assign streamHit = stream.size == offset;
    assign branchError = streamHit ? stream.taken ^ predict : predict;
    assign indirectError = stream.target != jalr_target;
    assign pred_error = op == `BRANCH_JALR ? indirectError :
                        op != `BRANCH_JAL ? branchError : 0;
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