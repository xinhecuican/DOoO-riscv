`include "../../../defines/defines.svh"

module Bypass(
    input logic clk,
    input logic rst,
    input logic `ARRAY(`REGFILE_READ_PORT, `PREG_WIDTH) raddr,
    input logic `ARRAY(`REGFILE_READ_PORT, `XLEN) reg_rdata,
    input WriteBackBus wbBus,
    output logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata
);
    logic `ARRAY(`REGFILE_READ_PORT, `PREG_WIDTH) raddr_n;
    always_ff @(posedge clk)begin
        raddr_n <= raddr;
    end
    // TODO: 优化时序，在wbBus的前一周期获得en和rd,然后下一周期选择data
    // 需要注意redirect情况
    // load不需要bypass
    logic `N(`WB_SIZE) wb_en;
    assign wb_en = wbBus.en & wbBus.we;
generate
    for(genvar i=0; i<`REGFILE_READ_PORT; i++)begin
        logic `N(`ALU_SIZE) eq, eq_pre, eq0;
        logic `N(`XLEN) data, data_pre, data0;
        ParallelEQ #(
            .WIDTH(`PREG_WIDTH),
            .RADIX(`ALU_SIZE),
            .DATA_WIDTH(`XLEN)
        ) parallel_eq_bypass(
            .origin(raddr_n[i]),
            .cmp_en(wb_en[`ALU_SIZE-1: 0]),
            .cmp(wbBus.rd[`ALU_SIZE-1: 0]),
            .data_i(wbBus.res[`ALU_SIZE-1: 0]),
            .eq(eq),
            .data_o(data)
        );
        ParallelEQ #(
            .WIDTH(`PREG_WIDTH),
            .RADIX(`ALU_SIZE),
            .DATA_WIDTH(`XLEN)
        ) parallel_eq_bypass0(
            .origin(raddr[i]),
            .cmp_en(wb_en[`ALU_SIZE-1: 0]),
            .cmp(wbBus.rd[`ALU_SIZE-1: 0]),
            .data_i(wbBus.res[`ALU_SIZE-1: 0]),
            .eq(eq_pre),
            .data_o(data_pre)
        );
        always_ff @(posedge clk)begin
            eq0 <= eq_pre;
            data0 <= data_pre;
        end
        assign rdata[i] = |eq0 ? data0 : 
                          |eq ? data : reg_rdata[i];
    end
endgenerate
endmodule