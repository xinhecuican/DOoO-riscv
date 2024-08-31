`include "../defines/devices.svh"
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
    output [64*4-1: 0]  io_memAXI_0_w_bits_data,
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
    input [64*4-1: 0]   io_memAXI_0_r_bits_data,
    input           io_memAXI_0_r_bits_last,
    input [7: 0]    io_memAXI_0_r_bits_id
);
    logic sync_rst_peri, sync_rst_core, core_rst, peri_rst;
    logic peri_rst_s1, core_rst_s1;
    SyncRst rst_core (clock, reset, sync_rst_core);
    SyncRst rst_peri (clock, reset, sync_rst_peri);
    always_ff @(posedge clock)begin
        core_rst_s1 <= sync_rst_core;
        core_rst <= core_rst_s1;
    end
    always_ff @(posedge clock)begin
        peri_rst_s1 <= sync_rst_peri;
        peri_rst <= peri_rst_s1;
    end

    AxiIO mem_axi();
    AxiIO core_axi();
    AxiIO peri_axi();

    CPUCore core(
        .clk(clock),
        .rst(core_rst),
        .axi(core_axi.master)
    );
    localparam [2: 0] AXI_SLAVE_NUM = 2;
    localparam xbar_cfg_t crossbar_cfg = '{
        NoSlvPorts: 1,
        NoMstPorts: AXI_SLAVE_NUM,
        MaxMstTrans: 1,
        MaxSlvTrans: 1,
        FallThrough: 0,
        LatencyMode: 0,
        PipelineStages: 1,
        AxiIdWidthSlvPorts: `AXI_ID_W,
        UniqueIds: 1,
        AxiAddrWidth: `PADDR_SIZE,
        AxiDataWidth: `XLEN,
        NoAddrRules: AXI_SLAVE_NUM,
        default: 0
    };

    AxiReq slv_req_i;
    AxiResp slv_resp_o;
    AxiReq `N(AXI_SLAVE_NUM) mst_req_o;
    AxiResp `N(AXI_SLAVE_NUM) mst_resp_i;
    addr_rule_t `N(AXI_SLAVE_NUM) addr_map;

    `AXI_REQ_ASSIGN(slv_req_i, core_axi)
    `AXI_RESP_ASSIGN(slv_resp_o, core_axi)
    `AXI_REQ_RECEIVE(mst_req_o[0], peri_axi)
    `AXI_RESP_RECEIVE(mst_resp_i[0], peri_axi)
    `AXI_REQ_RECEIVE(mst_req_o[1], mem_axi)
    `AXI_RESP_RECEIVE(mst_resp_i[1], mem_axi)

    assign addr_map[0] = '{
        idx: 0,
        start_addr: `PERIPHERAL_START,
        end_addr: `PERIPHERAL_END
    };
    assign addr_map[1] = '{
        idx: 1,
        start_addr: `MEM_START,
        end_addr: `MEM_END
    };

    axi_xbar #(
        .Cfg(crossbar_cfg),
        .slv_aw_chan_t(AxiMAW),
        .mst_aw_chan_t(AxiMAW),
        .w_chan_t(AxiMW),
        .slv_b_chan_t(AxiSB),
        .mst_b_chan_t(AxiSB),
        .slv_ar_chan_t(AxiMAR),
        .mst_ar_chan_t(AxiMAR),
        .slv_r_chan_t(AxiSR),
        .mst_r_chan_t(AxiSR),
        .slv_req_t(AxiReq),
        .slv_resp_t(AxiResp),
        .mst_req_t(AxiReq),
        .mst_resp_t(AxiResp),
        .rule_t(addr_rule_t)
    )crossbar(
        .clk_i(clock),
        .rst_ni(~core_rst),
        .test_i(1'b0),
        .slv_ports_req_i(slv_req_i),
        .slv_ports_resp_o(slv_resp_o),
        .mst_ports_req_o(mst_req_o),
        .mst_ports_resp_i(mst_resp_i),
        .addr_map_i(addr_map),
        .en_default_mst_port_i(0),
        .default_mst_port_i(0)
    );

    /* verilator lint_off UNOPTFLAT */
    AxiReq peri_req;
    AxiResp peri_resp;
    AxiLReq peri_lreq;
    AxiLResp peri_lresp;
    ApbReq uart_req;
    ApbResp uart_resp;
    addr_rule_t `N(`PERIPHERAL_SIZE) map_rules;

    assign map_rules[0] = '{
        idx: 0,
        start_addr: `UART_START,
        end_addr: `UART_END
    };

    `AXI_REQ_ASSIGN(peri_req, peri_axi)
    `AXI_RESP_ASSIGN(peri_resp, peri_axi)

    axi_to_axi_lite #(
        .AxiAddrWidth(`PADDR_SIZE),
        .AxiDataWidth(`XLEN),
        .AxiIdWidth(`AXI_ID_W),
        .AxiUserWidth(1),
        .AxiMaxWriteTxns(32'd16),
        .AxiMaxReadTxns(32'd16),
        .full_req_t(AxiReq),
        .full_resp_t(AxiResp),
        .lite_req_t(AxiLReq),
        .lite_resp_t(AxiLResp)
    ) axi_to_lite_inst(
        .clk_i(clock),
        .rst_ni(~peri_rst),
        .test_i(1'b0),
        .slv_req_i(peri_req),
        .slv_resp_o(peri_resp),
        .mst_req_o(peri_lreq),
        .mst_resp_i(peri_lresp)
    );

    axi_lite_to_apb #(
        .NoApbSlaves(`PERIPHERAL_SIZE),
        .NoRules(`PERIPHERAL_SIZE),
        .AddrWidth(`PADDR_SIZE),
        .DataWidth(`XLEN),
        .axi_lite_req_t(AxiLReq),
        .axi_lite_resp_t(AxiLResp),
        .apb_req_t(ApbReq),
        .apb_resp_t(ApbResp),
        .rule_t(addr_rule_t)
    )axi_to_apb_inst (
        .clk_i(clock),
        .rst_ni(~peri_rst),
        .axi_lite_req_i(peri_lreq),
        .axi_lite_resp_o(peri_lresp),
        .apb_req_o(uart_req),
        .apb_resp_i(uart_resp),
        .addr_map_i(map_rules)
    );
    ApbIO uart_io();
    assign uart_io.req = uart_req;
    assign uart_resp = uart_io.resp;
    SimUart uart(
        .clk(clock),
        .rst(peri_rst),
        .apb(uart_io),
        .io_uart_out_valid(io_uart_out_valid),
        .io_uart_out_ch(io_uart_out_ch),
        .io_uart_in_valid(io_uart_in_valid),
        .io_uart_in_ch(io_uart_in_ch)
    );

`ifdef DRAMSIM3
    assign mem_axi.aw_ready = io_memAXI_0_aw_ready;
    assign io_memAXI_0_aw_valid = mem_axi.aw_valid;
    assign io_memAXI_0_aw_bits_addr = mem_axi.maw.addr;
    assign io_memAXI_0_aw_bits_prot = mem_axi.maw.prot;
    assign io_memAXI_0_aw_bits_id = mem_axi.maw.id;
    assign io_memAXI_0_aw_bits_len = mem_axi.maw.len;
    assign io_memAXI_0_aw_bits_burst = mem_axi.maw.burst;
    assign io_memAXI_0_aw_bits_size = mem_axi.maw.size;
    assign io_memAXI_0_aw_bits_lock = mem_axi.maw.lock;
    assign io_memAXI_0_aw_bits_cache = mem_axi.maw.cache;
    assign io_memAXI_0_aw_bits_qos = mem_axi.maw.qos;

    assign mem_axi.w_ready = io_memAXI_0_w_ready;
    assign io_memAXI_0_w_valid = mem_axi.w_valid;
    assign io_memAXI_0_w_bits_data = mem_axi.mw.data;
    assign io_memAXI_0_w_bits_strb = mem_axi.mw.strb;
    assign io_memAXI_0_w_bits_last = mem_axi.mw.last;

    assign io_memAXI_0_b_ready = mem_axi.b_ready;
    assign mem_axi.b_valid = io_memAXI_0_b_valid;
    assign mem_axi.sb.resp = io_memAXI_0_b_bits_resp;
    assign mem_axi.sb.id = io_memAXI_0_b_bits_id;

    assign mem_axi.ar_ready = io_memAXI_0_ar_ready;
    assign io_memAXI_0_ar_valid = mem_axi.ar_valid;
    assign io_memAXI_0_ar_bits_addr = mem_axi.mar.addr;
    assign io_memAXI_0_ar_bits_prot = mem_axi.mar.prot;
    assign io_memAXI_0_ar_bits_id = mem_axi.mar.id;
    assign io_memAXI_0_ar_bits_len = mem_axi.mar.len;
    assign io_memAXI_0_ar_bits_size = mem_axi.mar.size;
    assign io_memAXI_0_ar_bits_burst = mem_axi.mar.burst;
    assign io_memAXI_0_ar_bits_lock = mem_axi.mar.lock;
    assign io_memAXI_0_ar_bits_cache = mem_axi.mar.cache;
    assign io_memAXI_0_ar_bits_qos = mem_axi.mar.qos;

    assign io_memAXI_0_r_ready = mem_axi.r_ready;
    assign mem_axi.r_valid = io_memAXI_0_r_valid;
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