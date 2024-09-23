`include "../../../defines/defines.svh"

module Bypass(
    input logic clk,
    input logic rst,
    RegfileIO.bypass reg_io,
    input WriteBackBus wbBus,
    output logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata
);
    logic `ARRAY(`REGFILE_READ_PORT, `PREG_WIDTH) raddr_n;
    always_ff @(posedge clk)begin
        raddr_n <= reg_io.raddr;
    end
    // TODO: 优化时序，在wbBus的前一周期获得en和rd,然后下一周期选择data
    // 需要注意redirect情况
generate
    for(genvar i=0; i<`REGFILE_READ_PORT; i++)begin
        logic `N(`WB_SIZE) eq, eq_pre, eq0;
        logic `N(`XLEN) data, data_pre, data0;
        ParallelEQ #(
            .WIDTH(`PREG_WIDTH),
            .RADIX(`WB_SIZE),
            .DATA_WIDTH(`XLEN)
        ) parallel_eq_bypass(
            .origin(raddr_n[i]),
            .cmp_en(wbBus.en & wbBus.we),
            .cmp(wbBus.rd),
            .data_i(wbBus.res),
            .eq(eq),
            .data_o(data)
        );
        ParallelEQ #(
            .WIDTH(`PREG_WIDTH),
            .RADIX(`WB_SIZE),
            .DATA_WIDTH(`XLEN)
        ) parallel_eq_bypass0(
            .origin(reg_io.raddr[i]),
            .cmp_en(wbBus.en & wbBus.we),
            .cmp(wbBus.rd),
            .data_i(wbBus.res),
            .eq(eq_pre),
            .data_o(data_pre)
        );
        always_ff @(posedge clk)begin
            eq0 <= eq_pre;
            data0 <= data_pre;
        end
        assign rdata[i] = |eq0 ? data0 : 
                          |eq ? data : reg_io.rdata[i];
    end
endgenerate
endmodule