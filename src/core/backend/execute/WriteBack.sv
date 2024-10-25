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
    output WriteBackBus int_wbBus
`ifdef RVF
    ,output WriteBackBus fp_wbBus
`endif
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
        assign int_wbBus.en[i] = wbData.en;
        assign int_wbBus.we[i] = wbData.we;
        assign int_wbBus.robIdx[i] = wbData.robIdx;
        assign int_wbBus.rd[i] = wbData.rd;
        assign int_wbBus.res[i] = wbData.res;
        assign int_wbBus.exccode[i] = wbData.exccode;

    end
endgenerate

generate
    // store don't in wbBus
    for(genvar i=0; i<`LSU_SIZE; i++)begin
        assign lsu_wb_io.valid[i] = 1'b1;
        // always_ff @(posedge clk)begin
            // control by lsu
            assign int_wbBus.en[`ALU_SIZE+i] = lsu_wb_io.datas[i].en;
            assign int_wbBus.we[`ALU_SIZE+i] = lsu_wb_io.datas[i].we;
            assign int_wbBus.robIdx[`ALU_SIZE+i] = lsu_wb_io.datas[i].robIdx;
            assign int_wbBus.rd[`ALU_SIZE+i] = lsu_wb_io.datas[i].rd;
            assign int_wbBus.res[`ALU_SIZE+i] = lsu_wb_io.datas[i].res;
            assign int_wbBus.exccode[`ALU_SIZE+i] = lsu_wb_io.datas[i].exccode;
        // end
    end
endgenerate

`ifdef RVF
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign fp_wbBus.en[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en;
        assign fp_wbBus.we[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].we;
        assign fp_wbBus.robIdx[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].robIdx;
        assign fp_wbBus.rd[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].rd;
        assign fp_wbBus.res[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].res;
        assign fp_wbBus.exccode[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].exccode;
    end
endgenerate
`endif
endmodule