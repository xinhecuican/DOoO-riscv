`ifndef __ACE_SVH__
`define __ACE_SVH__

interface AceIO #(
    parameter int AXI_ADDR_WIDTH = 0,
    parameter int AXI_DATA_WIDTH = 0,
    parameter int AXI_ID_WIDTH   = 0,
    parameter int AXI_USER_WIDTH = 0
);

    localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

    typedef logic [AXI_ID_WIDTH-1:0] id_t;
    typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
    typedef logic [AXI_DATA_WIDTH-1:0] data_t;
    typedef logic [AXI_STRB_WIDTH-1:0] strb_t;
    typedef logic [AXI_USER_WIDTH-1:0] user_t;

    id_t         aw_id;
    addr_t       aw_addr;
    logic  [7:0] aw_len;
    logic  [2:0] aw_size;
    logic  [1:0] aw_burst;
    logic        aw_lock;
    logic  [3:0] aw_cache;
    logic  [2:0] aw_prot;
    logic  [3:0] aw_qos;
    logic  [3:0] aw_region;
    logic  [5:0] aw_atop;
    user_t       aw_user;
    logic        aw_valid;
    logic        aw_ready;
    logic  [2:0] aw_snoop;
    logic  [1:0] aw_domain;
    logic  [1:0] aw_bar;
    logic        aw_awunique;

    data_t       w_data;
    strb_t       w_strb;
    logic        w_last;
    user_t       w_user;
    logic        w_valid;
    logic        w_ready;

    id_t         b_id;
    logic  [1:0] b_resp;
    user_t       b_user;
    logic        b_valid;
    logic        b_ready;

    id_t         ar_id;
    addr_t       ar_addr;
    logic  [7:0] ar_len;
    logic  [2:0] ar_size;
    logic  [1:0] ar_burst;
    logic        ar_lock;
    logic  [3:0] ar_cache;
    logic  [2:0] ar_prot;
    logic  [3:0] ar_qos;
    logic  [3:0] ar_region;
    user_t       ar_user;
    logic        ar_valid;
    logic        ar_ready;
    logic  [3:0] ar_snoop;
    logic  [1:0] ar_domain;
    logic  [1:0] ar_bar;

    id_t         r_id;
    data_t       r_data;
    logic  [3:0] r_resp;
    logic        r_last;
    user_t       r_user;
    logic        r_valid;
    logic        r_ready;

    logic rack, wack;

    modport master(
        output aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_lock, aw_cache, aw_prot, aw_qos, aw_region, aw_atop, aw_user, aw_valid, aw_snoop, aw_domain, aw_bar, aw_awunique,
        input aw_ready,
        output w_data, w_strb, w_last, w_user, w_valid,
        input w_ready,
        input b_id, b_resp, b_user, b_valid,
        output b_ready,
        output ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_lock, ar_cache, ar_prot, ar_qos, ar_region, ar_user, ar_valid, ar_snoop, ar_domain, ar_bar,
        input ar_ready,
        input r_id, r_data, r_resp, r_last, r_user, r_valid,
        output r_ready,
        output rack, wack
    );

    modport slave(
        input aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_lock, aw_cache, aw_prot, aw_qos, aw_region, aw_atop, aw_user, aw_valid, aw_snoop, aw_domain, aw_bar, aw_awunique,
        output aw_ready,
        input w_data, w_strb, w_last, w_user, w_valid,
        output w_ready,
        output b_id, b_resp, b_user, b_valid,
        input b_ready,
        input ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_lock, ar_cache, ar_prot, ar_qos, ar_region, ar_user, ar_valid, ar_snoop, ar_domain, ar_bar,
        output ar_ready,
        output r_id, r_data, r_resp, r_last, r_user, r_valid,
        input r_ready,
        input rack, wack
    );

    modport masterr(
        output ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_lock, ar_cache, ar_prot, ar_qos, ar_region, ar_user, ar_valid, ar_snoop, ar_domain, ar_bar,
        input ar_ready,
        input r_id, r_data, r_resp, r_last, r_user, r_valid,
        output r_ready,
        output rack
    );

    modport slaver(
        input ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_lock, ar_cache, ar_prot, ar_qos, ar_region, ar_user, ar_valid, ar_snoop, ar_domain, ar_bar,
        output ar_ready,
        output r_id, r_data, r_resp, r_last, r_user, r_valid,
        input r_ready,
        input rack
    );

    modport masterw(
        output aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_lock, aw_cache, aw_prot, aw_qos, aw_region, aw_atop, aw_user, aw_valid, aw_snoop, aw_domain, aw_bar, aw_awunique,
        input aw_ready,
        output w_data, w_strb, w_last, w_user, w_valid,
        input w_ready,
        input b_id, b_resp, b_user, b_valid,
        output b_ready,
        output wack
    );

