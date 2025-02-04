module snoop_cut #(
    parameter bit Bypass = 1'b0,
    parameter type ac_chan_t = logic,
    parameter type cr_chan_t = logic,
    parameter type cd_chan_t = logic,
    parameter type snoop_id_t = logic,
    parameter type req_t = logic,
    parameter type resp_t = logic
)(
    input logic clk_i,
    input logic rst_ni,
    input req_t slv_req_i,
    output resp_t slv_resp_o,
    output req_t mst_req_o,
    input resp_t mst_resp_i
);
  spill_register #(
    .T       ( ac_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_ac (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( slv_req_i.ac_valid  ),
    .ready_o ( slv_resp_o.ac_ready ),
    .data_i  ( slv_req_i.ac        ),
    .valid_o ( mst_req_o.ac_valid  ),
    .ready_i ( mst_resp_i.ac_ready ),
    .data_o  ( mst_req_o.ac        )
  );
  
  spill_register #(
    .T       ( cr_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_cr (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( mst_resp_i.cr_valid  ),
    .ready_o ( mst_req_o.cr_ready ),
    .data_i  ( mst_resp_i.cr_resp        ),
    .valid_o ( slv_resp_o.cr_valid  ),
    .ready_i ( slv_req_i.cr_ready ),
    .data_o  ( slv_resp_o.cr_resp        )
  );
  
  spill_register #(
    .T       ( cd_chan_t ),
    .Bypass  ( Bypass    )
  ) i_reg_cd (
    .clk_i   ( clk_i               ),
    .rst_ni  ( rst_ni              ),
    .valid_i ( mst_resp_i.cd_valid  ),
    .ready_o ( mst_req_o.cd_ready ),
    .data_i  ( mst_resp_i.cd        ),
    .valid_o ( slv_resp_o.cd_valid  ),
    .ready_i ( slv_req_i.cd_ready ),
    .data_o  ( slv_resp_o.cd        )
  );

generate
    if(Bypass)begin
        assign mst_req_o.ar_snoop_id = slv_req_i.ar_snoop_id;
        assign slv_resp_o.r_snoop_id = mst_resp_i.r_snoop_id;
        assign slv_resp_o.rack = mst_resp_i.rack;
    end
    else begin
        snoop_id_t ar_snoop_id, r_snoop_id;
        logic rack;
        always_ff @(posedge clk_i, negedge rst_ni) begin
            if(~rst_ni)begin
                ar_snoop_id <= 0;
                r_snoop_id <= 0;
                rack <= 0;
            end
            else begin
                ar_snoop_id <= slv_req_i.ar_snoop_id;
                r_snoop_id <= mst_resp_i.r_snoop_id;
                rack <= mst_resp_i.rack;
            end
        end
        assign mst_req_o.ar_snoop_id = ar_snoop_id;
        assign slv_resp_o.r_snoop_id = r_snoop_id;
        assign slv_resp_o.rack = rack;
    end
endgenerate

endmodule

module snoop_multicut #(
    parameter int unsigned NoCuts = 32'd1,
    parameter type ac_chan_t = logic,
    parameter type cr_chan_t = logic,
    parameter type cd_chan_t = logic,
    parameter type snoop_id_t = logic,
    parameter type req_t = logic,
    parameter type resp_t = logic
)(
  input  logic      clk_i,   // Clock
  input  logic      rst_ni,  // Asynchronous reset active low
  // slave port
  input  req_t  slv_req_i,
  output resp_t slv_resp_o,
  // master port
  output req_t  mst_req_o,
  input  resp_t mst_resp_i
);
generate
    if(NoCuts == '0)begin
        assign mst_req_o  = slv_req_i;
        assign slv_resp_o = mst_resp_i;
    end
    else begin
        req_t  [NoCuts:0] cut_req;
        resp_t [NoCuts:0] cut_resp;

        // connect slave to the lowest index
        assign cut_req[0] = slv_req_i;
        assign slv_resp_o = cut_resp[0];

        // AXI cuts
        for (genvar i = 0; i < NoCuts; i++) begin : gen_snoop_cuts
        snoop_cut #(
            .Bypass     (       1'b0 ),
            .ac_chan_t  (  ac_chan_t ),
            .cr_chan_t   (   cr_chan_t ),
            .cd_chan_t   (   cd_chan_t ),
            .snoop_id_t ( snoop_id_t ),
            .req_t       (    req_t ),
            .resp_t      (  resp_t )
        ) i_cut (
            .clk_i,
            .rst_ni,
            .slv_req_i  ( cut_req[i]    ),
            .slv_resp_o ( cut_resp[i]   ),
            .mst_req_o  ( cut_req[i+1]  ),
            .mst_resp_i ( cut_resp[i+1] )
        );
        end

        // connect master to the highest index
        assign mst_req_o        = cut_req[NoCuts];
        assign cut_resp[NoCuts] = mst_resp_i;
    end
endgenerate
endmodule