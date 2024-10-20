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
`ifdef RVA
    IssueRegIO.regfile amo_reg_io,
`endif
    input WriteBackBus wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_rat
`endif
);
    logic `N(`REGFILE_READ_PORT) en;
    logic `ARRAY(`REGFILE_READ_PORT, `PREG_WIDTH) raddr;
    logic `ARRAY(`REGFILE_READ_PORT, `XLEN) reg_rdata;
    logic `N(`REGFILE_WRITE_PORT) we;
    logic `ARRAY(`REGFILE_WRITE_PORT, `PREG_WIDTH) waddr;
    logic `ARRAY(`REGFILE_WRITE_PORT, `XLEN) wdata;
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
    assign en[`ALU_SIZE-1: 0] = int_en;
    assign en[`ALU_SIZE*2-1: `ALU_SIZE] = int_en;
    assign raddr[`ALU_SIZE*2-1: 0] = int_preg;

    localparam LOAD_BASE = `ALU_SIZE * 2;
    logic `N(`LOAD_PIPELINE) load_en;
    logic `ARRAY(`LOAD_PIPELINE, `PREG_WIDTH) load_preg;
    assign load_reg_io.ready = {`LOAD_PIPELINE{1'b1}};
    assign load_reg_io.data = rdata[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE];
    always_ff @(posedge clk)begin
        load_en <= load_reg_io.en;
        load_preg <= load_reg_io.preg;
    end
    assign en[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_en;
    assign raddr[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_preg;

    localparam STORE_BASE = `ALU_SIZE * 2 + `LOAD_PIPELINE;
    logic `N(`STORE_PIPELINE * 2) store_en;
    logic `ARRAY(`STORE_PIPELINE * 2, `PREG_WIDTH) store_preg;
    always_comb begin
        store_reg_io.ready = {`STORE_PIPELINE*2{1'b1}};
        en[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_en;
`ifdef RVA
        store_reg_io.ready[`STORE_PIPELINE] = ~amo_reg_io.en[0];
        store_reg_io.ready[`STORE_PIPELINE+1] = ~amo_reg_io.en[0];
`endif
    end
    assign store_reg_io.data = rdata[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE];
`ifdef RVA
    assign amo_reg_io.data[0] = rdata[`STORE_PIPELINE+STORE_BASE];
    assign amo_reg_io.data[1] = rdata[`STORE_PIPELINE+STORE_BASE+1];
`endif
    always_ff @(posedge clk)begin
        store_en <= store_reg_io.en;
        store_preg <= store_reg_io.preg;
`ifdef RVA
        store_en[`STORE_PIPELINE] <= amo_reg_io.en[0] | store_reg_io.en[`STORE_PIPELINE];
        store_en[`STORE_PIPELINE+1] <= amo_reg_io.en[0] | store_reg_io.en[`STORE_PIPELINE+1];
        store_preg[`STORE_PIPELINE] <= amo_reg_io.en[0] ? amo_reg_io.preg[0] : store_reg_io.preg[`STORE_PIPELINE];
        store_preg[`STORE_PIPELINE+1] <= amo_reg_io.en[0] ? amo_reg_io.preg[1] : store_reg_io.preg[`STORE_PIPELINE+1];
`endif
    end
    assign en[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_en;
    assign raddr[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE] = store_preg;

generate
    for(genvar i=0; i<`WB_SIZE; i++)begin
        assign we[i] = wbBus.en[i] & wbBus.we[i];
        assign waddr[i] = wbBus.rd[i];
        assign wdata[i] = wbBus.res[i];
    end
endgenerate

    Regfile regfile(
        .*,
        .rdata(reg_rdata)
    );
    Bypass bypass(.*);
endmodule