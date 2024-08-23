`ifndef AXI_SVH
`define AXI_SVH
`include "global.svh"

// axi

`define AXI_ID_W 4
`define AXI_USER_W 1

`define AXI_RESP_OKAY 2'b00
`define AXI_RESP_EXOKAY 2'b01
`define AXI_RESP_SLVERR 2'b10
`define AXI_RESP_DECERR 2'b11

`define AXI_BURST_FIXED 2'b00
`define AXI_BURST_INCR  2'b01
`define AXI_BURST_WRAP  2'b10

`define AXI_CACHE_BUFFERABLE 4'b0001
`define AXI_CACHE_MODIFIABLE 4'b0010
`define AXI_CACHE_RD_ALLOC   4'b0100
`define AXI_CACHE_WR_ALLOC   4'b1000

`define AXI_ATOP_NONE 2'b00
`define AXI_ATOP_ATOMICSTORE 2'b01
`define AXI_ATOP_ATOMICLOAD 2'b10
`define AXI_ATOP_RRESP 6'd5

typedef struct packed {
    logic [`AXI_ID_W-1: 0] id;
    logic `PADDR_BUS addr;
    logic [7: 0] len;
    logic [2: 0] size;
    logic [1: 0] burst;
    logic lock;
    logic [3: 0] cache;
    logic [2: 0] prot;
    logic [3: 0] qos; // axi4
    logic [3: 0] region; // axi4
    logic `N(`AXI_USER_W) user; // axi4
} AxiMAR;

typedef struct packed {
    logic `PADDR_BUS addr;
    logic [2: 0] prot;
} AxiLMAR;

typedef struct packed {
    logic [`AXI_ID_W-1: 0] id;
    logic `N(`XLEN) data;
    logic [1 :0] resp;
    logic last;
    logic `N(`AXI_USER_W) user; // axi4
} AxiSR;

typedef struct packed {
    logic `N(`XLEN) data;
    logic [1 :0] resp;
} AxiLSR;

typedef struct packed {
    logic [`AXI_ID_W-1 :0] id;
    logic `PADDR_BUS addr;
    logic [7 :0] len;
    logic [2 :0] size;
    logic [1 :0] burst;
    logic lock;
    logic [3 :0] cache;
    logic [2 :0] prot;
    logic [3: 0] qos; // axi4
    logic [3: 0] region; // axi4
    logic `N(`AXI_USER_W) user; // axi4
    logic `N(6) atop; // axi5
} AxiMAW;

typedef struct packed {
    logic `PADDR_BUS addr;
    logic [2 :0] prot;
} AxiLMAW;

