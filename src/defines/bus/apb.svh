`ifndef __APB_SVH__
`define __APB_SVH__
`include "../global.svh"
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

interface ApbIO #(
    parameter ADDR_WIDTH=`PADDR_SIZE,
    parameter DATA_WIDTH=`XLEN
);
    logic `N(ADDR_WIDTH) paddr;   // same as AXI4-Lite
    logic [2: 0] pprot;   // same as AXI4-Lite, specification is the same
    logic  psel;    // each APB4 slave has its own single-bit psel
    logic  penable; // enable signal shows second APB4 cycle
    logic  pwrite;  // write enable
    logic `N(DATA_WIDTH) pwdata;  // write data, comes from W channel
    logic `N(DATA_WIDTH/8) pstrb;   // write strb, comes from W channel

    logic  pready;   // slave signals that it is ready
    /*verilator lint_off UNOPTFLAT*/
    logic `N(DATA_WIDTH) prdata;   // read data, connects to R channel
    logic  pslverr; 

    modport master (output paddr, pprot, psel, penable, pwrite, pwdata, pstrb, input pready, prdata, pslverr);
    modport slave  (input paddr, pprot, psel, penable, pwrite, pwdata, pstrb, output pready, prdata, pslverr);

endinterface

`define APB_REQ_ASSIGN(name, intf) \
    assign intf.paddr = name.paddr; \
    assign intf.pprot = name.pprot; \
    assign intf.penable = name.penable; \
    assign intf.pwrite = name.pwrite; \
    assign intf.pwdata = name.pwdata; \
    assign intf.pstrb = name.pstrb; \
    assign intf.psel = name.psel;

`define APB_RESP_ASSIGN(name, intf) \
    assign name.pready = intf.pready; \
    assign name.prdata = intf.prdata; \
    assign name.pslverr = intf.pslverr;
`endif