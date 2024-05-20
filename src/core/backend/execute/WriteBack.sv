`include "../../../defines/defines.svh"

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb io
);
generate
    for(genvar i=0; i<`FU_SIZE; i++)begin
        assign io.valid[i] = 1'b1;
    end
endgenerate

    always_ff @(posedge clk)begin
        for(int i=0; i<`WB_SIZE; i++)begin
            io.wbData[i] <= io.datas[i];
        end
    end
endmodule