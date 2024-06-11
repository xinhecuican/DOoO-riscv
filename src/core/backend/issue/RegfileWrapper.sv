`include "../../../defines/defines.svh"

module RegfileWrapper(
    input logic clk,
    input logic rst,
    IssueRegfileIO.regfile int_reg_io,
    IssueRegfileIO.regfile load_reg_io,
    IssueRegfileIO.regfile store_reg_io,
    WriteBackBus wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_rat
`endif
);
    RegfileIO reg_io();
    Regfile regfile(
        .clk(clk),
        .rst(rst),
        .io(reg_io),
        .*
    );

generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign reg_io.en[i] = int_reg_io.en[i];
        assign reg_io.en[`ALU_SIZE+i] = int_reg_io.en[i];
        assign reg_io.raddr[i] = int_reg_io.preg[i];
        assign reg_io.raddr[`ALU_SIZE+i] = int_reg_io.preg[`ALU_SIZE+i];
        
        assign int_reg_io.data[i] = reg_io.rdata[i];
        assign int_reg_io.data[`ALU_SIZE+i] = reg_io.rdata[`ALU_SIZE+i];
    end
    localparam LOAD_BASE = `ALU_SIZE * 2;
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign reg_io.en[LOAD_BASE+i] = load_reg_io.en[i];
        assign reg_io.raddr[LOAD_BASE+i] = load_reg_io.preg[i];
        assign load_reg_io.data[i] = reg_io.rdata[LOAD_BASE+i];
    end
    localparam STORE_BASE = LOAD_BASE + `LOAD_PIPELINE;
    for(genvar i=0; i<`STORE_PIPELINE * 2; i++)begin
        assign reg_io.en[STORE_BASE+i] = store_reg_io.en[i];
        assign reg_io.raddr[STORE_BASE+i] = store_reg_io.preg[i];
        assign store_reg_io.data[i] = reg_io.rdata[STORE_BASE+i];
    end
    for(genvar i=0; i<`WB_SIZE; i++)begin
        assign reg_io.we[i] = wbBus.en[i] & (wbBus.rd[i] != 0);
        assign reg_io.waddr[i] = wbBus.rd[i];
        assign reg_io.wdata[i] = wbBus.res[i];
    end
endgenerate

endmodule