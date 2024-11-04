`ifndef __MULT_DEFINE_SVH__
`define __MULT_DEFINE_SVH__
`define STA_NUM_DEF(stage, stagen) \
    localparam S``stagen`` = S``stage``_ALL / 3; \
    localparam S``stagen``_REM = (S``stage``_ALL % 3); \
    localparam S``stagen``_BASE = S``stage``_BASE + S``stage``; \
    localparam S``stagen``_ALL = (S``stagen`` * 2 + S``stage``_ALL % 3);

`define ST_REG(num, stage, stagen) \
    logic valid_s``stagen, selh_s``stagen; \
    ExStatusBundle status_s``stagen; \
    logic bigger``stage; \
    LoopCompare #(`ROB_WIDTH) cmp_bigger``stage (status_s``stage.robIdx, backendCtrl.redirectIdx, bigger``stage); \
    always_ff @(posedge clk)begin \
        valid_s``stagen <= valid_s``stage & (~backendCtrl.redirect | bigger``stage); \
        selh_s``stagen <= selh_s``stage``; \
        status_s``stagen <= status_s``stage``; \
    end

`define CSA_DEF(stage, stagen) \
    logic `ARRAY(NUM*2+1, S``stagen``_ALL) st``stagen``; \
    logic `N(HNUM) c``stagen``; \
    for(genvar i=0; i<S``stagen``; i++)begin : cal_st``stagen \
        for(genvar j=0; j<NUM*2; j++)begin \
            CSA #(1) csa``stagen( \
                .a(st``stage``[j][3*i]), \
                .b(st``stage``[j][3*i+1]), \
                .cin(st``stage``[j][3*i+2]), \
                .sum(st``stagen``[j][i]), \
                .cout(st``stagen``[j+1][i+S``stagen``+S``stagen``_REM]) \
            ); \
        end \
        assign st``stagen``[0][i+S``stagen``+S``stagen``_REM] = c``stagen``[i+S``stagen``_BASE]; \
    end \
    for(genvar i=0; i<S``stagen``_REM; i++)begin \
        for(genvar j=0; j<NUM*2; j++)begin \
            assign st``stagen``[j][S``stagen`` + i] = st``stage``[j][3 * S``stagen`` + i]; \
        end \
    end \
    assign c``stagen`` = c``stage``;

`define CSAN_DEF(stage, stagen) \
    logic `ARRAY(NUM*2, S``stage``_ALL) st``stage``_n; \
    logic `ARRAY(NUM*2+1, S``stagen``_ALL) st``stagen``; \
    for(genvar i=0; i<NUM*2; i++)begin \
        always_ff @(posedge clk)begin \
            st``stage``_n[i] <= st``stage``[i]; \
        end \
    end \
    logic `N(HNUM) c``stagen``; \
    for(genvar i=0; i<S``stagen``; i++)begin : cal_st``stagen \
        for(genvar j=0; j<NUM*2; j++)begin \
            CSA #(1) csa``stagen( \
                .a(st``stage``_n[j][3*i]), \
                .b(st``stage``_n[j][3*i+1]), \
                .cin(st``stage``_n[j][3*i+2]), \
                .sum(st``stagen``[j][i]), \
                .cout(st``stagen``[j+1][i+S``stagen``+S``stagen``_REM]) \
            ); \
        end \
        assign st``stagen``[0][i+S``stagen``+S``stagen``_REM] = c``stagen``[i+S``stagen``_BASE]; \
    end \
    for(genvar i=0; i<S``stagen``_REM; i++)begin \
        for(genvar j=0; j<NUM*2; j++)begin \
            assign st``stagen``[j][S``stagen`` + i] = st``stage``_n[j][3 * S``stagen`` + i]; \
        end \
    end \
    always_ff @(posedge clk)begin \
        c``stagen`` <= c``stage``; \
    end
`endif