endinterface

// Snoop bus interafces
interface SnoopIO #(
  parameter int SNOOP_ADDR_WIDTH = 0,
  parameter int SNOOP_DATA_WIDTH = 0
);

  typedef logic [SNOOP_ADDR_WIDTH-1:0] addr_t;
  typedef logic [SNOOP_DATA_WIDTH-1:0] data_t;

  addr_t                ac_addr;
  logic [2: 0]   ac_prot;
  logic [3: 0]  ac_snoop;
  logic                 ac_valid;
  logic                 ac_ready;

  logic [4: 0]     cr_resp;
  logic                 cr_valid;
  logic                 cr_ready;

  data_t                cd_data;
  logic                 cd_last;
  logic                 cd_valid;
  logic                 cd_ready;

  modport master (
    input   ac_addr, ac_prot, ac_snoop, ac_valid, output ac_ready,
    input   cr_ready, output cr_valid, cr_resp,
    input   cd_ready, output cd_data, cd_last, cd_valid
  );

 modport slave (
    output   ac_addr, ac_prot, ac_snoop, ac_valid, input ac_ready,
    output   cr_ready, input cr_valid, cr_resp,
    output   cd_ready, input cd_data, cd_last, cd_valid
  );

endinterface

interface NativeSnoopIO #(
  parameter int SNOOP_ADDR_WIDTH = 0,
  parameter int SNOOP_DATA_WIDTH = 0,
  parameter int SNOOP_USER_WIDTH = 1
);
  logic [SNOOP_ADDR_WIDTH-1: 0] ac_addr;
  logic ac_valid;
  logic ac_ready;
  logic [SNOOP_USER_WIDTH-1: 0] ac_user;

  logic [SNOOP_DATA_WIDTH-1: 0] cd_data;
  logic cd_last;
  logic cd_valid;
  logic cd_ready;
  logic [SNOOP_USER_WIDTH-1: 0] cd_user;

  modport master (
    input ac_addr, ac_valid, ac_user, output ac_ready,
    input cd_ready, output cd_data, cd_last, cd_valid, cd_user
  );

  modport masterd (
    input cd_ready, output cd_data, cd_last, cd_valid, cd_user
  );

  modport slave (
    output ac_addr, ac_valid, ac_user, input ac_ready,
    output cd_ready, input cd_data, cd_last, cd_valid, cd_user
  );
