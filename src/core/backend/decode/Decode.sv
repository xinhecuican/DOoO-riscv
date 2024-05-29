`include "../../../defines/defines.svh"

module Decode(
    input logic clk,
    input logic rst,
    input FetchBundle insts,
    DecodeRenameIO.decode dec_rename_io,
    BackendCtrl backendCtrl
);
    DecodeInfo decodeInfo `N(`FETCH_WIDTH);

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        DecodeUnit decodeUnit(
            .inst(insts.inst[i]),
            .addr(insts.addr[i]),
            .info(decodeInfo[i])
        );
    end
endgenerate

    // TODO: Fusion Decoder，在rob中添加一个funsion位表示为两条指令
    always_ff @(posedge clk)begin
        if(rst == `RST || backendCtrl.redirect)begin
            dec_rename_io.op <= 0;
        end
        else if(~(backendCtrl.rename_full | backendCtrl.rob_full | backendCtrl.dis_full))begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dec_rename_io.op[i].en <= insts.en[i];
                dec_rename_io.op[i].di <= decodeInfo[i];
                dec_rename_io.op[i].fsqInfo <= insts.fsqInfo[i];
`ifdef DIFFTEST
                dec_rename_io.op[i].inst <= insts.inst[i];
`endif
            end
        end
    end

endmodule