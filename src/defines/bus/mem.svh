`ifndef __MEM_SVH__
`define __MEM_SVH__

interface CacheBus #(
    parameter int ADDR_WIDTH = 0,
    parameter int DATA_WIDTH = 0,
    parameter int ID_WIDTH = 0,
    parameter int USER_WIDTH = 0
);
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    typedef logic [ID_WIDTH-1:0] id_t;
    typedef logic [ADDR_WIDTH-1:0] addr_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [STRB_WIDTH-1:0] strb_t;
    typedef logic [USER_WIDTH-1:0] user_t;

    id_t aw_id;
    addr_t aw_addr;
    logic  [7:0] aw_len;
    logic  [2:0] aw_size;
    logic  [1:0] aw_burst;
    user_t       aw_user;
    logic        aw_valid;
    logic        aw_ready;
    logic  [2:0] aw_snoop;

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
    user_t       ar_user;
    logic        ar_valid;
    logic        ar_ready;
    logic  [3:0] ar_snoop;

    id_t         r_id;
    data_t       r_data;
    logic  [4:0] r_resp;
    logic        r_last;
    user_t       r_user;
    logic        r_valid;
    logic        r_ready;

    modport master(
        output aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_user, aw_valid, aw_snoop,
        input aw_ready,
        output w_data, w_strb, w_last, w_user, w_valid,
        input w_ready,
        input b_id, b_resp, b_user, b_valid,
        output b_ready,
        output ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_user, ar_valid, ar_snoop,
        input ar_ready,
        input r_id, r_data, r_resp, r_last, r_user, r_valid,
        output r_ready
    );

    modport slave(
        input aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_user, aw_valid, aw_snoop,
        output aw_ready,
        input w_data, w_strb, w_last, w_user, w_valid,
        output w_ready,
        output b_id, b_resp, b_user, b_valid,
        input b_ready,
        input ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_user, ar_valid, ar_snoop,
        output ar_ready,
        output r_id, r_data, r_resp, r_last, r_user, r_valid,
        input r_ready
    );

    modport masterr(
        output ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_user, ar_valid, ar_snoop,
        input ar_ready,
        input r_id, r_data, r_resp, r_last, r_user, r_valid,
        output r_ready
    );

    modport slaver(
        input ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_user, ar_valid, ar_snoop,
        output ar_ready,
        output r_id, r_data, r_resp, r_last, r_user, r_valid,
        input r_ready
    );

    modport masterw(
        output aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_user, aw_valid, aw_snoop,
        input aw_ready,
        output w_data, w_strb, w_last, w_user, w_valid,
        input w_ready,
        input b_id, b_resp, b_user, b_valid,
        output b_ready
    );
endinterface //CacheBus

`define CACHE_TYPEDEF_AW_CHAN_T(aw_chan_t, addr_t, id_t, user_t)  \
  typedef struct packed {                                       \
    id_t                id;                                       \
    addr_t              addr;                                     \
    logic [7: 0]      len;                                      \
    logic [2: 0]     size;                                     \
    logic [1: 0]    burst;                                    \
    user_t              user;                                     \
    logic [2: 0]  snoop;                                  \
  } aw_chan_t;
`define CACHE_TYPEDEF_AR_CHAN_T(ar_chan_t, addr_t, id_t, user_t)  \
  typedef struct packed {                                         \
    id_t                id;                                       \
    addr_t              addr;                                     \
    logic [7: 0]      len;                                      \
    logic [2: 0]     size;                                     \
    logic [1: 0]    burst;                                    \
    user_t              user;                                     \
    logic [3: 0]  snoop;                                  \
  } ar_chan_t;
`define CACHE_TYPEDEF_R_CHAN_T(r_chan_t, data_t, id_t, user_t)  \
  typedef struct packed {                                        \
    id_t              id;                                       \
    data_t            data;                                     \
    logic [3: 0]  resp;                                    \
    logic             last;                                     \
    user_t            user;                                     \
  } r_chan_t;
`define CACHE_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)  \
  typedef struct packed {                                       \
    data_t data;                                                \
    strb_t strb;                                                \
    logic  last;                                                \
    user_t user;                                                \
  } w_chan_t;
`define CACHE_TYPEDEF_B_CHAN_T(b_chan_t, id_t, user_t)  \
  typedef struct packed {                             \
    id_t            id;                               \
    logic [1: 0] resp;                             \
    user_t          user;                             \
  } b_chan_t;
`define CACHE_TYPEDEF_REQ_T(req_t, aw_chan_t, w_chan_t, ar_chan_t)  \
  typedef struct packed {                                         \
    aw_chan_t aw;                                             \
    logic     aw_valid;                                           \
    w_chan_t  w;                                                  \
    logic     w_valid;                                            \
    logic     b_ready;                                            \
    ar_chan_t ar;                                             \
    logic     ar_valid;                                           \
    logic     r_ready;                                            \
  } req_t;
