`include "../../../defines/defines.svh"

module BackendRedirectCtrl (
    input logic clk,
    input logic rst,
    BackendRedirectIO.redirect io,
    RobRedirectIO.redirect rob_redirect_io,
    output RobIdx redirectIdx
);
    logic branchOlder;
    logic branchValid, branchValid_n;
    RobIdx preRedirectIdx;
    BackendRedirectInfo preRedirect;
    BranchRedirectInfo  preBranch;
    LoopCompare #(`ROB_WIDTH) compare_rob (
        io.branchRedirect.robIdx,
        io.memRedirect.robIdx,
        branchOlder
    );
    assign branchValid = (io.branchRedirect.en & branchOlder) | (io.branchRedirect.en & ~io.memRedirect.en);
    always_ff @(posedge clk)begin
        branchValid_n <= branchValid;
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst == `RST) begin
            preRedirect <= 0;
            preBranch   <= 0;
            preRedirectIdx <= 0;
        end 
        else begin
            preRedirect <= branchValid ? io.branchRedirect : io.memRedirect;
            preBranch <= io.branchInfo;
            preRedirectIdx <= branchValid ? io.branchRedirect.robIdx : io.memRedirectIdx;
        end
    end
    assign io.out = rob_redirect_io.csrRedirect.en ? rob_redirect_io.csrRedirect : preRedirect;
    assign io.branchOut.en = branchValid_n & ~rob_redirect_io.csrRedirect.en;
    assign io.branchOut.taken = preBranch.taken;
    assign io.branchOut.target = preBranch.target;
    assign io.branchOut.br_type = preBranch.br_type;
    assign io.branchOut.ras_type = preBranch.ras_type;
    assign io.csrOut = rob_redirect_io.csrInfo;
    assign redirectIdx = rob_redirect_io.csrRedirect.en ? rob_redirect_io.csrRedirect.robIdx : preRedirectIdx;
endmodule
