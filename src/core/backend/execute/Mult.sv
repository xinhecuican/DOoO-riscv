//-------------------------------------------------------------------
//
//  COPYRIGHT (C) 2023, devin
//  balddonkey@outlook.com
//
//-------------------------------------------------------------------
`include "../../../defines/defines.svh"

module MultUnit(
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(`MULTOP_WIDTH) multop,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input ExStatusBundle status_i,
    output WBData wbData,
    output logic wakeup_en,
    output logic wakeup_we,
    output logic `N(`PREG_WIDTH) wakeup_rd,
    BackendCtrl backendCtrl
);
    localparam NUM = `XLEN + 2;
    localparam HNUM = (NUM / 2); // 17 33
    localparam HM = HNUM-1;
    logic `N(NUM) d1, d2;
    logic `N(NUM/2) z0, z1, n;
    logic `N(NUM+1) pp   `N(NUM/2);
    logic `N(NUM+1) pp2c `N(NUM/2);
    logic `N(NUM*2) fpp  `N(NUM/2);
    logic sext1, sext2;
    logic valid_s0, selh_s0;
    ExStatusBundle status_s0;

    assign sext1 = multop == `MULT_MUL ||
                   multop == `MULT_MULH ||
                   multop == `MULT_MULHSU;
    assign sext2 = multop == `MULT_MUL ||
                   multop == `MULT_MULH;
    
    assign valid_s0 = en & ~multop[2];
    assign selh_s0 = multop == `MULT_MULH ||
                     multop == `MULT_MULHSU ||
                     multop == `MULT_MULHU;
    assign status_s0 = status_i;
    assign d1 = {{2{sext1}}, rs1_data};
    assign d2 = {{2{sext2}}, rs2_data};

    assign wakeup_en = valid_s0;
    assign wakeup_we = status_s0.we;
    assign wakeup_rd = status_s0.rd;

generate
    for(genvar i=0; i<NUM/2; i++)begin
        if(i == 0)begin
            booth_encoder be0(
                .y   ({d2[1], d2[0], 1'b0}),
                .z0  (z0[i]),
                .z1  (z1[i]),
                .neg (n[i])
            );
        end
        else if(i == HM)begin
            booth_encoder be1(
                .y   ({1'b0, 1'b0, d2[NUM-1]}),
                .z0  (z0[i]),
                .z1  (z1[i]),
                .neg (n[i])
            );
        end
        else begin
            booth_encoder be2(
                .y   ({d2[2*i+1], d2[2*i], d2[2*i-1]}),
                .z0  (z0[i]),
                .z1  (z1[i]),
                .neg (n[i])
            );
        end
        for(genvar j=0; j<NUM; j++)begin
            if(j==0) begin
                booth_selector bs(     // LSB
                    .z0  (z0[i]),
                    .z1  (z1[i]),
                    .x   (d1[j]),
                    .xs  (1'b0),
                    .neg (n[i]),
                    .p   (pp[i][j])
                );
                booth_selector bs0(
                    .z0  (z0[i]),
                    .z1  (z1[i]),
                    .x   (d1[j+1]),
                    .xs  (d1[j]),
                    .neg (n[i]),
                    .p   (pp[i][j+1])
                );
            end 
            else if(j==NUM-1) begin
                booth_selector u_bs(
                    .z0  (z0[i]),
                    .z1  (z1[i]),
                    .x   (1'b0),
                    .xs  (d1[j]),
                    .neg (n[i]),
                    .p   (pp[i][j+1])
                );
            end 
            else begin
                booth_selector u_bs(
                    .z0  (z0[i]),
                    .z1  (z1[i]),
                    .x   (d1[j+1]),
                    .xs  (d1[j]),
                    .neg (n[i]),
                    .p   (pp[i][j+1])
                );
            end
        end
        RCA #(NUM+1) u_rca(
            .a    (pp[i]),
            .b    ({{NUM{1'b0}},n[i]}),
            .cin  (1'b0),
            .sum  (pp2c[i]),
            .cout ()
        );
    end
endgenerate

generate
    for(genvar i=0; i<NUM/2; i++)begin
        if(i == HM)begin
            assign fpp[i] = {pp2c[HM][NUM-1:0], {NUM{1'b0}}};
        end
        else begin
            assign fpp[i] = {{(NUM-1-2*i){n[i] & (z0[i] | z1[i])}}, pp2c[i], {(2*i){1'b0}}};
        end
    end
endgenerate


    localparam S1 = HNUM / 3; // 5 11
    localparam S1_ALL = (S1 * 2 + HNUM % 3); // 12 22
    localparam S2 = S1_ALL / 3; // 4 7
    localparam S2_ALL = (S2 * 2 + S1_ALL % 3); // 8 15
    localparam S3 = S2_ALL / 3; // 2 5
    localparam S3_ALL = (S3 * 2 + S2_ALL % 3); // 6 10
    localparam S4 = S3_ALL / 3; // 2 3
    localparam S4_ALL = (S4 * 2 + S3_ALL % 3); // 4 7
    localparam S5 = S4_ALL / 3; // 1 2
    localparam S5_ALL = (S5 * 2 + S4_ALL % 3); // 3 5
    localparam S6 = S5_ALL / 3; // 1 1
    localparam S6_ALL = (S6 * 2 + S5_ALL % 3); // 2 3
    localparam S7 = S6_ALL / 3; // 0 1
    localparam S7_ALL = (S7 * 2 + S6_ALL % 3); // 2 2
    logic `N(NUM*2) st1  `N(S1_ALL);
    logic `N(NUM*2) st2  `N(S2_ALL);
    logic `N(NUM*2) st2_n `N(S2_ALL);
    logic `N(NUM*2) st3  `N(S3_ALL);
    logic `N(NUM*2) st4 `N(S4_ALL);
    logic `N(NUM*2) st5 `N(S5_ALL);
    logic `N(NUM*2) st5_n `N(S5_ALL);
    logic `N(NUM*2) st6 `N(S6_ALL);
`ifdef RV64
    logic `N(NUM*2) st7 `N(S7_ALL);
