`include "../defines/defines.svh"

module Soc(
    input logic clk,
    input logic rst,

    input logic uart_clk,
    input logic rxd,
    output logic txd
);
    AxiIO core_axi();
    AxiIO uart_axi();
    CPUCore core(.*, .axi(core_axi.master));
    UartWrapper uart(.*, .clk(uart_clk), .axi(uart_axi.slave));

    AxiCrossbar #(
        .SLAVE(1),
        .MASTER(1),
        .SLV_START()
    ) crossbar (
        .clk(clk),
        .rst(rst),
        .mclk(uart_clk),
        .mrst(rst),
        .sclk(clk),
        .srst(rst),
        .m_mar(uart_axi.mar),
        .m_maw(uart_axi.maw),
        .m_mr (uart_axi.mr ),
        .m_mw (uart_axi.mw ),
        .m_mb (uart_axi.mb ),
        .m_sar(uart_axi.sar),
        .m_saw(uart_axi.saw),
        .m_sr (uart_axi.sr ),
        .m_sw (uart_axi.sw ),
        .m_sb (uart_axi.sb ),
        .s_mar(core_axi.mar),
        .s_maw(core_axi.maw),
        .s_mr (core_axi.mr ),
        .s_mw (core_axi.mw ),
        .s_mb (core_axi.mb ),
        .s_sar(core_axi.sar),
        .s_saw(core_axi.saw),
        .s_sr (core_axi.sr ),
        .s_sw (core_axi.sw ),
        .s_sb (core_axi.sb )
    );


endmodule