endinterface

  /// Slice on Demux AW channel.
  localparam logic [9:0] DemuxAw = (1 << 9);
  /// Slice on Demux W channel.
  localparam logic [9:0] DemuxW  = (1 << 8);
  /// Slice on Demux B channel.
  localparam logic [9:0] DemuxB  = (1 << 7);
  /// Slice on Demux AR channel.
  localparam logic [9:0] DemuxAr = (1 << 6);
  /// Slice on Demux R channel.
  localparam logic [9:0] DemuxR  = (1 << 5);
  /// Slice on Mux AW channel.
  localparam logic [9:0] MuxAw   = (1 << 4);
  /// Slice on Mux W channel.
  localparam logic [9:0] MuxW    = (1 << 3);
  /// Slice on Mux B channel.
  localparam logic [9:0] MuxB    = (1 << 2);
  /// Slice on Mux AR channel.
  localparam logic [9:0] MuxAr   = (1 << 1);
  /// Slice on Mux R channel.
  localparam logic [9:0] MuxR    = (1 << 0);
  /// Latency configuration for `ace_xbar`.
  typedef enum logic [9:0] {
    NO_LATENCY    = 10'b000_00_000_00,
    CUT_SLV_AX    = DemuxAw | DemuxAr,
    CUT_MST_AX    = MuxAw | MuxAr,
    CUT_ALL_AX    = DemuxAw | DemuxAr | MuxAw | MuxAr,
    CUT_SLV_PORTS = DemuxAw | DemuxW | DemuxB | DemuxAr | DemuxR,
    CUT_MST_PORTS = MuxAw | MuxW | MuxB | MuxAr | MuxR,
    CUT_ALL_PORTS = 10'b111_11_111_11
  } ccu_latency_e;

  /// Configuration for `ace_ccu`.
  typedef struct packed {
    int  NoSlvPorts;
    int  MaxMstTrans;
    int  MaxSlvTrans;
    bit           FallThrough;
    ccu_latency_e LatencyMode;
    int  AxiIdWidthSlvPorts;
    int  AxiIdUsedSlvPorts;
    bit           UniqueIds;
    int  AxiAddrWidth;
    int  AxiDataWidth;
    int  AxiUserWidth;
    int  DcacheLineWidth;
  } ccu_cfg_t;

  // transaction type
  typedef enum logic[2:0] {
    READ_NO_SNOOP,
    READ_ONCE,
    READ_SHARED,
    READ_UNIQUE,
    CLEAN_UNIQUE,
    WRITE_NO_SNOOP,
    WRITE_BACK,
    WRITE_UNIQUE
  } ace_trs_t;

  typedef struct packed {
    logic        wasUnique;
    logic        isShared;
    logic        passDirty;
    logic        error;
    logic        dataTransfer;
  } crresp_t;

  `define ACEOP_READ_ONCE = 4'b0000;
  `define ACEOP_READ_SHARED = 4'b0001;
  `define ACEOP_READ_CLEAN = 4'b0010;
  `define ACEOP_READ_NOT_SHARED_DIRTY = 4'b0011;
  `define ACEOP_READ_UNIQUE = 4'b0111;
  `define ACEOP_CLEAN_SHARED = 4'b1000;
  `define ACEOP_CLEAN_INVALID = 4'b1001;
  `define ACEOP_CLEAN_UNIQUE = 4'b1011;
  `define ACEOP_MAKE_INVALID = 4'b1101;
  `define ACEOP_DVM_COMPLETE = 4'b1110;
  `define ACEOP_DVM_MESSAGE = 4'b1111;

`define ACE_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)  \
  typedef struct packed {                                       \
    id_t                id;                                       \
    addr_t              addr;                                     \
    logic [7: 0]      len;                                      \
    logic [2: 0]     size;                                     \
    logic [1: 0]    burst;                                    \
    logic               lock;                                     \
    logic [3: 0]    cache;                                    \
    logic [2: 0]     prot;                                     \
    logic [3: 0]      qos;                                      \
    logic [3: 0]   region;                                   \
    logic [5: 0]     atop;                                     \
    user_t              user;                                     \
    logic [2: 0]  snoop;                                  \
    logic [1: 0]      bar;                                      \
    logic [1: 0]   domain;                                   \
    logic  awunique;                                 \
  } aw_chan_t;
`define ACE_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)  \
  typedef struct packed {                                         \
    id_t                id;                                       \
    addr_t              addr;                                     \
    logic [7: 0]      len;                                      \
    logic [2: 0]     size;                                     \
    logic [1: 0]    burst;                                    \
    logic               lock;                                     \
    logic [3: 0]    cache;                                    \
    logic [2: 0]     prot;                                     \
    logic [3: 0]      qos;                                      \
    logic [3: 0]   region;                                   \
    user_t              user;                                     \
    logic [3: 0]  snoop;                                  \
    logic [1: 0]      bar;                                      \
    logic [1: 0]   domain;                                   \
  } ar_chan_t;
`define ACE_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)  \
  typedef struct packed {                                        \
    id_t              id;                                       \
    data_t            data;                                     \
    logic [3: 0]  resp;                                    \
    logic             last;                                     \
    user_t            user;                                     \
  } r_chan_t;
