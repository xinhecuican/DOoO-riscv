`include "../defines/defines.svh"

module AxiInterface(
    input logic clk,
    input logic rst,
    AxiIO.slaver icache_io,
    AxiIO.slaver tlb_io,
    AxiIO.slave dcache_io,
    AxiIO.slave ducache_io,
    AxiIO.master axi,
    NativeSnoopIO.slave dcache_snoop_io
);

    logic mux_rst, coherence_rst;
    SyncRst rst_mux (clk, rst, mux_rst);
    SyncRst rst_coherence (clk, rst, coherence_rst);

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
    AxiReq ireq, dreq, du_req, tlb_req;
    AxiResp iresp, dresp, du_resp, tlb_resp;
    AxiMReq req_o, co_req_o;
    AxiMResp resp_i, co_resp_i;

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

    `AXI_ASSIGN_TO_AR(tlb_req.ar, tlb_io)
    assign tlb_req.ar_valid = tlb_io.ar_valid;
    assign tlb_req.r_ready = icache_io.r_ready;
    assign tlb_req.aw = 0;
    assign tlb_req.w = 0;
    assign tlb_req.aw_valid = 0;
    assign tlb_req.w_valid = 0;
    assign tlb_req.b_ready = 0;
    `AXI_ASSIGN_FROM_R(tlb_io, tlb_resp.r)
    assign tlb_io.ar_ready = tlb_resp.ar_ready;
    assign tlb_io.r_valid = tlb_resp.r_valid;

    `AXI_ASSIGN_TO_REQ(dreq, dcache_io)
    `AXI_ASSIGN_FROM_RESP(dcache_io, dresp)

    `AXI_ASSIGN_TO_REQ(du_req, ducache_io)
    `AXI_ASSIGN_FROM_RESP(ducache_io, du_resp)

    `AXI_ASSIGN_FROM_REQ(axi, co_req_o)
    `AXI_ASSIGN_TO_RESP(co_resp_i, axi)

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
        .MaxWTrans(1), // 只有DCache有写
        .NoSlvPorts(4)
    ) axi_mux_inst(
        .clk_i(clk),
        .rst_ni(~mux_rst),
        .test_i(1'b0),
        .slv_reqs_i({dreq, du_req, tlb_req, ireq}),
        .slv_resps_o({dresp, du_resp, tlb_resp, iresp}),
        .mst_req_o(req_o),
        .mst_resp_i(resp_i)
    );

    logic `N(`DCACHE_WAY_WIDTH) wway;
    always_ff @(posedge clk)begin
        wway <= dcache_io.ar_user;
    end

    DCacheCoherence #(
        .aw_chan_t(AxiMAW),
        .w_chan_t(AxiW),
        .b_chan_t(AxiMB),
        .ar_chan_t(AxiMAR),
        .r_chan_t(AxiMR),
        .axi_req_t(AxiMReq),
        .axi_resp_t(AxiMResp)
    ) dcache_coherence (
        .clk,
        .rst(coherence_rst),
        .wway_i(wway),
        .slv_req_i(req_o),
        .slv_resp_o(resp_i),
        .mst_req_o(co_req_o),
        .mst_resp_i(co_resp_i),
        .dcache_snoop_io(dcache_snoop_io)
    );

endmodule

module DCacheCoherence #(
    // AXI channel structs
    parameter type  aw_chan_t = logic,
    parameter type   w_chan_t = logic,
    parameter type   b_chan_t = logic,
    parameter type  ar_chan_t = logic,
    parameter type   r_chan_t = logic,
    // AXI request & response structs
    parameter type  axi_req_t = logic,
    parameter type axi_resp_t = logic
)(
    input logic clk,
    input logic rst,
    input logic `N(`DCACHE_WAY_WIDTH) wway_i,
    input axi_req_t slv_req_i,
    output axi_resp_t slv_resp_o,

    output axi_req_t mst_req_o,
    input axi_resp_t mst_resp_i,
    NativeSnoopIO.slave dcache_snoop_io
);
    logic `N(`DCACHE_SET_WIDTH) widx, widx_n;
    logic `N(`DCACHE_TAG) wtag;
    logic `ARRAY(`DCACHE_WAY, `DCACHE_TAG+1) w_tagv, tagv;
    logic w_valid;
    logic `N(`DCACHE_WAY_WIDTH) w_way_idx;
    logic `N(`DCACHE_WAY) w_way;
    logic `N(`DCACHE_WAY) tagv_hits;
    logic `N(`PADDR_SIZE) ac_addr;
    logic tagv_hit;
    logic `N(`DCACHE_TAG) rtag;
    logic r_dcache;
    r_chan_t snoop_r;

    logic `N(`DCACHE_REPLACE_SIZE) replace_valid;
    logic `N(`DCACHE_BLOCK_SIZE) replace_tag `N(`DCACHE_REPLACE_SIZE);
    logic replace_en;
    logic `N(`DCACHE_WAY_WIDTH) replace_way;
    logic `N(`DCACHE_REPLACE_WIDTH) replace_free_idx;
    logic `N(`PADDR_SIZE) replace_clear_addr;
    logic `N(`DCACHE_REPLACE_SIZE) replace_hits, replace_clear_hits;
    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx, replace_clear_idx;
    logic replace_hit, replace_clear_en;
    logic aw_writeEvict;

    axi_req_t slv_req_i_s2;
    axi_resp_t slv_resp_o_s2;

    assign w_valid = (slv_resp_o.r.last & slv_resp_o.r_valid & slv_req_i.r_ready & 
                     (slv_resp_o.r.id[`CORE_WIDTH+1: `CORE_WIDTH] == 2'b11));
    Decoder #(`DCACHE_WAY) decoder_way (w_way_idx, w_way);
    MPRAM #(
        .WIDTH(`DCACHE_WAY * (`DCACHE_TAG+1)),
        .DEPTH(`DCACHE_SET),
        .READ_PORT(1),
        .WRITE_PORT(0),
        .RW_PORT(1),
        .READ_LATENCY(1),
        .RESET(1),
        .BYTE_WRITE(1),
        .BYTES(`DCACHE_WAY)
    ) tagv_ram (
        .clk,
        .rst,
        .en({slv_resp_o.r.last, slv_req_i.ar_valid}),
        .we(w_way & {`DCACHE_WAY{w_valid}}),
        .raddr(slv_req_i.ar.addr`DCACHE_SET_BUS),
        .rdata({w_tagv, tagv}),
        .waddr(widx),
        .wdata({`DCACHE_WAY{wtag, 1'b1}}),
        .ready()
    );

    assign tagv_hit = |tagv_hits;
generate
    for(genvar i=0; i<`DCACHE_REPLACE_SIZE; i++)begin
        assign replace_hits[i] = replace_valid[i] & (slv_req_i.ar.addr`DCACHE_BLOCK_BUS == replace_tag[i]);
        assign replace_clear_hits[i] = replace_valid[i] & (replace_clear_addr`DCACHE_BLOCK_BUS == replace_tag[i]);
    end
    for(genvar i=0; i<`DCACHE_WAY; i++)begin
        assign tagv_hits[i] = tagv[i][0] & (rtag == tagv[i][`DCACHE_TAG: 1]);
    end
endgenerate
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_replace_free_idx (~replace_valid, replace_free_idx);
    Encoder #(`DCACHE_REPLACE_SIZE) encoder_replace_idx (replace_clear_hits, replace_idx);
    always_ff @(posedge clk)begin
        replace_en <= w_valid;
        replace_way <= w_way_idx;
        replace_hit <= |replace_hits;
        rtag <= slv_req_i.ar.addr`DCACHE_TAG_BUS;
        ac_addr <= slv_req_i.ar.addr;
        r_dcache <= slv_req_i.ar.id[`CORE_WIDTH+1: `CORE_WIDTH] == 2'b11;
        aw_writeEvict <= slv_req_i.aw_valid & ~slv_req_i.aw.user & 
                         (slv_req_i.aw.id[`CORE_WIDTH+1: `CORE_WIDTH] == 2'b11);
        if(slv_req_i.ar_valid & (slv_req_i.ar.id[`CORE_WIDTH+1: `CORE_WIDTH] == 2'b11))begin
            wtag <= slv_req_i.ar.addr`DCACHE_TAG_BUS;
            widx <= slv_req_i.ar.addr`DCACHE_SET_BUS;
            w_way_idx <= wway_i;
        end
        widx_n <= widx;
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            replace_valid <= 0;
            replace_tag <= '{default: 0};
            replace_clear_en <= 1'b0;
            replace_clear_idx <= 0;
            replace_clear_addr <= 0;
        end
        else begin
            if(replace_en)begin
                replace_valid[replace_free_idx] <= 1'b1;
                replace_tag[replace_free_idx] <= {w_tagv[replace_way][`DCACHE_TAG: 1], widx_n};
            end
            if(slv_req_i.aw_valid & slv_resp_o.aw_ready & slv_req_i.aw.user)begin
                replace_clear_en <= 1'b1;
            end
            if(slv_req_i.aw_valid)begin
                replace_clear_addr <= slv_req_i.aw.addr;
            end
            if(replace_clear_en & ~slv_req_i.ar_valid)begin
                replace_clear_en <= 1'b0;
                replace_clear_idx <= replace_idx;
            end
            if(slv_resp_o.b_valid & slv_req_i.b_ready & 
              (slv_resp_o.b.id[`CORE_WIDTH+1: `CORE_WIDTH] == 2'b11))begin
                replace_valid[replace_clear_idx] <= 1'b0;
            end
            if(aw_writeEvict)begin
                replace_valid[replace_idx] <= 1'b0;
            end
        end
    end

    axi_cut #(
        .aw_chan_t(aw_chan_t),
        .w_chan_t(w_chan_t),
        .b_chan_t(b_chan_t),
        .ar_chan_t(ar_chan_t),
        .r_chan_t(r_chan_t),
        .axi_req_t(axi_req_t),
        .axi_resp_t(axi_resp_t)
    ) axi_cut_inst (
        .clk_i(clk),
        .rst_ni(~rst),
        .slv_req_i(slv_req_i),
        .slv_resp_o(slv_resp_o),
        .mst_req_o(slv_req_i_s2),
        .mst_resp_i(slv_resp_o_s2)
    );

    assign mst_req_o.aw = slv_req_i_s2.aw;
    assign mst_req_o.aw_valid = ~aw_writeEvict & slv_req_i_s2.aw_valid;
    assign mst_req_o.w = slv_req_i_s2.w;
    assign mst_req_o.w_valid = slv_req_i_s2.w_valid;
    assign mst_req_o.b_ready = slv_req_i_s2.b_ready;
    assign mst_req_o.ar = slv_req_i_s2.ar;
    assign mst_req_o.ar_valid = (~replace_hit & ~tagv_hit | r_dcache) & slv_req_i_s2.ar_valid;
    assign mst_req_o.r_ready = slv_req_i_s2.r_ready;

    assign slv_resp_o_s2.aw_ready = mst_resp_i.aw_ready | aw_writeEvict;
    assign slv_resp_o_s2.ar_ready = (~replace_hit & ~tagv_hit | r_dcache) ? mst_resp_i.ar_ready : dcache_snoop_io.ac_ready;
    assign slv_resp_o_s2.w_ready = mst_resp_i.w_ready;
    assign slv_resp_o_s2.b_valid = mst_resp_i.b_valid;
    assign slv_resp_o_s2.b = mst_resp_i.b;
    assign slv_resp_o_s2.r_valid = dcache_snoop_io.cd_valid | mst_resp_i.r_valid;
    assign slv_resp_o_s2.r = mst_resp_i.r_valid ? mst_resp_i.r : snoop_r;

    assign dcache_snoop_io.ac_addr = ac_addr;
    assign dcache_snoop_io.ac_valid = (replace_hit | tagv_hit) & ~r_dcache & slv_req_i_s2.ar_valid;
    assign dcache_snoop_io.ac_user = slv_req_i_s2.ar.id;
    assign dcache_snoop_io.cd_ready = ~mst_resp_i.r_valid;
    assign snoop_r.id = dcache_snoop_io.cd_user;
    assign snoop_r.data = dcache_snoop_io.cd_data;
    assign snoop_r.resp = 0;
    assign snoop_r.last = dcache_snoop_io.cd_last;
    assign snoop_r.user = 0;

endmodule