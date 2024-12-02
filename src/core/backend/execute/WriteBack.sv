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
`ifdef RVF
    WriteBackIO.wb fmisc_wb_io,
    WriteBackIO.wb fma_wb_io,
    WriteBackIO.wb fdiv_wb_io,
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
        assign int_wbBus.irq_enable[i] = wbData.irq_enable;
    end
endgenerate

generate
    // store don't in wbBus
    for(genvar i=0; i<`LSU_SIZE; i++)begin
        assign lsu_wb_io.valid[i] = 1'b1;
`ifdef RVF
        assign fmisc_wb_io.valid[`FMISC_SIZE+i] = ~lsu_wb_io.datas[i].en;
        assign int_wbBus.en[`ALU_SIZE+i] = lsu_wb_io.datas[i].en | fmisc_wb_io.datas[`FMISC_SIZE+i].en;
        assign int_wbBus.we[`ALU_SIZE+i] = lsu_wb_io.datas[i].en ? lsu_wb_io.datas[i].we : fmisc_wb_io.datas[`FMISC_SIZE+i].we;
        assign int_wbBus.robIdx[`ALU_SIZE+i] = lsu_wb_io.datas[i].en ? lsu_wb_io.datas[i].robIdx : fmisc_wb_io.datas[`FMISC_SIZE+i].robIdx;
        assign int_wbBus.rd[`ALU_SIZE+i] = lsu_wb_io.datas[i].en ? lsu_wb_io.datas[i].rd : fmisc_wb_io.datas[`FMISC_SIZE+i].rd;
        assign int_wbBus.res[`ALU_SIZE+i] = lsu_wb_io.datas[i].en ? lsu_wb_io.datas[i].res : fmisc_wb_io.datas[`FMISC_SIZE+i].res;
        assign int_wbBus.exccode[`ALU_SIZE+i] = lsu_wb_io.datas[i].en ? lsu_wb_io.datas[i].exccode : fmisc_wb_io.datas[`FMISC_SIZE+i].exccode;
        assign int_wbBus.irq_enable[`ALU_SIZE+i] = lsu_wb_io.datas[i].en ? lsu_wb_io.datas[i].irq_enable : fmisc_wb_io.datas[`FMISC_SIZE+i].irq_enable;
`else
        assign int_wbBus.en[`ALU_SIZE+i] = lsu_wb_io.datas[i].en;
        assign int_wbBus.we[`ALU_SIZE+i] = lsu_wb_io.datas[i].we;
        assign int_wbBus.robIdx[`ALU_SIZE+i] = lsu_wb_io.datas[i].robIdx;
        assign int_wbBus.rd[`ALU_SIZE+i] = lsu_wb_io.datas[i].rd;
        assign int_wbBus.res[`ALU_SIZE+i] = lsu_wb_io.datas[i].res;
        assign int_wbBus.exccode[`ALU_SIZE+i] = lsu_wb_io.datas[i].exccode;
        assign int_wbBus.irq_enable[`ALU_SIZE+i] = lsu_wb_io.datas[i].irq_enable;
`endif
    end
endgenerate

`ifdef RVF
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign fmisc_wb_io.valid[i] = ~lsu_wb_io.datas[`LOAD_PIPELINE+i].en;
        assign fp_wbBus.en[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en | fmisc_wb_io.datas[i].en;
        assign fp_wbBus.we[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en ? lsu_wb_io.datas[`LOAD_PIPELINE+i].we : fmisc_wb_io.datas[i].we;
        assign fp_wbBus.robIdx[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en ? lsu_wb_io.datas[`LOAD_PIPELINE+i].robIdx : fmisc_wb_io.datas[i].robIdx;
        assign fp_wbBus.rd[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en ? lsu_wb_io.datas[`LOAD_PIPELINE+i].rd : fmisc_wb_io.datas[i].rd;
        assign fp_wbBus.res[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en ? lsu_wb_io.datas[`LOAD_PIPELINE+i].res : fmisc_wb_io.datas[i].res;
        assign fp_wbBus.exccode[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en ? lsu_wb_io.datas[`LOAD_PIPELINE+i].exccode : fmisc_wb_io.datas[i].exccode;
        assign fp_wbBus.irq_enable[i] = lsu_wb_io.datas[`LOAD_PIPELINE+i].en ? lsu_wb_io.datas[`LOAD_PIPELINE+i].irq_enable : fmisc_wb_io.datas[i].irq_enable;
    end
    for(genvar i=0; i<`FMA_SIZE; i++)begin
        WBData fma_data;
        always_ff @(posedge clk)begin
            fma_data <= fma_wb_io.datas[i];
        end
        assign fma_wb_io.valid[i] = 1'b1;
        if(i == 0)begin
            assign fdiv_wb_io.valid[0] = ~fma_data.en;
            assign fp_wbBus.en[`FMISC_SIZE+i] = fdiv_wb_io.datas[0].en | fma_data.en;
            assign fp_wbBus.we[`FMISC_SIZE+i] = fma_data.en ? fma_data.we : fdiv_wb_io.datas[0].we;
            assign fp_wbBus.robIdx[`FMISC_SIZE+i] = fma_data.en ? fma_data.robIdx : fdiv_wb_io.datas[0].robIdx;
            assign fp_wbBus.rd[`FMISC_SIZE+i] = fma_data.en ? fma_data.rd : fdiv_wb_io.datas[0].rd;
            assign fp_wbBus.res[`FMISC_SIZE+i] = fma_data.en ? fma_data.res : fdiv_wb_io.datas[0].res;
            assign fp_wbBus.exccode[`FMISC_SIZE+i] = fma_data.en ? fma_data.exccode : fdiv_wb_io.datas[0].exccode;
            assign fp_wbBus.irq_enable[`FMISC_SIZE+i] = fma_data.en ? fma_data.irq_enable : fdiv_wb_io.datas[0].irq_enable;
        end
        else begin
            assign fp_wbBus.en[`FMISC_SIZE+i] = fma_data.en;
            assign fp_wbBus.we[`FMISC_SIZE+i] = fma_data.we;
            assign fp_wbBus.robIdx[`FMISC_SIZE+i] = fma_data.robIdx;
            assign fp_wbBus.rd[`FMISC_SIZE+i] = fma_data.rd;
            assign fp_wbBus.res[`FMISC_SIZE+i] = fma_data.res;
            assign fp_wbBus.exccode[`FMISC_SIZE+i] = fma_data.exccode;
            assign fp_wbBus.irq_enable[`FMISC_SIZE+i] = fma_data.irq_enable;
        end
    end
endgenerate
`endif
endmodule