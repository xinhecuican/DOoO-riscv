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
`ifdef RVF
    input WriteBackBus fp_wbBus,
    IssueRegIO.regfile fmisc_reg_io,
    IssueRegIO.regfile fma_reg_io,
`endif
    input WriteBackBus int_wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_int_rat
`ifdef RVF
    ,DiffRAT.regfile diff_fp_rat
`endif
`endif
);
    logic `N(`INT_REG_READ_PORT) en;
    logic `ARRAY(`INT_REG_READ_PORT, `PREG_WIDTH) raddr;
    logic `ARRAY(`INT_REG_READ_PORT, `XLEN) reg_rdata;
`ifdef RVF
    logic `N(`FP_REG_READ_PORT) fp_en;
    logic `ARRAY(`FP_REG_READ_PORT, `PREG_WIDTH) fp_raddr;
    logic `ARRAY(`FP_REG_READ_PORT, `XLEN) fp_reg_rdata, fp_rdata;
    logic `N(`FP_REG_WRITE_PORT) fp_we;
    logic `ARRAY(`FP_REG_WRITE_PORT, `PREG_WIDTH) fp_waddr;
    logic `ARRAY(`FP_REG_WRITE_PORT, `XLEN) fp_wdata;
`endif
    logic `N(`INT_REG_WRITE_PORT) we;
    logic `ARRAY(`INT_REG_WRITE_PORT, `PREG_WIDTH) waddr;
    logic `ARRAY(`INT_REG_WRITE_PORT, `XLEN) wdata;
    logic `ARRAY(`INT_REG_READ_PORT, `XLEN) rdata;


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
`ifdef RVF
    `CONSTRAINT(FMISC_SIZE, `LOAD_PIPELINE, "fmisc's read port must smaller than load")
generate
    for(genvar i=0; i<`FMISC_SIZE; i++)begin
        always_ff @(posedge clk)begin
            load_en[i] <= load_reg_io.en[i] | fmisc_reg_io.en[`FMISC_SIZE+i];
            load_preg[i] <= load_reg_io.en[i] ? load_reg_io.preg[i] : fmisc_reg_io.preg[i+`FMISC_SIZE*2];
        end
        assign en[LOAD_BASE+i] = load_en[i];
        assign raddr[LOAD_BASE+i] = load_preg[i];
        assign fmisc_reg_io.ready[`FMISC_SIZE+i] = ~load_reg_io.en[i];
        assign fmisc_reg_io.data[`FMISC_SIZE*2+i] = rdata[i+LOAD_BASE];
    end
endgenerate
`else
    always_ff @(posedge clk)begin
        load_en <= load_reg_io.en;
        load_preg <= load_reg_io.preg;
    end
    assign en[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_en;
    assign raddr[`LOAD_PIPELINE+LOAD_BASE-1: LOAD_BASE] = load_preg;
`endif

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
    assign store_reg_io.data[0 +: `STORE_PIPELINE * 2] = rdata[`STORE_PIPELINE*2+STORE_BASE-1: STORE_BASE];
`ifdef RVA
    assign amo_reg_io.data[0] = rdata[`STORE_PIPELINE+STORE_BASE];
    assign amo_reg_io.data[1] = rdata[`STORE_PIPELINE+STORE_BASE+1];
`endif
    always_ff @(posedge clk)begin
        store_en <= store_reg_io.en[`STORE_PIPELINE * 2-1: 0];
        store_preg <= store_reg_io.preg[`STORE_PIPELINE * 2-1: 0];
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
        assign we[i] = int_wbBus.en[i] & int_wbBus.we[i];
        assign waddr[i] = int_wbBus.rd[i];
        assign wdata[i] = int_wbBus.res[i];
    end
endgenerate

    Regfile #(
        `INT_REG_READ_PORT,
        `INT_REG_WRITE_PORT,
        `INT_PREG_SIZE
    ) int_regfile(
        .*,
        .rdata(reg_rdata)
`ifdef DIFFTEST
        ,.diff_rat(diff_int_rat)
`endif
    );
    Bypass #(
        `ALU_SIZE, `INT_REG_READ_PORT
    ) bypass(
        .*,
        .wb_en(int_wbBus.en[`ALU_SIZE-1: 0] & int_wbBus.we[`ALU_SIZE-1: 0]),
        .wb_rd(int_wbBus.rd[`ALU_SIZE-1: 0]),
        .wb_res(int_wbBus.res[`ALU_SIZE-1: 0])
    );

