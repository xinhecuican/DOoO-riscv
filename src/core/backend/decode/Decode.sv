`include "../../../defines/defines.svh"

module Decode(
    input logic clk,
    input logic rst,
    input FetchBundle insts,
    DecodeRenameIO.decode dec_rename_io,
    input BackendCtrl backendCtrl,
    input CommitWalk commitWalk
);
    DecodeInfo decodeInfo `N(`FETCH_WIDTH);

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        DecodeUnit decodeUnit(
            .inst(insts.inst[i]),
            .iam(insts.iam[i]),
            .ipf(insts.ipf[i]),
            .info(decodeInfo[i])
        );
    end
endgenerate

    // TODO: Fusion Decoder，在rob中添加一个funsion位表示为两条指令
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            dec_rename_io.op <= 0;
        end
        else if(backendCtrl.redirect || commitWalk.walk)begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dec_rename_io.op[i].en <= 1'b0;
            end
        end
        else if(~(backendCtrl.rename_full | backendCtrl.dis_full))begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                dec_rename_io.op[i].en <= insts.en[i];
                dec_rename_io.op[i].di <= decodeInfo[i];
                dec_rename_io.op[i].fsqInfo <= insts.fsqInfo[i];
                dec_rename_io.op[i].inst <= insts.inst[i];
`ifdef FEAT_MEMPRED
                dec_rename_io.op[i].ssit_idx <= insts.ssit_idx[i];
`endif
            end
        end
    end

    `PERF(commit_walk_stall, commitWalk.walk & insts.en[0])

endmodule