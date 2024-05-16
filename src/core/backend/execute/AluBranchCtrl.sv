`include "../../../defines/defines.svh"

// control branch result
// generator oldest predict error instr and send to frontend

interface AluBranchCtrlIO;
    FsqIdxInfo `N(`ALU_SIZE) fsqInfo;
    logic `N(`ALU_SIZE) pred_error;
    logic `ARRAY(`ALU_SIZE, `VADDR_SIZE) target;
endinterface

module AluBranchCtrl(

);

endmodule