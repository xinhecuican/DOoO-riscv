module axi_to_apb #(
  parameter int unsigned NoApbSlaves = 32'd1,  // Number of connected APB slaves
  parameter int unsigned NoRules     = 32'd1,  // Number of APB address rules
  parameter bit PipelineRequest      = 1'b0,   // Pipeline request path
  parameter bit PipelineResponse     = 1'b0,   // Pipeline response path
  parameter int unsigned AxiAddrWidth    = 32'd0,
  parameter int unsigned AxiDataWidth    = 32'd0,
  parameter int unsigned AxiIdWidth      = 32'd0,
  parameter int unsigned AxiUserWidth    = 32'd0,
  parameter int unsigned AxiMaxWriteTxns = 32'd0,
  parameter int unsigned AxiMaxReadTxns  = 32'd0,
  parameter bit          FullBW          = 0,     // ID Queue in Full BW mode in axi_burst_splitter
  parameter bit          FallThrough     = 1'b1,  // FIFOs in Fall through mode in ID reflect
  parameter type         full_req_t      = logic,
  parameter type         full_resp_t     = logic,
  parameter type         lite_req_t      = logic,
  parameter type         lite_resp_t     = logic,
  parameter type           apb_req_t = logic,  // APB4 request struct
  parameter type          apb_resp_t = logic,  // APB4 response struct
  parameter type              rule_t = logic   // Address Decoder rule from `common_cells`
) (
  input  logic       clk_i,    // Clock
  input  logic       rst_ni,   // Asynchronous reset active low
  input  logic       test_i,   // Testmode enable
  // slave port full AXI4+ATOP
  input  full_req_t  axi_req_i,
  output full_resp_t axi_resp_o,
  // APB master port
  output apb_req_t  [NoApbSlaves-1:0] apb_req_o,
  input  apb_resp_t [NoApbSlaves-1:0] apb_resp_i,
  // APB Slave Address Map
  input  rule_t     [NoRules-1:0]     addr_map_i
);
    lite_req_t mst_req_o;
    /* verilator lint_off UNOPTFLAT */
    lite_resp_t mst_resp_i;
    axi_to_axi_lite #(
        .AxiAddrWidth(AxiAddrWidth),
        .AxiDataWidth(AxiDataWidth),
        .AxiIdWidth(AxiIdWidth),
        .AxiUserWidth(AxiUserWidth),
        .AxiMaxWriteTxns(AxiMaxWriteTxns),
        .AxiMaxReadTxns(AxiMaxReadTxns),
        .FullBW(FullBW),
        .FallThrough(FallThrough),
        .full_req_t(full_req_t),
        .full_resp_t(full_resp_t),
        .lite_req_t(lite_req_t),
        .lite_resp_t(lite_resp_t)
    ) axi_to_lite_inst (
        .*,
        .slv_req_i(axi_req_i),
        .slv_resp_o(axi_resp_o)
    );

    axi_lite_to_apb #(
        .NoApbSlaves(NoApbSlaves),
        .NoRules(NoRules),
        .AddrWidth(AxiAddrWidth),
        .DataWidth(AxiDataWidth),
        .PipelineRequest(PipelineRequest),
        .PipelineResponse(PipelineResponse),
        .axi_lite_req_t(lite_req_t),
        .axi_lite_resp_t(lite_resp_t),
        .apb_req_t(apb_req_t),
        .apb_resp_t(apb_resp_t),
        .rule_t(rule_t)
    ) lite_to_apb_inst (
        .*,
        .axi_lite_req_i(mst_req_o),
        .axi_lite_resp_o(mst_resp_i)
    );
endmodule