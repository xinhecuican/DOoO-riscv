`include "../../defines/defines.svh"

module AxiInterface(
    input logic clk,
    input logic rst,
    ICacheAxi.axi icache_io,
    DCacheAxi.axi dcache_io,
    AxiIO.slave ducache_io,
    AxiIO.master axi
);

    AxiReq ireq, dreq, du_req, req_o;
    AxiResp iresp, dresp, du_resp, resp_i;

    assign ireq.ar = icache_io.mar;
    assign ireq.ar_valid = icache_io.ar_valid;
    assign ireq.r_ready = icache_io.r_ready;
    assign ireq.aw = 0;
    assign ireq.w = 0;
    assign ireq.aw_valid = 0;
    assign ireq.w_valid = 0;
    assign ireq.b_ready = 0;
    assign icache_io.sr = iresp.r;
    assign icache_io.ar_ready = iresp.ar_ready;
    assign icache_io.r_valid = iresp.r_valid;

    `AXI_REQ_ASSIGN(dreq, dcache_io)
    `AXI_RESP_ASSIGN(dresp, dcache_io)
    `AXI_REQ_ASSIGN(du_req, ducache_io)
    `AXI_RESP_ASSIGN(du_resp, ducache_io)
    `AXI_REQ_RECEIVE(req_o, axi)
    `AXI_RESP_RECEIVE(resp_i, axi)

    axi_mux #(
        .SlvAxiIDWidth(2),
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
        .NoSlvPorts(3)
    ) axi_mux_inst(
        .clk_i(clk),
        .rst_ni(~rst),
        .test_i(1'b0),
        .slv_reqs_i({ireq, dreq, du_req}),
        .slv_resps_o({iresp, dresp, du_resp}),
        .mst_req_o(req_o),
        .mst_resp_i(resp_i)
    );

endmodule