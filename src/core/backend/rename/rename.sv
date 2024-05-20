`include "../../../defines/defines.svh"

module Rename(
    input logic clk,
    input logic rst,
    DecodeRenameIO.rename dec_rename_io,
    RenameDisIO.rename rename_dis_io,
    ROBRenameIO.rename rob_rename_io,
    CommitBus commitBus
);

    RenameTableIO rename_io;
    FreelistIO fl_io;
    logic `N($clog2(`FETCH_WIDTH)) rdNum;
    logic `N(`FETCH_WIDTH) rd_en;

    RenameTableIO renameTable(.*);
    assign fl_io.en = rdNum;
    assign fl_io.old_prd = rename_io.old_prd;
    Freelist(.*);

// conflict
    logic `ARRAY(`FETCH_WIDTH, `FETCH_WIDTH) raw_rs1, raw_rs2, waw; // read after write
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) raw_rs1_idx, raw_rs2_idx;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs1, prs2, prd;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) prdIdx;

generate
    assign prdIdx[0] = 0;
    for(genvar i=1; i<`FETCH_WIDTH; i++)begin
        assign prdIdx[i] = prdIdx[i-1] + rd_en[i];
    end
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign prd[i] = rd_en[i] ? fl_io.prd[prdIdx[i]] : 0;
        assign prs1[i] = |raw_rs1[i] ? prd[raw_rs1_idx[i]] : rename_io.prs1[i];
        assign prs2[i] = |raw_rs2[i] ? prd[raw_rs2_idx[i]] : rename_io.prs2[i];
    end

    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        for(genvar j=0; j<`FETCH_WIDTH; j++)begin
            if(j <= i)begin
                assign raw_rs1[i][j] = 0;
                assign raw_rs2[i][j] = 0;
                assign waw[i][j] = 0;
            end
            else begin
                assign raw_rs1[i][j] = rd_en[j] && dec_rename_io.op[i].di.rs1 == dec_rename_io.op[j].di.rd;
                assign raw_rs2[i][j] = rd_en[j] && dec_rename_io.op[i].di.rs2 == dec_rename_io.op[j].di.rd;
                assign waw[i][j] = rd_en[i] & rd_en[j] & (dec_rename_io.op[i].di.rd == dec_rename_io.op[j].di.rd);
            end
        end
        PEncoder #(`FETCH_WIDTH) encoder_rs1_idx (raw_rs1[i], raw_rs1_idx[i]);
        PEncoder #(`FETCH_WIDTH) encoder_rs2_idx (raw_rs2[i], raw_rs2_idx[i]);
    end
endgenerate

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign rdNum = rdNum + rd_en[i];
        assign rd_en[i] = dec_rename_io.op[i].di.en && dec_rename_io.op[i].di.we;
        assign rename_io.vrs1[i] = dec_rename_io.op[i].di.rs1;
        assign rename_io.vrs2[i] = dec_rename_io.op[i].di.rs2;
        assign rename_io.rename_we[i] = rd_en[i] & ~(|waw[i]);
        assign rename_io.rename_vrd[i] = dec_rename_io.op[i].di.rd;
        assign rename_io.rename_prd[i] = prd[i];
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