`include "../../../defines/defines.svh"


/***
* 在指令写回的前两个周期进行wakeup
* Select & Wakeup,  Reg read, E1, wb
* Select, Reg read, E1 & Wakeup, E2, E3, wb
***/
module Wakeup(
    input logic clk,
    input logic rst,
`ifdef RVM
    IssueWakeupIO.wakeup mult_wakeup_io,
    IssueWakeupIO.wakeup div_wakeup_io,
`endif
    output WakeupBus int_wakeupBus,
`ifdef RVF
    IssueWakeupIO.wakeup fmisc_wakeup_io,
    IssueWakeupIO.wakeup fma_wakeup_io,
    output WakeupBus fp_wakeupBus,
`endif
    IssueWakeupIO.wakeup int_wakeup_io,
    IssueWakeupIO.wakeup load_wakeup_io,
    IssueWakeupIO.wakeup csr_wakeup_io
);

    logic `N(`ALU_SIZE) int_en, int_we;
    logic `ARRAY(`ALU_SIZE, `PREG_WIDTH) int_rd;
    assign csr_wakeup_io.ready = 1'b1;
    assign mult_wakeup_io.ready = 1'b1;
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        if(i == 0)begin
            assign int_wakeup_io.ready[i] = ~csr_wakeup_io.en;
            assign int_en[i] = int_wakeup_io.en[i] | csr_wakeup_io.en; 
            assign int_we[i] = csr_wakeup_io.en ? csr_wakeup_io.we : int_wakeup_io.we[i];
            assign int_rd[i] = csr_wakeup_io.en ? csr_wakeup_io.rd : int_wakeup_io.rd[i];
        end
`ifdef RVM
        else if(i == 2)begin
            assign int_wakeup_io.ready[i] = ~mult_wakeup_io.en;
            assign int_en[i] = int_wakeup_io.en[i] | mult_wakeup_io.en;
            assign int_we[i] = mult_wakeup_io.en ? mult_wakeup_io.we : int_wakeup_io.we[i];
            assign int_rd[i] = mult_wakeup_io.en ? mult_wakeup_io.rd : int_wakeup_io.rd[i];
        end
        else if(i == 3)begin
            assign int_wakeup_io.ready[i] = ~div_wakeup_io.en;
            assign int_en[i] = int_wakeup_io.en[i] | div_wakeup_io.en;
            assign int_we[i] = div_wakeup_io.en ? div_wakeup_io.we : int_wakeup_io.we[i];
            assign int_rd[i] = div_wakeup_io.en ? div_wakeup_io.rd : int_wakeup_io.rd[i];
        end
`endif
        else begin
            assign int_wakeup_io.ready[i] = 1'b1;
            assign int_en[i] = int_wakeup_io.en[i];
            assign int_we[i] = int_wakeup_io.we[i];
            assign int_rd[i] = int_wakeup_io.rd[i];
        end
    end
endgenerate
    assign int_wakeupBus.en[`ALU_SIZE-1: 0] = int_en;
    assign int_wakeupBus.we[`ALU_SIZE-1: 0] = int_we;
    assign int_wakeupBus.rd[`ALU_SIZE-1: 0] = int_rd;


    localparam LOAD_BASE = `ALU_SIZE * 2;
    assign load_wakeup_io.ready = {`LOAD_PIPELINE{1'b1}};
`ifdef RVF
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign fmisc_wakeup_io.ready[`FMISC_SIZE+i] = ~load_wakeup_io.en[i];
        assign int_wakeupBus.en[`ALU_SIZE+i] = load_wakeup_io.en[i] | fmisc_wakeup_io.en[`FMISC_SIZE+i];
        assign int_wakeupBus.we[`ALU_SIZE+i] = load_wakeup_io.en[i] ? load_wakeup_io.we[i] : fmisc_wakeup_io.we[`FMISC_SIZE+i];
        assign int_wakeupBus.rd[`ALU_SIZE+i] = load_wakeup_io.en[i] ? load_wakeup_io.rd[i] : fmisc_wakeup_io.rd[`FMISC_SIZE+i];
    end
endgenerate
`else
    assign int_wakeupBus.en[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.en[`LOAD_PIPELINE-1: 0];
    assign int_wakeupBus.we[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.we[`LOAD_PIPELINE-1: 0];
    assign int_wakeupBus.rd[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.rd[`LOAD_PIPELINE-1: 0];
`endif

`ifdef RVF
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign fmisc_wakeup_io.ready[i] = ~load_wakeup_io.en[`LOAD_PIPELINE+i];
        assign fp_wakeupBus.en[i] = load_wakeup_io.en[`LOAD_PIPELINE+i] | fmisc_wakeup_io.en[i];
        assign fp_wakeupBus.we[i] = load_wakeup_io.en[`LOAD_PIPELINE+i] ? load_wakeup_io.we[`LOAD_PIPELINE+i] : fmisc_wakeup_io.we[i];
        assign fp_wakeupBus.rd[i] = load_wakeup_io.en[`LOAD_PIPELINE+i] ? load_wakeup_io.rd[`LOAD_PIPELINE+i] : fmisc_wakeup_io.rd[i];
    end
    for(genvar i=0; i<`FMA_SIZE; i++)begin
        assign fma_wakeup_io.ready[i] = 1'b1;
        assign fp_wakeupBus.en[`FMISC_SIZE+i] = fma_wakeup_io.en[i];
        assign fp_wakeupBus.we[`FMISC_SIZE+i] = fma_wakeup_io.we[i];
        assign fp_wakeupBus.rd[`FMISC_SIZE+i] = fma_wakeup_io.rd[i];
    end
endgenerate
`endif
endmodule