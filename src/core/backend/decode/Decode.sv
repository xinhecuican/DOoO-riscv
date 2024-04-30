`include "../../../defines/defines.svh"

module Decode(
    input logic clk,
    input logic rst,
    input FetchBundle insts,
    DecodeRenameIO.decode decode_rename_io
);
    DecodeInfo decodeInfo `N(`FETCH_WIDTH);

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        DecodeUnit decodeUnit(
            .inst(insts.inst[i]),
            .info(decodeInfo[i])
        );
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst)begin
            decode_rename_io.opBundles <= 0;
        end
        else begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                decode_rename_io.opBundles[i].en <= insts.en[i];
                decode_rename_io.opBundles[i].decodeInfo <= decodeInfo[i];
                decode_rename_io.opBundles[i].fsqIdx = insts.fsqIdx[i];
            end
        end
    end

endmodule