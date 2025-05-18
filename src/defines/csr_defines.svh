`ifndef CSR_DEFINES_SVH
`define CSR_DEFINES_SVH
`include "global.svh"

`define U_MODE 2'b00
`define S_MODE 2'b01
`define M_MODE 2'b11

`define PMA_SIZE 2
`define PMP_SIZE 16
`ifdef RV32I
`define PMACFG_SIZE (`PMA_SIZE < 4 ? 1 : `PMA_SIZE / 4)
`define PMPCFG_SIZE (`PMP_SIZE / 4)
`endif
`ifdef RV64I
`define PMACFG_SIZE (`PMA_SIZE < 8 ? 1 : `PMA_SIZE / 8)
`define PMPCFG_SIZE (`PMP_SIZE / 8)
`endif
`define CSR_GROUP_SIZE (3 \
`ifdef RV32I \
    + 1 \
`endif \
)

`define CSR_NORMAL_NUM 30
`define CSR_NUM (`CSR_NORMAL_NUM \
`ifdef RV32I \
    + 3 \
`endif \
`ifdef RVF \
    +3 \
`endif \
)

`define CSRID_mstatus   12'h300
`define CSRID_misa      12'h301
`define CSRID_medeleg   12'h302
`define CSRID_mideleg   12'h303
`define CSRID_mie       12'h304
`define CSRID_mtvec     12'h305
`define CSRID_mcounteren 12'h306
`define CSRID_menvcfg   12'h30a
`define CSRID_mstatush  12'h310
`define CSRID_medelegh  12'h312
`define CSRID_menvcfgh  12'h31a
`define CSRID_mcounterinhibit 12'h320
`define CSRID_mscratch  12'h340
`define CSRID_mepc      12'h341
`define CSRID_mcause    12'h342
`define CSRID_mtval     12'h343
`define CSRID_mip       12'h344
`define CSRID_mcycle    12'hb00
`define CSRID_minstret  12'hb02
`define CSRID_mcycleh   12'hb80
`define CSRID_minstreth 12'hb82
`define CSRID_mvendorid 12'hf11
`define CSRID_marchid   12'hf12
`define CSRID_mimpid    12'hf13
`define CSRID_mhartid   12'hf14
`define CSRID_mconfigptr 12'hf15
`define CSRID_pmpcfg    12'h3a0
`define CSRID_pmpaddr   12'h3b0
`define CSRID_pmacfg    12'h3d0
`define CSRID_pmaaddr   12'h3e0

`define CSRID_sstatus   12'h100
`define CSRID_stvec     12'h105
`define CSRID_scounteren 12'h106
`define CSRID_senvcfg   12'h10a
`define CSRID_sip       12'h144
`define CSRID_sie       12'h104
`define CSRID_sscratch  12'h140
`define CSRID_sepc      12'h141
`define CSRID_scause    12'h142
`define CSRID_stval     12'h143
`define CSRID_satp      12'h180

`define CSRID_fflags    12'h001
`define CSRID_frm       12'h002
`define CSRID_fcsr      12'h003


`define CSRGROUP_mpf        0
`define CSRGROUP_pmpcfg     1
`define CSRGROUP_pmpaddr    2
`define CSRGROUP_mpfh       3    

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
`define MARCH_INIT 32'h34

`define MISA_INIT '{ \
`ifdef RV32I \
    mxl: 2'b1,  \