`define ACE_TYPEDEF_REQ_T(req_t, aw_chan_t, w_chan_t, ar_chan_t)  \
  typedef struct packed {                                         \
    aw_chan_t aw;                                             \
    logic     aw_valid;                                           \
    w_chan_t  w;                                                  \
    logic     w_valid;                                            \
    logic     b_ready;                                            \
    ar_chan_t ar;                                             \
    logic     ar_valid;                                           \
    logic     r_ready;                                            \
    logic     wack;                                               \
    logic     rack;                                               \
  } req_t;
`define ACE_TYPEDEF_RESP_T(resp_t, b_chan_t, r_chan_t)  \
  typedef struct packed {                               \
    logic     aw_ready;                                 \
    logic     ar_ready;                                 \
    logic     w_ready;                                  \
    logic     b_valid;                                  \
    b_chan_t  b;                                        \
    logic     r_valid;                                  \
    r_chan_t  r;                                        \
  } resp_t;

`define SNOOP_TYPEDEF_AC_CHAN_T(ac_chan_t, addr_t)              \
  typedef struct packed {                                       \
    addr_t                addr;                                 \
    logic [3: 0]  snoop;                              \
    logic [2: 0]   prot;                               \
  } ac_chan_t;
`define SNOOP_TYPEDEF_CD_CHAN_T(cd_chan_t, data_t)              \
  typedef struct packed {                                       \
    data_t                data;                                 \
    logic                 last;                                 \
  } cd_chan_t;
`define SNOOP_TYPEDEF_CR_CHAN_T(cr_chan_t)                      \
   typedef crresp_t     cr_chan_t;
`define SNOOP_TYPEDEF_REQ_T(req_t, ac_chan_t)      \
  typedef struct packed {                                       \
    logic     ac_valid;                                         \
    logic     cd_ready;                                         \
    ac_chan_t ac;                                               \
    logic     cr_ready;                                         \
  } req_t;
`define SNOOP_TYPEDEF_RESP_T(resp_t, cd_chan_t, cr_chan_t)      \
  typedef struct packed {                                       \
    logic     ac_ready;                                         \
    logic     cd_valid;                                         \
    cd_chan_t cd;                                               \
    logic     cr_valid;                                         \
    cr_chan_t cr_resp;                                          \
  } resp_t;
`define __ACE_TO_AW(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)   \
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
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;       \
  __opt_as __lhs``__lhs_sep``snoop   = __rhs``__rhs_sep``snoop; \
  __opt_as __lhs``__lhs_sep``bar   = __rhs``__rhs_sep``bar;         \
  __opt_as __lhs``__lhs_sep``domain   = __rhs``__rhs_sep``domain;   \
  __opt_as __lhs``__lhs_sep``awunique   = __rhs``__rhs_sep``awunique;


