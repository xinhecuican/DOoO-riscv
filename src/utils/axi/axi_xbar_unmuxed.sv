// Copyright (c) 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Authors:
// - Wolfgang Roenninger <wroennin@iis.ee.ethz.ch>
// - Andreas Kurth <akurth@iis.ee.ethz.ch>
// - Florian Zaruba <zarubaf@iis.ee.ethz.ch>

/// axi_xbar: Fully-connected AXI4+ATOP crossbar with an arbitrary number of slave and master ports.
/// See `doc/axi_xbar.md` for the documentation, including the definition of parameters and ports.
`include "../../defines/bus/axi.svh"


module axi_xbar_unmuxed
#(
  /// Configuration struct for the crossbar see `axi_pkg` for fields and definitions.
  parameter xbar_cfg_t Cfg                                   = '0,
  /// Enable atomic operations support.
  parameter bit  ATOPs                                                = 1'b1,
  /// Connectivity matrix
  parameter bit [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts-1:0] Connectivity = '1,
  /// AXI4+ATOP AW channel struct type for the slave ports.
  parameter type aw_chan_t                                            = logic,
  /// AXI4+ATOP W channel struct type for all ports.
  parameter type w_chan_t                                             = logic,
  /// AXI4+ATOP B channel struct type for the slave ports.
  parameter type b_chan_t                                             = logic,
  /// AXI4+ATOP AR channel struct type for the slave ports.
  parameter type ar_chan_t                                            = logic,
  /// AXI4+ATOP R channel struct type for the slave ports.
  parameter type r_chan_t                                             = logic,
  /// AXI4+ATOP request struct type for the slave ports.
  parameter type req_t                                                = logic,
  /// AXI4+ATOP response struct type for the slave ports.
  parameter type resp_t                                               = logic,
  /// Address rule type for the address decoders from `common_cells:addr_decode`.
  /// Example types are provided in `axi_pkg`.
  /// Required struct fields:
  /// ```
  /// typedef struct packed {
  ///   int unsigned idx;
  ///   axi_addr_t   start_addr;
  ///   axi_addr_t   end_addr;
  /// } rule_t;
  /// ```
  parameter type rule_t                                               = logic,
  parameter NoMstPorts                                                = 2,
  parameter int unsigned MstPortsIdxWidth = NoMstPorts > 1 ? $clog2(NoMstPorts) : 1
) (
  /// Clock, positive edge triggered.
  input  logic                                                          clk_i,
  /// Asynchronous reset, active low.
  input  logic                                                          rst_ni,
  /// Testmode enable, active high.
  input  logic                                                          test_i,
  /// AXI4+ATOP requests to the slave ports.
  input  req_t  [Cfg.NoSlvPorts-1:0]                                    slv_ports_req_i,
  /// AXI4+ATOP responses of the slave ports.
  output resp_t [Cfg.NoSlvPorts-1:0]                                    slv_ports_resp_o,
  /// AXI4+ATOP requests of the master ports.
  output req_t  [Cfg.NoMstPorts-1:0][Cfg.NoSlvPorts-1:0]                mst_ports_req_o,
  /// AXI4+ATOP responses to the master ports.
  input  resp_t [Cfg.NoMstPorts-1:0][Cfg.NoSlvPorts-1:0]                mst_ports_resp_i,
  /// Address map array input for the crossbar. This map is global for the whole module.
  /// It is used for routing the transactions to the respective master ports.
  /// Each master port can have multiple different rules.
  input  rule_t     [Cfg.NoAddrRules-1:0]                               addr_map_i,
  /// Enable default master port.
  input  logic      [Cfg.NoSlvPorts-1:0]                                en_default_mst_port_i,
`ifdef VCS
  /// Enables a default master port for each slave port. When this is enabled unmapped
  /// transactions get issued at the master port given by `default_mst_port_i`.
  /// When not used, tie to `'0`.
  input  logic      [Cfg.NoSlvPorts-1:0][MstPortsIdxWidth-1:0]          default_mst_port_i
`else
  /// Enables a default master port for each slave port. When this is enabled unmapped
  /// transactions get issued at the master port given by `default_mst_port_i`.
  /// When not used, tie to `'0`.
  input  logic      [Cfg.NoSlvPorts-1:0][MstPortsIdxWidth-1:0] default_mst_port_i
`endif
);

  // Address tpye for inidvidual address signals
  typedef logic [Cfg.AxiAddrWidth-1:0] addr_t;
  // to account for the decoding error slave
  localparam MstPortsIdxWidthOne = $clog2(NoMstPorts+1);
`ifdef VCS
  typedef logic [MstPortsIdxWidthOne-1:0]           mst_port_idx_t;
`else
  typedef logic [MstPortsIdxWidthOne-1:0] mst_port_idx_t;
`endif

  // signals from the axi_demuxes, one index more for decode error
  req_t  [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_reqs;
  resp_t [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_resps;

  // workaround for issue #133 (problem with vsim 10.6c)
  localparam int unsigned cfg_NoMstPorts = Cfg.NoMstPorts;

  for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_slv_port_demux
`ifdef VCS
    logic [MstPortsIdxWidth-1:0]          dec_aw,        dec_ar;
`else
    logic [MstPortsIdxWidth-1:0] dec_aw,        dec_ar;
`endif
    mst_port_idx_t                        slv_aw_select, slv_ar_select;
    logic                                 dec_aw_valid,  dec_aw_error;
    logic                                 dec_ar_valid,  dec_ar_error;

    addr_decode #(
      .NoIndices  ( Cfg.NoMstPorts  ),
      .NoRules    ( Cfg.NoAddrRules ),
      .addr_t     ( addr_t          ),
      .rule_t     ( rule_t          )
    ) i_axi_aw_decode (
      .addr_i           ( slv_ports_req_i[i].aw.addr ),
      .addr_map_i       ( addr_map_i                 ),
      .idx_o            ( dec_aw                     ),
      .dec_valid_o      ( dec_aw_valid               ),
      .dec_error_o      ( dec_aw_error               ),
      .en_default_idx_i ( en_default_mst_port_i[i]   ),
      .default_idx_i    ( default_mst_port_i[i]      )
    );

    addr_decode #(
      .NoIndices  ( Cfg.NoMstPorts  ),
      .addr_t     ( addr_t          ),
      .NoRules    ( Cfg.NoAddrRules ),
      .rule_t     ( rule_t          )
    ) i_axi_ar_decode (
      .addr_i           ( slv_ports_req_i[i].ar.addr ),
      .addr_map_i       ( addr_map_i                 ),
      .idx_o            ( dec_ar                     ),
      .dec_valid_o      ( dec_ar_valid               ),
      .dec_error_o      ( dec_ar_error               ),
      .en_default_idx_i ( en_default_mst_port_i[i]   ),
      .default_idx_i    ( default_mst_port_i[i]      )
    );

    assign slv_aw_select = (dec_aw_error) ?
        mst_port_idx_t'(Cfg.NoMstPorts) : mst_port_idx_t'(dec_aw);
    assign slv_ar_select = (dec_ar_error) ?
        mst_port_idx_t'(Cfg.NoMstPorts) : mst_port_idx_t'(dec_ar);

    axi_demux #(
      .AxiIdWidth     ( Cfg.AxiIdWidthSlvPorts ),  // ID Width
      .AtopSupport    ( ATOPs                  ),
      .aw_chan_t      ( aw_chan_t              ),  // AW Channel Type
      .w_chan_t       ( w_chan_t               ),  //  W Channel Type
      .b_chan_t       ( b_chan_t               ),  //  B Channel Type
      .ar_chan_t      ( ar_chan_t              ),  // AR Channel Type
      .r_chan_t       ( r_chan_t               ),  //  R Channel Type
      .axi_req_t      ( req_t                  ),
      .axi_resp_t     ( resp_t                 ),
      .NoMstPorts     ( Cfg.NoMstPorts + 1     ),
      .MaxTrans       ( Cfg.MaxMstTrans        ),
      .AxiLookBits    ( Cfg.AxiIdUsedSlvPorts  ),
      .UniqueIds      ( Cfg.UniqueIds          ),
      .SpillAw        ( Cfg.LatencyMode[9]     ),
      .SpillW         ( Cfg.LatencyMode[8]     ),
      .SpillB         ( Cfg.LatencyMode[7]     ),
      .SpillAr        ( Cfg.LatencyMode[6]     ),
      .SpillR         ( Cfg.LatencyMode[5]     )
    ) i_axi_demux (
      .clk_i,   // Clock
      .rst_ni,  // Asynchronous reset active low
      .test_i,  // Testmode enable
      .slv_req_i       ( slv_ports_req_i[i]  ),
      .slv_aw_select_i ( slv_aw_select       ),
      .slv_ar_select_i ( slv_ar_select       ),
      .slv_resp_o      ( slv_ports_resp_o[i] ),
      .mst_reqs_o      ( slv_reqs[i]         ),
      .mst_resps_i     ( slv_resps[i]        )
    );

    axi_err_slv #(
      .AxiIdWidth  ( Cfg.AxiIdWidthSlvPorts ),
      .axi_req_t   ( req_t                  ),
      .axi_resp_t  ( resp_t                 ),
      .Resp        ( `AXI_RESP_DECERR   ),
      .ATOPs       ( ATOPs                  ),
      .MaxTrans    ( 4                      )   // Transactions terminate at this slave, so minimize
                                                // resource consumption by accepting only a few
                                                // transactions at a time.
    ) i_axi_err_slv (
      .clk_i,   // Clock
      .rst_ni,  // Asynchronous reset active low
      .test_i,  // Testmode enable
      // slave port
      .slv_req_i  ( slv_reqs[i][Cfg.NoMstPorts]   ),
      .slv_resp_o ( slv_resps[i][cfg_NoMstPorts]  )
    );
  end

  // cross all channels
  for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_xbar_slv_cross
    for (genvar j = 0; j < Cfg.NoMstPorts; j++) begin : gen_xbar_mst_cross
      if (Connectivity[i][j]) begin : gen_connection
        axi_multicut #(
          .NoCuts     ( Cfg.PipelineStages ),
          .aw_chan_t  ( aw_chan_t          ),
          .w_chan_t   ( w_chan_t           ),
          .b_chan_t   ( b_chan_t           ),
          .ar_chan_t  ( ar_chan_t          ),
          .r_chan_t   ( r_chan_t           ),
          .axi_req_t  ( req_t              ),
          .axi_resp_t ( resp_t             )
        ) i_axi_multicut_xbar_pipeline (
          .clk_i,
          .rst_ni,
          .slv_req_i  ( slv_reqs[i][j]         ),
          .slv_resp_o ( slv_resps[i][j]        ),
          .mst_req_o  ( mst_ports_req_o[j][i]  ),
          .mst_resp_i ( mst_ports_resp_i[j][i] )
        );

      end else begin : gen_no_connection
        assign mst_ports_req_o[j][i] = '0;
        axi_err_slv #(
          .AxiIdWidth ( Cfg.AxiIdWidthSlvPorts  ),
          .axi_req_t  ( req_t                   ),
          .axi_resp_t ( resp_t                  ),
          .Resp       ( `AXI_RESP_DECERR    ),
          .ATOPs      ( ATOPs                   ),
          .MaxTrans   ( 1                       )
        ) i_axi_err_slv (
          .clk_i,
          .rst_ni,
          .test_i,
          .slv_req_i  ( slv_reqs[i][j]  ),
          .slv_resp_o ( slv_resps[i][j] )
        );
      end
    end
  end
endmodule