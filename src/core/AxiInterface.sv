`include "../defines/defines.svh"

module AxiInterface(
    input logic clk,
    input logic rst,
    AxiIO.slaver icache_io,
    AxiIO.slave dcache_io,
    AxiIO.slave ducache_io,
    AxiIO.master axi
);
    typedef logic [`PADDR_SIZE-1: 0] addr_t;
    typedef logic [`CORE_WIDTH-1: 0] id_t;
    typedef logic user_t;
    typedef logic [`CORE_WIDTH+2-1: 0] mst_id_t;
    typedef logic [`XLEN-1: 0] data_t;
    typedef logic [`XLEN/8-1: 0] strb_t;
    `AXI_TYPEDEF_AW_CHAN_T(AxiAW, addr_t, id_t, user_t)
    `AXI_TYPEDEF_W_CHAN_T(AxiW, data_t, strb_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(AxiB, id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(AxiAR, addr_t, id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(AxiR, data_t, id_t, user_t)
    `AXI_TYPEDEF_REQ_T(AxiReq, AxiAW, AxiW, AxiAR)
    `AXI_TYPEDEF_RESP_T(AxiResp, AxiB, AxiR)

    `AXI_TYPEDEF_AW_CHAN_T(AxiMAW, addr_t, mst_id_t, user_t)
    `AXI_TYPEDEF_B_CHAN_T(AxiMB, mst_id_t, user_t)
    `AXI_TYPEDEF_AR_CHAN_T(AxiMAR, addr_t, mst_id_t, user_t)
    `AXI_TYPEDEF_R_CHAN_T(AxiMR, data_t, mst_id_t, user_t)
    `AXI_TYPEDEF_REQ_T(AxiMReq, AxiMAW, AxiW, AxiMAR)
    `AXI_TYPEDEF_RESP_T(AxiMResp, AxiMB, AxiMR)
    AxiReq ireq, dreq, du_req;
    AxiResp iresp, dresp, du_resp;
    AxiMReq req_o;
    AxiMResp resp_i;

    `AXI_ASSIGN_TO_AR(ireq.ar, icache_io)
    assign ireq.ar_valid = icache_io.ar_valid;
    assign ireq.r_ready = icache_io.r_ready;
    assign ireq.aw = 0;
    assign ireq.w = 0;
    assign ireq.aw_valid = 0;
    assign ireq.w_valid = 0;
    assign ireq.b_ready = 0;
    `AXI_ASSIGN_FROM_R(icache_io, iresp.r)
    assign icache_io.ar_ready = iresp.ar_ready;
    assign icache_io.r_valid = iresp.r_valid;

    `AXI_ASSIGN_TO_REQ(dreq, dcache_io)
    `AXI_ASSIGN_FROM_RESP(dcache_io, dresp)

    `AXI_ASSIGN_TO_REQ(du_req, ducache_io)
    `AXI_ASSIGN_FROM_RESP(ducache_io, du_resp)

    `AXI_ASSIGN_FROM_REQ(axi, req_o)
    `AXI_ASSIGN_TO_RESP(resp_i, axi)

    axi_mux #(
        .SlvAxiIDWidth(`CORE_WIDTH),
        .slv_aw_chan_t(AxiAW),
        .mst_aw_chan_t(AxiMAW),
        .w_chan_t(AxiW),
        .slv_b_chan_t(AxiB),
        .mst_b_chan_t(AxiMB),
        .slv_ar_chan_t(AxiAR),
        .mst_ar_chan_t(AxiMAR),
        .slv_r_chan_t(AxiR),
        .mst_r_chan_t(AxiMR),
        .slv_req_t(AxiReq),
        .slv_resp_t(AxiResp),
        .mst_req_t(AxiMReq),
        .mst_resp_t(AxiMResp),
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