`include "../defines/devices.svh"
`include "../defines/defines.svh"

module Soc(
    input logic clk,
    input logic rst,

    input logic rtc_clk,
    input logic rxd,
    output logic txd
);
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
    logic uart_irq;
    logic `N(`NUM_CORE) irq;

    logic sync_rst_peri, sync_rst_core, core_rst, peri_rst;
    logic peri_rst_s1, core_rst_s1;
    SyncRst rst_core (clk, rst, sync_rst_core);
    SyncRst rst_peri (clk, rst, sync_rst_peri);
    always_ff @(posedge clk)begin
        core_rst_s1 <= sync_rst_core;
        core_rst <= core_rst_s1;
    end
    always_ff @(posedge clk)begin
        peri_rst_s1 <= sync_rst_peri;
        peri_rst <= peri_rst_s1;
    end

    CPUCore core(
        .clk(clk),
        .rst(core_rst),
        .ext_irq(irq[0]),
        .axi(core_axi.master),
        .clint_io(clint_io.cpu)
    );

    localparam AXI_SLAVE_NUM = 2;

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
    `AXI_ASSIGN_FROM_REQ(irq_axi, mst_req_o[1])
    `AXI_ASSIGN_TO_RESP(mst_resp_i[1], irq_axi)

    assign addr_map[0] = '{
        idx: 0,
        start_addr: `PERIPHERAL_START,
        end_addr: `PERIPHERAL_END
    };
    assign addr_map[1] = '{
        idx: 1,
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
        .clk_i(clk),
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
        .AxiMaxWriteTxns(32'd16),
        .AxiMaxReadTxns(32'd16),
        .full_req_t(AxiReq),
        .full_resp_t(AxiResp),
        .lite_req_t(AxiLReq),
        .lite_resp_t(AxiLResp),
        .apb_req_t(ApbReq),
        .apb_resp_t(ApbResp),
        .rule_t(addr_rule_t)
    ) irq_axi_to_apb (
        .clk_i(clk),
        .rst_ni(~peri_rst),
        .test_i(1'b0),
        .axi_req_i(irq_req),
        .axi_resp_o(irq_resp),
        .apb_req_o({plic_req, clint_req}),
        .apb_resp_i({plic_resp, clint_resp}),
        .addr_map_i(map_rules)
    );

    ApbIO clint_apb_io();
    `APB_REQ_ASSIGN(clint_req, clint_apb_io)
    `APB_RESP_ASSIGN(clint_resp, clint_apb_io)

    apb4_clint clint(
        .clk(clk),
        .rtc_clk(rtc_clk),
        .rst(peri_rst),
        .apb4(clint_apb_io.slave),
        .clint(clint_io.clint)
    );

    ApbIO plic_apb_io();
    `APB_REQ_ASSIGN(plic_req, plic_apb_io)
    `APB_RESP_ASSIGN(plic_resp, plic_apb_io)
    assign irq_source[0] = uart_irq;
    apb4_plic_top #(
        .PADDR_SIZE(`PADDR_SIZE),
        .PDATA_SIZE(`XLEN),
        .SOURCES(`IRQ_NUM),
        .TARGETS(`NUM_CORE)
    ) plic (
        .PRESETn(~peri_rst),
        .PCLK(clk),
        .apb(plic_apb_io),
        .src(irq_source),
        .irq(irq)
    );

// peri
    AxiReq peri_req, peri_req_cdc;
    AxiResp peri_resp, peri_resp_cdc;
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

    axi_cdc #(
        .aw_chan_t(AxiAW),
        .w_chan_t(AxiW),
        .b_chan_t(AxiB),
        .ar_chan_t(AxiAR),
        .r_chan_t(AxiR),
        .axi_req_t(AxiReq),
        .axi_resp_t(AxiResp)
    ) uart_axi_cdc(
        .src_clk_i(clk),
        .src_rst_ni(~core_rst),
        .src_req_i(peri_req),
        .src_resp_o(peri_resp),
        .dst_clk_i(clk),
        .dst_rst_ni(~peri_rst),
        .dst_req_o(peri_req_cdc),
        .dst_resp_i(peri_resp_cdc)
    );

    axi_to_apb #(
        .NoApbSlaves(`PERIPHERAL_SIZE),
        .NoRules(`PERIPHERAL_SIZE),
        .AxiAddrWidth(`PADDR_SIZE),
        .AxiDataWidth(`XLEN),
        .AxiIdWidth(`CORE_WIDTH+2),
        .AxiUserWidth(1),
        .AxiMaxWriteTxns(32'd16),
        .AxiMaxReadTxns(32'd16),
        .full_req_t(AxiReq),
        .full_resp_t(AxiResp),
        .lite_req_t(AxiLReq),
        .lite_resp_t(AxiLResp),
        .apb_req_t(ApbReq),
        .apb_resp_t(ApbResp),
        .rule_t(addr_rule_t)
    ) uart_axi_to_apb (
        .clk_i(clk),
        .rst_ni(~peri_rst),
        .test_i(1'b0),
        .axi_req_i(peri_req_cdc),
        .axi_resp_o(peri_resp_cdc),
        .apb_req_o(uart_req),
        .apb_resp_i(uart_resp),
        .addr_map_i(map_rules)
    );

// uart
    ApbIO uart_io();
    `APB_REQ_ASSIGN(uart_req, uart_io)
    `APB_RESP_ASSIGN(uart_resp, uart_io)
    uart uart_inst(
        .clk(clk),
        .rstn(~peri_rst),
        .s_apb_intf(uart_io),
        .irq_out(uart_irq),
        .uart_rx(rxd),
        .uart_tx(txd)
    );
endmodule