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
    IssueWakeupIO.wakeup store_wakeup_io,
    IssueWakeupIO.wakeup csr_wakeup_io,
    WakeupBus.wakeup wakeupBus,
    WriteBackBus wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_rat
`endif
);
    RegfileIO reg_io();
    logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata;

    logic `N(`ALU_SIZE) int_en, int_we, int_en_n;
    logic `ARRAY(`ALU_SIZE, `PREG_WIDTH) int_rd;
    logic `ARRAY(`ALU_SIZE*2, `PREG_WIDTH) int_preg;

    assign int_wakeup_io.data = rdata[`ALU_SIZE * 2 - 1: 0];
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        if(i == 1)begin
            assign int_wakeup_io.ready[i] = ~csr_wakeup_io.en;
            always_ff @(posedge clk)begin
                int_en_n[i] <= int_en[i];
                int_preg[i] <= csr_wakeup_io.en ? csr_wakeup_io.preg : int_wakeup_io.preg[i];
                int_preg[`ALU_SIZE+i] <= int_wakeup_io.preg[`ALU_SIZE+i];
            end
            assign int_en[i] = int_wakeup_io.en[i] | csr_wakeup_io.en; 
            assign int_we[i] = csr_wakeup_io.en ? csr_wakeup_io.rd != 0 : int_wakeup_io.rd[i] != 0;
            assign int_rd[i] = csr_wakeup_io.en ? csr_wakeup_io.rd : int_wakeup_io.rd[i];
        end
        else begin
            assign int_wakeup_io.ready[i] = 1'b1;
            always_ff @(posedge clk)begin
                int_en_n[i] <= int_en[i];
                int_preg[i] <= int_wakeup_io.preg[i];
                int_preg[`ALU_SIZE+i] <= int_wakeup_io.preg[`ALU_SIZE+i];
            end
            assign int_en[i] = int_wakeup_io.en[i];
            assign int_we[i] = int_wakeup_io.rd[i] != 0;
            assign int_rd[i] = int_wakeup_io.rd[i];
        end
    end
endgenerate
    assign wakeupBus.en[`ALU_SIZE-1: 0] = int_en;
    assign wakeupBus.we[`ALU_SIZE-1: 0] = int_we;
    assign wakeupBus.rd[`ALU_SIZE-1: 0] = int_rd;
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign reg_io.en[i] = int_en_n[i];
        assign reg_io.en[`ALU_SIZE+i] = int_en_n[i];
    end
endgenerate
    assign reg_io.raddr[`ALU_SIZE*2-1: 0] = int_preg;

    assign csr_wakeup_io.ready = 1'b1;
    assign csr_wakeup_io.data = rdata[1];


    localparam LOAD_BASE = `ALU_SIZE * 2;
    logic `N(`LOAD_PIPELINE) load_en, load_we, load_en_n;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) load_preg;
    assign load_wakeup_io.ready = {`LOAD_PIPELINE{1'b1}};
    assign load_wakeup_io.data = rdata[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE];
    always_ff @(posedge clk)begin
        load_en <= load_wakeup_io.en;
        load_preg <= load_wakeup_io.preg;
    end
    assign reg_io.en[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_en;
    assign reg_io.raddr[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_preg;
    assign wakeupBus.en[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.wakeup_en;
    assign wakeupBus.we[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_we;
    assign wakeupBus.rd[`LOAD_PIPELINE+`ALU_SIZE-1: `ALU_SIZE] = load_wakeup_io.rd;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign load_we[i] = load_wakeup_io.rd[i] != 0;
    end
endgenerate

    localparam STORE_BASE = `ALU_SIZE * 2 + `LOAD_PIPELINE;
    logic `N(`STORE_PIPELINE * 2) store_en;
    logic `ARRAY(`STORE_PIPELINE * 2, `PREG_WIDTH) store_preg;
    assign store_wakeup_io.ready = {`STORE_PIPELINE*2{1'b1}};
    assign store_wakeup_io.data = rdata[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE];
    always_ff @(posedge clk)begin
        store_en <= store_wakeup_io.en;
        store_preg <= store_wakeup_io.preg;
    end
    assign reg_io.en[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_en;
    assign reg_io.raddr[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_preg;


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
    Bypass bypass(.*);
endmodule