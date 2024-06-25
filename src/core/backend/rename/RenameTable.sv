`include "../../../defines/defines.svh"

interface RenameTableIO;
    logic `ARRAY(`FETCH_WIDTH, 5) vrs1;
    logic `ARRAY(`FETCH_WIDTH, 5) vrs2;
    logic `ARRAY(`FETCH_WIDTH, 5) vrd;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs1;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prs2;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) prd;
    logic `ARRAY(`COMMIT_WIDTH, `PREG_WIDTH) commit_prd;
    logic `N(`FETCH_WIDTH) rename_we;
    logic `ARRAY(`FETCH_WIDTH, 5) rename_vrd;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rename_prd;

    modport rename (input vrs1, vrs2, vrd, rename_we, rename_vrd, rename_prd, output prs1, prs2, prd, commit_prd);
endinterface

module RenameTable(
    input logic clk,
    input logic rst,
    RenameTableIO.rename rename_io,
    CommitBus.in commitBus,
    CommitWalk commitWalk
`ifdef DIFFTEST
    ,DiffRAT.rat diff_rat
`endif
);

    RATIO #(`FETCH_WIDTH, `WB_SIZE) rs1_io();
    RATIO #(`FETCH_WIDTH, `WB_SIZE) rs2_io();
    RATIO #(`FETCH_WIDTH, `WB_SIZE) rd_io();
    RATIO #(`COMMIT_WIDTH, `COMMIT_WIDTH) commit_io();
    RAT #(`FETCH_WIDTH, `WB_SIZE) rs1_rat(.*, .rat_io(rs1_io));
    RAT #(`FETCH_WIDTH, `WB_SIZE) rs2_rat(.*, .rat_io(rs2_io));
    RAT #(`FETCH_WIDTH, `WB_SIZE) rd_rat(.*, .rat_io(rd_io));
    RAT #(`FETCH_WIDTH, `COMMIT_WIDTH) commit_rat(.*, .rat_io(commit_io));

    logic `ARRAY(`COMMIT_WIDTH, `COMMIT_WIDTH) waw;
    logic `N(`COMMIT_WIDTH) commit_cancel_waw;
    // logic `ARRAY(`COMMIT_WIDTH, $clog2(`COMMIT_WIDTH)) waw_replaceIdx;
    logic `N(`COMMIT_WIDTH) commit_we;

    assign rs1_io.vreg = rename_io.vrs1;
    assign rename_io.prs1 = rs1_io.preg;
    assign rs2_io.vreg = rename_io.vrs2;
    assign rename_io.prs2 = rs2_io.preg;
    assign rd_io.vreg = rename_io.vrd;
    assign rename_io.prd = rd_io.preg;

    assign rs1_io.we = commitWalk.walk ? commitWalk.en & commitWalk.we  & ~commit_cancel_waw : rename_io.rename_we;
    assign rs2_io.we = commitWalk.walk ? commitWalk.en & commitWalk.we  & ~commit_cancel_waw : rename_io.rename_we;
    assign rd_io.we = commitWalk.walk ? commitWalk.en & commitWalk.we  & ~commit_cancel_waw : rename_io.rename_we;
    assign rs1_io.waddr = commitWalk.walk ? commitWalk.vrd : rename_io.rename_vrd;
    assign rs2_io.waddr = commitWalk.walk ? commitWalk.vrd : rename_io.rename_vrd;
    assign rd_io.waddr = commitWalk.walk ? commitWalk.vrd : rename_io.rename_vrd;
    assign rs1_io.wdata = commitWalk.walk ? commitWalk.old_prd : rename_io.rename_prd;
    assign rs2_io.wdata = commitWalk.walk ? commitWalk.old_prd : rename_io.rename_prd;
    assign rd_io.wdata = commitWalk.walk ? commitWalk.old_prd : rename_io.rename_prd;
    
    assign commit_we = commitBus.en & commitBus.we;
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
endgenerate

    assign commit_io.vreg = commitBus.vrd;
    assign commit_io.we = commit_we & ~commit_cancel_waw;
    assign commit_io.waddr = commitBus.vrd;
    assign commit_io.wdata = commitBus.prd;

`ifdef DIFFTEST
    logic `ARRAY(32, `PREG_WIDTH) diff_map;
    assign diff_rat.map_reg = diff_map;
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<32; i++)begin
                diff_map[i] <= i;
            end
        end
        else begin
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(commit_io.we[i])begin
                    diff_map[commit_io.waddr[i]] <= commit_io.wdata[i];
                end
            end
        end
    end
`endif
endmodule