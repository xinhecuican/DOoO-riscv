`include "../../../defines/defines.svh"

module DirectionSelectorModel #(
	parameter DEPTH=8,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
	input logic [DEPTH-1: 0] ready,
	input logic [DEPTH-1: 0][ADDR_WIDTH-1: 0] index,
	input logic [DEPTH-1: 0] direction,
	output logic [DEPTH-1: 0] select
);
	logic [DEPTH-1: 0][DEPTH-1: 0] bigger;
generate
    for(genvar i=0; i<DEPTH; i++)begin
        for(genvar j=i+1; j<DEPTH; j++)begin
            // i older than j
            assign bigger[i][j] = ((direction[i] ^ direction[j]) ^ (index[i] < index[j]));
        end
    end

    for(genvar i=0; i<DEPTH; i++)begin
        assign select[i] = ready[i];
        for(genvar j=0; j<DEPTH; j++)begin
            if(i < j)begin
                assign select[i] = select[i] & ((~ready[j]) | ready[j] & bigger[i][j]);
            end
            else if(i > j)begin
                assign select[i] = select[i] & ((~ready[j]) | ready[j] & ~bigger[j][i]);
            end
        end
    end
endgenerate
endmodule

// 1 0 0 0  1 1 1 1  1 0 1 1  1 0 0 1
// 0 1 0 0  0 0 0 0  1 1 1 1  1 1 0 1
// 0 0 1 0  0 0 0 0  0 0 1 0  1 1 1 1
// 0 0 0 1  0 0 0 0  0 0 0 1  0 0 0 1
// ready [1, 1, 0, 0]
// if ready[i] & ~ready[j] -> ready[i][j] = 1
// if ~ready[i] -> ready[i][] = 0
// 1 0 1 1
// 1 1 1 1
// 0 0 0 0
// 0 0 0 0
module DirectionSelector #(
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic [DEPTH-1: 0] idx,
    input logic [DEPTH-1: 0] ready,
    output logic [DEPTH-1: 0] select
);
    logic [DEPTH-1: 0][DEPTH-1: 0] bigger, bigger_mask;

generate
    for(genvar i=0; i<DEPTH; i++)begin
        for(genvar j=0; j<DEPTH; j++)begin
            assign bigger_mask[i][j] = (bigger[i][j] | (~ready[j])) & ready[i];
        end
        assign select[i] = &bigger_mask[i];
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            bigger <= 0;
        end
        else begin
            if(en)begin
                for(int i=0; i<DEPTH; i++)begin
                    for(int j=0; j<DEPTH; j++)begin
                        bigger[i][j] <= (bigger[i][j] & ~(idx[j])) | (idx[i]);
                    end
                end
            end
        end
    end

endmodule