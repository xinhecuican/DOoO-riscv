`include "../../../defines/defines.svh"
`include "../../../defines/mult_define.svh"

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
    input BackendCtrl backendCtrl
);
    localparam NUM = `XLEN + 2;
    localparam HNUM = (NUM / 2); // 17 33
    localparam HM = HNUM-1;
    logic `N(NUM) d1, d2;
    logic `N(NUM/2) n;
    logic `ARRAY(NUM*2, NUM/2) st0;
    logic `N(NUM*2) result;
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
    assign d1 = {{2{sext1 & rs1_data[`XLEN-1]}}, rs1_data};
    assign d2 = {{2{sext2 & rs2_data[`XLEN-1]}}, rs2_data};

    assign wakeup_en = valid_s0;
    assign wakeup_we = status_s0.we;
    assign wakeup_rd = status_s0.rd;

    booth_tree #(NUM) booth_tree_inst (.*);

    localparam S1 = HNUM / 3; // 5 11
    localparam S1_REM = HNUM % 3; // 2 0
    localparam S1_BASE = 0;
    localparam S1_ALL = (S1 * 2 + HNUM % 3); // 12 22
    `STA_NUM_DEF(1, 2)
    `STA_NUM_DEF(2, 3)
    `STA_NUM_DEF(3, 4)
    `STA_NUM_DEF(4, 5)
    `STA_NUM_DEF(5, 6)
    `STA_NUM_DEF(6, 7)
    // localparam S2 = S1_ALL / 3; // 4 7
    // localparam S2_REM = (S1_ALL % 3); // 0 1
    // localparam S2_ALL = (S2 * 2 + S1_ALL % 3); // 8 15
    // localparam S3 = S2_ALL / 3; // 2 5
    // localparam S3_ALL = (S3 * 2 + S2_ALL % 3); // 6 10
    // localparam S4 = S3_ALL / 3; // 2 3
    // localparam S4_ALL = (S4 * 2 + S3_ALL % 3); // 4 7
    // localparam S5 = S4_ALL / 3; // 1 2
    // localparam S5_ALL = (S5 * 2 + S4_ALL % 3); // 3 5
    // localparam S6 = S5_ALL / 3; // 1 1
    // localparam S6_ALL = (S6 * 2 + S5_ALL % 3); // 2 3
    // localparam S7 = S6_ALL / 3; // 0 1
    // localparam S7_ALL = (S7 * 2 + S6_ALL % 3); // 2 2

generate
// stage1
    logic `N(NUM/2) c0;
    assign c0 = n;
    `CSA_DEF(0, 1)
    `CSA_DEF(1, 2)
    `ST_REG(2, 0, 1)
    `CSAN_DEF(2, 3)
    `CSA_DEF(3, 4)
    `CSA_DEF(4, 5)
    `ST_REG(5, 1, 2)
    `CSAN_DEF(5, 6)
`ifdef RV64I
    `CSA_DEF(6, 7)
`endif
endgenerate
    logic bigger;
    LoopCompare #(`ROB_WIDTH) cmp_bigger (status_s2.robIdx, backendCtrl.redirectIdx, bigger);
    assign wbData.en = valid_s2 & (~backendCtrl.redirect | bigger);
    assign wbData.we = status_s2.we;
    assign wbData.rd = status_s2.rd;
    assign wbData.robIdx = status_s2.robIdx;
    assign wbData.exccode = `EXC_NONE;
    assign wbData.irq_enable = 1;

    logic `ARRAY(2, NUM*2) transpose;

generate
    for(genvar i=0; i<2; i++)begin
        for(genvar j=0; j<NUM*2; j++)begin
`ifdef RV32I
            assign transpose[i][j] = st6[j][i];
`elsif RV64I
            assign transpose[i][j] = st7[j][i];
`endif
        end
    end
endgenerate
    
`ifdef RV32I
    assign result = transpose[0] + transpose[1] + c6[HNUM-2];
`elsif RV64I
    assign result = transpose[0] + transpose[1] + c7[HNUM-2];
`endif
    assign wbData.res = selh_s2 ? result[`XLEN*2-1: `XLEN] : result[`XLEN-1: 0];

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

module booth_tree #(
    parameter WIDTH=1
)(
    input logic [WIDTH-1: 0] d1,
    input logic [WIDTH-1: 0] d2,
    output logic [WIDTH/2-1: 0] n,
    output logic `ARRAY(WIDTH*2, WIDTH/2) st0
);
    logic `N(WIDTH/2) z0, z1, c0;
    logic `N(WIDTH) pp   `N(WIDTH/2);
    logic `N(WIDTH*2) fpp  `N(WIDTH/2);

generate
    for(genvar i=0; i<WIDTH/2; i++)begin
        if(i == 0)begin
            booth_encoder be0(
                .y   ({d2[1], d2[0], 1'b0}),
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
        for(genvar j=0; j<WIDTH; j++)begin
            if(j==0) begin
                booth_selector bs(     // LSB
                    .z0  (z0[i]),
                    .z1  (z1[i]),
                    .x   (d1[j]),
                    .xs  (1'b0),
                    .neg (n[i]),
                    .p   (pp[i][j])
                );
            end 
            else begin
                booth_selector u_bs(
                    .z0  (z0[i]),
                    .z1  (z1[i]),
                    .x   (d1[j]),
                    .xs  (d1[j-1]),
                    .neg (n[i]),
                    .p   (pp[i][j])
                );
            end
        end
    end
endgenerate

generate
    for(genvar i=0; i<WIDTH/2; i++)begin
        assign fpp[i] = {{(WIDTH-2*i){pp[i][WIDTH-1]}}, pp[i], {(2*i){n[i]}}};
        for(genvar j=0; j<WIDTH*2; j++)begin
            assign st0[j][i] = fpp[i][j];
        end
    end
endgenerate
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
    if(WID == 1)begin
        FA u_fa(a, b, cin, sum, cout);
    end
    else begin
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
        assign cout = {c[WID-1:1],1'b0};
    end
endgenerate
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