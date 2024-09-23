`include "../../../defines/defines.svh"

module RegfileWrapper(
    input logic clk,
    input logic rst,
    IssueRegIO.regfile int_reg_io,
    IssueRegIO.regfile load_reg_io,
    IssueRegIO.regfile store_reg_io,
    IssueRegIO.regfile csr_reg_io,
`ifdef RVM
    IssueRegIO.regfile mult_reg_io,
`endif
    input WriteBackBus wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_rat
`endif
);
    RegfileIO reg_io();
    logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata;


    logic `N(`ALU_SIZE) int_en;
    logic `ARRAY(`ALU_SIZE*2, `PREG_WIDTH) int_preg;
    assign int_reg_io.data = rdata[`ALU_SIZE * 2 - 1 : 0];

    assign csr_reg_io.ready = 1'b1;
    assign csr_reg_io.data[0] = rdata[0];
    assign csr_reg_io.data[1] = rdata[`ALU_SIZE];

    assign mult_reg_io.ready = 1'b1;
    assign mult_reg_io.data[0] = rdata[1];
    assign mult_reg_io.data[1] = rdata[`ALU_SIZE+1];
generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        if(i == 0)begin
            assign int_reg_io.ready[i] = ~csr_reg_io.en;
            always_ff @(posedge clk)begin
                int_en[i] <= int_reg_io.en[i] | csr_reg_io.en;
                int_preg[i] <= csr_reg_io.en ? csr_reg_io.preg[0] : int_reg_io.preg[i];
                int_preg[`ALU_SIZE+i] <= csr_reg_io.en ? csr_reg_io.preg[1] : int_reg_io.preg[`ALU_SIZE+i];
            end
        end
`ifdef RVM
        else if(i == 1)begin
            assign int_reg_io.ready[i] = ~mult_reg_io.en;
            always_ff @(posedge clk)begin
                int_en[i] <= int_reg_io.en[i] | mult_reg_io.en;
                int_preg[i] <= mult_reg_io.en ? mult_reg_io.preg[0] : int_reg_io.preg[i];
                int_preg[`ALU_SIZE+i] <= mult_reg_io.en ? mult_reg_io.preg[1] : int_reg_io.preg[`ALU_SIZE+i];
            end
        end
`endif
        else begin
            assign int_reg_io.ready[i] = 1'b1;
            always_ff @(posedge clk)begin
                int_en[i] <= int_reg_io.en[i];
                int_preg[i] <= int_reg_io.preg[i];
                int_preg[`ALU_SIZE+i] <= int_reg_io.preg[`ALU_SIZE+i];
            end
        end
    end
endgenerate
    assign reg_io.en[`ALU_SIZE-1: 0] = int_en;
    assign reg_io.en[`ALU_SIZE*2-1: `ALU_SIZE] = int_en;
    assign reg_io.raddr[`ALU_SIZE*2-1: 0] = int_preg;

    localparam LOAD_BASE = `ALU_SIZE * 2;
    logic `N(`LOAD_PIPELINE) load_en;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) load_preg;
    assign load_reg_io.ready = {`LOAD_PIPELINE{1'b1}};
    assign load_reg_io.data = rdata[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE];
    always_ff @(posedge clk)begin
        load_en <= load_reg_io.en;
        load_preg <= load_reg_io.preg;
    end
    assign reg_io.en[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_en;
    assign reg_io.raddr[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_preg;

    localparam STORE_BASE = `ALU_SIZE * 2 + `LOAD_PIPELINE;
    logic `N(`STORE_PIPELINE * 2) store_en;
    logic `ARRAY(`STORE_PIPELINE * 2, `PREG_WIDTH) store_preg;
    assign store_reg_io.ready = {`STORE_PIPELINE*2{1'b1}};
    assign store_reg_io.data = rdata[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE];
    always_ff @(posedge clk)begin
        store_en <= store_reg_io.en;
        store_preg <= store_reg_io.preg;
    end
    assign reg_io.en[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_en;
    assign reg_io.raddr[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_preg;

generate
    for(genvar i=0; i<`WB_SIZE; i++)begin
        assign reg_io.we[i] = wbBus.en[i] & wbBus.we[i];
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