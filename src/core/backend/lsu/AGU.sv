`include "../../../defines/defines.svh"

module AGU(
    input logic [11: 0] imm,
    input logic `N(`XLEN) data,
    output logic `VADDR_BUS addr,
    output logic [`TLB_PN-1: 0][1: 0] carry /*verilator split_var*/
);
    logic `N(`VADDR_SIZE) sext_imm;
    assign sext_imm = {{`VADDR_SIZE-12{imm[11]}}, imm[11: 0]};
    KSA #(`VADDR_SIZE) ksa (data[`VADDR_SIZE-1: 0], sext_imm, addr);

    logic [12: 0] carry_imm, carry_data, carry_res;
    assign carry_imm = {imm[11], imm[11: 0]};
    assign carry_data = {1'b0, data[11: 0]};
    assign carry_res = carry_imm + carry_data;
    assign carry[0][1] = carry_res[12] & ~imm[11];
    assign carry[0][0] = carry_res[12] & imm[11];
    
    VPNAddr vpn_addr;
    assign vpn_addr = data[`VADDR_SIZE-1: `TLB_OFFSET];
generate
    for(genvar i=1; i<`TLB_PN; i++)begin
        assign carry[i][1] = (&vpn_addr.vpn[i-1]) & carry[i-1][1];
        assign carry[i][0] = (~(|vpn_addr.vpn[i-1])) & carry[i-1][0];
    end
endgenerate
endmodule