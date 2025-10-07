`include "../../../defines/defines.svh"
`include "../../../defines/mult_define.svh"

module MultUnit(
    input logic clk,
    input logic rst,
    input logic en,
`ifdef RV64I
    input logic word,
`endif
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
    
    assign valid_s0 = en & ~multop[2] & ~multop[3];
    assign selh_s0 = multop == `MULT_MULH ||
                     multop == `MULT_MULHSU ||
                     multop == `MULT_MULHU;
    assign status_s0 = status_i;
    assign d1 = {{2{sext1 & rs1_data[`XLEN-1]}}, rs1_data};
    assign d2 = {{2{sext2 & rs2_data[`XLEN-1]}}, rs2_data};

    assign wakeup_en = en & ~multop[2];
    assign wakeup_we = status_s0.we;
    assign wakeup_rd = status_s0.rd;

    booth_tree #(NUM) booth_tree_inst (.*);

    localparam S0_ALL = HNUM;
    localparam S0_BASE = 0;
    localparam S0 = 0;

    `STA_NUM_DEF(0, 1) // 12 22
    `STA_NUM_DEF(1, 2)
    `STA_NUM_DEF(2, 3)
    `STA_NUM_DEF(3, 4)
    `STA_NUM_DEF(4, 5)
    `STA_NUM_DEF(5, 6)
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
    // localparam S6_ALL = (S6 * 2 + S5_ALL % 3); // 2 4
    // localparam S7 = S6_ALL / 3; // 0 1
    // localparam S7_ALL = (S7 * 2 + S6_ALL % 3); // 2 3

    `ST_REG(2, 0, 1)
    `ST_REG(5, 1, 2)
generate
// stage1
    logic `N(NUM/2) c0;
    assign c0 = n;
    `CSA_DEF(0, 1)
    `CSA_DEF(1, 2)
    `CSAN_DEF(2, 3)
    `CSA_DEF(3, 4)
    `CSA_DEF(4, 5)
    `CSAN_DEF(5, 6)
`ifdef RV64I

    `STA_NUM_DEF(6, 7)
    `STA_NUM_DEF(7, 8)
    `CSA_DEF(6, 7)
    `CSA_DEF(7, 8)
    logic word_s1, word_s2;
    always_ff @(posedge clk)begin
        word_s1 <= word;
        word_s2 <= word_s1;
    end
`endif
endgenerate

`ifdef ZBC
    logic valid_clmul_s0, valid_clmul_s1, valid_clmul_s2;
    logic `N(`XLEN) clmul_res;
    wire clmulh = multop == `MULT_CLMULH;
    wire clmulr = multop == `MULT_CLMULR;
    assign valid_clmul_s0 = en & multop[3];
    always_ff @(posedge clk)begin
        valid_clmul_s1 <= valid_clmul_s0 & (~backendCtrl.redirect | bigger0);
        valid_clmul_s2 <= valid_clmul_s1 & (~backendCtrl.redirect | bigger1);
    end
    CLMULModel clmul_model(clk, rs1_data, rs2_data, clmulh, clmulr, clmul_res);
`endif

    logic bigger;
    LoopCompare #(`ROB_WIDTH) cmp_bigger (status_s2.robIdx, backendCtrl.redirectIdx, bigger);
    assign wbData.en = (valid_s2
                    `ifdef ZBC
                      | valid_clmul_s2
                    `endif
    ) & (~backendCtrl.redirect | bigger);
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
            assign transpose[i][j] = st8[j][i];
`endif
        end
    end
endgenerate
    
`ifdef RV32I
    assign result = transpose[0] + transpose[1] + c6[HNUM-2];
    assign wbData.res = 
                    `ifdef ZBC
                        valid_clmul_s2 ? clmul_res :
                    `endif
                        selh_s2 ? result[`XLEN*2-1: `XLEN] : result[`XLEN-1: 0];
`elsif RV64I
    assign result = transpose[0] + transpose[1] + c8[HNUM-2];
    assign wbData.res = 
                        `ifdef ZBC
                        valid_clmul_s2 ? clmul_res :
                        `endif
                        word_s2 ? {{32{result[31]}}, result[31: 0]} :
                        selh_s2 ? result[`XLEN*2-1: `XLEN] : result[`XLEN-1: 0];
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

module CLMULModel(
    input logic clk,
    input logic `N(`XLEN) data1,
    input logic `N(`XLEN) data2,
    input logic high,
    input logic reverse,
    output logic `N(`XLEN) result
);

    logic `ARRAY(`XLEN, `XLEN*2) mul0;
    logic `ARRAY(`XLEN/2, `XLEN*2) mul1;
    logic `ARRAY(`XLEN/4, `XLEN*2) mul2;
    logic `ARRAY(`XLEN/8, `XLEN*2) mul3;
    logic `ARRAY(`XLEN/8, `XLEN*2) mul3_r;
    logic `N(`XLEN*2) mul_res;
    logic high_r, reverse_r;

generate
    for(genvar i=0; i<`XLEN; i++)begin
        if(i == 0)begin
            assign mul0[i] = {{`XLEN{1'b0}}, data1} & {`XLEN*2{data2[i]}};
        end
        else begin
            assign mul0[i] = {data1, {i{1'b0}}} & {`XLEN*2{data2[i]}};
        end
    end
    for(genvar i=0; i<`XLEN/2; i++)begin
        assign mul1[i] = mul0[i*2] ^ mul0[i*2+1];
    end
    for(genvar i=0; i<`XLEN/4; i++)begin
        assign mul2[i] = mul1[i*2] ^ mul1[i*2+1];
    end
    for(genvar i=0; i<`XLEN/8; i++)begin
        assign mul3[i] = mul2[i*2] ^ mul2[i*2+1];
    end
endgenerate
    always_ff @(posedge clk)begin
        mul3_r <= mul3;
        high_r <= high;
        reverse_r <= reverse;
    end
    ParallelXOR #(`XLEN*2, `XLEN/8) parallel_xor (mul3_r, mul_res);
    always_ff @(posedge clk) begin
        case({high_r, reverse_r})
        2'b10: result <= mul_res[`XLEN*2-1:`XLEN];
        2'b01: result <= mul_res[`XLEN*2-2:`XLEN-1];
        default: result <= mul_res[`XLEN-1:0];
        endcase
    end
endmodule