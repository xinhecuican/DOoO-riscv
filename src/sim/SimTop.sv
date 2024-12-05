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

    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH+2, 1
    ) mem_axi();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH+2, 1
    ) core_axi();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH+2, 1
    ) peri_axi();
    AxiIO #(
        `PADDR_SIZE, `XLEN, `CORE_WIDTH+2, 1
    ) irq_axi();

    ClintIO clint_io();
    logic `N(`IRQ_NUM) irq_source;
    logic `N(`NUM_CORE) meip, seip;

    CPUCore core(
        .clk(clock),
        .rst(core_rst),
        .axi(core_axi.master),
        .clint_io(clint_io.cpu)
    );
    assign clint_io.meip = meip[0];
    assign clint_io.seip = seip[0];


    localparam [2: 0] AXI_SLAVE_NUM = 3;
    localparam xbar_cfg_t crossbar_cfg = '{
        NoSlvPorts: 1,
        NoMstPorts: AXI_SLAVE_NUM,
        MaxMstTrans: 1,
        MaxSlvTrans: 1,
        FallThrough: 0,
        LatencyMode: 10'b11111_11111,
        PipelineStages: 1,
        AxiIdWidthSlvPorts: `CORE_WIDTH+2,
        UniqueIds: 1,
        AxiAddrWidth: `PADDR_SIZE,
        AxiDataWidth: `XLEN,
        NoAddrRules: AXI_SLAVE_NUM,
        default: 0
    };
    typedef logic [`PADDR_SIZE-1: 0] addr_t;
    typedef logic user_t;
    typedef logic [`CORE_WIDTH+2-1: 0] id_t;
    typedef logic [`XLEN-1: 0] data_t;
    typedef logic [`XLEN/8-1: 0] strb_t;
    `AXI_TYPEDEF_AW_CHAN_T(AxiAW, addr_t, id_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T(AxiW, data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(AxiB, id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(AxiAR, addr_t, id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(AxiR, data_t, id_t, user_t)
    `AXI_TYPEDEF_REQ_T(AxiReq, AxiAW, AxiW, AxiAR)
    `AXI_TYPEDEF_RESP_T(AxiResp, AxiB, AxiR)
    `AXI_LITE_TYPEDEF_AW_CHAN_T(AxiLAW, addr_t)
    `AXI_LITE_TYPEDEF_W_CHAN_T(AxiLW, data_t, strb_t)
    `AXI_LITE_TYPEDEF_B_CHAN_T(AxiLB)
    `AXI_LITE_TYPEDEF_AR_CHAN_T(AxiLAR, addr_t)
    `AXI_LITE_TYPEDEF_R_CHAN_T(AxiLR, data_t)
    `AXI_LITE_TYPEDEF_REQ_T(AxiLReq, AxiLAW, AxiLW, AxiLAR)
    `AXI_LITE_TYPEDEF_RESP_T(AxiLResp, AxiLB, AxiLR)

    AxiReq slv_req_i;
    AxiResp slv_resp_o;
    AxiReq `N(AXI_SLAVE_NUM) mst_req_o;
    AxiResp `N(AXI_SLAVE_NUM) mst_resp_i;
    addr_rule_t `N(AXI_SLAVE_NUM) addr_map;

    `AXI_ASSIGN_TO_REQ(slv_req_i, core_axi)
    `AXI_ASSIGN_FROM_RESP(core_axi, slv_resp_o)
    `AXI_ASSIGN_FROM_REQ(peri_axi, mst_req_o[0])
    `AXI_ASSIGN_TO_RESP(mst_resp_i[0], peri_axi)
    `AXI_ASSIGN_FROM_REQ(mem_axi, mst_req_o[1])
    `AXI_ASSIGN_TO_RESP(mst_resp_i[1], mem_axi)
    `AXI_ASSIGN_FROM_REQ(irq_axi, mst_req_o[2])
    `AXI_ASSIGN_TO_RESP(mst_resp_i[2], irq_axi)

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
    assign addr_map[2] = '{
        idx: 2,
        start_addr: `IRQ_START,
        end_addr: `IRQ_END
    };

    axi_xbar #(
        .Cfg(crossbar_cfg),
        .slv_aw_chan_t(AxiAW),
        .mst_aw_chan_t(AxiAW),
        .w_chan_t(AxiW),
        .slv_b_chan_t(AxiB),
        .mst_b_chan_t(AxiB),
        .slv_ar_chan_t(AxiAR),
        .mst_ar_chan_t(AxiAR),
        .slv_r_chan_t(AxiR),
        .mst_r_chan_t(AxiR),
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

// interrupt
    AxiReq irq_req;
    AxiResp irq_resp;
    ApbReq clint_req, plic_req;
    ApbResp clint_resp, plic_resp;
    addr_rule_t `N(2) irq_map_rules;
    assign irq_map_rules[0] = '{
        idx: 0,
        start_addr: `CLINT_START,
        end_addr: `CLINT_END
    };
    assign irq_map_rules[1] = '{
        idx: 1,
        start_addr: `PLIC_START,
        end_addr: `PLIC_END
    };

    `AXI_ASSIGN_TO_REQ(irq_req, irq_axi)
    `AXI_ASSIGN_FROM_RESP(irq_axi, irq_resp)
    axi_to_apb #(
        .NoApbSlaves(2),
        .NoRules(2),
        .AxiAddrWidth(`PADDR_SIZE),
        .AxiDataWidth(`XLEN),
        .AxiIdWidth(`CORE_WIDTH+2),
        .AxiUserWidth(1),
        .PipelineRequest(1),
        .PipelineResponse(1),
        .AxiMaxWriteTxns((`NUM_CORE < 2 ? 2 : `NUM_CORE)),
        .AxiMaxReadTxns((`NUM_CORE < 2 ? 2 : `NUM_CORE)),
        .full_req_t(AxiReq),
        .full_resp_t(AxiResp),
        .lite_req_t(AxiLReq),
        .lite_resp_t(AxiLResp),
        .apb_req_t(ApbReq),
        .apb_resp_t(ApbResp),
        .rule_t(addr_rule_t)
    ) irq_axi_to_apb (
        .clk_i(clock),
        .rst_ni(~peri_rst),
        .test_i(1'b0),
        .axi_req_i(irq_req),
        .axi_resp_o(irq_resp),
        .apb_req_o({plic_req, clint_req}),
        .apb_resp_i({plic_resp, clint_resp}),
        .addr_map_i(irq_map_rules)
    );

    ApbIO clint_apb_io();
    `APB_REQ_ASSIGN(clint_req, clint_apb_io)
    `APB_RESP_ASSIGN(clint_resp, clint_apb_io)

    apb4_clint clint(
        .clk(clock),
        .rtc_clk(clock),
        .rst_n_i(~peri_rst),
        .apb4(clint_apb_io.slave),
        .clint(clint_io.clint)
    );

    ApbIO plic_apb_io();
    `APB_REQ_ASSIGN(plic_req, plic_apb_io)
    `APB_RESP_ASSIGN(plic_resp, plic_apb_io)
    plic plic_inst (
        .rstn(~peri_rst),
        .clk(clock),
        .apb(plic_apb_io),
        .ints({{32-`IRQ_NUM{1'b0}}, irq_source}),
        .meip(meip),
        .seip(seip)
    );

// peri
    AxiReq peri_req;
    AxiResp peri_resp;
    ApbReq uart_req;
    ApbResp uart_resp;
    addr_rule_t `N(`PERIPHERAL_SIZE) map_rules;

    assign map_rules[0] = '{
        idx: 0,
        start_addr: `UART_START,
        end_addr: `UART_END
    };

    `AXI_ASSIGN_TO_REQ(peri_req, peri_axi)
    `AXI_ASSIGN_FROM_RESP(peri_axi, peri_resp)

    axi_to_apb #(
        .NoApbSlaves(`PERIPHERAL_SIZE),
        .NoRules(`PERIPHERAL_SIZE),
        .AxiAddrWidth(`PADDR_SIZE),
        .AxiDataWidth(`XLEN),
        .AxiIdWidth(`CORE_WIDTH+2),
        .AxiUserWidth(1),
        .PipelineRequest(1),
        .PipelineResponse(1),
        .AxiMaxWriteTxns((`NUM_CORE < 2 ? 2 : `NUM_CORE)),
        .AxiMaxReadTxns((`NUM_CORE < 2 ? 2 : `NUM_CORE)),
        .full_req_t(AxiReq),
        .full_resp_t(AxiResp),
        .lite_req_t(AxiLReq),
        .lite_resp_t(AxiLResp),
        .apb_req_t(ApbReq),
        .apb_resp_t(ApbResp),
        .rule_t(addr_rule_t)
    ) uart_axi_to_apb (
        .clk_i(clock),
        .rst_ni(~peri_rst),
        .test_i(1'b0),
        .axi_req_i(peri_req),
        .axi_resp_o(peri_resp),
        .apb_req_o(uart_req),
        .apb_resp_i(uart_resp),
        .addr_map_i(map_rules)
    );

// uart

    ApbIO uart_io();
    `APB_REQ_ASSIGN(uart_req, uart_io)
    `APB_RESP_ASSIGN(uart_resp, uart_io)
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
    assign io_memAXI_0_aw_bits_addr = mem_axi.aw_addr;
    assign io_memAXI_0_aw_bits_prot = mem_axi.aw_prot;
    assign io_memAXI_0_aw_bits_id = mem_axi.aw_id;
    assign io_memAXI_0_aw_bits_len = mem_axi.aw_len;
    assign io_memAXI_0_aw_bits_burst = mem_axi.aw_burst;
    assign io_memAXI_0_aw_bits_size = mem_axi.aw_size;
    assign io_memAXI_0_aw_bits_lock = mem_axi.aw_lock;
    assign io_memAXI_0_aw_bits_cache = mem_axi.aw_cache;
    assign io_memAXI_0_aw_bits_qos = mem_axi.aw_qos;

    assign mem_axi.w_ready = io_memAXI_0_w_ready;
    assign io_memAXI_0_w_valid = mem_axi.w_valid;
    assign io_memAXI_0_w_bits_data = mem_axi.w_data;
    assign io_memAXI_0_w_bits_strb = mem_axi.w_strb;
    assign io_memAXI_0_w_bits_last = mem_axi.w_last;

    assign io_memAXI_0_b_ready = mem_axi.b_ready;
    assign mem_axi.b_valid = io_memAXI_0_b_valid;
    assign mem_axi.b_resp = io_memAXI_0_b_bits_resp;
    assign mem_axi.b_id = io_memAXI_0_b_bits_id;

    assign mem_axi.ar_ready = io_memAXI_0_ar_ready;
    assign io_memAXI_0_ar_valid = mem_axi.ar_valid;
    assign io_memAXI_0_ar_bits_addr = mem_axi.ar_addr;
    assign io_memAXI_0_ar_bits_prot = mem_axi.ar_prot;
    assign io_memAXI_0_ar_bits_id = mem_axi.ar_id;
    assign io_memAXI_0_ar_bits_len = mem_axi.ar_len;
    assign io_memAXI_0_ar_bits_size = mem_axi.ar_size;
    assign io_memAXI_0_ar_bits_burst = mem_axi.ar_burst;
    assign io_memAXI_0_ar_bits_lock = mem_axi.ar_lock;
    assign io_memAXI_0_ar_bits_cache = mem_axi.ar_cache;
    assign io_memAXI_0_ar_bits_qos = mem_axi.ar_qos;

    assign io_memAXI_0_r_ready = mem_axi.r_ready;
    assign mem_axi.r_valid = io_memAXI_0_r_valid;
    assign mem_axi.r_resp = io_memAXI_0_r_bits_resp;
    assign mem_axi.r_data = io_memAXI_0_r_bits_data;
    assign mem_axi.r_last = io_memAXI_0_r_bits_last;
    assign mem_axi.r_id = io_memAXI_0_r_bits_id;

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