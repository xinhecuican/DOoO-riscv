`include "../../../defines/defines.svh"

// control branch result
// generator oldest predict error instr and send to frontend

interface AluBranchCtrlIO;
    AluBranchBundle `N(`ALU_SIZE) bundles;
    BackendRedirectInfo redirectInfo;
    BranchRedirectInfo branchInfo;

    modport ctrl (input bundles, output redirectInfo, branchInfo);
endinterface

module AluBranchCtrl(
    input logic clk,
    input logic rst,
    AluBranchCtrlIO.ctrl io
);
    AluBranchBundle bundle_o;
    BranchCtrlCmp #(`ALU_SIZE) cmp (io.bundles, bundle_o);
    always_comb begin
        io.redirectInfo.en = bundle_o.en & bundle_o.res.error;
        io.redirectInfo.fsqInfo = bundle_o.fsqInfo;
        io.redirectInfo.robIdx = bundle_o.robIdx;
        io.branchInfo.en = 1'b0;
        io.branchInfo.taken = bundle_o.res.direction;
        io.branchInfo.target = bundle_o.res.target;
        io.branchInfo.br_type = bundle_o.res.br_type;
        io.branchInfo.ras_type = bundle_o.res.ras_type;
    end
endmodule

module BranchCtrlCmp #(
    parameter WIDTH = 4
)(
    input AluBranchBundle `N(WIDTH) bundles,
    output AluBranchBundle bundle_o
);
generate
    if(WIDTH == 1)begin
        assign bundle_o = bundles[0];
    end
    else if(WIDTH == 2)begin
        logic bigger, sameLine;
        assign sameLine = ((bundles[0].fsqDir == bundles[1].fsqDir)) &
                          (bundles[0].fsqInfo.idx == bundles[1].fsqInfo.idx);
        assign bigger = (bundles[0].fsqDir ^ bundles[1].fsqDir) ^
                        (bundles[0].fsqInfo.idx < bundles[1].fsqInfo.idx);
        always_comb begin
            case({bundles[1].en & bundles[1].res.error, bundles[0].en & bundles[0].res.error})
            2'b00: bundle_o = bundles[0];
            2'b01: bundle_o = bundles[0];
            2'b10: bundle_o = bundles[1];
            2'b11: bundle_o = sameLine && bundles[0].fsqInfo.offset < bundles[1].fsqInfo.offset || 
                                    !sameLine && bigger ? bundles[0] : bundles[1];
            endcase
        end

    end
    else begin
        localparam HALF = WIDTH / 2;
        AluBranchBundle bundle1, bundle2;
        BranchCtrlCmp #(HALF) cmp1(bundles[HALF-1: 0], bundle1);
        BranchCtrlCmp #(WIDTH-HALF) cmp2(bundles[WIDTH-1: HALF], bundle2);
        BranchCtrlCmp #(2) cmp({bundle2, bundle1}, bundle_o);
    end
endgenerate
endmodule