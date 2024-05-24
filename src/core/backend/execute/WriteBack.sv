`include "../../../defines/defines.svh"

interface WriteBackIO;
    WBData `N(`FU_SIZE) datas;
    logic `N(`FU_SIZE) valid;
    WBData `N(`WB_SIZE) wbData;

    modport wb (input datas, output valid, wbData);
endinterface

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb io,
    BackendCtrl backendCtrl
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