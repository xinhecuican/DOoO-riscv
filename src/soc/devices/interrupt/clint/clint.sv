// Copyright (c) 2023 Beijing Institute of Open Source Chip
// clint is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "../../../../defines/clint_define.sv"

module apb4_clint (
    input logic clk,
    input logic rtc_clk,
    input logic rst_n_i,
    ApbIO.slave apb4,
    ClintIO.clint clint
);

  logic [15:0] s_apb4_addr;
  logic s_apb4_wr_hdshk, s_apb4_rd_hdshk;
  logic [`CLINT_MSIP_WIDTH-1:0] s_msip_d, s_msip_q;
  logic s_msip_en;
  logic [`CLINT_MTIME_WIDTH-1:0] s_mtime_d, s_mtime_q;
  logic s_mtime_en;
  logic [`CLINT_MTIMECMP_WIDTH-1:0] s_mtimecmp_d, s_mtimecmp_q;
  logic s_mtimecmp_en;
  logic s_rtc_rise_edge;

  assign s_apb4_addr     = apb4.paddr[15: 0];
  assign s_apb4_wr_hdshk = (apb4.psel && apb4.penable) && apb4.pwrite;
  /*verilator lint_off UNOPTFLAT*/
  assign s_apb4_rd_hdshk = (apb4.psel && apb4.penable) && (~apb4.pwrite);
  assign apb4.pready     = 1'b1;
  assign apb4.pslverr    = 1'b0;

`ifdef DIFFTEST
  assign s_rtc_rise_edge = 1'b1;
`else
  edge_det_re #(2, 1) u_edge_det_re (
      .clk_i  (clk),
      .rst_n_i,
      .dat_i  (rtc_clk),
      .re_o   (s_rtc_rise_edge)
  );
`endif

  assign s_msip_en = s_apb4_wr_hdshk && s_apb4_addr == `CLINT_MSIP;
  assign s_msip_d  = apb4.pwdata[`CLINT_MSIP_WIDTH-1:0];
  dffer #(`CLINT_MSIP_WIDTH) u_msip_dffer (
      clk,
      rst_n_i,
      s_msip_en,
      s_msip_d,
      s_msip_q
  );

  assign s_mtime_en = s_rtc_rise_edge;
  assign s_mtime_d  = s_mtime_q + 1'b1;
  dffer #(`CLINT_MTIME_WIDTH) u_mtime_dffer (
      clk,
      rst_n_i,
      s_mtime_en,
      s_mtime_d,
      s_mtime_q
  );

  assign s_mtimecmp_en = s_apb4_wr_hdshk && (s_apb4_addr == `CLINT_MTIMECMPL || s_apb4_addr == `CLINT_MTIMECMPH);
  always_comb begin
    s_mtimecmp_d = s_mtimecmp_q;
    if (s_apb4_wr_hdshk) begin
      unique case (s_apb4_addr)
        `CLINT_MTIMECMPL: s_mtimecmp_d = {s_mtimecmp_q[63:32], apb4.pwdata};
        `CLINT_MTIMECMPH: s_mtimecmp_d = {apb4.pwdata, s_mtimecmp_q[31:0]};
        default:          s_mtimecmp_d = s_mtimecmp_q;
      endcase
    end
  end
  dfferh #(`CLINT_MTIMECMP_WIDTH) u_mtimecmp_dfferh (
      clk,
      rst_n_i,
      s_mtimecmp_en,
      s_mtimecmp_d,
      s_mtimecmp_q
  );

  always_ff @(posedge clk)begin
    clint.timer_irq <= s_mtime_q >= s_mtimecmp_q;
    clint.soft_irq <= s_msip_q[0];
    clint.mtime <= s_mtime_q;
  end
  

  always_comb begin
    apb4.prdata = '0;
    if (s_apb4_rd_hdshk) begin
      unique case (s_apb4_addr)
        `CLINT_MSIP:      apb4.prdata = s_msip_q;
        `CLINT_MTIMEL:    apb4.prdata = s_mtime_q[31:0];
        `CLINT_MTIMEH:    apb4.prdata = s_mtime_q[63:32];
        `CLINT_MTIMECMPL: apb4.prdata = s_mtimecmp_q[31:0];
        `CLINT_MTIMECMPH: apb4.prdata = s_mtimecmp_q[63:32];
        default:          apb4.prdata = '0;
      endcase
    end
  end

endmodule
