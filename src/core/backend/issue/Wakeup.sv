`include "../../../defines/defines.svh"

module Wakeup(
    input logic clk,
    input logic rst,
    IssueWakeupIO.wakeup int_wakeup_io,
    IssueWakeupIO.wakeup load_wakeup_io,
    IssueWakeupIO.wakeup store_wakeup_io,
`ifdef ZICSR
    IssueWakeupIO.wakeup csr_wakeup_io,
`endif
    WakeupBus.wakeup wakeupBus,
    WriteBackBus wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_rat
`endif
);
    RegfileIO reg_io();

    logic `N(`ALU_SIZE) int_en, int_we;
    logic `ARRAY(`ALU_SIZE, `PREG_WIDTH) int_rd;
    logic `ARRAY(`ALU_SIZE*2, `PREG_WIDTH) int_preg;

    assign int_wakeup_io.data = reg_io.rdata[`ALU_SIZE * 2 - 1: 0];
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        if(i == 1 && HAS_ZICSR)begin
            assign int_wakeup_io.ready[i] = ~csr_wakeup_io.en;
            always_ff @(posedge clk)begin
                int_en[i] <= int_wakeup_io.en[i] | csr_wakeup_io.en; 
                int_we[i] <= csr_wakeup_io.en ? csr_wakeup_io.rd != 0 : int_wakeup_io.rd != 0;
                int_rd[i] <= csr_wakeup_io.en ? csr_wakeup_io.rd : int_wakeup_io.rd;
                int_preg[i] <= csr_wakeup_io.en ? csr_wakeup_io.preg : int_wakeup_io.preg[i];
                int_preg[`ALU_SIZE+i] <= int_wakeup_io.preg[i];
            end
        end
        else begin
            assign int_wakeup_io.ready[i] = 1'b1;
            always_ff @(posedge clk)begin
                int_en[i] <= int_wakeup_io.en[i];
                int_we[i] <= int_wakeup_io.rd[i] != 0;
                int_rd[i] <= int_wakeup_io.rd[i];
                int_preg[i] <= int_wakeup_io.preg[i];
                int_preg[`ALU_SIZE+i] <= int_wakeup_io.preg[i];
            end
        end
    end
endgenerate
    assign wakeupBus.en[`ALU_SIZE-1: 0] = int_en;
    assign wakeupBus.rd[`ALU_SIZE-1: 0] = int_rd;
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign reg_io.en[i] = int_en[i];
        assign reg_io.en[`ALU_SIZE+i] = int_en[i];
    end
endgenerate
    assign reg_io.raddr[`ALU_SIZE*2-1: 0] = int_preg;

`ifdef ZICSR
    assign csr_wakeup_io.ready = 1'b1;
    assign csr_wakeup_io.data = reg_io.rdata[1];
`endif


    localparam LOAD_BASE = `ALU_SIZE * 2;
    assign load_wakeup_io.ready = {`LOAD_PIPELINE{1'b1}};
    assign load_wakeup_io.data = reg_io.rdata[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE];
    assign reg_io.en[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_wakeup_io.en;
    assign reg_io.raddr[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_wakeup_io.preg;
    assign wakeupBus.en[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.en;
    assign wakeupBus.rd[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.rd;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign wakeupBus.we[`ALU_SIZE+i] = load_wakeup_io.rd[i] != 0;
    end
endgenerate

    localparam STORE_BASE = `ALU_SIZE * 2 + `LOAD_PIPELINE;
    assign store_wakeup_io.ready = {`STORE_PIPELINE{1'b1}};
    assign store_wakeup_io.data = reg_io.rdata[`STORE_PIPELINE+STORE_BASE-1: STORE_BASE];
    assign reg_io.en[`STORE_PIPELINE+STORE_BASE-1: STORE_BASE] = store_wakeup_io.en;
    assign reg_io.raddr[`STORE_PIPELINE+STORE_BASE-1: STORE_BASE] = store_wakeup_io.preg;


generate
    for(genvar i=0; i<`WB_SIZE; i++)begin
        assign reg_io.we[i] = wbBus.en[i] & (wbBus.rd[i] != 0);
        assign reg_io.waddr[i] = wbBus.rd[i];
        assign reg_io.wdata[i] = wbBus.res[i];
    end
endgenerate

    Regfile regfile(
        .clk(clk),
        .rst(rst),
        .io(reg_io),
        .*
    );
endmodule