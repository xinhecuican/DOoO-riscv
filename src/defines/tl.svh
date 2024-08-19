`ifndef __TL_SVH__
`define __TL_SVH__
`include "global.svh"

`define TL_SIZE 3
`define TL_SOURCE 3
`define TL_SINK 3

// operation
`define TL_OP_WIDTH 3
`define TL_GET              `TL_OP_WIDTH'd4
`define TL_ACCESS_ACK_DATA  `TL_OP_WIDTH'd1
`define TL_PUT_FULL         `TL_OP_WIDTH'd0
`define TL_PUT_PARTIAL      `TL_OP_WIDTH'd1
`define TL_ACCESS_ACK       `TL_OP_WIDTH'd2
`define TL_ARITHMETIC       `TL_OP_WIDTH'd2
`define TL_LOGICAL          `TL_OP_WIDTH'd3
`define TL_INTENT           `TL_OP_WIDTH'd5
`define TL_HINT_ACK         `TL_OP_WIDTH'd2
`define TL_ACQUIRE          `TL_OP_WIDTH'd6
`define TL_GRANT            `TL_OP_WIDTH'd4
`define TL_GRANT_DATA       `TL_OP_WIDTH'd5
`define TL_GRANT_ACK        `TL_OP_WIDTH'd0
`define TL_PROBE            `TL_OP_WIDTH'd6
`define TL_PROBE_ACK        `TL_OP_WIDTH'd4
`define TL_PROBE_ACK_DATA   `TL_OP_WIDTH'd5
`define TL_RELEASE          `TL_OP_WIDTH'd6
`define TL_RELEASE_DATA     `TL_OP_WIDTH'd7
`define TL_RELEASE_ACK      `TL_OP_WIDTH'd6

typedef struct packed {
    logic [2: 0] op;
    logic [2: 0] param;
    logic `N(`TL_SIZE) size;
    logic `N(`TL_SOURCE) source;
    logic `N(`PADDR_SIZE) addr;
    logic `N(`DATA_BYTE) mask;
    logic `N(`XLEN) data;
    logic corrupt;
    logic valid;
} TLMA;

typedef struct packed {
    logic ready;
} TLSA;

typedef struct packed {
    logic ready;
} TLMD;

typedef struct packed {
    logic `N(3) op;
    logic `N(3) param;
    logic `N(`TL_SIZE) size;
    logic `N(`TL_SOURCE) source;
    logic `N(`TL_SINK) sink;
    logic `N(`XLEN) data;
    logic valid;
} TLSD;

`endif