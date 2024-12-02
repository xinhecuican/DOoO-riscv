`include "../../../defines/defines.svh"

typedef struct packed {
    logic sext;
    logic zero;
    logic ov;
    logic rem;
    logic `N($clog2(`XLEN)) lzc;
    logic `N(`XLEN) src1;
    logic ha, hb; // sign bit of divisor and dividend
    ExStatusBundle status;
} DivPipeInfo;

module DivUnit(
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
    output logic ready,
    output logic div_end,
    input BackendCtrl backendCtrl
);

    logic `N(`XLEN) abs_a, abs_b;
    logic zero;
    assign zero = rs2_data == 0;

    DivPipeInfo pipe0_i, pipe1_i;
    logic `N($clog2(`XLEN/2)+1) pipe0_cnt;
    logic pipe0_ready;
    logic `N($clog2(`XLEN)) lzc_rs2;
    logic bigger_i;
    logic en_i;
    logic clean;
    logic sext;

    logic `N(2*`XLEN+1) pipe1_pa, pa_o;
    logic `N(`XLEN) q_pos, q_neg, q_neg_last, pipe1_q_pos, pipe1_q_neg;
    logic en_o, we_o, pipe1_en;
    logic rem_o;
    logic zero_o, ov_o;
    logic `N(`XLEN) src1_o, pipe1_b;
    logic sext_o, ha_o;
    ExStatusBundle status_o;
    logic `N(`XLEN) r, q;

    LoopCompare #(`ROB_WIDTH) cmp_in (status_i.robIdx, backendCtrl.redirectIdx, bigger_i);
    assign en_i = en & multop[2] & (~backendCtrl.redirect | bigger_i);
    assign sext = multop == `MULT_DIV || multop == `MULT_REM;
    assign pipe0_i.sext = sext;
    assign pipe0_i.zero = rs2_data == 0;
    assign pipe0_i.ov = (rs1_data == 32'h80000000) && (rs2_data == 32'hffffffff) && sext;
    assign pipe0_i.rem = multop == `MULT_REM || multop == `MULT_REMU;
    assign pipe0_i.lzc = lzc_rs2;
    lzc #(`XLEN, 1) lzc_gen (abs_b, lzc_rs2,);
    assign abs_a = (sext & rs1_data[`XLEN-1]) ? ~rs1_data + 1 : rs1_data;
    assign abs_b = (sext & rs2_data[`XLEN-1]) ? ~rs2_data + 1 : rs2_data;
    assign pipe0_i.ha = rs1_data[`XLEN-1];
    assign pipe0_i.hb = rs2_data[`XLEN-1];
    assign pipe0_i.status = status_i;
    assign pipe0_i.src1 = rs1_data;

    DivPipe #(`XLEN/2, `XLEN, $bits(DivPipeInfo)) pipe0(
        .clk(clk),
        .rst(rst),
        .info_i(pipe0_i),
        .info_o(pipe1_i),
        .en_i(en_i),
        .pa_i({{`XLEN+1{1'b0}}, abs_a} << lzc_rs2),
        .b_i(abs_b << lzc_rs2),
        .q_pos_i(0),
        .q_neg_i(0),
        .en_o(pipe1_en),
        .pa_o(pipe1_pa),
        .b_o(pipe1_b),
        .q_pos_o(pipe1_q_pos),
        .q_neg_o(pipe1_q_neg),
        .cnt_o(pipe0_cnt),
        .ready(pipe0_ready),
        .clean(clean),
        .backendCtrl(backendCtrl)
    );

    always_ff @(posedge clk)begin
        wakeup_en <= pipe0_cnt == 2;
        wakeup_we <= pipe1_i.status.we;
        wakeup_rd <= pipe1_i.status.rd;
    end

    // div end
    assign q_neg_last = pipe1_pa[2*`XLEN] ? pipe1_q_neg + 1 : pipe1_q_neg;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            ready <= 1'b1;
        end
        else begin
            if(clean)begin
                ready <= 1'b1;
            end
            else if(en_i)begin
                ready <= 1'b0;
            end
            else if(pipe0_cnt == 2)begin
                ready <= 1'b1;
            end
        end
    end

    always_ff @(posedge clk)begin
        div_end <= pipe0_cnt == 2;
        if(pipe1_pa[2*`XLEN])begin
            pa_o <= ((pipe1_pa + {pipe1_b, `XLEN'b0}) >> pipe1_i.lzc) & {2*`XLEN+1{~pipe1_i.ov}};
        end
        else begin
            pa_o <= (pipe1_pa >> pipe1_i.lzc) & {2*`XLEN+1{~pipe1_i.ov}};
        end
        en_o <= pipe1_en & ~clean;
        status_o <= pipe1_i.status;
        rem_o <= pipe1_i.rem;
        zero_o <= pipe1_i.zero;
        ov_o <= pipe1_i.ov;
        src1_o <= pipe1_i.src1;
        sext_o <= pipe1_i.sext;
        ha_o <= pipe1_i.ha;
        if((pipe1_i.ha ^ pipe1_i.hb) & pipe1_i.sext)begin
            q_pos <= q_neg_last;
            q_neg <= pipe1_q_pos;
        end
        else begin
            q_pos <= pipe1_q_pos;
            q_neg <= q_neg_last;
        end
    end
    logic bigger_o;
    LoopCompare #(`ROB_WIDTH) cmp_out (status_o.robIdx, backendCtrl.redirectIdx, bigger_o);
    assign q = ov_o ? src1_o :
               (q_pos - q_neg) | {`XLEN{zero_o}};
    assign r = zero_o           ? src1_o : 
               sext_o & ha_o    ? ~pa_o[`XLEN*2-1: `XLEN] + 1 : 
                                   pa_o[`XLEN*2-1: `XLEN];
    assign wbData.en = en_o & (~backendCtrl.redirect | bigger_o);
    assign wbData.we = status_o.we;
    assign wbData.rd = status_o.rd;
    assign wbData.robIdx = status_o.robIdx;
    assign wbData.res = rem_o ? r : q;
    assign wbData.exccode = `EXC_NONE;
    assign wbData.irq_enable = 1;
endmodule

module DivPipe #(
    parameter PIPE_NUM=4,
    parameter WIDTH=32,
    parameter DATA_WIDTH=1,
    parameter PIPE_START=0,
    parameter PIPE_ALL_WIDTH=$clog2(WIDTH),
    parameter PIPE_WIDTH=$clog2(PIPE_NUM)
)(
    input logic clk,
    input logic rst,
    input logic `N(DATA_WIDTH) info_i,
    output logic `N(DATA_WIDTH) info_o,
    input logic en_i,
    input logic `N(WIDTH*2+1) pa_i,
    input logic `N(WIDTH) b_i,
    input logic `N(WIDTH) q_pos_i,
    input logic `N(WIDTH) q_neg_i,
    output logic en_o,
    output logic `N(WIDTH*2+1) pa_o,
    output logic `N(WIDTH) b_o,
    output logic `N(WIDTH) q_pos_o,
    output logic `N(WIDTH) q_neg_o,
    output logic `N(PIPE_WIDTH+1) cnt_o,
    output logic ready,
    output logic clean,
    input BackendCtrl backendCtrl
);
    logic `N(PIPE_WIDTH+1) cnt;
    logic `N(PIPE_ALL_WIDTH) cnt_global;
    logic sext, rem;
    logic `N(WIDTH*2+1) pa, pa_n, pa_shift;
    logic `N(WIDTH) b;
    logic `N(WIDTH*2+1) b_n1, b_n2, b_p1, b_p2;
    logic `N(WIDTH) q_pos, q_neg, q_pos_n, q_neg_n;
    logic `N(WIDTH) src1;
    logic `N(DATA_WIDTH) data;
    logic ha, hb, zero, ov;
    RobIdx robIdx;
    logic `N(3) q;

    qselect q_select(
        .b(b[WIDTH-1: WIDTH-4]),
        .p(pa[WIDTH*2: WIDTH*2-5]),
        .q(q)
    );

    always_comb begin
        pa_shift = pa << 2;
        b_n1 = {1'b0, b, {WIDTH{1'b0}}};
        b_n2 = {b, {WIDTH+1{1'b0}}};
        b_p1 = ~b_n1 + 1;
        b_p2 = b_p1 << 1;
        case(q)
        3'b110: pa_n = pa_shift - b_p2;
        3'b111: pa_n = pa_shift - b_p1;
        3'b000: pa_n = pa_shift;
        3'b001: pa_n = pa_shift - b_n1;
        3'b010: pa_n = pa_shift - b_n2;
        default: pa_n = pa_shift;
        endcase
        if(q == 3'b110)begin
            q_neg_n = q_neg + ('d2 << ({cnt_global, 1'b0}));
        end
        else if(q == 3'b111)begin
            q_neg_n = q_neg + ('d1 << ({cnt_global, 1'b0}));
        end
        else begin
            q_neg_n = q_neg;
        end
        if(q == 3'b001)begin
            q_pos_n = q_pos + ('d1 << ({cnt_global, 1'b0}));
        end
        else if(q == 3'b010)begin
            q_pos_n = q_pos + ('d2 << ({cnt_global, 1'b0}));
        end
        else begin
            q_pos_n = q_pos;
        end
    end

    logic bigger;
    LoopCompare #(`ROB_WIDTH) cmp_bigger (backendCtrl.redirectIdx, robIdx, bigger);
    assign clean = backendCtrl.redirect & bigger;
    assign ready = cnt == 0;
    assign cnt_o = cnt;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            cnt <= 0;
            cnt_global <= 0;
            sext <= 0;
            pa <= 0;
            b <= 0;
            data <= 0;
            q_pos <= 0;
            q_neg <= 0;
            robIdx <= 0;
        end
        else begin
            if(clean & cnt != 0)begin
                cnt <= 0;
            end
            else if(en_i & ready)begin
                cnt <= PIPE_NUM ;
                cnt_global <= PIPE_NUM + PIPE_START - 1;
                data <= info_i;
                pa <= pa_i;
                b <= b_i;
                q_pos <= q_pos_i;
                q_neg <= q_neg_i;
                robIdx <= info_i[$bits(RobIdx)-1: 0];
            end
            else if(cnt != 0)begin
                cnt <= cnt - 1;
                cnt_global <= cnt_global - 1;
                pa <= pa_n;
                q_pos <= q_pos_n;
                q_neg <= q_neg_n;
            end
        end
    end

    always_ff @(posedge clk)begin
        en_o <= cnt == 1 & ~clean;
    end
    assign info_o = data;
    assign pa_o = pa;
    assign b_o = b;
    assign q_pos_o = q_pos;
    assign q_neg_o = q_neg;
endmodule

module qselect (
    // check 6 bits of P and 4 bits of B
    input           [3:0]   b,
    input   signed  [5:0]   p,
    output          [2:0]   q
);
    wire b_1000 = (b == 4'b1000);
    wire b_1001 = (b == 4'b1001);
    wire b_1010 = (b == 4'b1010);
    wire b_1011 = (b == 4'b1011);
    wire b_1100 = (b == 4'b1100);
    wire b_1101 = (b == 4'b1101);
    wire b_1110 = (b == 4'b1110);
    wire b_1111 = (b == 4'b1111);

    wire p_ge_neg22 = p >= -22;
    wire p_ge_neg20 = p >= -20;
    wire p_ge_neg19 = p >= -19;
    wire p_ge_neg18 = p >= -18;
    wire p_ge_neg16 = p >= -16;
    wire p_ge_neg15 = p >= -15;
    wire p_ge_neg14 = p >= -14;
    wire p_ge_neg12 = p >= -12;
    wire p_ge_neg11 = p >= -11;
    wire p_ge_neg10 = p >= -10;

    wire p_ge_neg9 = p >= -9;
    wire p_ge_neg8 = p >= -8;
    wire p_ge_neg7 = p >= -7;
    wire p_ge_neg6 = p >= -6;
    wire p_ge_neg5 = p >= -5;
    wire p_ge_neg4 = p >= -4;
    wire p_ge_neg3 = p >= -3;
    wire p_ge_neg2 = p >= -2;

    wire p_ge_1 = p >= 1;
    wire p_ge_2 = p >= 2;
    wire p_ge_3 = p >= 3;
    wire p_ge_4 = p >= 4;
    wire p_ge_5 = p >= 5;
    wire p_ge_6 = p >= 6;
    wire p_ge_7 = p >= 7;
    wire p_ge_8 = p >= 8;
    wire p_ge_9 = p >= 9;

    wire p_ge_10 = p >= 10;
    wire p_ge_11 = p >= 11;
    wire p_ge_12 = p >= 12;
    wire p_ge_13 = p >= 13;
    wire p_ge_14 = p >= 14;
    wire p_ge_15 = p >= 15;
    wire p_ge_16 = p >= 16;
    wire p_ge_17 = p >= 17;
    wire p_ge_18 = p >= 18;
    wire p_ge_19 = p >= 19;
    wire p_ge_20 = p >= 20;
    wire p_ge_21 = p >= 21;
    wire p_ge_22 = p >= 22;
    // right bound need to +1 (to fit in the `~` `>=` combination)
    // 8
    wire p_1000_q_neg2 = (b_1000 & p_ge_neg12 & ~p_ge_neg6);
    wire p_1000_q_neg1 = (b_1000 & p_ge_neg6 & ~p_ge_neg2);
    wire p_1000_q_0 = (b_1000 & p_ge_neg2 & ~p_ge_2);
    wire p_1000_q_1 = (b_1000 & p_ge_2 & ~p_ge_6);
    wire p_1000_q_2 = (b_1000 & p_ge_6 & ~p_ge_12);
    // 9
    wire p_1001_q_neg2 = (b_1001 & p_ge_neg14 & ~p_ge_neg7);
    wire p_1001_q_neg1 = (b_1001 & p_ge_neg7 & ~p_ge_neg2);
    wire p_1001_q_0 = (b_1001 & p_ge_neg3 & ~p_ge_3);
    wire p_1001_q_1 = (b_1001 & p_ge_2 & ~p_ge_7);
    wire p_1001_q_2 = (b_1001 & p_ge_7 & ~p_ge_14);
    // 10
    wire p_1010_q_neg2 = (b_1010 & p_ge_neg15 & ~p_ge_neg8);
    wire p_1010_q_neg1 = (b_1010 & p_ge_neg8 & ~p_ge_neg2);
    wire p_1010_q_0 = (b_1010 & p_ge_neg3 & ~p_ge_3);
    wire p_1010_q_1 = (b_1010 & p_ge_2 & ~p_ge_8);
    wire p_1010_q_2 = (b_1010 & p_ge_8 & ~p_ge_15);
    // 11
    wire p_1011_q_neg2 = (b_1011 & p_ge_neg16 & ~p_ge_neg8);
    wire p_1011_q_neg1 = (b_1011 & p_ge_neg9 & ~p_ge_neg2);
    wire p_1011_q_0 = (b_1011 & p_ge_neg3 & ~p_ge_3);
    wire p_1011_q_1 = (b_1011 & p_ge_2 & ~p_ge_9);
    wire p_1011_q_2 = (b_1011 & p_ge_8 & ~p_ge_16);
    // 12
    wire p_1100_q_neg2 = (b_1100 & p_ge_neg18 & ~p_ge_neg9);
    wire p_1100_q_neg1 = (b_1100 & p_ge_neg10 & ~p_ge_neg3);
    wire p_1100_q_0 = (b_1100 & p_ge_neg4 & ~p_ge_4);
    wire p_1100_q_1 = (b_1100 & p_ge_3 & ~p_ge_10);
    wire p_1100_q_2 = (b_1100 & p_ge_9 & ~p_ge_18);
    // 13
    wire p_1101_q_neg2 = (b_1101 & p_ge_neg19 & ~p_ge_neg10);
    wire p_1101_q_neg1 = (b_1101 & p_ge_neg10 & ~p_ge_neg3);
    wire p_1101_q_0 = (b_1101 & p_ge_neg4 & ~p_ge_4);
    wire p_1101_q_1 = (b_1101 & p_ge_3 & ~p_ge_10);
    wire p_1101_q_2 = (b_1101 & p_ge_10 & ~p_ge_19);
    // 14
    wire p_1110_q_neg2 = (b_1110 & p_ge_neg20 & ~p_ge_neg10);
    wire p_1110_q_neg1 = (b_1110 & p_ge_neg11 & ~p_ge_neg3);
    wire p_1110_q_0 = (b_1110 & p_ge_neg4 & ~p_ge_4);
    wire p_1110_q_1 = (b_1110 & p_ge_3 & ~p_ge_11);
    wire p_1110_q_2 = (b_1110 & p_ge_10 & ~p_ge_20);
    // 15
    wire p_1111_q_neg2 = (b_1111 & p_ge_neg22 & ~p_ge_neg11);
    wire p_1111_q_neg1 = (b_1111 & p_ge_neg12 & ~p_ge_neg3);
    wire p_1111_q_0 = (b_1111 & p_ge_neg5 & ~p_ge_5);
    wire p_1111_q_1 = (b_1111 & p_ge_3 & ~p_ge_12);
    wire p_1111_q_2 = (b_1111 & p_ge_11 & ~p_ge_22);

    wire q_neg2 = p_1000_q_neg2 | p_1001_q_neg2 | p_1010_q_neg2 | p_1011_q_neg2 | 
                p_1100_q_neg2 | p_1101_q_neg2 | p_1110_q_neg2 | p_1111_q_neg2;

    wire q_neg1 = p_1000_q_neg1 | p_1001_q_neg1 | p_1010_q_neg1 | p_1011_q_neg1 | 
                p_1100_q_neg1 | p_1101_q_neg1 | p_1110_q_neg1 | p_1111_q_neg1;

    wire q_0 = p_1000_q_0 | p_1001_q_0 | p_1010_q_0 | p_1011_q_0 | 
                p_1100_q_0 | p_1101_q_0 | p_1110_q_0 | p_1111_q_0;

    wire q_1 = p_1000_q_1 | p_1001_q_1 | p_1010_q_1 | p_1011_q_1 | 
                p_1100_q_1 | p_1101_q_1 | p_1110_q_1 | p_1111_q_1;

    wire q_2 = p_1000_q_2 | p_1001_q_2 | p_1010_q_2 | p_1011_q_2 | 
                p_1100_q_2 | p_1101_q_2 | p_1110_q_2 | p_1111_q_2;

    assign q = q_neg2? 3'b110:
        q_neg1? 3'b111:
        q_0? 0:
        q_1? 3'b001:
        3'b010;

endmodule