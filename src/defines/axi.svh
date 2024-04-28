`ifndef AXI_SVH
`define AXI_SVH
`include "global.svh"

// axi

typedef struct packed {
    logic [3: 0] id;
    logic `PADDR_BUS addr;
    logic [7: 0] len;
    logic [2: 0] size;
    logic [1: 0] burst;
    logic [1: 0] lock;
    logic [3: 0] cache;
    logic [2: 0] prot;
    logic valid;
    logic [3: 0] qos; // axi4
    logic [3: 0] region; // axi4
    logic user; // axi4
} AxiMAR;

typedef struct packed {
    logic ready;
} AxiSAR;

typedef struct packed {
    logic [3 :0] id;
    logic `N(`XLEN) data;
    logic [1 :0] resp;
    logic last;
    logic valid;
    logic user; // axi4
} AxiSR;

typedef struct packed {
    logic ready;
} AxiMR;

typedef struct packed {
    logic [3 :0] id;
    logic `PADDR_BUS addr;
    logic [7 :0] len;
    logic [2 :0] size;
    logic [1 :0] burst;
    logic [1 :0] lock;
    logic [3 :0] cache;
    logic [2 :0] prot;
    logic valid;
    logic [3: 0] qos; // axi4
    logic [3: 0] region; // axi4
    logic user; // axi4
} AxiMAW;

typedef struct packed {
    logic ready;
} AxiSAW;

typedef struct packed {
    // logic [3 :0] id; // remove in axi4
    logic `N(`XLEN) data;
    logic [7 :0] wstrb;
    logic last;
    logic valid;
    logic user; // axi4
} AxiMW;

typedef struct packed {
    logic ready;
} AxiSW;

typedef struct packed {
    logic ready;
} AxiMB;

typedef struct packed {
    logic [3 :0] id;
    logic [1 :0] resp;
    logic valid;
    logic user; // axi4
} AxiSB;

interface AxiIO;
    AxiMAR mar;
    AxiSAR sar;
    AxiMR mr;
    AxiSR sr;
    AxiMAW maw;
    AxiSAW saw;
    AxiMW mw;
    AxiSW sw;
    AxiMB mb;
    AxiSB sb;

    modport master(
        output mar, mr, maw, mw, mb,
        input sar, sr, saw, sw, sb
    );

    modport slave(
        input mar, mr, maw, mw, mb,
        output sar, sr, saw, sw, sb
    );
endinterface
`endif