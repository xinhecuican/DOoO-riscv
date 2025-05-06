`include "../../../../defines/defines.svh"
`include "../../../../defines/devices.svh"

module plic #(
    parameter INT_NUM = 32
) (
    input                        clk,
    input                        rstn,
    ApbIO.slave                  apb,

    output logic [`NUM_CORE-1: 0] meip,
    output logic [`NUM_CORE-1: 0] seip,
    input        [INT_NUM-1: 0] ints
);

logic [        31:0] claim_id    [2*`NUM_CORE];
logic [        31:0] cmplet_id   [2*`NUM_CORE];

logic [INT_NUM-1:1] claim;
logic [INT_NUM-1:1] cmplet;

logic [INT_NUM-1:0] int_pend;
logic [INT_NUM-1:0] int_type;
logic [INT_NUM-1:0] int_pol;
logic [        31:0] int_prior   [    INT_NUM];
logic [INT_NUM-1:0] int_en      [2*`NUM_CORE];
logic [        31:0] int_id      [2*`NUM_CORE];
logic [        31:0] threshold   [2*`NUM_CORE];

logic [        31:0] int_id_tmp  [2*`NUM_CORE];
logic [        31:0] int_max_pri [2*`NUM_CORE];

logic                apb_wr;

logic [        31:0] prdata_t;
logic [        31:0] prdata_pri;
logic [        31:0] prdata_ip;
logic [        31:0] prdata_ityp;
logic [        31:0] prdata_ipol;
logic [        31:0] prdata_ie;
logic [        31:0] prdata_id;
logic [        31:0] prdata_th;

`define CMP_TREE_L0_NUM  (INT_NUM)                                  // MAX: 1024
`define CMP_TREE_L1_NUM  (`CMP_TREE_L0_NUM/2 + `CMP_TREE_L0_NUM%2)   // MAX:  512
`define CMP_TREE_L2_NUM  (`CMP_TREE_L1_NUM/2 + `CMP_TREE_L1_NUM%2)   // MAX:  256
`define CMP_TREE_L3_NUM  (`CMP_TREE_L2_NUM/2 + `CMP_TREE_L2_NUM%2)   // MAX:  128
`define CMP_TREE_L4_NUM  (`CMP_TREE_L3_NUM/2 + `CMP_TREE_L3_NUM%2)   // MAX:   64
`define CMP_TREE_L5_NUM  (`CMP_TREE_L4_NUM/2 + `CMP_TREE_L4_NUM%2)   // MAX:   32
`define CMP_TREE_L6_NUM  (`CMP_TREE_L5_NUM/2 + `CMP_TREE_L5_NUM%2)   // MAX:   16
`define CMP_TREE_L7_NUM  (`CMP_TREE_L6_NUM/2 + `CMP_TREE_L6_NUM%2)   // MAX:    8
`define CMP_TREE_L8_NUM  (`CMP_TREE_L7_NUM/2 + `CMP_TREE_L7_NUM%2)   // MAX:    4
`define CMP_TREE_L9_NUM  (`CMP_TREE_L8_NUM/2 + `CMP_TREE_L8_NUM%2)   // MAX:    2
`define CMP_TREE_L10_NUM (`CMP_TREE_L9_NUM/2 + `CMP_TREE_L9_NUM%2)   // MAX:    1

parameter int CMP_TREE_NUM [0:10] = {
    `CMP_TREE_L0_NUM, 
    `CMP_TREE_L1_NUM, 
    `CMP_TREE_L2_NUM, 
    `CMP_TREE_L3_NUM, 
    `CMP_TREE_L4_NUM, 
    `CMP_TREE_L5_NUM, 
    `CMP_TREE_L6_NUM, 
    `CMP_TREE_L7_NUM, 
    `CMP_TREE_L8_NUM, 
    `CMP_TREE_L9_NUM, 
    `CMP_TREE_L10_NUM
};

genvar gvar_i;
genvar gvar_j;
genvar gvar_k;
generate
    for (gvar_i = 1; gvar_i < INT_NUM; gvar_i = gvar_i + 1) begin: g_gateway

        always_comb begin
            integer i;
            claim [gvar_i] = 1'b0;
            cmplet[gvar_i] = 1'b0;
            for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
                claim [gvar_i] = claim [gvar_i] | (claim_id [i][0+:$clog2(INT_NUM)] == gvar_i[0+:$clog2(INT_NUM)]);
                cmplet[gvar_i] = cmplet[gvar_i] | (cmplet_id[i][0+:$clog2(INT_NUM)] == gvar_i[0+:$clog2(INT_NUM)]);
            end
        end

        gateway u_gateway(
            .clk      ( clk    ),
            .rstn     ( rstn ),
            .src      ( ints    [gvar_i] ),
            .src_type ( int_type[gvar_i] ), // 0: edge, 1: level
            .src_pol  ( int_pol [gvar_i] ), // 0: high, 1: low
            .claim    ( claim   [gvar_i] ),
            .cmplet   ( cmplet  [gvar_i] ),
            .pend     ( int_pend[gvar_i] )
        );
    end

    assign int_pend[0] = 1'b0;

    for (gvar_i = 0; gvar_i < 2*`NUM_CORE; gvar_i = gvar_i + 1) begin: g_target
        logic [INT_NUM-1:0] ip_ie_ints;
        logic [        31:0] en_ints_pri [11][`CMP_TREE_L0_NUM] /*verilator split_var*/;
        logic [         9:0] id_sel      [11][`CMP_TREE_L0_NUM] /*verilator split_var*/;
        
        assign ip_ie_ints = int_pend & int_en[gvar_i];
        for(gvar_j = 0; gvar_j < INT_NUM; gvar_j = gvar_j + 1) begin
            assign en_ints_pri[0][gvar_j] = {32{ip_ie_ints[gvar_j]}} & int_prior[gvar_j];
        end

        for (gvar_j = 0; gvar_j < 10; gvar_j = gvar_j + 1) begin: g_cmp_tree_lvl
            if (gvar_j % 3 == 2) begin: g_pipelining
                for (gvar_k = 0; gvar_k <= CMP_TREE_NUM[gvar_j] - 1; gvar_k = gvar_k + 2) begin: g_cmp
                    if (gvar_k == CMP_TREE_NUM[gvar_j] - 1) begin: g_remainder
                        always_ff @(posedge clk or negedge rstn) begin
                            if (~rstn) begin
                                en_ints_pri[gvar_j+1][gvar_k>>1]     <= 32'b0;
                                id_sel[gvar_j+1][gvar_k>>1][gvar_j]  <= 1'b0;
                            end
                            else begin
                                en_ints_pri[gvar_j+1][gvar_k>>1]     <= en_ints_pri[gvar_j][gvar_k];
                                id_sel[gvar_j+1][gvar_k>>1][gvar_j]  <= 1'b0;
                            end
                        end
                        if (gvar_j > 0) begin: g_non_first
                            always_ff @(posedge clk or negedge rstn) begin
                                if (~rstn) begin
                                    id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] <= {gvar_j{1'b0}};
                                end
                                else begin
                                    id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] <= id_sel[gvar_j][gvar_k][0+:gvar_j];
                                end
                            end
                        end
                    end
                    else begin: g_cmp
                        always_ff @(posedge clk or negedge rstn) begin
                            if (~rstn) begin
                                en_ints_pri[gvar_j+1][gvar_k>>1]     <= 32'b0;
                                id_sel[gvar_j+1][gvar_k>>1][gvar_j]  <= 1'b0;
                            end
                            else begin
                                if (en_ints_pri[gvar_j][gvar_k] < en_ints_pri[gvar_j][gvar_k + 1]) begin
                                    en_ints_pri[gvar_j+1][gvar_k>>1]     <= en_ints_pri[gvar_j][gvar_k + 1];
                                    id_sel[gvar_j+1][gvar_k>>1][gvar_j]  <= 1'b1;
                                end
                                else begin
                                    en_ints_pri[gvar_j+1][gvar_k>>1]     <= en_ints_pri[gvar_j][gvar_k];
                                    id_sel[gvar_j+1][gvar_k>>1][gvar_j]  <= 1'b0;
                                end
                            end
                        end
                        if (gvar_j > 0) begin: g_non_first
                            always_ff @(posedge clk or negedge rstn) begin
                                if (~rstn) begin
                                    id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] <= {gvar_j{1'b0}};
                                end
                                else begin
                                    if (en_ints_pri[gvar_j][gvar_k] < en_ints_pri[gvar_j][gvar_k + 1]) begin
                                        id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] <= id_sel[gvar_j][gvar_k+1][0+:gvar_j];
                                    end
                                    else begin
                                        id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] <= id_sel[gvar_j][gvar_k][0+:gvar_j];
                                    end
                                end
                            end
                        end
                    end
                end
            end
            else begin: g_non_pipelining
                for (gvar_k = 0; gvar_k <= CMP_TREE_NUM[gvar_j] - 1; gvar_k = gvar_k + 2) begin: g_cmp
                    if (gvar_k == CMP_TREE_NUM[gvar_j] - 1) begin: g_remainder
                        assign en_ints_pri[gvar_j+1][gvar_k>>1]     = en_ints_pri[gvar_j][gvar_k];
                        if (gvar_j > 0) begin: g_non_first
                            assign id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] = id_sel[gvar_j][gvar_k][0+:gvar_j];
                        end
                        else begin
                            assign id_sel[gvar_j+1][gvar_k>>1][gvar_j]  = 1'b0;
                        end
                    end
                    else begin: g_cmp
                        assign en_ints_pri[gvar_j+1][gvar_k>>1] = en_ints_pri[gvar_j][gvar_k] < en_ints_pri[gvar_j][gvar_k + 1] ?
                                                                en_ints_pri[gvar_j][gvar_k + 1] : en_ints_pri[gvar_j][gvar_k];
                        if (gvar_j > 0) begin: g_non_first
                            assign id_sel[gvar_j+1][gvar_k>>1][0+:gvar_j] = en_ints_pri[gvar_j][gvar_k] < en_ints_pri[gvar_j][gvar_k + 1] ?
                                                                    id_sel[gvar_j][gvar_k+1][0+:gvar_j] : id_sel[gvar_j][gvar_k][0+:gvar_j];
                        end
                        else begin
                            assign id_sel[gvar_j+1][gvar_k>>1][gvar_j] = en_ints_pri[gvar_j][gvar_k] < en_ints_pri[gvar_j][gvar_k + 1];
                        end
                    end
                end
            end
        end
        
        assign int_id_tmp[gvar_i]  = {22'b0, id_sel[10][0][9:0]};
        assign int_max_pri[gvar_i] = en_ints_pri[10][0];
    end
endgenerate

always_comb begin: comb_meip
    integer i;
    for (i = 0; i < `NUM_CORE; i = i + 1) begin
        meip[i] = claim_id[i*2  ] != int_id[i*2  ];
        seip[i] = claim_id[i*2+1] != int_id[i*2+1];
    end
end

always_comb begin: comb_apb_wr
    apb_wr = ~apb.penable & apb.psel & apb.pwrite;
end

always_ff @(posedge clk or negedge rstn) begin: reg_int_prior
    integer i;
    if (~rstn) begin
        for (i = 0; i < INT_NUM; i = i + 1) begin
            int_prior[i] <= 32'b0;
        end
    end
    else if (apb_wr) begin
        for (i = 1; i < INT_NUM; i = i + 1) begin
            if (apb.paddr[25:0] == `PLIC_INT_PRIOR + 26'h4 * i[25:0]) begin
                int_prior[i] <= apb.pwdata;
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_int_type
    integer i;
    if (~rstn) begin
        int_type <= {INT_NUM{1'b1}};
    end
    else if (apb_wr) begin
        for (i = 0; i < INT_NUM; i = i + 32) begin
            if (apb.paddr[25:0] == `PLIC_INT_TYPE + i[28:3]) begin
                int_type[i+:32] <= apb.pwdata;
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_int_pol
    integer i;
    if (~rstn) begin
        int_pol <= {INT_NUM{1'b0}};
    end
    else if (apb_wr) begin
        for (i = 0; i < INT_NUM; i = i + 32) begin
            if (apb.paddr[25:0] == `PLIC_INT_POL + i[28:3]) begin
                int_pol[i+:32] <= apb.pwdata;
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_int_en
    integer i, j;
    if (~rstn) begin
        for (j = 0; j < 2*`NUM_CORE; j = j + 1) begin
            int_en[j] <= {INT_NUM{1'b0}};
        end
    end
    else if (apb_wr) begin
        for (j = 0; j < 2*`NUM_CORE; j = j + 1) begin
            for (i = 0; i < INT_NUM; i = i + 32) begin
                if (apb.paddr[25:0] == `PLIC_INT_EN + i[28:3] + 26'h80 * j[25:0]) begin
                    int_en[j][i+:32] <= apb.pwdata;
                end
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_threshold
    integer i;
    if (~rstn) begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            threshold[i] <= 32'b0;
        end
    end
    else if (apb_wr) begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            if (apb.paddr[25:0] == `PLIC_PRIOR_TH + 26'h1000 * i[25:0]) begin
                threshold[i] <= apb.pwdata;
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_int_id
    integer i;
    if (~rstn) begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            int_id   [i] <= 32'b0;
        end
    end
    else begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            if (!(~apb.penable && apb.psel &&
                apb.paddr[25:0] == `PLIC_PRIOR_TH + 26'h1000 * i[25:0] + 26'h4)) begin
                if (~|claim_id[i]) begin // non-preemptive
                    int_id   [i] <= int_max_pri[i] > threshold[i] ? int_id_tmp[i] : 32'b0;
                end
            end
            else if (apb.pwrite) begin
                int_id   [i] <= 32'b0;
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_claim_id
    integer i;
    if (~rstn) begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            claim_id [i] <= 32'b0;
        end
    end
    else begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            if (~apb.penable && apb.psel &&
                apb.paddr[25:0] == `PLIC_PRIOR_TH + 26'h1000 * i[25:0] + 26'h4) begin
                claim_id [i] <= apb.pwrite ? 32'b0 : int_id[i];
            end
        end
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_cmplet_id
    integer i;
    if (~rstn) begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            cmplet_id[i] <= 32'b0;
        end
    end
    else begin
        for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
            if (apb_wr && apb.paddr[25:0] == `PLIC_PRIOR_TH + 26'h1000 * i[25:0] + 26'h4) begin
                cmplet_id[i] <= claim_id[i];
            end
            else begin
                cmplet_id[i] <= 32'b0;
            end
        end
    end
end

always_comb begin: comb_prdata_pri
    integer i;
    prdata_pri = 32'b0;
    for (i = 0; i < INT_NUM; i = i + 1) begin
        prdata_pri = prdata_pri |
                    (int_prior[i] & {32{apb.paddr[25:0] == `PLIC_INT_PRIOR + 26'h4 * i[25:0]}});
    end
end

always_comb begin: comb_prdata_ip
    integer i;
    prdata_ip = 32'b0;
    for (i = 0; i < INT_NUM; i = i + 32) begin
        prdata_ip = prdata_ip |
                    (int_pend[i+:32] & {32{apb.paddr[25:0] == `PLIC_INT_PEND + i[28:3]}});
    end
end

always_comb begin: comb_prdata_ityp
    integer i;
    prdata_ityp = 32'b0;
    for (i = 0; i < INT_NUM; i = i + 32) begin
        prdata_ityp = prdata_ityp |
                      (int_type[i+:32] & {32{apb.paddr[25:0] == `PLIC_INT_TYPE + i[28:3]}});
    end
end

always_comb begin: comb_prdata_ipol
    integer i;
    prdata_ipol = 32'b0;
    for (i = 0; i < INT_NUM; i = i + 32) begin
        prdata_ipol = prdata_ipol |
                      (int_pol[i+:32] & {32{apb.paddr[25:0] == `PLIC_INT_POL + i[28:3]}});
    end
end

always_comb begin: comb_prdata_ie
    integer i, j;
    prdata_ie = 32'b0;
    for (j = 0; j < 2*`NUM_CORE; j = j + 1) begin
        for (i = 0; i < INT_NUM; i = i + 32) begin
            prdata_ie = prdata_ie |
                        (int_en[j][i+:32] &
                         {32{apb.paddr[25:0] == `PLIC_INT_EN + i[28:3] + 26'h80 * j[25:0]}});
        end
    end
end

always_comb begin: comb_prdata_th
    integer i;
    prdata_th = 32'b0;
    for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
        prdata_th = prdata_th |
                    (threshold[i] & {32{apb.paddr[25:0] == `PLIC_PRIOR_TH + 26'h1000 * i[25:0]}});
    end
end

always_comb begin: comb_prdata_id
    integer i;
    prdata_id = 32'b0;
    for (i = 0; i < 2*`NUM_CORE; i = i + 1) begin
        prdata_id = prdata_id |
                    (int_id[i] & {32{apb.paddr[25:0] == `PLIC_PRIOR_TH + 26'h1000 * i[25:0] + 26'h4}});
    end
end

assign prdata_t = prdata_pri | prdata_ip | prdata_ityp | prdata_ipol | prdata_ie | prdata_id | prdata_th;

always_ff @(posedge clk or negedge rstn) begin: reg_rdata
    if (~rstn) begin
        apb.prdata <= 32'b0;
    end
    else begin
        apb.prdata <= prdata_t;
    end
end

assign apb.pslverr = 1'b0;
assign apb.pready  = 1'b1;

endmodule


module gateway (
    input        clk,
    input        rstn,
    input        src,
    input        src_type, // 0: edge, 1: level
    input        src_pol,  // 0: high, 1: low
    input        claim,
    input        cmplet,
    output logic pend
);

parameter [1:0] STATE_IDLE  = 2'b00,
                STATE_PEND  = 2'b01,
                STATE_CLAIM = 2'b10;

logic [1:0] cur_state;
logic [1:0] nxt_state;

logic       src_pol_dly;
logic       src_lvl;
logic       src_edge;
logic       is_pend;
logic       is_claim;
logic       is_cancel;
logic       is_cmplet;
logic       src_tmp;

always_ff @(posedge clk or negedge rstn) begin: fsm
    if (~rstn) begin
        cur_state <= STATE_IDLE;
    end
    else begin
        cur_state <= nxt_state;
    end
end

always_comb begin: next_state
    nxt_state = cur_state;
    case (cur_state)
        STATE_IDLE : nxt_state = is_pend   ? STATE_PEND  : STATE_IDLE;
        STATE_PEND : nxt_state = is_claim  ? STATE_CLAIM :
                                 is_cancel ? STATE_IDLE  : STATE_PEND;
        STATE_CLAIM: nxt_state = is_cmplet ? STATE_IDLE  : STATE_CLAIM;
        default: nxt_state = cur_state;
    endcase
end

assign src_tmp = src ^ src_pol;

always_ff @(posedge clk or negedge rstn) begin: reg_src_pol_dly
    if (~rstn) begin
        src_pol_dly  <= 1'b0;
    end
    else begin
        src_pol_dly  <= src_pol;
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_src_lvl
    if (~rstn) begin
        src_lvl <= 1'b0;
    end
    else begin
        src_lvl <= src_tmp;
    end
end

always_ff @(posedge clk or negedge rstn) begin: reg_src_edge
    if (~rstn) begin
        src_edge <= 1'b0;
    end
    else begin
        src_edge <= ~src_lvl & src_tmp;
    end
end

assign is_pend   = src_type ?  src_lvl : src_edge;
assign is_claim  = claim;
assign is_cancel = (src_type ? ~src_lvl : 1'b0) | (src_pol ^ src_pol_dly);
assign is_cmplet = cmplet;

assign pend      = cur_state == STATE_PEND;

endmodule