`ifdef RVF
    logic `N(`STORE_PIPELINE) fp_store_en;
    logic `ARRAY(`STORE_PIPELINE, `PREG_WIDTH) fp_store_preg;
    always_ff @(posedge clk)begin
        fp_store_en <= store_reg_io.en[`STORE_PIPELINE * 2 +: `STORE_PIPELINE];
        fp_store_preg <= store_reg_io.preg[`STORE_PIPELINE * 2 +: `STORE_PIPELINE];
    end
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        always_ff @(posedge clk)begin
            fp_store_en[i] <= store_reg_io.en[`STORE_PIPELINE+i] | fmisc_reg_io.en[i];
            fp_store_preg[i] <= store_reg_io.en[`STORE_PIPELINE+i] ? store_reg_io.preg[`STORE_PIPELINE+i] : fmisc_reg_io.preg[i];
        end
        assign fp_en[i] = fp_store_en[i];
        assign fp_raddr[i] = fp_store_preg[i];
        assign fmisc_reg_io.ready[i] = ~store_reg_io.en[`STORE_PIPELINE+i];
    end
    for(genvar i=`STORE_PIPELINE; i<`FMISC_SIZE; i++)begin
        logic fmisc_en;
        logic `N(`PREG_WIDTH) fmisc_preg;
        always_ff @(posedge clk)begin
            fmisc_en <= fmisc_reg_io.en[i];
            fmisc_preg <= fmisc_reg_io.preg[i];
        end
        assign fp_en[i] = fmisc_en;
        assign fp_raddr[i] = fmisc_preg;
        assign fmisc_reg_io.ready[i] = 1'b1;
    end
endgenerate
    logic `N(`FMISC_SIZE) fmisc_rs2_en;
    logic `ARRAY(`FMISC_SIZE, `PREG_WIDTH) fmisc_rs2;
    always_ff @(posedge clk)begin
        fmisc_rs2_en <= fmisc_reg_io.en[0 +: `FMISC_SIZE];
        fmisc_rs2 <= fmisc_reg_io.preg[`FMISC_SIZE +: `FMISC_SIZE];
    end
    assign fp_en[`FMISC_SIZE +: `FMISC_SIZE] = fmisc_rs2_en;
    assign fp_raddr[`FMISC_SIZE +: `FMISC_SIZE] = fmisc_rs2;
    assign store_reg_io.data[`STORE_PIPELINE*2 +: `STORE_PIPELINE] = fp_rdata[0 +: `STORE_PIPELINE];
    assign fmisc_reg_io.data[0 +: `FMISC_SIZE * 2] = fp_rdata[0 +: `FMISC_SIZE * 2];

    logic `N(`FMA_SIZE) fma_en;
    logic `ARRAY(`FMA_SIZE * 3, `PREG_WIDTH) fma_src;
    always_ff @(posedge clk)begin
        fma_en <= fma_reg_io.en;
        fma_src <= fma_reg_io.preg;
    end
    localparam FMA_BASE = `FMISC_SIZE*2;
    assign fp_en[FMA_BASE +: `FMA_SIZE*3] = {3{fma_en}};
    assign fp_raddr[FMA_BASE +: `FMA_SIZE*3] = fma_src;
    assign fma_reg_io.ready = {`FMA_SIZE{1'b1}};
    assign fma_reg_io.data = fp_rdata[FMA_BASE +: `FMA_SIZE * 3];
    
generate
    for(genvar i=0; i<`FP_WB_SIZE; i++)begin
        assign fp_we[i] = fp_wbBus.en[i] & fp_wbBus.we[i];
        assign fp_waddr[i] = fp_wbBus.rd[i];
        assign fp_wdata[i] = fp_wbBus.res[i];
    end
endgenerate
    Regfile #(
        .READ_PORT(`FP_REG_READ_PORT),
        .WRITE_PORT(`FP_REG_WRITE_PORT),
        .FP(1),
        .PREG_SIZE(`FP_PREG_SIZE)
    ) fp_regfile(
        .*,
        .en(fp_en),
        .raddr(fp_raddr),
        .rdata(fp_reg_rdata),
        .we(fp_we),
        .waddr(fp_waddr),
        .wdata(fp_wdata)
`ifdef DIFFTEST
        ,.diff_rat(diff_fp_rat)
`endif
    );

    Bypass #(
        `FMA_SIZE, `FP_REG_READ_PORT, 0
    ) fp_bypass (
        .clk,
        .rst,
        .raddr(fp_raddr),
        .reg_rdata(fp_reg_rdata),
        .wb_en(fp_wbBus.en[`FMISC_SIZE +: `FMA_SIZE] & fp_wbBus.we[`FMISC_SIZE +: `FMA_SIZE]),
        .wb_rd(fp_wbBus.rd[`FMISC_SIZE +: `FMA_SIZE]),
        .wb_res(fp_wbBus.res[`FMISC_SIZE +: `FMA_SIZE]),
        .rdata(fp_rdata)
    );
`endif
endmodule