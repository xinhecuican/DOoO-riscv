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
    ,DiffRAT.rat diff_int_rat
`ifdef RVF
    ,DiffRAT.rat diff_fp_rat
`endif
`endif
`ifdef FEAT_MEMPRED
    ,StoreSetIO.rename storeset_io
`endif
);
    logic `ARRAY(`FETCH_WIDTH, `ROB_WIDTH) robIdx;
    logic `N(`FETCH_WIDTH) int_rd_en;
    logic `N(`FETCH_WIDTH) en;
    logic `TENSOR(2, `FETCH_WIDTH, 5) vsrc;
    logic `ARRAY(`FETCH_WIDTH, 5) vrd;
    logic `TENSOR(2, `FETCH_WIDTH, `PREG_WIDTH) int_psrc;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) int_prd, int_old_prd;
    logic int_full;
    logic stall;
`ifdef RVF
    logic `N(`FETCH_WIDTH) fp_rd_en;
    logic `ARRAY(`FETCH_WIDTH, 5) vrs3;
    logic `TENSOR(3, `FETCH_WIDTH, `PREG_WIDTH) fp_psrc;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) fp_prd, fp_old_prd;
    logic fp_full;
`endif

    assign full = int_full
`ifdef RVF
                 | fp_full
`endif
    ;
    assign stall = backendCtrl.dis_full;
    
    RenameImpl #(
        .SRC_NUM(2), 
        .PREG_SIZE(`INT_PREG_SIZE)
    ) rename_int (
        .*,
        .rd_en(int_rd_en),
        .vsrc(vsrc),
        .psrc(int_psrc),
        .prd(int_prd),
        .old_prd(int_old_prd),
        .full(int_full)
`ifdef DIFFTEST
        ,.diff_rat(diff_int_rat)
`endif
    );
`ifdef RVF
    RenameImpl #(
        .SRC_NUM(3), 
        .FPV(1),
        .PREG_SIZE(`FP_PREG_SIZE)
    ) rename_fp (
        .*,
        .rd_en(fp_rd_en),
        .vsrc({vrs3, vsrc}),
        .psrc(fp_psrc),
        .prd(fp_prd),
        .old_prd(fp_old_prd),
        .full(fp_full)
`ifdef DIFFTEST
        ,.diff_rat(diff_fp_rat)
`endif
    );
`endif

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign vsrc[0][i] = dec_rename_io.op[i].di.rs1;
        assign vsrc[1][i] = dec_rename_io.op[i].di.rs2;
        assign vrd[i] = dec_rename_io.op[i].di.rd;
        assign en[i] = dec_rename_io.op[i].en;
        assign int_rd_en[i] = dec_rename_io.op[i].en & dec_rename_io.op[i].di.we
`ifdef RVF
                              & ~dec_rename_io.op[i].di.flt_we;
`endif
        ;
`ifdef RVF
        assign fp_rd_en[i] = dec_rename_io.op[i].en & dec_rename_io.op[i].di.flt_we;
        assign vrs3[i] = dec_rename_io.op[i].di.rs3;
`endif
        assign robIdx[i] = rob_rename_io.robIdx.idx + i;
    end
endgenerate

    logic `N($clog2(`FETCH_WIDTH) + 1) validNum;
    ParallelAdder #(1, `FETCH_WIDTH) adder_valid (en, validNum);
    assign rob_rename_io.validNum = validNum;
    always_ff @(posedge clk)begin
        if(~stall)begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                rename_dis_io.prs1[i] <= 
`ifdef RVF
                dec_rename_io.op[i].di.frs1_sel ? fp_psrc[0][i] :
`endif
                int_psrc[0][i];
                rename_dis_io.prs2[i] <= 
`ifdef RVF
                dec_rename_io.op[i].di.frs2_sel ? fp_psrc[1][i] :
`endif
                int_psrc[1][i];
`ifdef RVF
                rename_dis_io.prs3[i] <= fp_psrc[2][i];
`endif
                rename_dis_io.prd[i] <= 
`ifdef RVF
                dec_rename_io.op[i].di.flt_we ? fp_prd[i] :
`endif
                int_prd[i];
                rename_dis_io.old_prd[i] <= 
`ifdef RVF
                dec_rename_io.op[i].di.flt_we ? fp_old_prd[i] : 
`endif
                int_old_prd[i];
            end
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                rename_dis_io.robIdx[i].idx <= robIdx[i];
                rename_dis_io.robIdx[i].dir <= rob_rename_io.robIdx.idx[`ROB_WIDTH-1] & ~robIdx[i][`ROB_WIDTH-1] ? ~rob_rename_io.robIdx.dir : rob_rename_io.robIdx.dir;
            end
        end
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            rename_dis_io.op <= 0;
            rename_dis_io.int_wen <= 0;
