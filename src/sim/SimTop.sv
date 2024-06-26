`include "../defines/defines.svh"
module SimTop(
    input         clock,
    input         reset,
    input  [63:0] io_logCtrl_log_begin,
    input  [63:0] io_logCtrl_log_end,
    input  [63:0] io_logCtrl_log_level,
    input         io_perfInfo_clean,
    input         io_perfInfo_dump,
    output        io_uart_out_valid,
    output [7:0]  io_uart_out_ch,
    output        io_uart_in_valid,
    input  [7:0]  io_uart_in_ch
);
    AxiIO cpu_mem_io();

    CPUCore cpu(
        .clk(clock),
        .rst(reset),
        .axi(cpu_mem_io.master)
    );

    SimRam ram(
        .clk(clock),
        .rst(reset),
        .axi(cpu_mem_io.slave)
    );

import DLog::*;
    initial begin
        logLevel = io_logCtrl_log_level;
    end
    always_ff @(posedge clock)begin
        logValid <= cycleCnt > io_logCtrl_log_begin && cycleCnt < io_logCtrl_log_end;
    end
endmodule