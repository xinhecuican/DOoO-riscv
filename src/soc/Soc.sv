`include "../defines/defines.svh"

module Soc(
    input logic core_clk,
    input logic rst,

    input logic uart_clk,
    input logic rxd,
    output logic txd
);
    AxiIO core_axi();
    AxiIO uart_axi();

    logic sync_rst_uart, sync_rst_core, uart_rst, core_rst;
    logic uart_rst_s1, core_rst_s1;
    SyncRst rst_core (clk, rst, sync_rst_core);
    SyncRst rst_uart (uart_clk, rst, sync_rst_uart);
    always_ff @(posedge clk)begin
        core_rst_s1 <= sync_rst_core;
        core_rst <= core_rst_s1;
    end
    always_ff @(posedge uart_clk)begin
        uart_rst_s1 <= sync_rst_uart;
        uart_rst <= uart_rst_s1;
    end

    CPUCore core(
        .clk(core_clk),
        .rst(core_rst),
        .axi(core_axi.master)
    );
    UartWrapper uart(
        .clk(uart_clk), 
        .rst(uart_rst),
        .axi(uart_axi.slave),
        .rxd(rxd),
        .txd(txd)
    );

    AxiCrossbar #(
        .SLAVE(1),
        .MASTER(1),
        .SLV_START(`PADDR_SIZE'h20000000),
        .SLV_END(`PADDR_SIZE'h200000004)
    ) crossbar (
        .clk(core_clk),
        .rst(core_rst),
        .mclk(uart_clk),
        .mrst(uart_rst),
        .sclk(core_clk),
        .srst(core_rst),
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