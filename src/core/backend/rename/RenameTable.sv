`include "../../../defines/defines.svh"

interface RenameTableIO #(
    parameter SRC_NUM=2
);
    logic `TENSOR(SRC_NUM, `FETCH_WIDTH, 5) vsrc;
    logic `ARRAY(`FETCH_WIDTH, 5) vrd;
    logic `TENSOR(SRC_NUM, `FETCH_WIDTH, `PREG_WIDTH) psrc;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) commit_prd;
    logic `N(`FETCH_WIDTH) rename_we;
    logic `ARRAY(`FETCH_WIDTH, 5) rename_vrd;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rename_prd;

    modport rename (input vsrc, vrd, rename_we, rename_vrd, rename_prd, output psrc, prd, commit_prd);
endinterface

module RenameTable #(
    parameter SRC_NUM=2,
    parameter FPV=0
)(
    input logic clk,
    input logic rst,
    RenameTableIO.rename rename_io,
    CommitBus.in commitBus,
    input CommitWalk commitWalk
`ifdef DIFFTEST
    ,DiffRAT.rat diff_rat
`endif
);

    RATIO #(`FETCH_WIDTH, `WALK_WIDTH) rd_io();
    RATIO #(`COMMIT_WIDTH, `COMMIT_WIDTH) commit_io();
    RAT #(`FETCH_WIDTH, `WALK_WIDTH) rd_rat(.*, .rat_io(rd_io));
    RAT #(`FETCH_WIDTH, `COMMIT_WIDTH) commit_rat(.*, .rat_io(commit_io));

    logic `ARRAY(`COMMIT_WIDTH, `COMMIT_WIDTH) waw;
    logic `N(`COMMIT_WIDTH) commit_cancel_waw;
    // logic `ARRAY(`COMMIT_WIDTH, $clog2(`COMMIT_WIDTH)) waw_replaceIdx;
    logic `N(`COMMIT_WIDTH) commit_we;
    logic `N(`WALK_WIDTH) walk_we;
    logic `N(`WALK_WIDTH) walk_cancel_waw;
    logic `ARRAY(`WALK_WIDTH, `WALK_WIDTH) walk_waw;
generate
    for(genvar i=0; i<SRC_NUM; i++)begin
        RATIO #(`FETCH_WIDTH, `WALK_WIDTH) src_io();
        RAT #(`FETCH_WIDTH, `WALK_WIDTH) rat (.*, .rat_io(src_io));
        assign src_io.vreg = rename_io.vsrc[i];
        assign rename_io.psrc[i] = src_io.preg;
        assign src_io.we = commitWalk.walk ? walk_we  & ~walk_cancel_waw : rename_io.rename_we;
        assign src_io.waddr = commitWalk.walk ? commitWalk.vrd : rename_io.rename_vrd;
        assign src_io.wdata = commitWalk.walk ? commitWalk.old_prd : rename_io.rename_prd;
    end
endgenerate
    assign rd_io.vreg = rename_io.vrd;
    assign rename_io.prd = rd_io.preg;
    assign rd_io.we = commitWalk.walk ? walk_we  & ~walk_cancel_waw : rename_io.rename_we;
    assign rd_io.waddr = commitWalk.walk ? commitWalk.vrd : rename_io.rename_vrd;
    assign rd_io.wdata = commitWalk.walk ? commitWalk.old_prd : rename_io.rename_prd;
    
generate
    if(FPV)begin
        assign commit_we = commitBus.en & commitBus.fp_we & ~commitBus.excValid;
        assign walk_we = commitWalk.en & commitWalk.fp_we;
    end
    else begin
        assign commit_we = commitBus.en & commitBus.we & ~commitBus.fp_we & ~commitBus.excValid;
        assign walk_we = commitWalk.en & commitWalk.we & ~commitWalk.fp_we;
    end
endgenerate
    
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        for(genvar j=0; j<`COMMIT_WIDTH; j++)begin
            if(j <= i)begin
                assign waw[i][j] = 0;
            end
            else begin
                assign waw[i][j] = commit_we[i] & commit_we[j] & (commitBus.vrd[i] == commitBus.vrd[j]);
            end
        end
        assign commit_cancel_waw[i] = |waw[i];
        logic `N(`COMMIT_WIDTH) waw_select;
        PRSelector #(`COMMIT_WIDTH) prselector_waw (waw[i], waw_select);
        // Encoder #(`COMMIT_WIDTH) encoder_waw (waw_select, waw_replaceIdx[i]);

        assign rename_io.commit_prd[i] = commit_cancel_waw[i] ? commitBus.prd[i] : commit_io.preg[i];
    end
    for(genvar i=0; i<`WALK_WIDTH; i++)begin
        for(genvar j=0; j<`WALK_WIDTH; j++)begin
            if(j <= i)begin
                assign walk_waw[i][j] = 0;
            end
            else begin
                assign walk_waw[i][j] = walk_we[i] & walk_we[j] & (commitWalk.vrd[i] == commitWalk.vrd[j]);
            end
        end
        assign walk_cancel_waw[i] = |walk_waw[i];
    end

endgenerate

    assign commit_io.vreg = commitBus.vrd;
    assign commit_io.we = commit_we & ~commit_cancel_waw;
    assign commit_io.waddr = commitBus.vrd;
    assign commit_io.wdata = commitBus.prd;

`ifdef DIFFTEST
    logic `ARRAY(32, `PREG_WIDTH) diff_map;
    assign diff_rat.map_reg = diff_map;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            for(int i=0; i<32; i++)begin
                diff_map[i] <= i;
            end
        end
        else begin
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(commit_we[i])begin
                    diff_map[commit_io.waddr[i]] <= commit_io.wdata[i];
                end
            end
        end
    end
`endif
endmodule