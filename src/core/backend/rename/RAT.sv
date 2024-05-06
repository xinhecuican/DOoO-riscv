`include "../../../defines/defines.svh"

// rename alias table
module RAT(
    input logic clk,
    input logic rst,
    RATIO.rat rat_io
);

    logic `N(`PREG_WIDTH) rat `N(5);

generate;
    for(genvar i=0; i<`RAT_PORT; i++)begin
        assign rat_io.preg[i] = rat[rat_io.vreg[i]];
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            rat <= '{default: 0};
        end
        else begin
        end
    end

endmodule