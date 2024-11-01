`include "../../../defines/defines.svh"

module Bypass #(
    parameter WB_SIZE=1,
    parameter READ_PORT=1,
    parameter BYPASS_S0=1
)(
    input logic clk,
    input logic rst,
    input logic `ARRAY(READ_PORT, `PREG_WIDTH) raddr,
    input logic `ARRAY(READ_PORT, `XLEN) reg_rdata,
    input logic `N(WB_SIZE) wb_en,
    input logic `ARRAY(WB_SIZE, `PREG_WIDTH) wb_rd,
    input logic `ARRAY(WB_SIZE, `XLEN) wb_res,
    output logic `ARRAY(READ_PORT, `XLEN) rdata
);
    logic `ARRAY(READ_PORT, `PREG_WIDTH) raddr_n;
    always_ff @(posedge clk)begin
        raddr_n <= raddr;
    end
    // TODO: 优化时序，在wbBus的前一周期获得en和rd,然后下一周期选择data
    // 需要注意redirect情况
    // load不需要bypass
generate
    for(genvar i=0; i<READ_PORT; i++)begin
        logic `N(WB_SIZE) eq, eq_pre, eq0;
        logic `N(`XLEN) data, data_pre, data0;

        always_ff @(posedge clk)begin
            eq0 <= eq_pre;
            data0 <= data_pre;
        end
            ParallelEQ #(
                .WIDTH(`PREG_WIDTH),
                .RADIX(WB_SIZE),
                .DATA_WIDTH(`XLEN)
            ) parallel_eq_bypass0(
                .origin(raddr[i]),
                .cmp_en(wb_en),
                .cmp(wb_rd),
                .data_i(wb_res),
                .eq(eq_pre),
                .data_o(data_pre)
            );
        if(BYPASS_S0)begin
            ParallelEQ #(
                .WIDTH(`PREG_WIDTH),
                .RADIX(WB_SIZE),
                .DATA_WIDTH(`XLEN)
            ) parallel_eq_bypass(
                .origin(raddr_n[i]),
                .cmp_en(wb_en),
                .cmp(wb_rd),
                .data_i(wb_res),
                .eq(eq),
                .data_o(data)
            );
            assign rdata[i] = |eq0 ? data0 : 
                    |eq ? data : reg_rdata[i];
        end
        else begin
            assign rdata[i] = |eq0 ? data0 : reg_rdata[i];
        end
    end
endgenerate
endmodule