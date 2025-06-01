`ifndef __FUNCTIONS_SVH__
`define __FUNCTIONS_SVH__
`include "bundles.svh"

function automatic rasValid(BranchType br_type);
    return br_type == POP || br_type == POP_PUSH || 
            br_type == PUSH || br_type == INDIRECT_CALL;
endfunction

function automatic logic[1: 0] getRasType(BranchType br_type);
    getRasType[0] = br_type == POP || br_type == POP_PUSH;
    getRasType[1] = br_type == PUSH || br_type == INDIRECT_CALL || br_type == POP_PUSH;
endfunction

function automatic logic[`SSIT_WIDTH-1: 0] ssitFoldPC(logic [`VADDR_SIZE-1: 0] pc);
    ssitFoldPC = pc[`INST_OFFSET +: `SSIT_WIDTH] ^  pc[`INST_OFFSET + `SSIT_WIDTH +: `SSIT_WIDTH];
endfunction
`endif