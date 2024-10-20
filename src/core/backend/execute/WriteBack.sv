`include "../../../defines/defines.svh"

module WriteBack(
    input logic clk,
    input logic rst,
    WriteBackIO.wb alu_wb_io,
    WriteBackIO.wb lsu_wb_io,
    WriteBackIO.wb csr_wb_io,
`ifdef RVM
    WriteBackIO.wb mult_wb_io,
    WriteBackIO.wb div_wb_io,
`endif
    output WriteBackBus wbBus
);
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign alu_wb_io.valid[i] = 1'b1;
        WBData wbData;
        always_ff @(posedge clk)begin
            if(i == 0)begin
                wbData <= csr_wb_io.datas[0].en ? csr_wb_io.datas[0] : alu_wb_io.datas[0];
            end
`ifdef RVM
            else if(i == 2)begin
                wbData <= mult_wb_io.datas[0].en ? mult_wb_io.datas[0] : alu_wb_io.datas[2];
            end
            else if(i == 3)begin
                wbData <= div_wb_io.datas[0].en ? div_wb_io.datas[0] : alu_wb_io.datas[3];
            end
`endif
            else begin
                wbData <= alu_wb_io.datas[i];
            end
        end
        assign wbBus.en[i] = wbData.en;
        assign wbBus.we[i] = wbData.we;
        assign wbBus.robIdx[i] = wbData.robIdx;
        assign wbBus.rd[i] = wbData.rd;
        assign wbBus.res[i] = wbData.res;
        assign wbBus.exccode[i] = wbData.exccode;

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