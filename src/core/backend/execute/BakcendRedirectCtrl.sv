`include "../../../defines/defines.svh"

module BackendRedirectCtrl(
    input logic clk,
    input logic rst,
    BackendRedirectIO.redirect io
);
    logic branchOlder;
    RobIdx outIdx;
    LoopCompare #(`ROB_WIDTH) compare_rob (io.branchRedirect.robIdx, io.memRedirect.robIdx, branchOlder, outIdx);
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            io.out <= 0;
            io.branchOut <= 0;
        end
        else begin
            if(io.branchRedirect.en || io.memRedirect.en)begin
                io.out <= (io.branchRedirect.en & branchOlder) | (io.branchRedirect.en & ~io.memRedirect.en) ? io.branchRedirect : io.memRedirect;
            end
            else begin
                io.out <= 0;
            end
            if(io.branchRedirect.en)begin
                io.branchOut.en <= (io.branchRedirect.en & branchOlder) | (io.branchRedirect.en & ~io.memRedirect.en);
                io.branchOut.taken <= io.branchInfo.taken;
                io.branchOut.target <= io.branchInfo.target;
                io.branchOut.br_type <= io.branchInfo.br_type;
                io.branchOut.ras_type <= io.branchInfo.ras_type;
            end
            else begin
                io.branchOut <= 0;
            end
        end

    end
endmodule