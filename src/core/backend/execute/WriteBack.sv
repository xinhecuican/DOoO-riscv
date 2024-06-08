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
        always_ff @(posedge clk)begin
            wbBus.en[i] <= alu_wb_io.datas[i].en;
            wbBus.we[i] <= alu_wb_io.datas[i].rd != 0;
            wbBus.robIdx[i] <= alu_wb_io.datas[i].robIdx;
            wbBus.rd[i] <= alu_wb_io.datas[i].rd;
            wbBus.res[i] <= alu_wb_io.datas[i].res;
        end
    end
endgenerate

generate
    // store don't in wbBus
    for(genvar i=0; i<`LSU_SIZE; i++)begin
        assign lsu_wb_io.valid[i] = 1'b1;
        // always_ff @(posedge clk)begin
            // control by lsu
            assign wbBus.en[i] = lsu_wb_io.datas[i].en;
            assign wbBus.we[i] = lsu_wb_io.datas[i].rd != 0;
            assign wbBus.robIdx[i] = lsu_wb_io.datas[i].robIdx;
            assign wbBus.rd[i] = lsu_wb_io.datas[i].rd;
            assign wbBus.res[i] = lsu_wb_io.datas[i].res;
        // end
    end
endgenerate

endmodule