`endif

`define ST_REG(num, stage, stagen) \
    for(genvar i=0; i<S``num``_ALL; i++)begin \
        always_ff @(posedge clk)begin \
            st``num``_n[i] <= st``num``[i]; \
        end \
    end \
    logic valid_s``stagen, selh_s``stagen; \
    ExStatusBundle status_s``stagen; \
    logic bigger``stage; \
    LoopCompare #(`ROB_WIDTH) cmp_bigger``stage (status_s``stage, backendCtrl.redirectIdx, bigger``stage); \
    always_ff @(posedge clk)begin \
        valid_s``stagen <= valid_s``stage & (~backendCtrl.redirect | bigger``stage); \
        selh_s``stagen <= selh_s``stage``; \
        status_s``stagen <= status_s``stage``; \
    end

`define CSA_DEF(stage, stagen) \
    for(genvar i=0; i<S``stagen``; i++)begin : cal_st``stagen \
        CSA csa``stagen( \
            .a(st``stage``[3*i]), \
            .b(st``stage``[3*i+1]), \
            .cin(st``stage``[3*i+2]), \
            .sum(st``stagen``[2*i]), \
            .cout(st``stagen``[2*i+1]) \
        ); \
    end \
    for(genvar i=0; i<S``stage``_ALL % 3; i++)begin \
        assign st``stagen``[2 * S``stagen`` + i] = st``stage``[3 * S``stage`` + i]; \
    end

`define CSAN_DEF(stage, stagen) \
    for(genvar i=0; i<S``stagen``; i++)begin : cal_st``stagen \
        CSA csa``stagen( \
            .a(st``stage``_n[3*i]), \
            .b(st``stage``_n[3*i+1]), \
            .cin(st``stage``_n[3*i+2]), \
            .sum(st``stagen``[2*i]), \
            .cout(st``stagen``[2*i+1]) \
        ); \
    end \
    for(genvar i=0; i<S``stage``_ALL % 3; i++)begin \
        assign st``stagen``[2 * S``stagen`` + i] = st``stage``_n[3 * S``stage`` + i]; \
    end

