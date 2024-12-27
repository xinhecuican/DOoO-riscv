`ifndef __FUNCTIONS_SVH__
`define __FUNCTIONS_SVH__
`include "bundles.svh"

function automatic integer idxWidth(input integer num_idx);
    return (num_idx > 32'd1) ?$clog2(num_idx) : 32'd1;
endfunction

function rasValid(BranchType br_type);
    return br_type == POP || br_type == POP_PUSH || 
            br_type == PUSH || br_type == INDIRECT_CALL;
endfunction

function logic[1: 0] getRasType(BranchType br_type);
    getRasType[0] = br_type == POP || br_type == POP_PUSH;
    getRasType[1] = br_type == PUSH || br_type == INDIRECT_CALL || br_type == POP_PUSH;
endfunction

`endif