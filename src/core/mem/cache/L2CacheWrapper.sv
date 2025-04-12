`include "../../../defines/defines.svh"

module L2CacheWrapper #(
    parameter type snoop_req_t = logic,
    parameter type snoop_resp_t = logic,
    parameter type mst_snoop_req_t = logic,
    parameter type mst_snoop_resp_t = logic,
    parameter MST_SNOOP_ID_WIDTH = 1
)(
    input logic clk,
    input logic rst,
    CacheBus.slave icache_io,
    CacheBus.slave tlb_io,
    CacheBus.slave dcache_io,
    CacheBus.master master_io, // to mem
    output snoop_req_t snoop_req,
    input snoop_resp_t snoop_resp,
    input mst_snoop_req_t mst_snoop_req,
    output mst_snoop_resp_t mst_snoop_resp
);
    typedef logic [`PADDR_SIZE-1: 0] addr_t;
    typedef logic [0: 0] id_t;
    typedef logic user_t;
    typedef logic [2: 0] mst_id_t;
    typedef logic [`XLEN-1: 0] data_t;
    typedef logic [`XLEN/8-1: 0] strb_t;
    typedef logic [$clog2(`L2MSHR_SIZE)-1: 0] snoop_ack_id_t;

    `CACHE_TYPEDEF_AW_CHAN_T(AxiAW, addr_t, id_t, user_t)
    `CACHE_TYPEDEF_W_CHAN_T(AxiW, data_t, strb_t, user_t)
    `CACHE_TYPEDEF_B_CHAN_T(AxiB, id_t, user_t)
    `CACHE_TYPEDEF_AR_CHAN_T(AxiAR, addr_t, id_t, user_t)
    `CACHE_TYPEDEF_R_CHAN_T(AxiR, data_t, id_t, user_t)
    `CACHE_TYPEDEF_REQ_T(AxiReq, AxiAW, AxiW, AxiAR)
    `CACHE_TYPEDEF_RESP_T(AxiResp, AxiB, AxiR)

    `CACHE_TYPEDEF_AW_CHAN_T(AxiMAW, addr_t, mst_id_t, user_t)
    `CACHE_TYPEDEF_B_CHAN_T(AxiMB, mst_id_t, user_t)
    `CACHE_TYPEDEF_AR_CHAN_T(AxiMAR, addr_t, mst_id_t, user_t)
    `CACHE_TYPEDEF_R_CHAN_T(AxiMR, data_t, mst_id_t, user_t)
    `CACHE_TYPEDEF_REQ_T(AxiMReq, AxiMAW, AxiW, AxiMAR)
    `CACHE_TYPEDEF_RESP_T(AxiMResp, AxiMB, AxiMR)

    `SNOOP_TYPEDEF_AC_CHAN_T(snoop_ac_chan_t, addr_t)
    `SNOOP_TYPEDEF_CD_CHAN_T(snoop_cd_chan_t, data_t)
    `SNOOP_TYPEDEF_CR_CHAN_T(snoop_cr_chan_t)
    typedef logic [`L2MSHR_WIDTH-1: 0] snoop_id_t;

    snoop_req_t l2_snoop_req;
    snoop_resp_t l2_snoop_resp;

    AxiReq ireq, dreq, tlb_req;
    AxiResp iresp, dresp, tlb_resp;
    AxiMReq req_o;
    AxiMResp resp_i;
    CacheBus #(
        `PADDR_SIZE, `XLEN, 3, 1
    ) l2_cache_io();

    `CACHE_ASSIGN_TO_AR(ireq.ar, icache_io)
    assign ireq.ar_valid = icache_io.ar_valid;
    assign ireq.r_ready = icache_io.r_ready;
    assign ireq.aw = 0;
    assign ireq.w = 0;
    assign ireq.aw_valid = 0;
    assign ireq.w_valid = 0;
    assign ireq.b_ready = 0;
    `CACHE_ASSIGN_FROM_R(icache_io, iresp.r)
    assign icache_io.ar_ready = iresp.ar_ready;
    assign icache_io.r_valid = iresp.r_valid;

    `CACHE_ASSIGN_TO_AR(tlb_req.ar, tlb_io)
    assign tlb_req.ar_valid = tlb_io.ar_valid;
    assign tlb_req.r_ready = icache_io.r_ready;
    assign tlb_req.aw = 0;
    assign tlb_req.w = 0;
    assign tlb_req.aw_valid = 0;
    assign tlb_req.w_valid = 0;
    assign tlb_req.b_ready = 0;
    `CACHE_ASSIGN_FROM_R(tlb_io, tlb_resp.r)
    assign tlb_io.ar_ready = tlb_resp.ar_ready;
    assign tlb_io.r_valid = tlb_resp.r_valid;

    `CACHE_ASSIGN_TO_REQ(dreq, dcache_io)
    `CACHE_ASSIGN_FROM_RESP(dcache_io, dresp)

    `CACHE_ASSIGN_FROM_REQ(l2_cache_io, req_o)
    `CACHE_ASSIGN_TO_RESP(resp_i, l2_cache_io)

    axi_mux #(
        .SlvAxiIDWidth(1),
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
        .MaxWTrans(1),
        .NoSlvPorts(3),
        .SpillW(1),
        .SpillB(1), 
        .SpillR(1)
    ) axi_mux_inst(
        .clk_i(clk),
        .rst_ni(rst),
        .test_i(1'b0),
        .slv_reqs_i({dreq, tlb_req, ireq}),
        .slv_resps_o({dresp, tlb_resp, iresp}),
        .mst_req_o(req_o),
        .mst_resp_i(resp_i)
    );

    snoop_multicut #(
        .NoCuts(1),
        .ac_chan_t(snoop_ac_chan_t),
        .cr_chan_t(snoop_cr_chan_t),
        .cd_chan_t(snoop_cd_chan_t),
        .snoop_id_t(snoop_id_t),
        .req_t(snoop_req_t),
        .resp_t(snoop_resp_t)
    ) snoop_cut (
        .clk_i(clk),
        .rst_ni(rst),
        .slv_req_i(l2_snoop_req),
        .slv_resp_o(l2_snoop_resp),
        .mst_req_o(snoop_req),
        .mst_resp_i(snoop_resp)
    );

    L2Cache #(
        .MSHR_SIZE(`L2MSHR_SIZE),
        .SLAVE_BANK(`DCACHE_BANK),
        .CACHE_BANK(`L2CACHE_BANK),
        .DATA_BANK(`L2DATA_BANK),
        .ID_WIDTH(2),
        .ID_OFFSET(1),
        .SLAVE(1),
        .WAY_NUM(`L2WAY_NUM),
        .SET(`L2SET),
        .OFFSET(`L2OFFSET),
        .ISL2(1),
        .LLC(1),
        .SLAVE_DIR_SET(`L2SLAVE_SET),
        .SLAVE_DIR_WAY(`L2SLAVE_WAY),
        .PREPEND_PIPE(`L2PREPEND_PIPE),
        .APPEND_PIPE(`L2APPEND_PIPE),
        .snoop_ac_chan_t(snoop_ac_chan_t),
        .snoop_cd_chan_t(snoop_cd_chan_t),
        .snoop_req_t(snoop_req_t),
        .snoop_resp_t(snoop_resp_t),
        .mst_snoop_req_t(mst_snoop_req_t),
        .mst_snoop_resp_t(mst_snoop_resp_t),
        .MST_SNOOP_ID_WIDTH(MST_SNOOP_ID_WIDTH)
    ) l2_cache(
        .clk,
        .rst,
        .slave_io(l2_cache_io.slave),
        .master_io(master_io),
        .snoop_req(l2_snoop_req),
        .snoop_resp(l2_snoop_resp),
        .mst_snoop_req,
        .mst_snoop_resp
    );
endmodule