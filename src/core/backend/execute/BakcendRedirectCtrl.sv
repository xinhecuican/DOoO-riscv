`include "../../../defines/defines.svh"

module BackendRedirectCtrl(
    input logic clk,
    input logic rst,
    BackendRedirectIO.redirect io
);
    logic branchOlder;
    LoopCompare #(`ROB_WIDTH) compare_rob (io.branchRedirect.robIdx, io.memRedirect.robIdx, branchOlder);
    always_ff @(posedge clk)begin
        io.out <= (io.branchRedirect.en & branchOlder) | (io.branchRedirect.en & ~io.memRedirect.en) ? io.branchRedirect : io.memRedirect;
        io.branchOut.en <= (io.branchRedirect.en & branchOlder) | (io.branchRedirect.en & ~io.memRedirect.en);
        io.branchOut.taken <= io.branchInfo.taken;
        io.branchOut.target <= io.branchInfo.target;
        io.branchOut.br_type <= io.branchInfo.br_type;
        io.branchOut.ras_type <= io.branchInfo.ras_type;
    end
endmodule