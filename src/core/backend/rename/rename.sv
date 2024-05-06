`include "../../../defines/defines.svh"

module Rename(
    input logic clk,
    input logic rst,
    DecodeRenameIO.rename dec_rename_io,
    RenameDisIO.rename rename_dis_io,
    ROBRenameIO.rename rob_rename_io
);

    RATIO rs1_io;
    RATIO rs2_io;
    FreelistIO fl_io;
    logic `N($clog2(`FETCH_WIDTH)) rdNum;
    logic `N(`FETCH_WIDTH) rd_en;

    RAT rs1_rat(.*, .rat_io(rs1_io));
    RAT rs2_rat(.*, .rat_io(rs2_io));
    assign fl_io.en = rdNum;
    Freelist(.*);

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign rdNum = rdNum + rd_en[i];
        assign rd_en[i] = dec_rename_io.op[i].di.en && dec_rename_io.op[i].di.rd != 0;
        assign rs1_io.vreg[i] = dec_rename_io.op[i].di.rs1;
        assign rs2_io.vreg[i] = dec_rename_io.op[i].di.rs2;
    end
endgenerate

// conflict
    logic `ARRAY(`FETCH_WIDTH-1, `FETCH_WIDTH) raw_rs1, raw_rs2; // read after write
    logic `ARRAY(`FETCH_WIDTH-1, $clog2(`FETCH_WIDTH)) raw_rs1_idx, raw_rs2_idx;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs1, prs2, prd;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) prdIdx;

generate
    assign prdIdx[0] = 0;
    for(genvar i=1; i<`FETCH_WIDTH; i++)begin
        assign prdIdx[i] = prdIdx[i-1] + rd_en[i];
    end
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign prd[i] = rd_en[i] ? fl_io.prd[prdIdx[i]] : 0;
        assign prs1[i] = |raw_rs1[i] ? prd[raw_rs1_idx[i]] : rs1_io.preg[i];
        assign prs2[i] = |raw_rs2[i] ? prd[raw_rs2_idx[i]] : rs2_Io.preg[i];
    end

    for(genvar i=0; i<`FETCH_WIDTH-1; i++)begin
        for(genvar j=0; j<`FETCH_WIDTH; j++)begin
            if(j <= i)begin
                assign raw_rs1[i][j] = 0;
                assign raw_rs2[i][j] = 0;
                assign waw[i][j] = 0;
            end
            else begin
                assign raw_rs1[i][j] = rd_en[j] && dec_rename_io.op[i].di.rs1 == dec_rename_io.op[j].di.rd;
                assign raw_rs2[i][j] = rd_en[j] && dec_rename_io.op[i].di.rs2 == dec_rename_io.op[j].di.rd;
            end
        end
        PEncoder #(`FETCH_WIDTH) encoder_rs1_idx (raw_rs1[i], raw_rs1_idx[i]);
        PEncoder #(`FETCH_WIDTH) encoder_rs2_idx (raw_rs2[i], raw_rs2_idx[i]);
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            rename_dis_io.op <= 0;
            rename_dis_io.prs1 <= 0;
            rename_dis_io.prd <= 0;
            rename_dis_io.robIdx <= 0;
            rename_dis_io.wen <= 0;
        end
        else begin
            rename_dis_io.op <= dec_rename_io.op;
            rename_dis_io.prs1 <= prs1;
            rename_dis_io.prs2 <= prs2;
            rename_dis_io.prd <= prd;
            rename_dis_io.wen <= rd_en;
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                rename_dis_io.robIdx <= rob_rename_io.robIdx + i;
            end
        end
    end

endmodule