`define CACHE_TYPEDEF_RESP_T(resp_t, b_chan_t, r_chan_t)  \
  typedef struct packed {                               \
    logic     aw_ready;                                 \
    logic     ar_ready;                                 \
    logic     w_ready;                                  \
    logic     b_valid;                                  \
    b_chan_t  b;                                        \
    logic     r_valid;                                  \
    r_chan_t  r;                                        \
  } resp_t;


`define __CACHE_TO_AW(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)   \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``addr   = __rhs``__rhs_sep``addr;       \
  __opt_as __lhs``__lhs_sep``len    = __rhs``__rhs_sep``len;        \
  __opt_as __lhs``__lhs_sep``size   = __rhs``__rhs_sep``size;       \
  __opt_as __lhs``__lhs_sep``burst  = __rhs``__rhs_sep``burst;      \
  __opt_as __lhs``__lhs_sep``snoop  = __rhs``__rhs_sep``snoop;      \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __CACHE_TO_W(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``data   = __rhs``__rhs_sep``data;       \
  __opt_as __lhs``__lhs_sep``strb   = __rhs``__rhs_sep``strb;       \
  __opt_as __lhs``__lhs_sep``last   = __rhs``__rhs_sep``last;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __CACHE_TO_B(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``resp   = __rhs``__rhs_sep``resp;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __CACHE_TO_AR(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)   \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``addr   = __rhs``__rhs_sep``addr;       \
  __opt_as __lhs``__lhs_sep``len    = __rhs``__rhs_sep``len;        \
  __opt_as __lhs``__lhs_sep``size   = __rhs``__rhs_sep``size;       \
  __opt_as __lhs``__lhs_sep``burst  = __rhs``__rhs_sep``burst;      \
  __opt_as __lhs``__lhs_sep``snoop  = __rhs``__rhs_sep``snoop;      \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __CACHE_TO_R(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)    \
  __opt_as __lhs``__lhs_sep``id     = __rhs``__rhs_sep``id;         \
  __opt_as __lhs``__lhs_sep``data   = __rhs``__rhs_sep``data;       \
  __opt_as __lhs``__lhs_sep``resp   = __rhs``__rhs_sep``resp;       \
  __opt_as __lhs``__lhs_sep``last   = __rhs``__rhs_sep``last;       \
  __opt_as __lhs``__lhs_sep``user   = __rhs``__rhs_sep``user;
`define __CACHE_TO_REQ(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep)  \
  `__CACHE_TO_AW(__opt_as, __lhs.aw, __lhs_sep, __rhs.aw, __rhs_sep)  \
  __opt_as __lhs.aw_valid = __rhs.aw_valid;                         \
  `__CACHE_TO_W(__opt_as, __lhs.w, __lhs_sep, __rhs.w, __rhs_sep)     \
  __opt_as __lhs.w_valid = __rhs.w_valid;                           \
  __opt_as __lhs.b_ready = __rhs.b_ready;                           \
  `__CACHE_TO_AR(__opt_as, __lhs.ar, __lhs_sep, __rhs.ar, __rhs_sep)  \
  __opt_as __lhs.ar_valid = __rhs.ar_valid;                         \
  __opt_as __lhs.r_ready = __rhs.r_ready;
`define __CACHE_TO_RESP(__opt_as, __lhs, __lhs_sep, __rhs, __rhs_sep) \
  __opt_as __lhs.aw_ready = __rhs.aw_ready;                         \
  __opt_as __lhs.ar_ready = __rhs.ar_ready;                         \
  __opt_as __lhs.w_ready = __rhs.w_ready;                           \
  __opt_as __lhs.b_valid = __rhs.b_valid;                           \
  `__CACHE_TO_B(__opt_as, __lhs.b, __lhs_sep, __rhs.b, __rhs_sep)     \
  __opt_as __lhs.r_valid = __rhs.r_valid;                           \
  `__CACHE_TO_R(__opt_as, __lhs.r, __lhs_sep, __rhs.r, __rhs_sep)

`define CACHE_ASSIGN_TO_AW(aw_struct, axi_if) `__CACHE_TO_AW(assign, aw_struct, ., axi_if.aw, _)
`define CACHE_ASSIGN_TO_W(w_struct, axi_if) `__CACHE_TO_W(assign, w_struct, ., axi_if.w, _)
`define CACHE_ASSIGN_TO_B(b_struct, axi_if) `__CACHE_TO_B(assign, b_struct, ., axi_if.b, _)
`define CACHE_ASSIGN_TO_AR(ar_struct, axi_if) `__CACHE_TO_AR(assign, ar_struct, ., axi_if.ar, _)
`define CACHE_ASSIGN_TO_R(r_struct, axi_if) `__CACHE_TO_R(assign, r_struct, ., axi_if.r, _)
`define CACHE_ASSIGN_TO_REQ(req_struct, axi_if) `__CACHE_TO_REQ(assign, req_struct, ., axi_if, _)
`define CACHE_ASSIGN_TO_RESP(resp_struct, axi_if) `__CACHE_TO_RESP(assign, resp_struct, ., axi_if, _)
`define CACHE_ASSIGN_REQ_INTF(lhs, rhs) `__CACHE_TO_REQ(assign, lhs, _, rhs, _)
`define CACHE_ASSIGN_RESP_INTF(lhs, rhs) `__CACHE_TO_RESP(assign, lhs, _, rhs, _)
`define CACHE_ASSIGN_FROM_AW(axi_if, aw_struct) `__CACHE_TO_AW(assign, axi_if.aw, _, aw_struct, .)
`define CACHE_ASSIGN_FROM_W(axi_if, w_struct) `__CACHE_TO_W(assign, axi_if.w, _, w_struct, .)
`define CACHE_ASSIGN_FROM_B(axi_if, b_struct) `__CACHE_TO_B(assign, axi_if.b, _, b_struct, .)
`define CACHE_ASSIGN_FROM_AR(axi_if, ar_struct) `__CACHE_TO_AR(assign, axi_if.ar, _, ar_struct, .)
`define CACHE_ASSIGN_FROM_R(axi_if, r_struct) `__CACHE_TO_R(assign, axi_if.r, _, r_struct, .)
`define CACHE_ASSIGN_FROM_REQ(axi_if, req_struct) `__CACHE_TO_REQ(assign, axi_if, _, req_struct, .)
`define CACHE_ASSIGN_FROM_RESP(axi_if, resp_struct) `__CACHE_TO_RESP(assign, axi_if, _, resp_struct, .)

`define CACHE_ASSIGN_R_REQ(lhs, rhs) \
    `__CACHE_TO_AR(assign, lhs.ar, _, rhs.ar, _) \
    `__CACHE_TO_R(assign, rhs.r, _, lhs.r, _) \
    assign lhs.ar_valid = rhs.ar_valid; \
    assign rhs.ar_ready = lhs.ar_ready; \
    assign rhs.r_valid = lhs.r_valid; \
    assign lhs.r_ready = rhs.r_ready;
`define CACHE_ASSIGN_W_REQ(lhs, rhs) \
    `__CACHE_TO_AW(assign, lhs.aw, _, rhs.aw, _) \
    `__CACHE_TO_W(assign, lhs.w, _, rhs.w, _) \
    `__CACHE_TO_B(assign, rhs.b, _, lhs.b, _) \
    assign lhs.aw_valid = rhs.aw_valid; \
    assign lhs.w_valid = rhs.w_valid; \
    assign lhs.b_ready = rhs.b_ready; \
    assign rhs.aw_ready = lhs.aw_ready; \
    assign rhs.w_ready = lhs.w_ready; \
    assign rhs.b_valid = lhs.b_valid;
`define CACHE_ASSIGN_TO_AXI(axi_if, cache_if) \
    assign axi_if.ar_id     = cache_if.ar_id; \
    assign axi_if.ar_addr   = cache_if.ar_addr; \
    assign axi_if.ar_len    = cache_if.ar_len; \
    assign axi_if.ar_size   = cache_if.ar_size; \
    assign axi_if.ar_burst  = cache_if.ar_burst; \
    assign axi_if.ar_user   = cache_if.ar_user; \
    assign cache_if.r_data = axi_if.r_data; \
    assign cache_if.r_resp[4: 2] = 3'b001; \
    assign cache_if.r_resp[1: 0] = axi_if.r_resp[1: 0]; \
    assign cache_if.r_id = axi_if.r_id; \
    assign cache_if.r_last = axi_if.r_last; \
    assign cache_if.r_user = axi_if.r_user; \
    assign axi_if.aw_id     = cache_if.aw_id; \
    assign axi_if.aw_addr   = cache_if.aw_addr; \
    assign axi_if.aw_len    = cache_if.aw_len; \
    assign axi_if.aw_size   = cache_if.aw_size; \
    assign axi_if.aw_burst  = cache_if.aw_burst; \
    assign axi_if.aw_user   = cache_if.aw_user; \
    `__CACHE_TO_W(assign, axi_if.w, _, cache_if.w, _) \
    `__CACHE_TO_B(assign, cache_if.b, _, axi_if.b, _) \
    assign axi_if.ar_valid = cache_if.ar_valid; \
    assign cache_if.ar_ready = axi_if.ar_ready; \
    assign cache_if.r_valid = axi_if.r_valid; \
    assign axi_if.r_ready = cache_if.r_ready; \
    assign axi_if.aw_valid = cache_if.aw_valid; \
    assign axi_if.w_valid = cache_if.w_valid; \
    assign axi_if.b_ready = cache_if.b_ready; \
    assign cache_if.aw_ready = axi_if.aw_ready; \
    assign cache_if.w_ready = axi_if.w_ready; \
    assign cache_if.b_valid = axi_if.b_valid;


`endif