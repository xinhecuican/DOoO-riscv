// Copyright (c) 2019-2020 ETH Zurich, University of Bologna
//
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
// - Luca Valente <luca.valente@unibo.it>
// - Andreas Kurth <akurth@iis.ee.ethz.ch>

`include "../../../defines/defines.svh"

/// Source-clock-domain half of the AXI CDC crossing.
///
/// For each of the five AXI channels, this module instantiates the source or destination half of
/// a CDC FIFO.  IMPORTANT: For each AXI channel, you MUST properly constrain three paths through
/// the FIFO; see the header of `cdc_fifo_gray` for instructions.
module axi_cdc_src #(
  /// Depth of the FIFO crossing the clock domain, given as 2**LOG_DEPTH.
  parameter int unsigned LogDepth   = 1,
  /// Number of synchronization registers to insert on the async pointers
  parameter int unsigned SyncStages = 2,
  parameter type aw_chan_t = logic,
  parameter type w_chan_t = logic,
  parameter type b_chan_t = logic,
  parameter type ar_chan_t = logic,
  parameter type r_chan_t = logic,
  parameter type axi_req_t = logic,
  parameter type axi_resp_t = logic
) (
  // synchronous slave port - clocked by `src_clk_i`
  input  logic                        src_clk_i,
  input  logic                        src_rst_ni,
  input  axi_req_t                    src_req_i,
  output axi_resp_t                   src_resp_o,
  // asynchronous master port
  output aw_chan_t  [2**LogDepth-1:0] async_data_master_aw_data_o,
  output logic           [LogDepth:0] async_data_master_aw_wptr_o,
  input  logic           [LogDepth:0] async_data_master_aw_rptr_i,
  output w_chan_t   [2**LogDepth-1:0] async_data_master_w_data_o,
  output logic           [LogDepth:0] async_data_master_w_wptr_o,
  input  logic           [LogDepth:0] async_data_master_w_rptr_i,
  input  b_chan_t   [2**LogDepth-1:0] async_data_master_b_data_i,
  input  logic           [LogDepth:0] async_data_master_b_wptr_i,
  output logic           [LogDepth:0] async_data_master_b_rptr_o,
  output ar_chan_t  [2**LogDepth-1:0] async_data_master_ar_data_o,
  output logic           [LogDepth:0] async_data_master_ar_wptr_o,
  input  logic           [LogDepth:0] async_data_master_ar_rptr_i,
  input  r_chan_t   [2**LogDepth-1:0] async_data_master_r_data_i,
  input  logic           [LogDepth:0] async_data_master_r_wptr_i,
  output logic           [LogDepth:0] async_data_master_r_rptr_o
);

  cdc_fifo_gray_src #(
    // Workaround for a bug in Questa (see comment in `axi_cdc_dst` for details).
`ifdef QUESTA
    .T         ( logic [$bits(aw_chan_t)-1:0] ),
`else
    .T         ( aw_chan_t                    ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_src_aw (
    .src_clk_i,
    .src_rst_ni,
    .src_data_i   ( src_req_i.aw                ),
    .src_valid_i  ( src_req_i.aw_valid          ),
    .src_ready_o  ( src_resp_o.aw_ready         ),
    .async_data_o ( async_data_master_aw_data_o ),
    .async_wptr_o ( async_data_master_aw_wptr_o ),
    .async_rptr_i ( async_data_master_aw_rptr_i )
  );

  cdc_fifo_gray_src #(
`ifdef QUESTA
    .T         ( logic [$bits(w_chan_t)-1:0]  ),
`else
    .T         ( w_chan_t                     ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_src_w (
    .src_clk_i,
    .src_rst_ni,
    .src_data_i   ( src_req_i.w                 ),
    .src_valid_i  ( src_req_i.w_valid           ),
    .src_ready_o  ( src_resp_o.w_ready          ),
    .async_data_o ( async_data_master_w_data_o  ),
    .async_wptr_o ( async_data_master_w_wptr_o  ),
    .async_rptr_i ( async_data_master_w_rptr_i  )
  );

  cdc_fifo_gray_dst #(
`ifdef QUESTA
    .T         ( logic [$bits(b_chan_t)-1:0]  ),
`else
    .T         ( b_chan_t                     ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_dst_b (
    .dst_clk_i    ( src_clk_i                   ),
    .dst_rst_ni   ( src_rst_ni                  ),
    .dst_data_o   ( src_resp_o.b                ),
    .dst_valid_o  ( src_resp_o.b_valid          ),
    .dst_ready_i  ( src_req_i.b_ready           ),
    .async_data_i ( async_data_master_b_data_i  ),
    .async_wptr_i ( async_data_master_b_wptr_i  ),
    .async_rptr_o ( async_data_master_b_rptr_o  )
  );

  cdc_fifo_gray_src #(
`ifdef QUESTA
    .T         ( logic [$bits(ar_chan_t)-1:0] ),
`else
    .T         ( ar_chan_t                    ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_src_ar (
    .src_clk_i,
    .src_rst_ni,
    .src_data_i   ( src_req_i.ar                ),
    .src_valid_i  ( src_req_i.ar_valid          ),
    .src_ready_o  ( src_resp_o.ar_ready         ),
    .async_data_o ( async_data_master_ar_data_o ),
    .async_wptr_o ( async_data_master_ar_wptr_o ),
    .async_rptr_i ( async_data_master_ar_rptr_i )
  );

  cdc_fifo_gray_dst #(
`ifdef QUESTA
    .T         ( logic [$bits(r_chan_t)-1:0]  ),
`else
    .T         ( r_chan_t                     ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_dst_r (
    .dst_clk_i    ( src_clk_i                   ),
    .dst_rst_ni   ( src_rst_ni                  ),
    .dst_data_o   ( src_resp_o.r                ),
    .dst_valid_o  ( src_resp_o.r_valid          ),
    .dst_ready_i  ( src_req_i.r_ready           ),
    .async_data_i ( async_data_master_r_data_i  ),
    .async_wptr_i ( async_data_master_r_wptr_i  ),
    .async_rptr_o ( async_data_master_r_rptr_o  )
  );

endmodule