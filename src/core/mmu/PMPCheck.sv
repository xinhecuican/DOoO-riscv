`include "../../defines/defines.svh"

module PMPCheck (
    input logic `N(`PADDR_SIZE) paddr,
    input logic `ARRAY(`PMPCFG_SIZE, `MXL) pmpcfg,
    input logic `ARRAY(`PMP_SIZE, `MXL) pmpaddr,
    input logic `ARRAY(`PMACFG_SIZE, `MXL) pmacfg,
    input logic `ARRAY(`PMA_SIZE, `MXL) pmaaddr,
    output logic pmp_v,
    output logic pmp_r,
    output logic pmp_w,
    output logic pmp_x,
    output logic pma_uc
);
    PMPCfg `N(`PMP_SIZE) pmp_cfg;
    logic `N(`PADDR_SIZE-2) paddr_cmp;
    logic `ARRAY(`PMP_SIZE, `PADDR_SIZE-2) cmpaddr;
    logic `N(`PMP_SIZE) pmp_v_all, pmp_tor, pmp_na4, pmp_napot;
    logic `N(`PMP_SIZE) pmp_r_all, pmp_w_all, pmp_x_all, pmp_v_p;

    assign pmp_cfg = pmpcfg;
    assign paddr_cmp = paddr[`PADDR_SIZE-1: 2];
    PRSelector #(`PMP_SIZE) select_pmp_v (pmp_v, pmp_v_p);
    assign pmp_v = |pmp_v_all;
    assign pmp_r = |pmp_r_all;
    assign pmp_w = |pmp_w_all;
    assign pmp_x = |pmp_x_all;
generate
    for(genvar i=0; i<`PMP_SIZE; i++)begin
        assign cmpaddr[i] = pmpaddr[`PADDR_SIZE-3: 0];
        assign pmp_na4[i] = paddr_cmp == cmpaddr[i];
        assign pmp_v_all[i] = ((pmp_cfg[i].a == `PMP_TOR) & pmp_tor[i]) |
                          ((pmp_cfg[i].a == `PMP_NA4) & pmp_na4[i]) |
                          ((pmp_cfg[i].a == `PMP_NAPOT) & pmp_napot[i]);
        logic `N($clog2(`PADDR_SIZE-2)+1) cnt;
        logic `N(`PADDR_SIZE-2) mask;
        lzc #(
            .WIDTH(`PADDR_SIZE-2)
        ) lzc_inst(
            .in_i(cmpaddr),
            .cnt_o(cnt),
            .empty_o()
        )
        MaskGen #($clog2(`PADDR_SIZE-2)) mask_gen (cnt, mask);
        assign pmp_napot[i] = (paddr_cmp & ~mask) == (cmpaddr[i] & ~mask);
        assign pmp_r_all[i] = pmp_cfg[i].r & pmp_v_p[i];
        assign pmp_w_all[i] = pmp_cfg[i].w & pmp_v_p[i];
        assign pmp_x_all[i] = pmp_cfg[i].x & pmp_v_p[i];
    end
endgenerate
    PMPTORCompare #(
        .WIDTH(`PADDR_SIZE-2),
        .DEPTH(`PMP_SIZE)
    ) pmp_tor_cmp(
        .paddr(paddr_cmp),
        .cmpaddr(cmpaddr),
        .tor(pmp_tor)
    );


    PMACfg `N(`PMA_SIZE) pma_cfg;
    logic `ARRAY(`PMA_SIZE, `PADDR_SIZE-2) pma_cmp;
    logic `N(`PMA_SIZE) pma_v, pma_tor, pma_uc_all;
    
    assign pma_cfg = pmacfg;
generate
    for(genvar i=0; i<`PMA_SIZE; i++)begin
        assign pma_cmp[i] = pmaaddr[`PADDR_SIZE-3: 0];
        assign pma_v[i] = (pma_cfg[i].a == 2'b01) & pma_tor[i];
        assign pma_uc_all[i] = pma_v[i] & pma_cfg[i].uc;
    end
endgenerate
    PMPTORCompare #(
        .WIDTH(`PADDR_SIZE-2),
        .DEPTH(`PMA_SIZE)
    ) pma_tor_cmp(
        .paddr(paddr_cmp),
        .cmpaddr(pma_cmp),
        .tor(pma_tor)
    );
    
    assign pma_uc = |pma_uc_all;
endmodule

module PMPTORCompare #(
    parameter WIDTH=`PADDR_SIZE-2,
    parameter DEPTH=4
)(
    input logic `N(WIDTH) paddr,
    input logic `ARRAY(DEPTH, WIDTH) cmpaddr,
    output logic `N(DEPTH) tor
);
    logic `N(DEPTH)  tor_s;

generate
    for(genvar i=0; i<DEPTH; i++)begin
        if(i == 0)begin
            assign tor_s[i] = paddr < cmpaddr[i];
            assign tor[i] = tor_s[0];
        end
        else begin
            assign tor_s[i] = paddr < cmpaddr[i];
            assign tor[i] = ~tor_s[i-1] & tor_s[i];
        end
    end
endgenerate
endmodule
