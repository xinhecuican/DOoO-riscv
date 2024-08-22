`include "../defines/defines.svh"
`include "../defines/devices.svh"
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
    input  [7:0]  io_uart_in_ch,

    input           io_memAXI_0_aw_ready,
    output          io_memAXI_0_aw_valid,
    output [63: 0]  io_memAXI_0_aw_bits_addr,
    output [2: 0]   io_memAXI_0_aw_bits_prot,
    output [7: 0]   io_memAXI_0_aw_bits_id,
    output [7: 0]   io_memAXI_0_aw_bits_len,
    output [1: 0]   io_memAXI_0_aw_bits_burst,
    output [2: 0]   io_memAXI_0_aw_bits_size,
    output          io_memAXI_0_aw_bits_lock,
    output [3: 0]   io_memAXI_0_aw_bits_cache,
    output [3: 0]   io_memAXI_0_aw_bits_qos,

    input           io_memAXI_0_w_ready,
    output          io_memAXI_0_w_valid,
    output [63: 0]  io_memAXI_0_w_bits_data,
    output [7: 0]   io_memAXI_0_w_bits_strb,
    output          io_memAXI_0_w_bits_last,

    output          io_memAXI_0_b_ready,
    input           io_memAXI_0_b_valid,
    input [1: 0]    io_memAXI_0_b_bits_resp,
    input [7: 0]    io_memAXI_0_b_bits_id,

    input           io_memAXI_0_ar_ready,
    output          io_memAXI_0_ar_valid,
    output [63: 0]  io_memAXI_0_ar_bits_addr,
    output [2: 0]   io_memAXI_0_ar_bits_prot,
    output [7: 0]   io_memAXI_0_ar_bits_id,
    output [7: 0]   io_memAXI_0_ar_bits_len,
    output [3: 0]   io_memAXI_0_ar_bits_size,
    output [1: 0]   io_memAXI_0_ar_bits_burst,
    output          io_memAXI_0_ar_bits_lock,
    output [3: 0]   io_memAXI_0_ar_bits_cache,
    output [3: 0]   io_memAXI_0_ar_bits_qos,

    output          io_memAXI_0_r_ready,
    input           io_memAXI_0_r_valid,
    input [1: 0]    io_memAXI_0_r_bits_resp,
    input [63: 0]   io_memAXI_0_r_bits_data,
    input           io_memAXI_0_r_bits_last,
    input [7: 0]    io_memAXI_0_r_bits_id
);
    logic sync_rst_uart, sync_rst_core, uart_rst, core_rst;
    logic uart_rst_s1, core_rst_s1;
    SyncRst rst_core (clock, reset, sync_rst_core);
    SyncRst rst_uart (clock, reset, sync_rst_uart);
    always_ff @(posedge clock)begin
        core_rst_s1 <= sync_rst_core;
        core_rst <= core_rst_s1;
    end
    always_ff @(posedge clock)begin
        uart_rst_s1 <= sync_rst_uart;
        uart_rst <= uart_rst_s1;
    end

    AxiIO mem_axi();
    AxiIO core_axi();
    AxiIO uart_axi();

    CPUCore core(
        .clk(clock),
        .rst(core_rst),
        .axi(core_axi.master)
    );
    SimUart uart(
        .clk(clock), 
        .rst(uart_rst),
        .axi(uart_axi.slave),
        .io_uart_out_valid(io_uart_out_valid),
        .io_uart_out_ch(io_uart_out_ch),
        .io_uart_in_valid(io_uart_in_valid),
        .io_uart_in_ch(io_uart_in_ch)
    );

    AxiCrossbar #(
        .SLAVE(2),
        .MASTER(1),
        .SLV_START({`PADDR_SIZE'b0, `PADDR_SIZE'b0, `MEM_START, `UART_START}),
        .SLV_END({`PADDR_SIZE'b0, `PADDR_SIZE'b0, `MEM_END, `UART_END})
    ) crossbar (
        .clk(clock),
        .rst(core_rst),
        .sclk({clock, clock}),
        .srst({uart_rst, uart_rst}),
        .mclk(clock),
        .mrst(core_rst),
        .s_mar({mem_axi.mar, uart_axi.mar}),
        .s_maw({mem_axi.maw, uart_axi.maw}),
        .s_mr ({mem_axi.mr, uart_axi.mr}),
        .s_mw ({mem_axi.mw, uart_axi.mw}),
        .s_mb ({mem_axi.mb, uart_axi.mb}),
        .s_sar({mem_axi.sar, uart_axi.sar}),
        .s_saw({mem_axi.saw, uart_axi.saw}),
        .s_sr ({mem_axi.sr, uart_axi.sr}),
        .s_sw ({mem_axi.sw, uart_axi.sw}),
        .s_sb ({mem_axi.sb, uart_axi.sb}),
        .m_mar(core_axi.mar),
        .m_maw(core_axi.maw),
        .m_mr (core_axi.mr ),
        .m_mw (core_axi.mw ),
        .m_mb (core_axi.mb ),
        .m_sar(core_axi.sar),
        .m_saw(core_axi.saw),
        .m_sr (core_axi.sr ),
        .m_sw (core_axi.sw ),
        .m_sb (core_axi.sb )
    );

`ifdef DRAMSIM3
    assign io_memAXI_0_aw_ready = mem_axi.saw.ready;
    assign mem_axi.maw.valid = io_memAXI_0_aw_valid;
    assign mem_axi.maw.addr = io_memAXI_0_aw_bits_addr;
    assign mem_axi.maw.prot = io_memAXI_0_aw_bits_prot;
    assign mem_axi.maw.id = io_memAXI_0_aw_bits_id;
    assign mem_axi.maw.len = io_memAXI_0_aw_bits_len;
    assign mem_axi.maw.burst = io_memAXI_0_aw_bits_burst;
    assign mem_axi.maw.size = io_memAXI_0_aw_bits_size;
    assign mem_axi.maw.lock = io_memAXI_0_aw_bits_lock;
    assign mem_axi.maw.cache = io_memAXI_0_aw_bits_cache;
    assign mem_axi.maw.qos = io_memAXI_0_aw_bits_qos;

    assign io_memAXI_0_w_ready = mem_axi.sw.ready;
    assign mem_axi.mw.valid = io_memAXI_0_w_valid;
    assign mem_axi.mw.data = io_memAXI_0_w_bits_data;
    assign mem_axi.mw.strb = io_memAXI_0_w_bits_strb;
    assign mem_axi.mw.last = io_memAXI_0_w_bits_last;

    assign io_memAXI_0_b_ready = mem_axi.mb.ready;
    assign mem_axi.sb.valid = io_memAXI_0_b_valid;
    assign mem_axi.sb.resp = io_memAXI_0_b_bits_resp;
    assign mem_axi.sb.id = io_memAXI_0_b_bits_id;

    assign mem_axi.sar.ready = io_memAXI_0_ar_ready;
    assign io_memAXI_0_ar_valid = mem_axi.mar.valid;
    assign io_memAXI_0_ar_bits_addr = mem_axi.mar.addr;
    assign io_memAXI_0_ar_bits_prot = mem_axi.mar.prot;
    assign io_memAXI_0_ar_bits_id = mem_axi.mar.id;
    assign io_memAXI_0_ar_bits_len = mem_axi.mar.len;
    assign io_memAXI_0_ar_bits_size = mem_axi.mar.size;
    assign io_memAXI_0_ar_bits_burst = mem_axi.mar.burst;
    assign io_memAXI_0_ar_bits_lock = mem_axi.mar.lock;
    assign io_memAXI_0_ar_bits_cache = mem_axi.mar.cache;
    assign io_memAXI_0_ar_bits_qos = mem_axi.mar.qos;

    assign io_memAXI_0_r_ready = mem_axi.mr.ready;
    assign mem_axi.sr.valid = io_memAXI_0_r_valid;
    assign mem_axi.sr.resp = io_memAXI_0_r_bits_resp;
    assign mem_axi.sr.data = io_memAXI_0_r_bits_data;
    assign mem_axi.sr.last = io_memAXI_0_r_bits_last;
    assign mem_axi.sr.id = io_memAXI_0_r_bits_id;

`else
    SimRam ram(
        .clk(clock),
        .rst(reset),
        .axi(mem_axi.slave)
    );
`endif

import DLog::*;
    initial begin
        logLevel = io_logCtrl_log_level;
    end
    always_ff @(posedge clock)begin
        logValid <= cycleCnt > io_logCtrl_log_begin && cycleCnt < io_logCtrl_log_end;
    end
endmodule