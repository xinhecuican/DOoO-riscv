`include "../defines/devices.svh"
`include "../defines/defines.svh"

module Soc(
    input logic core_clk,
    input logic rst,

    input logic peri_clk,
    input logic rxd,
    output logic txd
);
    AxiIO core_axi();
    AxiIO peri_axi();

    logic sync_rst_peri, sync_rst_core, core_rst, peri_rst;
    logic peri_rst_s1, core_rst_s1;
    SyncRst rst_core (core_clk, rst, sync_rst_core);
    SyncRst rst_peri (peri_clk, rst, sync_rst_peri);
    always_ff @(posedge core_clk)begin
        core_rst_s1 <= sync_rst_core;
        core_rst <= core_rst_s1;
    end
    always_ff @(posedge peri_clk)begin
        peri_rst_s1 <= sync_rst_peri;
        peri_rst <= peri_rst_s1;
    end

    CPUCore core(
        .clk(core_clk),
        .rst(core_rst),
        .axi(core_axi.master)
    );

    localparam AXI_SLAVE_NUM = 1;

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
        .clk_i(core_clk),
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

    AxiReq peri_req, peri_req_cdc;
    AxiResp peri_resp, peri_resp_cdc;
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

    axi_cdc #(
        .aw_chan_t(AxiMAW),
        .w_chan_t(AxiMW),
        .b_chan_t(AxiSB),
        .ar_chan_t(AxiMAR),
        .r_chan_t(AxiSR),
        .axi_req_t(AxiReq),
        .axi_resp_t(AxiResp)
    ) uart_axi_cdc(
        .src_clk_i(core_clk),
        .src_rst_ni(~core_rst),
        .src_req_i(peri_req),
        .src_resp_o(peri_resp),
        .dst_clk_i(peri_clk),
        .dst_rst_ni(~peri_rst),
        .dst_req_o(peri_req_cdc),
        .dst_resp_i(peri_resp_cdc)
    );

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
        .slv_req_i(peri_req_cdc),
        .slv_resp_o(peri_resp_cdc),
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
    uart uart_inst(
        .clk(peri_clk),
        .rstn(~peri_rst),
        .s_apb_intf(uart_io),
        .irq_out(),
        .uart_rx(rxd),
        .uart_tx(txd)
    );
endmodule