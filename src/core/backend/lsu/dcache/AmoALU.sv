`include "../../../../defines/defines.svh"

module AmoALU(
`ifdef RV64I
    input logic word,
`endif
    input logic `N(`XLEN) mem_data,
    input logic `N(`XLEN) op_data,
    input logic `N(`AMOOP_WIDTH) op,
    output logic `N(`XLEN) res
);
    logic cmp, scmp;
    logic [1: 0] head;
`ifdef RV64I
    assign cmp = word ? mem_data[31: 0] < op_data[31: 0] : mem_data < op_data;
    assign head = word ? {mem_data[31], op_data[31]} : {mem_data[`XLEN-1], op_data[`XLEN-1]};
`else
    assign cmp = mem_data < op_data;
    assign head = {mem_data[`XLEN-1], op_data[`XLEN-1]};
`endif
    always_comb begin
        case(head)
        2'b00: scmp = cmp;
        2'b01: scmp = 0;
        2'b10: scmp = 1;
        2'b11: scmp = cmp;
        endcase
    end
    always_comb begin
        case(op)
        `AMO_SWAP: res = op_data;
        `AMO_ADD: res = op_data + mem_data;
        `AMO_XOR: res = op_data ^ mem_data;
        `AMO_AND: res = op_data & mem_data;
        `AMO_OR: res = op_data | mem_data;
        `AMO_MIN: res = scmp ? mem_data : op_data;
        `AMO_MAX: res = scmp ? op_data : mem_data;
        `AMO_MINU: res = cmp ? mem_data : op_data;
        `AMO_MAXU: res = cmp ? op_data : mem_data;
        default: res = 0;
        endcase
    end

endmodule