`include "../../../defines/defines.svh"

module RegfileWrapper(
    input logic clk,
    input logic rst,
    IssueRegfileIO.regfile int_reg_io,
    WriteBackBus wbBus
);
    RegfileIO reg_io();
    Regfile regfile(
        .clk(clk),
        .rst(rst),
        .io(reg_io)
    );

generate
    for(genvar i=0; i<`ALU_SIZE; i++)begin
        assign reg_io.en[i*2] = int_reg_io.en[i];
        assign reg_io.en[i*2+1] = int_reg_io.en[i];
        assign reg_io.raddr[i*2] = int_reg_io.rs1[i];
        assign reg_io.raddr[i*2+1] = int_reg_io.rs2[i];
        
        assign int_reg_io.rs1_data[i] = reg_io.rdata[i*2];
        assign int_reg_io.rs2_data[i] = reg_io.rdata[i*2+1];
    end
    for(genvar i=0; i<`WB_SIZE; i++)begin
        assign reg_io.we[i] = wbBus.en[i] & (wbBus.rd[i] != 0);
        assign reg_io.waddr[i] = wbBus.rd[i];
        assign reg_io.wdata[i] = wbBus.res[i];
    end
endgenerate

endmodule