`ifdef RVF
            rename_dis_io.fp_wen <= 0;
`endif
        end
        else if(backendCtrl.redirect)begin
            for(int i=0; i<`FETCH_WIDTH; i++)begin
                rename_dis_io.op[i].en <= 0;
                rename_dis_io.int_wen[i] <= 0;
`ifdef RVF
                rename_dis_io.fp_wen[i] <= 0;
`endif
            end
        end
        else if(~stall)begin
            if(backendCtrl.rename_full)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    rename_dis_io.op[i].en <= 0;
                    rename_dis_io.int_wen[i] <= 0;
`ifdef RVF
                    rename_dis_io.fp_wen[i] <= 0;
`endif
                end
            end
            else begin
                rename_dis_io.op <= dec_rename_io.op;
                rename_dis_io.int_wen <= int_rd_en;
`ifdef RVF
                rename_dis_io.fp_wen <= fp_rd_en;
`endif
            end
        end
    end

`ifdef FEAT_MEMPRED
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign storeset_io.en[i] = dec_rename_io.op[i].en & ~stall;
        assign storeset_io.raddr[i] = dec_rename_io.op[i].ssit_idx;
    end
endgenerate
`endif

endmodule

module RenameImpl #(
    parameter SRC_NUM=2,
    parameter PREG_SIZE=128,
    parameter FPV=0
)(
    input logic clk,
    input logic rst,
    input logic stall,
    input logic `N(`FETCH_WIDTH) rd_en,
    input logic `TENSOR(SRC_NUM, `FETCH_WIDTH, 5) vsrc,
    input logic `ARRAY(`FETCH_WIDTH, 5) vrd,
    output logic `TENSOR(SRC_NUM, `FETCH_WIDTH, `PREG_WIDTH) psrc,
    output logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd,
    output logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) old_prd,
    CommitBus.in commitBus,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl,
    output logic full
`ifdef DIFFTEST
    ,DiffRAT.rat diff_rat
`endif
);
    RenameTableIO #(SRC_NUM) rename_io();
    FreelistIO fl_io();
    logic `N($clog2(`FETCH_WIDTH)+1) rdNum;
    logic `N(`FETCH_WIDTH) rd_we;

    RenameTable #(.SRC_NUM(SRC_NUM),.FPV(FPV)) renameTable(.*);
    assign fl_io.rdNum = rdNum;
    assign fl_io.commit_prd = rename_io.commit_prd;
    assign full = fl_io.full;
    Freelist #(FPV, PREG_SIZE) freelist (.*);

// conflict
    logic `TENSOR(SRC_NUM, `FETCH_WIDTH, `FETCH_WIDTH) raw;
    logic `TENSOR(SRC_NUM, `FETCH_WIDTH, $clog2(`FETCH_WIDTH)) raw_idx;
    logic `ARRAY(`FETCH_WIDTH, `FETCH_WIDTH) waw, waw_old; // read after write
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) waw_idx;
    logic `ARRAY(`FETCH_WIDTH, $clog2(`FETCH_WIDTH)) prdIdx;
    
    CalValidNum #(`FETCH_WIDTH) cal_rd_num (rd_en, prdIdx);
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign prd[i] = rd_en[i] ? fl_io.prd[prdIdx[i]] : 0;
        assign old_prd[i] = |waw_old[i] ? prd[waw_idx[i]] : rename_io.prd[i];
    end
    for(genvar i=0; i<SRC_NUM; i++)begin
        for(genvar j=0; j<`FETCH_WIDTH; j++)begin
            for(genvar k=0; k<`FETCH_WIDTH; k++)begin
                if(j == k)begin
                    assign raw[i][j][k] = 0;
                end
                else if(k > j)begin
                    assign raw[i][j][k] = 0;
                end
                else begin
                    assign raw[i][j][k] = rd_en[k] && vsrc[i][j] == vrd[k];
                end
            end
            PEncoder #(`FETCH_WIDTH) encoder_raw_idx (raw[i][j], raw_idx[i][j]);
            assign psrc[i][j] = |raw[i][j] ? prd[raw_idx[i][j]] : rename_io.psrc[i][j];
        end
    end

    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        for(genvar j=0; j<`FETCH_WIDTH; j++)begin
            if(i == j)begin
                assign waw[i][j] = 0;
                assign waw_old[i][j] = 0;
            end
            else if(j > i)begin
                assign waw[i][j] = rd_en[i] & rd_en[j] & (vrd[i] == vrd[j]);
                assign waw_old[i][j] = 0;
            end
            else begin
                assign waw[i][j] = 0;
                assign waw_old[i][j] = rd_en[i] & rd_en[j] & (vrd[i] == vrd[j]);
            end
        end
        PEncoder #(`FETCH_WIDTH) encoder_waw_idx (waw_old[i], waw_idx[i]);
    end
endgenerate

    logic `ARRAY(`FETCH_WIDTH, `ROB_WIDTH) robIdx;
    ParallelAdder #(1, `FETCH_WIDTH) adder_rdnum (rd_en, rdNum);
    assign rename_io.vsrc = vsrc;
generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign rename_io.vrd[i] = vrd[i];
        assign rd_we[i] = rd_en[i] & ~(|waw[i]);
        assign rename_io.rename_we[i] = rd_we[i] & ~backendCtrl.redirect & ~stall & ~backendCtrl.rename_full;
        assign rename_io.rename_vrd[i] = vrd[i];
        assign rename_io.rename_prd[i] = prd[i];
    end
endgenerate

    `PERF(rename_full, (|rd_en) & fl_io.full)
endmodule