`define __ACE_TO_AR(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)   \
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
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;       \
  __opt_as __lhs``__lhs_sep``snoop = __rhs``__rhs_sep``snoop;   \
  __opt_as __lhs``__lhs_sep``bar = __rhs``__rhs_sep``bar;           \
  __opt_as __lhs``__lhs_sep``domain = __rhs``__rhs_sep``domain;
`define __ACE_TO_R(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``data   = __rhs``__rhs_sep``data;       \
  __opt_as __lhs``__lhs_sep``resp   = __rhs``__rhs_sep``resp;       \
  __opt_as __lhs``__lhs_sep``last   = __rhs``__rhs_sep``last;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __ACE_TO_REQ(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)  \
  `__ACE_TO_AW(__opt_as, __lhs.aw, __lhs_sep, __rhs.aw, __rhs_sep)  \
  __opt_as __lhs.aw_valid = __rhs.aw_valid;                         \
  `__AXI_TO_W(__opt_as, __lhs.w, __lhs_sep, __rhs.w, __rhs_sep)     \
  __opt_as __lhs.w_valid = __rhs.w_valid;                           \
  __opt_as __lhs.b_ready = __rhs.b_ready;                           \
  `__ACE_TO_AR(__opt_as, __lhs.ar, __lhs_sep, __rhs.ar, __rhs_sep)  \
  __opt_as __lhs.ar_valid = __rhs.ar_valid;                         \
  __opt_as __lhs.r_ready = __rhs.r_ready;                           \
  __opt_as __lhs.wack = __rhs.wack;                                 \
  __opt_as __lhs.rack = __rhs.rack;
`define __ACE_TO_RESP(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep) \
  __opt_as __lhs.aw_ready = __rhs.aw_ready;                         \
  __opt_as __lhs.ar_ready = __rhs.ar_ready;                         \
  __opt_as __lhs.w_ready = __rhs.w_ready;                           \
  __opt_as __lhs.b_valid = __rhs.b_valid;                           \
  `__AXI_TO_B(__opt_as, __lhs.b, __lhs_sep, __rhs.b, __rhs_sep)     \
  __opt_as __lhs.r_valid = __rhs.r_valid;                           \
  `__ACE_TO_R(__opt_as, __lhs.r, __lhs_sep, __rhs.r, __rhs_sep)

`define ACE_ASSIGN_AW(dst, src)               \
  `__ACE_TO_AW(assign, dst.aw, _, src.aw, _)  \
  assign dst.aw_valid = src.aw_valid;         \
  assign src.aw_ready = dst.aw_ready;

`define ACE_ASSIGN_AR(dst, src)               \
  `__ACE_TO_AR(assign, dst.ar, _, src.ar, _)  \
  assign dst.ar_valid = src.ar_valid;         \
  assign src.ar_ready = dst.ar_ready;
`define ACE_ASSIGN_R(dst, src)                \
  `__ACE_TO_R(assign, dst.r, _, src.r, _)     \
  assign dst.r_valid  = src.r_valid;          \
  assign src.r_ready  = dst.r_ready;
`define ACE_ASSIGN(slv, mst)  \
  `ACE_ASSIGN_AW(slv, mst)    \
  `AXI_ASSIGN_W(slv, mst)     \
  `AXI_ASSIGN_B(mst, slv)     \
  `ACE_ASSIGN_AR(slv, mst)    \
  `ACE_ASSIGN_R(mst, slv)     \
  assign slv.wack = mst.wack; \
  assign slv.rack = mst.rack;

`define ACE_TYPEDEF_ALL(__name, __addr_t, __id_t, __data_t, __strb_t, __user_t)                 \
  `ACE_TYPEDEF_AW_CHAN_T(__name``_aw_chan_t, __addr_t, __id_t, __user_t)                    \
  `AXI_TYPEDEF_W_CHAN_T(__name``_w_chan_t, __data_t, __strb_t, __user_t)                        \
  `AXI_TYPEDEF_B_CHAN_T(__name``_b_chan_t, __id_t, __user_t)                                    \
  `ACE_TYPEDEF_AR_CHAN_T(__name``_ar_chan_t, __addr_t, __id_t, __user_t)                    \
  `ACE_TYPEDEF_R_CHAN_T(__name``_r_chan_t, __data_t, __id_t, __user_t)                      \
  `ACE_TYPEDEF_REQ_T(__name``_req_t, __name``_aw_chan_t, __name``_w_chan_t, __name``_ar_chan_t) \
  `ACE_TYPEDEF_RESP_T(__name``_resp_t, __name``_b_chan_t, __name``_r_chan_t)

`define ACE_SET_FROM_AW(axi_if, aw_struct)      `__ACE_TO_AW(, axi_if.aw, _, aw_struct, .)
`define ACE_SET_FROM_AR(axi_if, ar_struct)      `__ACE_TO_AR(, axi_if.ar, _, ar_struct, .)
`define ACE_SET_FROM_R(axi_if, r_struct)        `__ACE_TO_R(, axi_if.r, _, r_struct, .)
`define ACE_SET_FROM_REQ(axi_if, req_struct)    `__ACE_TO_REQ(, axi_if, _, req_struct, .)
`define ACE_SET_FROM_RESP(axi_if, resp_struct)  `__ACE_TO_RESP(, axi_if, _, resp_struct, .)

`define ACE_ASSIGN_FROM_AW(axi_if, aw_struct)     `__ACE_TO_AW(assign, axi_if.aw, _, aw_struct, .)
`define ACE_ASSIGN_FROM_AR(axi_if, ar_struct)     `__ACE_TO_AR(assign, axi_if.ar, _, ar_struct, .)
`define ACE_ASSIGN_FROM_R(axi_if, r_struct)       `__ACE_TO_R(assign, axi_if.r, _, r_struct, .)
`define ACE_ASSIGN_FROM_REQ(axi_if, req_struct)   `__ACE_TO_REQ(assign, axi_if, _, req_struct, .)
`define ACE_ASSIGN_FROM_RESP(axi_if, resp_struct) `__ACE_TO_RESP(assign, axi_if, _, resp_struct, .)

`define ACE_SET_TO_AW(aw_struct, axi_if)     `__ACE_TO_AW(, aw_struct, ., axi_if.aw, _)
`define ACE_SET_TO_AR(ar_struct, axi_if)     `__ACE_TO_AR(, ar_struct, ., axi_if.ar, _)
`define ACE_SET_TO_R(r_struct, axi_if)       `__ACE_TO_R(, r_struct, ., axi_if.r, _)
`define ACE_SET_TO_REQ(req_struct, axi_if)   `__ACE_TO_REQ(, req_struct, ., axi_if, _)
`define ACE_SET_TO_RESP(resp_struct, axi_if) `__ACE_TO_RESP(, resp_struct, ., axi_if, _)

`define ACE_ASSIGN_TO_AW(aw_struct, axi_if)     `__ACE_TO_AW(assign, aw_struct, ., axi_if.aw, _)
`define ACE_ASSIGN_TO_AR(ar_struct, axi_if)     `__ACE_TO_AR(assign, ar_struct, ., axi_if.ar, _)
`define ACE_ASSIGN_TO_R(r_struct, axi_if)       `__ACE_TO_R(assign, r_struct, ., axi_if.r, _)
`define ACE_ASSIGN_TO_REQ(req_struct, axi_if)   `__ACE_TO_REQ(assign, req_struct, ., axi_if, _)
`define ACE_ASSIGN_TO_RESP(resp_struct, axi_if) `__ACE_TO_RESP(assign, resp_struct, ., axi_if, _)

`define ACE_SET_AW_STRUCT(lhs, rhs)     `__ACE_TO_AW(, lhs, ., rhs, .)
`define ACE_SET_AR_STRUCT(lhs, rhs)     `__ACE_TO_AR(, lhs, ., rhs, .)
`define ACE_SET_R_STRUCT(lhs, rhs)       `__ACE_TO_R(, lhs, ., rhs, .)
`define ACE_SET_REQ_STRUCT(lhs, rhs)   `__ACE_TO_REQ(, lhs, ., rhs, .)
`define ACE_SET_RESP_STRUCT(lhs, rhs) `__ACE_TO_RESP(, lhs, ., rhs, .)

`define ACE_ASSIGN_AW_STRUCT(lhs, rhs)     `__ACE_TO_AW(assign, lhs, ., rhs, .)
`define ACE_ASSIGN_AR_STRUCT(lhs, rhs)     `__ACE_TO_AR(assign, lhs, ., rhs, .)
`define ACE_ASSIGN_R_STRUCT(lhs, rhs)       `__ACE_TO_R(assign, lhs, ., rhs, .)
`define ACE_ASSIGN_REQ_STRUCT(lhs, rhs)   `__ACE_TO_REQ(assign, lhs, ., rhs, .)
`define ACE_ASSIGN_RESP_STRUCT(lhs, rhs) `__ACE_TO_RESP(assign, lhs, ., rhs, .)

`define __SNOOP_TO_AC(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)       \
  __opt_as __lhs``__lhs_sep``addr      = __rhs``__rhs_sep``addr;          \
  __opt_as __lhs``__lhs_sep``snoop   = __rhs``__rhs_sep``snoop;       \
  __opt_as __lhs``__lhs_sep``prot    = __rhs``__rhs_sep``prot;
`define __SNOOP_TO_CD(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)       \
  __opt_as __lhs``__lhs_sep``data   = __rhs``__rhs_sep``data;             \
  __opt_as __lhs``__lhs_sep``last   = __rhs``__rhs_sep``last;
`define __SNOOP_TO_CR(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)       \
  __opt_as __lhs``__lhs_sep``resp   = __rhs``__rhs_sep``resp;
`define __SNOOP_TO_REQ(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)      \
  `__SNOOP_TO_AC(__opt_as, __lhs.ac, __lhs_sep, __rhs.ac, __rhs_sep)      \
  __opt_as __lhs.ac_valid = __rhs.ac_valid;                               \
  __opt_as __lhs.cd_ready = __rhs.cd_ready;                               \
  __opt_as __lhs.cr_ready = __rhs.cr_ready;
`define __SNOOP_TO_RESP(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)     \
  __opt_as __lhs.ac_ready = __rhs.ac_ready;                               \
  __opt_as __lhs.cd_valid = __rhs.cd_valid;                               \
  `__SNOOP_TO_CD(__opt_as, __lhs.cd, __lhs_sep, __rhs.cd, __rhs_sep)      \
  __opt_as __lhs.cr_valid = __rhs.cr_valid;                               \
  __opt_as __lhs.cr_resp = __rhs.cr_resp;

`define SNOOP_ASSIGN_AC(dst, src)               \
  `__SNOOP_TO_AC(assign, dst.ac, _, src.ac, _)  \
  assign dst.ac_valid = src.ac_valid;         \
  assign src.ac_ready = dst.ac_ready;
`define SNOOP_ASSIGN_CD(dst, src)                \
  `__SNOOP_TO_CD(assign, dst.cd, _, src.cd, _)     \
  assign dst.cd_valid  = src.cd_valid;          \
  assign src.cd_ready  = dst.cd_ready;
`define SNOOP_ASSIGN_CR(dst, src)                \
  `__SNOOP_TO_CR(assign, dst.cr, _, src.cr, _)     \
  assign dst.cr_valid  = src.cr_valid;          \
  assign src.cr_ready  = dst.cr_ready;
`define SNOOP_ASSIGN(slv, mst)  \
  `SNOOP_ASSIGN_AC(slv, mst)    \
  `SNOOP_ASSIGN_CD(mst, slv)    \
  `SNOOP_ASSIGN_CR(mst, slv)

`define SNOOP_ASSIGN_MONITOR(mon_dv, snoop_if)          \
  `__SNOOP_TO_AC(assign, mon_dv.ac, _, snoop_if.ac, _)  \
  assign mon_dv.ac_valid  = snoop_if.ac_valid;        \
  assign mon_dv.ac_ready  = snoop_if.ac_ready;        \
  `__SNOOP_TO_CD(assign, mon_dv.cd, _, snoop_if.cd, _)     \
  assign mon_dv.cd_valid   = snoop_if.cd_valid;         \
  assign mon_dv.cd_ready   = snoop_if.cd_ready;         \
  `__SNOOP_TO_CR(assign, mon_dv.cr, _, snoop_if.cr, _)     \
  assign mon_dv.cr_ready   = snoop_if.cr_ready;         \
  assign mon_dv.cr_valid   = snoop_if.cr_valid;

`define SNOOP_SET_FROM_AC(snoop_if, ac_struct)      `__SNOOP_TO_AC(, snoop_if.ac, _, ac_struct, .)
`define SNOOP_SET_FROM_CD(snoop_if, cd_struct)      `__SNOOP_TO_CD(, snoop_if.cd, _, cd_struct, .)
`define SNOOP_SET_FROM_CR(snoop_if, cr_struct)        `__SNOOP_TO_CR(, snoop_if.cr, _, cr_struct, .)
`define SNOOP_SET_FROM_REQ(snoop_if, req_struct)    `__SNOOP_TO_REQ(, snoop_if, _, req_struct, .)
`define SNOOP_SET_FROM_RESP(snoop_if, resp_struct)  `__SNOOP_TO_RESP(, snoop_if, _, resp_struct, .)

`define SNOOP_ASSIGN_FROM_AC(snoop_if, ac_struct)     `__SNOOP_TO_AC(assign, snoop_if.ac, _, ac_struct, .)
`define SNOOP_ASSIGN_FROM_CD(snoop_if, cd_struct)     `__SNOOP_TO_CD(assign, snoop_if.cd, _, cd_struct, .)
`define SNOOP_ASSIGN_FROM_CR(snoop_if, cr_struct)       `__SNOOP_TO_CR(assign, snoop_if.cr, _, cr_struct, .)
`define SNOOP_ASSIGN_FROM_REQ(snoop_if, req_struct)   `__SNOOP_TO_REQ(assign, snoop_if, _, req_struct, .)
`define SNOOP_ASSIGN_FROM_RESP(snoop_if, resp_struct) `__SNOOP_TO_RESP(assign, snoop_if, _, resp_struct, .)

`define SNOOP_SET_TO_AC(ac_struct, snoop_if)     `__SNOOP_TO_AC(, ac_struct, ., snoop_if.ac, _)
`define SNOOP_SET_TO_CD(cd_struct, snoop_if)     `__SNOOP_TO_CD(, cd_struct, ., snoop_if.cd, _)
`define SNOOP_SET_TO_CR(cr_struct, snoop_if)       `__SNOOP_TO_CR(, cr_struct, ., snoop_if.cr, _)
`define SNOOP_SET_TO_REQ(req_struct, snoop_if)   `__SNOOP_TO_REQ(, req_struct, ., snoop_if, _)
`define SNOOP_SET_TO_RESP(resp_struct, snoop_if) `__SNOOP_TO_RESP(, resp_struct, ., snoop_if, _)

`define SNOOP_ASSIGN_TO_AC(aw_struct, snoop_if)     `__SNOOP_TO_AC(assign, aw_struct, ., snoop_if.aw, _)
`define SNOOP_ASSIGN_TO_CD(ar_struct, snoop_if)     `__SNOOP_TO_CD(assign, ar_struct, ., snoop_if.ar, _)
`define SNOOP_ASSIGN_TO_CR(r_struct, snoop_if)       `__SNOOP_TO_CR(assign, r_struct, ., snoop_if.r, _)
`define SNOOP_ASSIGN_TO_REQ(req_struct, snoop_if)   `__SNOOP_TO_REQ(assign, req_struct, ., snoop_if, _)
`define SNOOP_ASSIGN_TO_RESP(resp_struct, snoop_if) `__SNOOP_TO_RESP(assign, resp_struct, ., snoop_if, _)

`define SNOOP_SET_AC_STRUCT(lhs, rhs)     `__SNOOP_TO_AC(, lhs, ., rhs, .)
`define SNOOP_SET_CD_STRUCT(lhs, rhs)     `__SNOOP_TO_CD(, lhs, ., rhs, .)
`define SNOOP_SET_CR_STRUCT(lhs, rhs)       `__SNOOP_TO_CR(, lhs, ., rhs, .)
`define SNOOP_SET_REQ_STRUCT(lhs, rhs)   `__SNOOP_TO_REQ(, lhs, ., rhs, .)
`define SNOOP_SET_RESP_STRUCT(lhs, rhs) `__SNOOP_TO_RESP(, lhs, ., rhs, .)

`define SNOOP_ASSIGN_AC_STRUCT(lhs, rhs)     `__SNOOP_TO_AC(assign, lhs, ., rhs, .)
`define SNOOP_ASSIGN_CD_STRUCT(lhs, rhs)     `__SNOOP_TO_CD(assign, lhs, ., rhs, .)
`define SNOOP_ASSIGN_CR_STRUCT(lhs, rhs)       `__SNOOP_TO_CR(assign, lhs, ., rhs, .)
`define SNOOP_ASSIGN_REQ_STRUCT(lhs, rhs)   `__SNOOP_TO_REQ(assign, lhs, ., rhs, .)
`define SNOOP_ASSIGN_RESP_STRUCT(lhs, rhs) `__SNOOP_TO_RESP(assign, lhs, ., rhs, .)


`endif
