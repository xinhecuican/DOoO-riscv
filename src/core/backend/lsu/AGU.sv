`include "../../../defines/defines.svh"

module AGU(
    input logic [11: 0] imm,
    input logic `N(`XLEN) data,
    output logic `VADDR_BUS addr
);
    logic `N(`VADDR_SIZE) sext_imm;
    assign sext_imm = {{`VADDR_SIZE-12{imm[11]}}, imm[11: 0]};
    KSA #(`VADDR_SIZE) ksa (data[`VADDR_SIZE-1: 0], sext_imm, addr);
endmodule