typedef struct packed {
    // logic [3 :0] id; // remove in axi4
    logic `N(`XLEN) data;
    logic [`XLEN/8-1 :0] strb;
    logic last;
    logic `N(`AXI_USER_W) user; // axi4
} AxiMW;

typedef struct packed {
    logic `N(`XLEN) data;
    logic [`XLEN/8-1 :0] strb;
} AxiLMW;

typedef struct packed {
    logic [`AXI_ID_W - 1 :0] id;
    logic [1 :0] resp;
    logic `N(`AXI_USER_W) user; // axi4
} AxiSB;

typedef struct packed {
    logic [1 :0] resp;
} AxiLSB;

interface AxiIO;
    logic ar_valid;
    logic ar_ready;
    logic aw_valid;
    logic aw_ready;
    logic r_valid;
    logic r_ready;
    logic w_valid;
    logic w_ready;
    logic b_valid;
    logic b_ready;
    AxiMAR mar;
    AxiSR sr;
    AxiMAW maw;
    AxiMW mw;
    AxiSB sb;

    modport master(
        output mar, maw, mw, ar_valid, aw_valid, w_valid, r_ready, b_ready,
        input sr, sb, ar_ready, aw_ready, w_ready, r_valid, b_valid
    );

    modport slave(
        input mar, maw, mw, ar_valid, aw_valid, w_valid, r_ready, b_ready,
        output sr, sb, ar_ready, aw_ready, w_ready, r_valid, b_valid
    );
endinterface

interface AxiLIO;
    logic ar_valid;
    logic ar_ready;
    logic aw_valid;
    logic aw_ready;
    logic r_valid;
    logic r_ready;
    logic w_valid;
    logic w_ready;
    logic b_valid;
    logic b_ready;
    AxiLMAR mar;
    AxiLSR sr;
    AxiLMAW maw;
    AxiLMW mw;
    AxiLSB sb;

    modport master(
        output mar, maw, mw, ar_valid, aw_valid, w_valid, r_ready, b_ready,
        input sr, sb, ar_ready, aw_ready, w_ready, r_valid, b_valid
    );

    modport slave(
        input mar, maw, mw, ar_valid, aw_valid, w_valid, r_ready, b_ready,
        output sr, sb, ar_ready, aw_ready, w_ready, r_valid, b_valid
    );
endinterface

typedef struct packed {
    AxiMAR ar;
    AxiMAW aw;
    AxiMW w;
    logic ar_valid;
    logic aw_valid;
    logic w_valid;
    logic r_ready;
    logic b_ready;
} AxiReq;

typedef struct packed {
    AxiSR r;
    AxiSB b;
    logic ar_ready;
    logic aw_ready;
    logic w_ready;
    logic r_valid;
    logic b_valid;
} AxiResp;

typedef struct packed {
    AxiLMAR ar;
    AxiLMAW aw;
    AxiLMW w;
    logic ar_valid;
    logic aw_valid;
    logic w_valid;
    logic r_ready;
    logic b_ready;
} AxiLReq;

typedef struct packed {
    AxiLSR r;
    AxiLSB b;
    logic ar_ready;
    logic aw_ready;
    logic w_ready;
    logic r_valid;
    logic b_valid;
} AxiLResp;

  /// Configuration for `axi_xbar`.
  typedef struct packed {
    /// Number of slave ports of the crossbar.
    /// This many master modules are connected to it.
    int unsigned   NoSlvPorts;
    /// Number of master ports of the crossbar.
    /// This many slave modules are connected to it.
    int unsigned   NoMstPorts;
    /// Maximum number of open transactions each master connected to the crossbar can have in
    /// flight at the same time.
    int unsigned   MaxMstTrans;
    /// Maximum number of open transactions each slave connected to the crossbar can have in
    /// flight at the same time.
    int unsigned   MaxSlvTrans;
    /// Determine if the internal FIFOs of the crossbar are instantiated in fallthrough mode.
    /// 0: No fallthrough
    /// 1: Fallthrough
    bit            FallThrough;
    /// The Latency mode of the xbar. This determines if the channels on the ports have
    /// a spill register instantiated.
    /// Example configurations are provided with the enum `xbar_latency_e`.
    bit [9:0]      LatencyMode;
    /// This is the number of `axi_multicut` stages instantiated in the line cross of the channels.
    /// Having multiple stages can potentially add a large number of FFs!
    int unsigned   PipelineStages;
    /// AXI ID width of the salve ports. The ID width of the master ports is determined
    /// Automatically. See `axi_mux` for details.
    int unsigned   AxiIdWidthSlvPorts;
    /// The used ID portion to determine if a different salve is used for the same ID.
    /// See `axi_demux` for details.
    int unsigned   AxiIdUsedSlvPorts;
    /// Are IDs unique?
    bit            UniqueIds;
    /// AXI4+ATOP address field width.
    int unsigned   AxiAddrWidth;
    /// AXI4+ATOP data field width.
    int unsigned   AxiDataWidth;
    /// The number of address rules defined for routing of the transactions.
    /// Each master port can have multiple rules, should have however at least one.
    /// If a transaction can not be routed the xbar will answer with an `axi_pkg::RESP_DECERR`.
    int unsigned   NoAddrRules;
  } xbar_cfg_t;

`define AXI_REQ_ASSIGN(name, intf) \
    assign name.ar = intf.mar; \
    assign name.aw = intf.maw; \
    assign name.w = intf.mw; \
    assign name.ar_valid = intf.ar_valid; \
    assign name.aw_valid = intf.aw_valid; \
    assign name.w_valid = intf.w_valid; \
    assign name.r_ready = intf.r_ready; \
    assign name.b_ready = intf.b_ready;

`define AXI_REQ_RECEIVE(name, intf) \
    assign intf.mar = name.ar; \
    assign intf.maw = name.aw; \
    assign intf.mw = name.w; \
    assign intf.ar_valid = name.ar_valid; \
    assign intf.aw_valid = name.aw_valid; \
    assign intf.w_valid = name.w_valid; \
    assign intf.r_ready = name.r_ready; \
    assign intf.b_ready = name.b_ready;

`define AXI_RESP_ASSIGN(name, intf) \
    assign intf.sr = name.r; \
    assign intf.sb = name.b; \
    assign intf.ar_ready = name.ar_ready; \
    assign intf.aw_ready = name.aw_ready; \
    assign intf.w_ready = name.w_ready; \
    assign intf.r_valid = name.r_valid; \
    assign intf.b_valid = name.b_valid;

`define AXI_RESP_RECEIVE(name, intf) \
    assign name.r = intf.sr; \
    assign name.b = intf.sb; \
    assign name.ar_ready = intf.ar_ready; \
    assign name.aw_ready = intf.aw_ready; \
    assign name.w_ready = intf.w_ready; \
    assign name.r_valid = intf.r_valid; \
    assign name.b_valid = intf.b_valid;

`define AXI_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)  \
  typedef struct packed {                                       \
    id_t              id;                                       \
    addr_t            addr;                                     \
    logic [7: 0]    len;                                      \
    logic [2: 0]   size;                                     \
    logic [1: 0]  burst;                                    \
    logic             lock;                                     \
    logic [3: 0]  cache;                                    \
    logic [2: 0]   prot;                                     \
    logic [3: 0]    qos;                                      \
    logic [3: 0] region;                                   \
    logic [5: 0]   atop;                                     \
    user_t            user;                                     \
  } aw_chan_t;
`define AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)  \
  typedef struct packed {                                       \
    data_t data;                                                \
    strb_t strb;                                                \
    logic  last;                                                \
    user_t user;                                                \
  } w_chan_t;
`define AXI_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)  \
  typedef struct packed {                             \
    id_t            id;                               \
    logic [1: 0] resp;                             \
    user_t          user;                             \
  } b_chan_t;
`define AXI_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)  \
  typedef struct packed {                                       \
    id_t              id;                                       \
    addr_t            addr;                                     \
    logic [7: 0]    len;                                      \
    logic [2: 0]   size;                                     \
    logic [1: 0]  burst;                                    \
    logic             lock;                                     \
    logic [3: 0]  cache;                                    \
    logic [2: 0]   prot;                                     \
    logic [3: 0]    qos;                                      \
    logic [3: 0] region;                                   \
    user_t            user;                                     \
  } ar_chan_t;
`define AXI_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)  \
  typedef struct packed {                                     \
    id_t            id;                                       \
    data_t          data;                                     \
    logic [1: 0] resp;                                     \
    logic           last;                                     \
    user_t          user;                                     \
  } r_chan_t;
`define AXI_TYPEDEF_REQ_T(req_t, aw_chan_t, w_chan_t, ar_chan_t)  \
  typedef struct packed {                                         \
    aw_chan_t aw;                                                 \
    logic     aw_valid;                                           \
    w_chan_t  w;                                                  \
    logic     w_valid;                                            \
    logic     b_ready;                                            \
    ar_chan_t ar;                                                 \
    logic     ar_valid;                                           \
    logic     r_ready;                                            \
  } req_t;
`define AXI_TYPEDEF_RESP_T(resp_t, b_chan_t, r_chan_t)  \
  typedef struct packed {                               \
    logic     aw_ready;                                 \
    logic     ar_ready;                                 \
    logic     w_ready;                                  \
    logic     b_valid;                                  \
    b_chan_t  b;                                        \
    logic     r_valid;                                  \
    r_chan_t  r;                                        \
  } resp_t;

`define __AXI_TO_AW(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)   \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``addr   = __rhs``__rhs_sep``addr;       \
  __opt_as __lhs``__lhs_sep``len    = __rhs``__rhs_sep``len;        \
  __opt_as __lhs``__lhs_sep``size   = __rhs``__rhs_sep``size;       \
  __opt_as __lhs``__lhs_sep``burst  = __rhs``__rhs_sep``burst;      \
  __opt_as __lhs``__lhs_sep``lock   = __rhs``__rhs_sep``lock;       \
  __opt_as __lhs``__lhs_sep``cache  = __rhs``__rhs_sep``cache;      \
  __opt_as __lhs``__lhs_sep``prot   = __rhs``__rhs_sep``prot;       \
  __opt_as __lhs``__lhs_sep``qos    = __rhs``__rhs_sep``qos;        \
  __opt_as __lhs``__lhs_sep``region = __rhs``__rhs_sep``region;     \
  __opt_as __lhs``__lhs_sep``atop   = __rhs``__rhs_sep``atop;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __AXI_TO_W(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``data   = __rhs``__rhs_sep``data;       \
  __opt_as __lhs``__lhs_sep``strb   = __rhs``__rhs_sep``strb;       \
  __opt_as __lhs``__lhs_sep``last   = __rhs``__rhs_sep``last;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __AXI_TO_B(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``resp   = __rhs``__rhs_sep``resp;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __AXI_TO_AR(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)   \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``addr   = __rhs``__rhs_sep``addr;       \
  __opt_as __lhs``__lhs_sep``len    = __rhs``__rhs_sep``len;        \
  __opt_as __lhs``__lhs_sep``size   = __rhs``__rhs_sep``size;       \
  __opt_as __lhs``__lhs_sep``burst  = __rhs``__rhs_sep``burst;      \
  __opt_as __lhs``__lhs_sep``lock   = __rhs``__rhs_sep``lock;       \
  __opt_as __lhs``__lhs_sep``cache  = __rhs``__rhs_sep``cache;      \
  __opt_as __lhs``__lhs_sep``prot   = __rhs``__rhs_sep``prot;       \
  __opt_as __lhs``__lhs_sep``qos    = __rhs``__rhs_sep``qos;        \
  __opt_as __lhs``__lhs_sep``region = __rhs``__rhs_sep``region;     \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __AXI_TO_R(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``data   = __rhs``__rhs_sep``data;       \
  __opt_as __lhs``__lhs_sep``resp   = __rhs``__rhs_sep``resp;       \
  __opt_as __lhs``__lhs_sep``last   = __rhs``__rhs_sep``last;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __AXI_TO_REQ(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)  \
  `__AXI_TO_AW(__opt_as, __lhs.aw, __lhs_sep, __rhs.aw, __rhs_sep)  \
  __opt_as __lhs.aw_valid = __rhs.aw_valid;                         \
  `__AXI_TO_W(__opt_as, __lhs.w, __lhs_sep, __rhs.w, __rhs_sep)     \
  __opt_as __lhs.w_valid = __rhs.w_valid;                           \
  __opt_as __lhs.b_ready = __rhs.b_ready;                           \
  `__AXI_TO_AR(__opt_as, __lhs.ar, __lhs_sep, __rhs.ar, __rhs_sep)  \
  __opt_as __lhs.ar_valid = __rhs.ar_valid;                         \
  __opt_as __lhs.r_ready = __rhs.r_ready;
`define __AXI_TO_RESP(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep) \
  __opt_as __lhs.aw_ready = __rhs.aw_ready;                         \
  __opt_as __lhs.ar_ready = __rhs.ar_ready;                         \
  __opt_as __lhs.w_ready = __rhs.w_ready;                           \
  __opt_as __lhs.b_valid = __rhs.b_valid;                           \
  `__AXI_TO_B(__opt_as, __lhs.b, __lhs_sep, __rhs.b, __rhs_sep)     \
  __opt_as __lhs.r_valid = __rhs.r_valid;                           \
  `__AXI_TO_R(__opt_as, __lhs.r, __lhs_sep, __rhs.r, __rhs_sep)

`define __AXI_TO_REQ(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)  \
  `__AXI_TO_AW(__opt_as, __lhs.aw, __lhs_sep, __rhs.aw, __rhs_sep)  \
  __opt_as __lhs.aw_valid = __rhs.aw_valid;                         \
  `__AXI_TO_W(__opt_as, __lhs.w, __lhs_sep, __rhs.w, __rhs_sep)     \
  __opt_as __lhs.w_valid = __rhs.w_valid;                           \
  __opt_as __lhs.b_ready = __rhs.b_ready;                           \
  `__AXI_TO_AR(__opt_as, __lhs.ar, __lhs_sep, __rhs.ar, __rhs_sep)  \
  __opt_as __lhs.ar_valid = __rhs.ar_valid;                         \
  __opt_as __lhs.r_ready = __rhs.r_ready;

`define __AXI_TO_RESP(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep) \
  __opt_as __lhs.aw_ready = __rhs.aw_ready;                         \
  __opt_as __lhs.ar_ready = __rhs.ar_ready;                         \
  __opt_as __lhs.w_ready = __rhs.w_ready;                           \
  __opt_as __lhs.b_valid = __rhs.b_valid;                           \
  `__AXI_TO_B(__opt_as, __lhs.b, __lhs_sep, __rhs.b, __rhs_sep)     \
  __opt_as __lhs.r_valid = __rhs.r_valid;                           \
  `__AXI_TO_R(__opt_as, __lhs.r, __lhs_sep, __rhs.r, __rhs_sep)

`define AXI_SET_AW_STRUCT(lhs, rhs)     `__AXI_TO_AW(, lhs, ., rhs, .)
`define AXI_SET_W_STRUCT(lhs, rhs)       `__AXI_TO_W(, lhs, ., rhs, .)
`define AXI_SET_B_STRUCT(lhs, rhs)       `__AXI_TO_B(, lhs, ., rhs, .)
`define AXI_SET_AR_STRUCT(lhs, rhs)     `__AXI_TO_AR(, lhs, ., rhs, .)
`define AXI_SET_R_STRUCT(lhs, rhs)       `__AXI_TO_R(, lhs, ., rhs, .)
`define AXI_ASSIGN_REQ_STRUCT(lhs, rhs)   `__AXI_TO_REQ(assign, lhs, ., rhs, .)
`define AXI_ASSIGN_RESP_STRUCT(lhs, rhs) `__AXI_TO_RESP(assign, lhs, ., rhs, .)

    /// Index width required to be able to represent up to `num_idx` indices as a binary
    /// encoded signal.
    /// Ensures that the minimum width if an index signal is `1`, regardless of parametrization.
    ///
    /// Sample usage in type definition:
    /// As parameter:
    ///   `parameter type idx_t = logic[cf_math_pkg::idx_width(NumIdx)-1:0]`
    /// As typedef:
    ///   `typedef logic [cf_math_pkg::idx_width(NumIdx)-1:0] idx_t`
    function automatic integer unsigned idx_width (input integer unsigned num_idx);
        return (num_idx > 32'd1) ? unsigned'($clog2(num_idx)) : 32'd1;
    endfunction
`endif