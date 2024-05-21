`include "../../defines/defines.svh"

module BTB (
    input logic clk,
    input logic rst,
    BpuBtbIO.btb btb_io
);


    typedef struct {
        logic we;
        logic `N(`BTB_SET_WIDTH) addr0;
        logic `N(`BTB_SET_WIDTH) addr1;
        BTBEntry wdata;
        BTBEntry rdata1;
    } BankCtrl;

    BankCtrl bank_ctrl `N(`BTB_WAY);

    logic `N(`BTB_SET_WIDTH) index, updateIdx;
    logic `N($clog2(`BTB_WAY)) s2_bank;
    logic `N(`BTB_WAY) bank_en, bank_we;

    localparam INDEX_POS = `BTB_SET_WIDTH+1+$clog2(`BTB_WAY);
    assign index = btb_io.pc[INDEX_POS: 2+$clog2(`BTB_WAY)];
    assign updateIdx = btb_io.updateInfo.start_addr[INDEX_POS: 2+$clog2(`BTB_WAY)];
    Decoder #(`BTB_WAY) decoder_bank(btb_io.pc[1+$clog2(`BTB_WAY): 2], bank_en);
    Decoder #(`BTB_WAY) decoder_we(btb_io.updateInfo.start_addr[1+$clog2(`BTB_WAY): 2], bank_we);

    generate;
        for(genvar i=0; i<`BTB_WAY; i++)begin
            SDPRAM #(
                .WIDTH($bits(BTBEntry)),
                .DEPTH(`BTB_SET_WIDTH),
                .READ_LATENCY(1)
            ) btb_bank(
                .clk(clk),
                .rst(rst),
                .en(bank_en[i] & ~btb_io.redirect.stall),
                .we(bank_ctrl[i].we),
                .addr0(bank_ctrl[i].addr0),
                .addr1(bank_ctrl[i].addr1),
                .wdata(bank_ctrl[i].wdata),
                .rdata1(bank_ctrl[i].rdata1)
            );
            assign bank_ctrl[i].addr1 = index;
            assign bank_ctrl[i].addr0 = btb_io.updateInfo.start_addr[INDEX_POS: 2+$clog2(`BTB_WAY)];
            assign bank_ctrl[i].we = btb_io.update & bank_we[i];
            assign bank_ctrl[i].wdata = btb_io.updateInfo.btbEntry;
        end
    endgenerate
    assign btb_io.entry = bank_ctrl[s2_bank].rdata1;

    always_ff @(posedge clk)begin
        if(~btb_io.redirect.stall)begin
            s2_bank <= btb_io.pc[1+$clog2(`BTB_WAY): 2];
        end
    end

endmodule