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

`include "../../defines/defines.svh"

/// Destination-clock-domain half of the AXI CDC crossing.
///
/// For each of the five AXI channels, this module instantiates the source or destination half of
/// a CDC FIFO.  IMPORTANT: For each AXI channel, you MUST properly constrain three paths through
/// the FIFO; see the header of `cdc_fifo_gray` for instructions.
module axi_cdc_dst #(
  /// Depth of the FIFO crossing the clock domain, given as 2**LOG_DEPTH.
  parameter int unsigned LogDepth = 1,
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
  // asynchronous slave port
  input  aw_chan_t  [2**LogDepth-1:0] async_data_slave_aw_data_i,
  input  logic           [LogDepth:0] async_data_slave_aw_wptr_i,
  output logic           [LogDepth:0] async_data_slave_aw_rptr_o,
  input  w_chan_t   [2**LogDepth-1:0] async_data_slave_w_data_i,
  input  logic           [LogDepth:0] async_data_slave_w_wptr_i,
  output logic           [LogDepth:0] async_data_slave_w_rptr_o,
  output b_chan_t   [2**LogDepth-1:0] async_data_slave_b_data_o,
  output logic           [LogDepth:0] async_data_slave_b_wptr_o,
  input  logic           [LogDepth:0] async_data_slave_b_rptr_i,
  input  ar_chan_t  [2**LogDepth-1:0] async_data_slave_ar_data_i,
  input  logic           [LogDepth:0] async_data_slave_ar_wptr_i,
  output logic           [LogDepth:0] async_data_slave_ar_rptr_o,
  output r_chan_t   [2**LogDepth-1:0] async_data_slave_r_data_o,
  output logic           [LogDepth:0] async_data_slave_r_wptr_o,
  input  logic           [LogDepth:0] async_data_slave_r_rptr_i,
  // synchronous master port - clocked by `dst_clk_i`
  input  logic                        dst_clk_i,
  input  logic                        dst_rst_ni,
  output axi_req_t                    dst_req_o,
  input  axi_resp_t                   dst_resp_i
);

  cdc_fifo_gray_dst #(
`ifdef QUESTA
    // Workaround for a bug in Questa: Pass flat logic vector instead of struct to type parameter.
    .T          ( logic [$bits(aw_chan_t)-1:0]  ),
`else
    // Other tools, such as VCS, have problems with type parameters constructed through `$bits()`.
    .T          ( aw_chan_t                     ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_dst_aw (
    .async_data_i ( async_data_slave_aw_data_i  ),
    .async_wptr_i ( async_data_slave_aw_wptr_i  ),
    .async_rptr_o ( async_data_slave_aw_rptr_o  ),
    .dst_clk_i,
    .dst_rst_ni,
    .dst_data_o   ( dst_req_o.aw                ),
    .dst_valid_o  ( dst_req_o.aw_valid          ),
    .dst_ready_i  ( dst_resp_i.aw_ready         )
  );

  cdc_fifo_gray_dst #(
`ifdef QUESTA
    .T          ( logic [$bits(w_chan_t)-1:0] ),
`else
    .T          ( w_chan_t                    ),
`endif
    .LOG_DEPTH   ( LogDepth                    ),
    .SYNC_STAGES ( SyncStages                  )
  ) i_cdc_fifo_gray_dst_w (
    .async_data_i ( async_data_slave_w_data_i ),
    .async_wptr_i ( async_data_slave_w_wptr_i ),
    .async_rptr_o ( async_data_slave_w_rptr_o ),
    .dst_clk_i,
    .dst_rst_ni,
    .dst_data_o   ( dst_req_o.w               ),
    .dst_valid_o  ( dst_req_o.w_valid         ),
    .dst_ready_i  ( dst_resp_i.w_ready        )
  );

  cdc_fifo_gray_src #(
`ifdef QUESTA
    .T          ( logic [$bits(b_chan_t)-1:0] ),
`else
    .T          ( b_chan_t                    ),
`endif
    .LOG_DEPTH   ( LogDepth                    ),
    .SYNC_STAGES ( SyncStages                  )
  ) i_cdc_fifo_gray_src_b (
    .src_clk_i    ( dst_clk_i                 ),
    .src_rst_ni   ( dst_rst_ni                ),
    .src_data_i   ( dst_resp_i.b              ),
    .src_valid_i  ( dst_resp_i.b_valid        ),
    .src_ready_o  ( dst_req_o.b_ready         ),
    .async_data_o ( async_data_slave_b_data_o ),
    .async_wptr_o ( async_data_slave_b_wptr_o ),
    .async_rptr_i ( async_data_slave_b_rptr_i )
  );

  cdc_fifo_gray_dst #(
`ifdef QUESTA
    .T          ( logic [$bits(ar_chan_t)-1:0]  ),
`else
    .T          ( ar_chan_t                     ),
`endif
    .LOG_DEPTH   ( LogDepth                     ),
    .SYNC_STAGES ( SyncStages                   )
  ) i_cdc_fifo_gray_dst_ar (
    .dst_clk_i,
    .dst_rst_ni,
    .dst_data_o   ( dst_req_o.ar                ),
    .dst_valid_o  ( dst_req_o.ar_valid          ),
    .dst_ready_i  ( dst_resp_i.ar_ready         ),
    .async_data_i ( async_data_slave_ar_data_i  ),
    .async_wptr_i ( async_data_slave_ar_wptr_i  ),
    .async_rptr_o ( async_data_slave_ar_rptr_o  )
  );

  cdc_fifo_gray_src #(
`ifdef QUESTA
    .T          ( logic [$bits(r_chan_t)-1:0] ),
`else
    .T          ( r_chan_t                    ),
`endif
    .LOG_DEPTH   ( LogDepth                    ),
    .SYNC_STAGES ( SyncStages                  )
  ) i_cdc_fifo_gray_src_r (
    .src_clk_i    ( dst_clk_i                 ),
    .src_rst_ni   ( dst_rst_ni                ),
    .src_data_i   ( dst_resp_i.r              ),
    .src_valid_i  ( dst_resp_i.r_valid        ),
    .src_ready_o  ( dst_req_o.r_ready         ),
    .async_data_o ( async_data_slave_r_data_o ),
    .async_wptr_o ( async_data_slave_r_wptr_o ),
    .async_rptr_i ( async_data_slave_r_rptr_i )
  );

endmodule