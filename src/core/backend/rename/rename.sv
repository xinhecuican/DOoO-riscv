`include "../../../defines/defines.svh"

module Rename(
    input logic clk,
    input logic rst,
    DecodeRenameIO.rename dec_rename_io,
    RenameDisIO.rename rename_dis_io,
    ROBRenameIO.rename rob_rename_io,
    CommitBus.in commitBus,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl,
    output logic full
`ifdef DIFFTEST
    ,DiffRAT.rat diff_rat
`endif
);

    RenameTableIO rename_io();
    FreelistIO fl_io();
    logic `N($clog2(`FETCH_WIDTH)+1) rdNum;
    logic `N(`FETCH_WIDTH) rd_en, rd_we;
    logic `N(`FETCH_WIDTH) en;
    logic stall;

    RenameTable renameTable(.*);
    assign fl_io.rdNum = rdNum;
    assign fl_io.commit_prd = rename_io.commit_prd;
    assign full = fl_io.full;
    Freelist freelist (.*);

// conflict
    logic `ARRAY(`FETCH_WIDTH, `FETCH_WIDTH) raw_rs1, raw_rs2, waw, waw_old; // read after write
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) raw_rs1_idx, raw_rs2_idx, waw_idx;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs1, prs2, old_prd, prd;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) prdIdx;

    assign stall = backendCtrl.dis_full;
    
    CalValidNum #(`FETCH_WIDTH) cal_rd_num (rd_en, prdIdx);
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign prd[i] = rd_en[i] ? fl_io.prd[prdIdx[i]] : 0;
        assign old_prd[i] = |waw_old[i] ? prd[waw_idx[i]] : rename_io.prd[i];
        assign prs1[i] = |raw_rs1[i] ? prd[raw_rs1_idx[i]] : rename_io.prs1[i];
        assign prs2[i] = |raw_rs2[i] ? prd[raw_rs2_idx[i]] : rename_io.prs2[i];
    end

    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        for(genvar j=0; j<`FETCH_WIDTH; j++)begin
            if(i == j)begin
                assign raw_rs1[i][j] = 0;
                assign raw_rs2[i][j] = 0;
                assign waw[i][j] = 0;
                assign waw_old[i][j] = 0;
            end
            else if(j > i)begin
                assign raw_rs1[i][j] = 0;
                assign raw_rs2[i][j] = 0;
                assign waw[i][j] = rd_en[i] & rd_en[j] & (dec_rename_io.op[i].di.rd == dec_rename_io.op[j].di.rd);
                assign waw_old[i][j] = 0;
            end
            else begin
                assign raw_rs1[i][j] = rd_en[j] && dec_rename_io.op[i].di.rs1 == dec_rename_io.op[j].di.rd;
                assign raw_rs2[i][j] = rd_en[j] && dec_rename_io.op[i].di.rs2 == dec_rename_io.op[j].di.rd;
                assign waw[i][j] = 0;
                assign waw_old[i][j] = rd_en[i] & rd_en[j] & (dec_rename_io.op[i].di.rd == dec_rename_io.op[j].di.rd);
            end
        end
        PEncoder #(`FETCH_WIDTH) encoder_rs1_idx (raw_rs1[i], raw_rs1_idx[i]);
        PEncoder #(`FETCH_WIDTH) encoder_rs2_idx (raw_rs2[i], raw_rs2_idx[i]);
        PEncoder #(`FETCH_WIDTH) encoder_waw_idx (waw_old[i], waw_idx[i]);
    end
endgenerate

    logic `ARRAY(`FETCH_WIDTH, `ROB_WIDTH) robIdx;
    ParallelAdder #(1, `FETCH_WIDTH) adder_rdnum (rd_en, rdNum);
generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign en[i] = dec_rename_io.op[i].en;
        assign rd_en[i] = dec_rename_io.op[i].en && dec_rename_io.op[i].di.we;
        assign rename_io.vrs1[i] = dec_rename_io.op[i].di.rs1;
        assign rename_io.vrs2[i] = dec_rename_io.op[i].di.rs2;
        assign rename_io.vrd[i] = dec_rename_io.op[i].di.rd;
        assign rd_we[i] = rd_en[i] & ~(|waw[i]);
        assign rename_io.rename_we[i] = rd_we[i] & ~backendCtrl.redirect & ~stall & ~backendCtrl.rename_full;
        assign rename_io.rename_vrd[i] = dec_rename_io.op[i].di.rd;
        assign rename_io.rename_prd[i] = prd[i];
        assign robIdx[i] = rob_rename_io.robIdx.idx + i;
    end
endgenerate

    logic `N($clog2(`FETCH_WIDTH) + 1) validNum;
    ParallelAdder #(1, `FETCH_WIDTH) adder_valid (en, validNum);
    assign rob_rename_io.validNum = validNum;
    always_ff @(posedge clk)begin
        if(~stall)begin
            rename_dis_io.prs1 <= prs1;
            rename_dis_io.prs2 <= prs2;
            rename_dis_io.prd <= prd;
            rename_dis_io.old_prd <= old_prd;
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                rename_dis_io.robIdx[i].idx <= robIdx[i];
                rename_dis_io.robIdx[i].dir <= rob_rename_io.robIdx.idx[`ROB_WIDTH-1] & ~robIdx[i][`ROB_WIDTH-1] ? ~rob_rename_io.robIdx.dir : rob_rename_io.robIdx.dir;
            end
        end
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            rename_dis_io.op <= 0;
            rename_dis_io.wen <= 0;
        end
        else if(backendCtrl.redirect)begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                rename_dis_io.op[i].en <= 0;
                rename_dis_io.wen[i] <= 0;
            end
        end
        else if(~stall)begin
            if(backendCtrl.rename_full)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    rename_dis_io.op[i].en <= 0;
                    rename_dis_io.wen[i] <= 0;
                end
            end
            else begin
                rename_dis_io.op <= dec_rename_io.op;
                rename_dis_io.wen <= rd_en;
            end
        end
    end

endmodule