`include "../../defines/defines.svh"

module BTBTagGen #(
    parameter OFFSET=0,
    parameter WIDTH=1
)(
    input logic `VADDR_BUS pc,
    output logic `N(WIDTH) tag
);
    parameter SIG_BIT = OFFSET + WIDTH;
    parameter MAX_SIZE = `VADDR_SIZE > SIG_BIT + WIDTH ? SIG_BIT + WIDTH : `VADDR_SIZE;
    logic `N(MAX_SIZE-SIG_BIT) pc_reverse;
generate
    for(genvar i=0; i<MAX_SIZE-SIG_BIT; i++)begin
        assign pc_reverse[i] = pc[MAX_SIZE-i-1];;
    end
endgenerate
    assign tag = pc[SIG_BIT - 1 : OFFSET] ^ pc_reverse;
endmodule

module BTBIndexGen(
    input logic `VADDR_BUS pc,
    output logic `N(`BTB_SET_WIDTH) index
);
    assign index = pc[`BTB_SET_WIDTH + `INST_OFFSET + $clog2(`BTB_WAY) - 1: `INST_OFFSET + $clog2(`BTB_WAY)];
endmodule

module BTB (
    input logic clk,
    input logic rst,
    BpuBtbIO.btb btb_io
);

`BTB_ENTRY_GEN(`BTB_TAG_SIZE)

    typedef struct packed {
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
    Decoder #(`BTB_WAY) decoder_bank(btb_io.pc[`INST_OFFSET+$clog2(`BTB_WAY)-1: `INST_OFFSET], bank_en);
    Decoder #(`BTB_WAY) decoder_we(btb_io.updateInfo.start_addr[`INST_OFFSET+$clog2(`BTB_WAY)-1: `INST_OFFSET], bank_we);
    BTBTagGen #(
        `BTB_SET_WIDTH + `INST_OFFSET + $clog2(`BTB_WAY), 
        `BTB_TAG_SIZE
    ) gen_update_tag(btb_io.updateInfo.start_addr, update_tag);
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
                .rst_sync(1'b0),
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
            assign bank_ctrl[i].we = btb_io.update & bank_we[i] & btb_io.updateInfo.btb_update;
            assign bank_ctrl[i].wdata = {update_tag, btb_io.updateInfo.btbEntry};
        end
    endgenerate
    assign btb_io.entry = bank_ctrl[s2_bank].rdata[$bits(BTBUpdateInfo)-1: 0];
    assign btb_io.tag = bank_ctrl[s2_bank].rdata.tag;

    always_ff @(posedge clk)begin
        if(~btb_io.redirect.stall)begin
            s2_bank <= btb_io.pc[`INST_OFFSET+$clog2(`BTB_WAY)-1: `INST_OFFSET];
        end
    end

`ifdef DIFFTEST
    `Log(DLog::Debug, T_BTB, btb_io.update & btb_io.updateInfo.btb_update,
    $sformatf("BTB update: addr: %h idx: %d bank: %b", btb_io.updateInfo.start_addr, updateIdx, bank_we))
`endif
endmodule