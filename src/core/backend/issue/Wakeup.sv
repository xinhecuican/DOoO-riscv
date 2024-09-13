`include "../../../defines/defines.svh"


/***
* 在指令写回的前两个周期进行wakeup
* Select & Wakeup,  Reg read, E1, wb
* Select, Reg read, E1 & Wakeup, E2, E3, wb
***/
module Wakeup(
    input logic clk,
    input logic rst,
    IssueWakeupIO.wakeup int_wakeup_io,
    IssueWakeupIO.wakeup load_wakeup_io,
    IssueWakeupIO.wakeup csr_wakeup_io,
`ifdef RVM
    IssueWakeupIO.wakeup mult_wakeup_io,
    IssueWakeupIO.wakeup div_wakeup_io,
`endif
    WakeupBus.wakeup wakeupBus,
    WriteBackBus wbBus
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
    assign wakeupBus.en[`ALU_SIZE-1: 0] = int_en;
    assign wakeupBus.we[`ALU_SIZE-1: 0] = int_we;
    assign wakeupBus.rd[`ALU_SIZE-1: 0] = int_rd;


    localparam LOAD_BASE = `ALU_SIZE * 2;
    assign load_wakeup_io.ready = {`LOAD_PIPELINE{1'b1}};
    assign wakeupBus.en[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.en;
    assign wakeupBus.we[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.we;
    assign wakeupBus.rd[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.rd;
endmodule