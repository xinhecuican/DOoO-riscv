`ifndef __APB_SVH__
`define __APB_SVH__
`include "global.svh"
typedef struct packed {
    logic `N(`PADDR_SIZE) paddr;   // same as AXI4-Lite
    logic [2: 0] pprot;   // same as AXI4-Lite, specification is the same
    logic  psel;    // each APB4 slave has its own single-bit psel
    logic  penable; // enable signal shows second APB4 cycle
    logic  pwrite;  // write enable
    logic `N(`XLEN) pwdata;  // write data, comes from W channel
    logic `N(`XLEN/8) pstrb;   // write strb, comes from W channel
} ApbReq;

typedef struct packed {
    logic  pready;   // slave signals that it is ready
    logic `N(`XLEN) prdata;   // read data, connects to R channel
    logic  pslverr; 
} ApbResp;

interface ApbIO;
    ApbReq req;
    ApbResp resp;

    modport master (output req, input resp);
    modport slave  (input req, output resp);

endinterface

`endif