generate
// stage1
    for(genvar i=0; i<S1; i++)begin : cal_st1
        CSA csa1(
            .a(fpp[3*i]),
            .b(fpp[3*i+1]),
            .cin(fpp[3*i+2]),
            .sum(st1[2*i]),
            .cout(st1[2*i+1])
        );
    end
    for(genvar i=0; i<HNUM % 3; i++)begin
        assign st1[2 * S1 + i] =  fpp[3 * S1 + i];
    end

    `CSA_DEF(1, 2)
    `ST_REG(2, 0, 1)
    `CSAN_DEF(2, 3)
    `CSA_DEF(3, 4)
    `CSA_DEF(4, 5)
    `ST_REG(5, 1, 2)
    `CSAN_DEF(5, 6)
`ifdef RV64
    `CSA_DEF(6, 7)
`endif
endgenerate

    assign wbData.en = valid_s2;
    assign wbData.we = status_s2.we;
    assign wbData.rd = status_s2.rd;
    assign wbData.robIdx = status_s2.robIdx;
    assign wbData.exccode = `EXC_NONE;
`ifdef RV32
    assign wbData.res = mulh_s2 ? st6[1][`XLEN-1: 0] : st6[0][`XLEN-1: 0];
`elsif RV64
    assign wbData.res = mulh_s2 ? st7[1][`XLEN-1: 0] : st7[0][`XLEN-1: 0];
`endif

endmodule

//------------------------ SUBROUTINE ------------------------//

// Booth Encoder
module booth_encoder(y,z0,z1,neg);
input [2:0] y;      // y_{i+1}, y_i, y_{i-1}
output      z0;     // abs(z) = 1
output      z1;     // abs(z) = 2, use the shifted one
output      neg;    // negative
assign z0 = y[0] ^ y[1];
assign z1 = (y[0] & y[1] & ~y[2]) | (~y[0] & ~y[1] &y[2]);
assign neg = y[2] & ~(y[1] & y[0]);
endmodule

// Booth Selector
module booth_selector(z0,z1,x,xs,neg,p);
input   z0;
input   z1;
input   x;
input   xs;     // x shifted
input   neg;
output  p;      // product
assign  p = (neg ^ ((z0 & x) | (z1 & xs)));
endmodule

// Carry Save Adder
module CSA #(
    parameter WID = 128
)(a, b, cin, sum, cout);
input  [WID-1:0] a, b, cin;
output [WID-1:0] sum, cout;
wire   [WID-1:0] c; // shift 1-bit
genvar i;
generate
    for(i=0; i<WID; i=i+1) begin : for_csa
        if(i==WID-1) begin
            FA u_fa(
                .a    (a[i]),
                .b    (b[i]),
                .cin  (cin[i]),
                .sum  (sum[i]),
                .cout ()
            );
        end else begin
            FA u_fa(
                .a    (a[i]),
                .b    (b[i]),
                .cin  (cin[i]),
                .sum  (sum[i]),
                .cout (c[i+1])
            );
        end
    end
endgenerate
assign cout = {c[WID-1:1],1'b0};
endmodule

// Ripple Carry Adder
module RCA #(
    parameter WID = 64
)(a, b, cin, sum, cout);
input  [WID-1:0] a, b;
input  cin;
output [WID-1:0] sum;
output cout;
wire   [WID-1:0] c;
genvar i;
generate
    for(i=0; i<WID; i=i+1) begin : for_rca
        if(i==0) begin
            FA u_fa(
                .a    (a[i]),
                .b    (b[i]),
                .cin  (cin),
                .sum  (sum[i]),
                .cout (c[i])
            );
        end else begin
            FA u_fa(
                .a    (a[i]),
                .b    (b[i]),
                .cin  (c[i-1]),
                .sum  (sum[i]),
                .cout (c[i])
            );
        end
    end
endgenerate
assign cout = c[WID-1];
endmodule

// Full Adder
module FA(a,b,cin,sum,cout);
input  a, b, cin;
output sum, cout;
wire   x, y, z;
xor x1(x,a,b);
xor x2(sum,x,cin);
and a1(y,a,b);
and a2(z,x,cin);
or  o1(cout,y,z);
endmodule