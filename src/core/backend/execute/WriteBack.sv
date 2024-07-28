`include "../../../defines/defines.svh"

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb alu_wb_io,
    WriteBackIO.wb lsu_wb_io,
    WriteBackIO.wb csr_wb_io,
`ifdef EXT_M
    WriteBackIO.wb mult_wb_io,
    WriteBackIO.wb div_wb_io,
`endif
    BackendCtrl backendCtrl,
    WriteBackBus.wb wbBus
);
    WBData csrData;
`ifdef EXT_M
    WBData `N(`MULT_SIZE) multData, divData;
`endif
    always_ff @(posedge clk)begin
        csrData <= csr_wb_io.datas[0];
`ifdef EXT_M
        multData <= mult_wb_io.datas;
        divData <= div_wb_io.datas;
`endif
    end
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign alu_wb_io.valid[i] = 1'b1;
        WBData wbData;
        always_ff @(posedge clk)begin
            wbData <= alu_wb_io.datas[i];
        end
        if(i == 0)begin
            assign wbBus.en[i] = csrData.en | wbData.en;
            assign wbBus.we[i] = csrData.en ? csrData.we : wbData.we;
            assign wbBus.robIdx[i] = csrData.en ? csrData.robIdx : wbData.robIdx;
            assign wbBus.rd[i] = csrData.en ? csrData.rd : wbData.rd;
            assign wbBus.res[i] = csrData.en ? csrData.res : wbData.res;
            assign wbBus.exccode[i] = csrData.en ? csrData.exccode : wbData.exccode;
        end
`ifdef EXT_M
        else if(i == 2)begin
            assign wbBus.en[i] = multData[0].en | wbData.en;
            assign wbBus.we[i] = multData[0].en ? multData[0].we : wbData.we;
            assign wbBus.robIdx[i] = multData[0].en ? multData[0].robIdx : wbData.robIdx;
            assign wbBus.rd[i] = multData[0].en ? multData[0].rd : wbData.rd;
            assign wbBus.res[i] = multData[0].en ? multData[0].res : wbData.res;
            assign wbBus.exccode[i] = multData[0].en ? multData[0].exccode : wbData.exccode;
        end
        else if(i == 3)begin
            assign wbBus.en[i] = divData[0].en | wbData.en;
            assign wbBus.we[i] = divData[0].en ? divData[0].we : wbData.we;
            assign wbBus.robIdx[i] = divData[0].en ? divData[0].robIdx : wbData.robIdx;
            assign wbBus.rd[i] = divData[0].en ? divData[0].rd : wbData.rd;
            assign wbBus.res[i] = divData[0].en ? divData[0].res : wbData.res;
            assign wbBus.exccode[i] = divData[0].en ? divData[0].exccode : wbData.exccode;
        end
`endif
        else begin
            assign wbBus.en[i] = wbData.en;
            assign wbBus.we[i] = wbData.we;
            assign wbBus.robIdx[i] = wbData.robIdx;
            assign wbBus.rd[i] = wbData.rd;
            assign wbBus.res[i] = wbData.res;
            assign wbBus.exccode[i] = wbData.exccode;
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
            assign wbBus.exccode[`ALU_SIZE+i] = lsu_wb_io.datas[i].exccode;
        // end
    end
endgenerate

endmodule