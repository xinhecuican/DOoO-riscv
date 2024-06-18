`include "../../../defines/defines.svh"

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb alu_wb_io,
    WriteBackIO.wb lsu_wb_io,
    WriteBackIO.wb csr_wb_io,
    BackendCtrl backendCtrl,
    WriteBackBus.wb wbBus
);
    WBData csrData;
    always_ff @(posedge clk)begin
        csrData <= csr_wb_io.datas[0];
    end
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign alu_wb_io.valid[i] = 1'b1;
        WBData wbData;
        always_ff @(posedge clk)begin
            wbData <= alu_wb_io.datas[i];
        end
        if(i == 1)begin
            assign wbBus.en[i] = csrData.en | wbData.en;
            assign wbBus.we[i] = csrData.en ? csrData.rd != 0 : wbData.rd != 0;
            assign wbBus.robIdx[i] = csrData.en ? csrData.robIdx : wbData.robIdx;
            assign wbBus.rd[i] = csrData.en ? csrData.rd : wbData.rd;
            assign wbBus.res[i] = csrData.en ? csrData.res : wbData.res;
        end
        else begin
            assign wbBus.en[i] = wbData.en;
            assign wbBus.we[i] = wbData.rd != 0;
            assign wbBus.robIdx[i] = wbData.robIdx;
            assign wbBus.rd[i] = wbData.rd;
            assign wbBus.res[i] = wbData.res;
        end

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