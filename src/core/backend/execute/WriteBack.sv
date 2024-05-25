`include "../../../defines/defines.svh"

interface WriteBackIO;
    WBData `N(`FU_SIZE) datas;
    logic `N(`FU_SIZE) valid;

    modport wb (input datas, output valid);
endinterface

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb io,
    BackendCtrl backendCtrl,
    WriteBackBus.wb wbBus
);
generate
    for(genvar i=0; i<`FU_SIZE; i++)begin
        assign io.valid[i] = 1'b1;
    end
endgenerate

    always_ff @(posedge clk)begin
        for(int i=0; i<`WB_SIZE; i++)begin
            wbBus.en[i] <= io.datas[i].en;
            wbBus.robIdx[i] <= io.datas[i].robIdx;
            wbBus.fsqInfo[i] <= io.datas[i].fsqInfo;
            wbBus.rd[i] <= io.datas[i].rd;
            wbBus.res[i] <= io.datas[i].res;
        end
    end
endmodule