`endif \
`ifdef RV64I \
    mxl: 2'b10, \
`endif \
    ext: '{ \
`ifdef RVM \
        m: 1'b1, \
`endif \
`ifdef RVA \
        a: 1'b1, \
`endif \
`ifdef RVF \
        f: 1'b1, \
`endif \
`ifdef RVD \
        d: 1'b1, \
`endif \
`ifdef RVC \
        c: 1'b1, \
`endif \
        i: 1'b1, \
        s: 1'b1, \
        u: 1'b1, \
        default: 0 \
    }, \
    default: 0 \
}

typedef struct packed {
    logic `N(25) bank;
    logic `N(7) offset;
} VENDORID;

typedef struct packed {
`ifdef RV64I
    logic sd;
    logic `N(20) unuse;
    logic mdt;
    logic mpelp;
    logic unuse1;
    logic mpv;
    logic gva;
    logic mbe;
    logic sbe;
    logic [1: 0] sxl;
    logic [1: 0] uxl;
    logic `N(7) unuse1_2;
`endif
`ifdef RV32I
    logic sd;
    logic `N(6) unuse;
`endif
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

`ifdef RV64I
`define STATUS_MASK {1'b1, 20'h0, 11'hff, 8'h0, 19'h7fff, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}
`define SSTATUS_MASK {1'b1, 29'h0, 2'h3, 12'h0, 2'h3, 1'h0, 4'hf, 2'h0, 3'h7, 1'h0, 2'h3, 3'h0, 1'h1, 1'h0}
`else
`define STATUS_MASK {1'b1, 7'h0, 19'h7fff, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}
`define SSTATUS_MASK {1'b1, 6'h0, 2'h3, 3'h0, 2'h3, 1'b0, 4'hf, 2'h0, 3'h7, 1'b0, 2'h3, 3'h0, 1'b1, 1'b0}
`endif

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

`define EPC_MASK {{`MXL-`INST_OFFSET{1'b1}}, {`INST_OFFSET{1'b0}}}

`define IP_MASK{{`MXL-14{1'b0}}, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0}
`define SIP_MASK{{`MXL-14{1'b0}}, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 3'b0, 1'b1, 1'b0}

typedef struct packed {
    logic intr;
    logic `N(`MXL-1) excode;
} CAUSE;

`define CAUSE_MASK {1'b1, {`MXL-7{1'b0}}, 6'h3f}
`define MEDELEG_INIT {{`MXL-16{1'b0}}, 16'hb3ff}
`define MEDELEG_MASK {{`MXL-16{1'b0}}, 16'hb3ff}
`define COUNTEREN_MASK 'h7

typedef struct packed {
`ifdef RV32I
    logic mode;
    logic `N(9) asid;
    logic `N(22) ppn;
`else
    logic `N(4) mode;
    logic `N(16) asid;
    logic `N(44) ppn;
`endif

} SATP;

typedef struct packed {
    logic `N(`MXL-16) unuse1;
    logic `N(2) unuse2;
    logic lcofip;
    logic unuse3;
    logic meip;
    logic unuse4;
    logic seip;
    logic unuse5;
    logic mtip;
    logic unuse6;
    logic stip;
    logic unuse7;
    logic msip;
    logic unuse8;
    logic ssip;
    logic unuse9;
} IP;

typedef struct packed {
    logic stce;
    logic pbmte;
    logic adue;
    logic dte;
    logic [24: 0] unuse1;
    logic [1: 0] pmm;
    logic [23: 0] unuse2;
    logic cbze;
    logic cbcfe;
    logic cbie;
    logic sse;
    logic lpe;
    logic unuse3;
    logic fiom;
} MENVCFG;

`define PMP_OFF     2'b00
`define PMP_TOR     2'b01
`define PMP_NA4     2'b10
`define PMP_NAPOT   2'b11
`ifdef RV32I
`define PMP_MASK    32'hfffffc00
`endif
`ifdef RV64I
`define PMP_MASK    64'hfffffffffffffc00
`endif
`define PMP_NAPOT_MASK ((~(`PMP_MASK)) >> 1)

typedef struct packed {
    logic l;
    logic [1: 0] unuse1;
    logic [1: 0] a;
    logic x;
    logic w;
    logic r;
} PMPCfg;

typedef struct packed {
    logic [1: 0] unuse1;
    logic uc; // uncache
    logic [1: 0] a;
    logic [2: 0] unuse2;
} PMACfg;

// same as pmpaddr, address[33: 2]
`define PMA_ASSIGN \
    logic `ARRAY(`PMACFG_SIZE, `MXL) pmacfg; \
    logic `ARRAY(`PMA_SIZE, `MXL) pmaaddr; \
    assign pmacfg[0] = 'h2808; \
    assign pmaaddr[0] = 'h01000000; \
    assign pmaaddr[1] = 'h08000000;

`endif