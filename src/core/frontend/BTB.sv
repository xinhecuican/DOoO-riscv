`include "../../defines/defines.svh"

module BTBTagGen(
    input logic `VADDR_BUS pc,
    output logic `N(`BTB_TAG_SIZE) tag
);
    assign tag = pc[`BTB_TAG_SIZE + 1 : 2] ^ pc[`BTB_TAG_SIZE + 1 + `BTB_TAG_SIZE : 2+`BTB_TAG_SIZE];
endmodule

module BTBIndexGen(
    input logic `VADDR_BUS pc,
    output logic `N(`BTB_SET_WIDTH) index
);
    assign index = pc[`BTB_SET_WIDTH + 1 + $clog2(`BTB_WAY): 2 + $clog2(`BTB_WAY)];
endmodule

module BTB (
    input logic clk,
    input logic rst,
    BpuBtbIO.btb btb_io
);

`ifdef DIFFTEST
    typedef struct packed {
`else
    typedef struct {
`endif
        logic we;
        logic `N(`BTB_SET_WIDTH) waddr;
        logic `N(`BTB_SET_WIDTH) raddr;
        BTBEntry wdata;
        BTBEntry rdata;
    } BankCtrl;

    BankCtrl bank_ctrl `N(`BTB_WAY);

    logic `N(`BTB_SET_WIDTH) index, updateIdx;
    logic `N($clog2(`BTB_WAY)) s2_bank;
    logic `N(`BTB_WAY) bank_en, bank_we;
    logic `N(`BTB_TAG_SIZE) update_tag;

    localparam INDEX_POS = `BTB_SET_WIDTH+1+$clog2(`BTB_WAY);
    BTBIndexGen index_gen(btb_io.pc, index);
    BTBIndexGen update_index_gen(btb_io.updateInfo.start_addr, updateIdx);
    Decoder #(`BTB_WAY) decoder_bank(btb_io.pc[1+$clog2(`BTB_WAY): 2], bank_en);
    Decoder #(`BTB_WAY) decoder_we(btb_io.updateInfo.start_addr[1+$clog2(`BTB_WAY): 2], bank_we);
    BTBTagGen gen_update_tag(btb_io.updateInfo.start_addr, update_tag);
    generate;
        for(genvar i=0; i<`BTB_WAY; i++)begin
            MPRAM #(
                .WIDTH($bits(BTBEntry)),
                .DEPTH(`BTB_SET),
                .READ_PORT(1),
                .WRITE_PORT(1),
                .RESET(1)
            ) btb_bank(
                .clk(clk),
                .rst(rst),
                .en(bank_en[i] & ~btb_io.redirect.stall),
                .we(bank_ctrl[i].we),
                .waddr(bank_ctrl[i].waddr),
                .raddr(bank_ctrl[i].raddr),
                .wdata(bank_ctrl[i].wdata),
                .rdata(bank_ctrl[i].rdata),
                .ready()
            );
            assign bank_ctrl[i].raddr = index;
            assign bank_ctrl[i].waddr = updateIdx;
            assign bank_ctrl[i].we = btb_io.update & bank_we[i] & btb_io.updateInfo.btbEntry.en;
            assign bank_ctrl[i].wdata = {update_tag, btb_io.updateInfo.btbEntry};
        end
    endgenerate
    assign btb_io.entry = bank_ctrl[s2_bank].rdata;

    always_ff @(posedge clk)begin
        if(~btb_io.redirect.stall)begin
            s2_bank <= btb_io.pc[1+$clog2(`BTB_WAY): 2];
        end
    end

endmodule