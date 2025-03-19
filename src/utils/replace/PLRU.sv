`include "../../defines/defines.svh"

// only support 4-way
module PLRU#(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter READ_PORT = 1,
    parameter WAY_WIDTH = idxWidth(WAY_NUM),
    parameter ADDR_WIDTH = idxWidth(DEPTH)
)(
    input logic clk,
    input logic rst,
    ReplaceIO.replace replace_io
);
generate
    if(WAY_NUM == 1)begin
        assign replace_io.miss_way = 1;
    end
    else begin 
        logic `N((WAY_NUM - 1)) plru `N(DEPTH);
        logic `N(WAY_NUM-1) rdata `N(READ_PORT);
        logic `N(WAY_NUM-1) updateData `N(READ_PORT);


        for(genvar i=0; i<READ_PORT; i++)begin
            assign rdata[i] = plru[replace_io.hit_index[i]];
            PLRUUpdate #(WAY_NUM) update (replace_io.hit_invalid[i], rdata[i], replace_io.hit_way[i], updateData[i]);
        end


        logic `N(WAY_NUM) replaceOut;
        PLRUReplace #(WAY_NUM) replace (plru[replace_io.miss_index], replaceOut);
        always_ff @(posedge clk)begin
            replace_io.miss_way <= replaceOut;
        end

        always_ff @(posedge clk or posedge rst)begin
            if(rst == `RST)begin
                plru <= '{default: 0};
            end
            else begin
                for(int i=0; i<READ_PORT; i++)begin
                    if(replace_io.hit_en[i])begin
                        plru[replace_io.hit_index[i]] <= updateData[i];
                    end
                end
            end
        end
    end
endgenerate


endmodule

module PLRUUpdate #(
    parameter WAY_NUM = 1,
    parameter WAY_WIDTH = idxWidth(WAY_NUM)
)(
    input logic invalid,
    input logic `N(WAY_NUM-1) rdata,
    input logic `N(WAY_NUM) hit_way,
    output logic `N(WAY_NUM-1) out
);
    always_comb begin
        automatic int unsigned idx_base, shift;
        automatic logic new_index;
        idx_base    = 0;
        shift       = 0;
        new_index   = 1'b0;
        out = rdata;

        for (int unsigned i = 0; i < WAY_NUM; i++) begin
            // we got a hit so update the pointer as it was least recently used
            if (hit_way[i]) begin
                // Set the nodes to the values we would expect
                for (int unsigned lvl = 0; lvl < WAY_WIDTH; lvl++) begin

                    idx_base = $unsigned((2**lvl)-1);
                    // lvl0 <=> MSB, lvl1 <=> MSB-1, ...
                    shift = WAY_WIDTH - lvl;
                    // to circumvent the 32 bit integer arithmetic assignment
                    new_index = 1'(~(i >> (shift-1))) ^ invalid;
                    out[idx_base + (i >> shift)] = new_index;
                end
            end
        end
    end
endmodule

module PLRUReplace #(
    parameter WAY_NUM = 1,
    parameter WAY_WIDTH = idxWidth(WAY_NUM)
)(
    input logic `N(WAY_NUM-1) rdata,
    output logic `N(WAY_NUM) out
);
    always_comb begin : plru_output
        automatic int unsigned idx_base, shift;
        automatic logic new_index;
        idx_base  = 0;
        shift     = 0;
        new_index = 1'b0;
        out = '1;
        // Decode tree to write enable signals
        // Next for-loop basically creates the following logic for e.g. an 8 entry
        // TLB (note: pseudo-code obviously):
        // plru_o[7] = &plru_tree_q[ 6, 2, 0]; //plru_tree_q[0,2,6]=={1,1,1}
        // plru_o[6] = &plru_tree_q[~6, 2, 0]; //plru_tree_q[0,2,6]=={1,1,0}
        // plru_o[5] = &plru_tree_q[ 5,~2, 0]; //plru_tree_q[0,2,5]=={1,0,1}
        // plru_o[4] = &plru_tree_q[~5,~2, 0]; //plru_tree_q[0,2,5]=={1,0,0}
        // plru_o[3] = &plru_tree_q[ 4, 1,~0]; //plru_tree_q[0,1,4]=={0,1,1}
        // plru_o[2] = &plru_tree_q[~4, 1,~0]; //plru_tree_q[0,1,4]=={0,1,0}
        // plru_o[1] = &plru_tree_q[ 3,~1,~0]; //plru_tree_q[0,1,3]=={0,0,1}
        // plru_o[0] = &plru_tree_q[~3,~1,~0]; //plru_tree_q[0,1,3]=={0,0,0}
        // For each entry traverse the tree. If every tree-node matches,
        // the corresponding bit of the entry's index, this is
        // the next entry to replace.
        for (int unsigned i = 0; i < WAY_NUM; i += 1) begin
            for (int unsigned lvl = 0; lvl < WAY_WIDTH; lvl++) begin
                idx_base = $unsigned((2**lvl)-1); // 0 1 3
                // lvl0 <=> MSB, lvl1 <=> MSB-1, ...
                shift = WAY_WIDTH - lvl;
                // plru_o[i] &= plru_tree_q[idx_base + (i>>shift)] == ((i >> (shift-1)) & 1'b1);
                new_index = 1'(i >> (shift-1));
                if (new_index) begin
                  out[i] &= rdata[idx_base + (i>>shift)];
                end else begin
                  out[i] &= ~rdata[idx_base + (i>>shift)];
                end
            end
        end
    end
endmodule