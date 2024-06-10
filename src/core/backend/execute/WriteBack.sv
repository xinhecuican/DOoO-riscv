`include "../../../defines/defines.svh"

interface WriteBackIO#(
    parameter FU_SIZE = 4
);
    WBData `N(FU_SIZE) datas;
    logic `N(FU_SIZE) valid;

    modport wb (input datas, output valid);
    modport fu (output datas, input valid);
endinterface

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb alu_wb_io,
    WriteBackIO.wb lsu_wb_io,
    BackendCtrl backendCtrl,
    WriteBackBus.wb wbBus
);
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign alu_wb_io.valid[i] = 1'b1;
        WBData wbData;
        always_ff @(posedge clk)begin
            wbData <= alu_wb_io.datas[i];
        end
        assign wbBus.en[i] = wbData.en;
        assign wbBus.we[i] = wbData.rd != 0;
        assign wbBus.robIdx[i] = wbData.robIdx;
        assign wbBus.rd[i] = wbData.rd;
        assign wbBus.res[i] = wbData.res;
    end
endgenerate

generate
    // store don't in wbBus
    for(genvar i=0; i<`LSU_SIZE; i++)begin
        assign lsu_wb_io.valid[i] = 1'b1;
        // always_ff @(posedge clk)begin
            // control by lsu
            assign wbBus.en[`ALU_SIZE+i] = lsu_wb_io.datas[i].en;
            assign wbBus.we[`ALU_SIZE+i] = lsu_wb_io.datas[i].rd != 0;
            assign wbBus.robIdx[`ALU_SIZE+i] = lsu_wb_io.datas[i].robIdx;
            assign wbBus.rd[`ALU_SIZE+i] = lsu_wb_io.datas[i].rd;
            assign wbBus.res[`ALU_SIZE+i] = lsu_wb_io.datas[i].res;
        // end
    end
endgenerate

endmodule