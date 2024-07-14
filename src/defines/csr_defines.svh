`ifndef CSR_DEFINES_SVH
`define CSR_DEFINES_SVH
`include "global.svh"

`define U_MODE 2'b00
`define S_MODE 2'b01
`define M_MODE 2'b11

`define CSR_NUM 26
`define CSRID_misa      12'h301
`define CSRID_mvendorid 12'hf11
`define CSRID_marchid   12'hf12
`define CSRID_mimpid    12'hf13
`define CSRID_mhartid   12'hf14
`define CSRID_mconfigptr 12'hf15
`define CSRID_mstatus   12'h300
`define CSRID_mtvec     12'h305
`define CSRID_medeleg   12'h302
`define CSRID_mideleg   12'h303
`define CSRID_mip       12'h344
`define CSRID_mie       12'h304
`define CSRID_mscratch  12'h340
`define CSRID_mepc      12'h341
`define CSRID_mcause    12'h342
`define CSRID_mtval     12'h343
`define CSRID_mstatush  12'h310
`define CSRID_medelegh  12'h312

`define CSRID_sstatus   12'h100
`define CSRID_stvec     12'h105
`define CSRID_sip       12'h144
`define CSRID_sie       12'h104
`define CSRID_sepc      12'h141
`define CSRID_scause    12'h142
`define CSRID_stval     12'h143
`define CSRID_satp      12'h180

typedef struct packed {
    logic `N(4) reserve0;
    logic v;
    logic u;
    logic reserve1;
    logic s;
    logic reserve2;
    logic q;
    logic p;
    logic reserve3;
    logic n;
    logic m;
    logic `N(3) reserve4;
    logic i;
    logic h;
    logic reserve5;
    logic f;
    logic e;
    logic d;
    logic c;
    logic b;
    logic a;
} Extensions;

typedef struct packed {
    logic `N(2) mxl;
    logic `N(`MXL-28) unuse;
    Extensions ext;
} ISA;
`define ISA_MASK {2'b11, {`MXL-28{1'b0}}, {4'h0, 2'h3, 1'b0, 1'b1, 1'b0, 2'h3, 1'b0, 2'h3, 3'b000, 2'h3, 1'b0, 6'h3f}}

`ifdef RV32I
`define MISA_INIT {2'b1, {`MXL-28{1'b0}}, 26'h80}
`endif

typedef struct packed {
    logic `N(25) bank;
    logic `N(7) offset;
} VENDORID;

typedef struct packed {
    logic sd;
    logic `N(6) unuse;
    logic sdt;
    logic spelp;
    logic tsr;
    logic tw;
    logic tvm;
    logic mxr;
    logic sum;
    logic mprv;
    logic `N(2) xs;
    logic `N(2) fs;
    logic `N(2) mpp;
    logic `N(2) vs;
    logic spp;
    logic mpie;
    logic ube;
    logic spie;
    logic unuse2;
    logic mie;
    logic unuse3;
    logic sie;
    logic unuse4;
} STATUS;

`define STATUS_MASK {1'b1, 7'h0, 19'h7fff, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}
`define SSTATUS_MASK {1'b1, 6'h0, 2'h3, 3'h0, 2'h3, 1'b0, 4'hf, 2'h0, 3'h7, 1'b0, 2'h3, 3'h0, 1'b1, 1'b0}

typedef struct packed {
    logic `N(21) unuse;
    logic mdt;
    logic mpelp;
    logic unuse2;
    logic mpv;
    logic gva;
    logic mbe;
    logic sbe;
    logic `N(4) unuse3;
} STATUSH;

`define STATUSH_MASK {21'b0, 2'b11, 1'b0, 4'hf, 4'b0}

typedef struct packed {
    logic `N(`MXL-2) base;
    logic `N(2) mode;
} TVEC;

`define TVEC_MASK {{`MXL-2{1'b1}}, 1'b0, 1'b1}

`define EPC_MASK {{`MXL-2{1'b1}}, 2'b00}

`define IP_MASK{{`MXL-14{1'b0}}, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}
`define SIP_MASK{{`MXL-14{1'b0}}, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 1'b0}

typedef struct packed {
    logic intr;
    logic `N(`MXL-1) excode;
} CAUSE;

`define CAUSE_MASK {1'b1, {`MXL-7{1'b0}}, 6'h3f}
`define MEDELEG_INIT {{`MXL-16{1'b0}}, 16'hb3ff}

typedef struct packed {
    logic mode;
    logic `N(`TLB_ASID) asid;
    logic `N(`TLB_PPN) ppn;
} SATP;
`endif