`include "../../../defines/defines.svh"

interface PTWL2IO;
    logic valid;
    logic ready;
    logic exception;
    TLBInfo info;
    PTEEntry entry;
    logic `N(`VADDR_SIZE) waddr;
    logic `N(`TLB_PN) wpn;

    modport ptw (output valid, exception, info, entry, waddr, wpn, input ready);
endinterface

module PTW(
    input logic clk,
    input logic rst,
    input logic flush,
    input logic fence_flush,
    CachePTWIO.ptw cache_ptw_io,
    CsrL2IO.tlb csr_io,
    CacheBus.masterr axi_io,
    PTWL2IO.ptw ptw_io,
    output logic ptw_wb
);
    typedef enum  { IDLE, WALK_PN1, WB_PN1, WALK_PN0, WB_PN0 
`ifdef SV39
    , WALK_PN2, WB_PN2
`endif
    } State;
    typedef struct packed {
        logic `N(`PADDR_SIZE) paddr;
        logic `N(`VADDR_SIZE) vaddr;
        TLBInfo info;
        PTEEntry wb_entry;
    } RequestBuffer;
    typedef struct packed {
        logic valid;
        logic `N(`VADDR_SIZE) vaddr;
        TLBInfo info;
        PTEEntry entry;
    } WritebackInfo;
    State state;
    RequestBuffer req_buf;
    WritebackInfo wb_info;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) rdata;
    logic `N($clog2(`DCACHE_BANK)) ridx;
    logic rlast;
    logic ar_valid;
    logic flush_q, fence_flush_q, flush_valid;

    logic pn_leaf;
    logic pn1_exception, pn_exception;
    logic pn1_unalign;
`ifdef SV39
    logic pn2_exception;
    logic pn2_unalign;
`endif

    typedef struct packed {
        logic `N(`VADDR_SIZE) vaddr;
        TLBInfo info;
        PPNAddr ppn;
    } PNData;

`define PN_BUF_DEF(st, stn) \
    PNData pn``st``_data, pn``st``_wb_data; \
    localparam PN``st``_TAG_SIZE = `TLB_VPN * (`TLB_PN - st); \
    localparam PN``st``_BIT_SIZE = `VADDR_SIZE + $bits(TLBInfo) + `PADDR_SIZE - `TLB_OFFSET; \
    PTBufferIO #( \
        .TAG_WIDTH(PN``st``_TAG_SIZE), \
        .DATA_WIDTH(PN``st``_BIT_SIZE - PN``st``_TAG_SIZE) \
    ) pn``st``_io(); \
    PTBuffer #( \
        .TAG_WIDTH(PN``st``_TAG_SIZE), \
        .DATA_WIDTH(PN``st``_BIT_SIZE-PN``st``_TAG_SIZE), \
        .DEPTH(`TLB_PTB``st``_SIZE), \
        .MULTI(1) \
    ) pn``st``_buffer (.*, .io(pn``st``_io)); \
    assign pn``st``_io.flush = flush | fence_flush; \
    assign pn``st``_io.en = cache_ptw_io.req & cache_ptw_io.valid[stn] & ~(|cache_ptw_io.valid[st: 0]) | \
                       (state == WB_PN``stn`` && (~pn_leaf &  \
                       ~pn``stn``_exception & ~pn``st``_io.full & pn``stn``_io.wb_valid & ~flush_q)); \
    assign pn``st``_io.tag = cache_ptw_io.req & cache_ptw_io.valid[stn] & ~(|cache_ptw_io.valid[st: 0]) ?  \
                                cache_ptw_io.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(st)] : \
                                pn``stn``_wb_data.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(st)]; \
    assign pn``st``_io.data = cache_ptw_io.req & cache_ptw_io.valid[stn] & ~(|cache_ptw_io.valid[st: 0]) ?  \
                         {cache_ptw_io.vaddr[`TLB_VPN_BASE(st)-1: 0], cache_ptw_io.info, cache_ptw_io.paddr[stn][`PADDR_SIZE-1: `TLB_OFFSET]} : \
                         {pn``stn``_wb_data.vaddr[`TLB_VPN_BASE(st)-1: 0], pn``stn``_wb_data.info, wb_info.entry.ppn}; \
    assign pn``st``_io.data_valid = rlast && (state == WALK_PN``st``); \
    assign pn``st``_io.ready = state == IDLE && !pn``stn``_io.valid; \
    assign pn``st``_io.ctag = req_buf.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(st)]; \
    assign pn``st``_data = pn``st``_io.data_o; \
    assign pn``st``_wb_data = pn``st``_io.wb_data;

    typedef struct packed {
        logic `N(`VADDR_SIZE) vaddr;
        TLBInfo info;
    } PNLData;

`define PN_LAST_BUF_DEF(st) \
    PNLData pn``st``_data, pn``st``_wb_data; \
    localparam PN``st``_TAG_SIZE = `TLB_VPN; \
    localparam PN``st``_BIT_SIZE = `VADDR_SIZE + $bits(TLBInfo); \
    PTBufferIO #( \
        .TAG_WIDTH(PN``st``_TAG_SIZE), \
        .DATA_WIDTH(PN``st``_BIT_SIZE - PN``st``_TAG_SIZE) \
    ) pn``st``_io(); \
    PTBuffer #( \
        .TAG_WIDTH(PN``st``_TAG_SIZE), \
        .DATA_WIDTH(PN``st``_BIT_SIZE-PN``st``_TAG_SIZE), \
        .DEPTH(`TLB_PTB``st``_SIZE), \
        .MULTI(1) \
    ) pn``st``_buffer (.*, .io(pn``st``_io)); \
    assign pn``st``_io.flush = flush | fence_flush; \
    assign pn``st``_io.en = cache_ptw_io.req & (~(|cache_ptw_io.valid)); \
    assign pn``st``_io.tag = cache_ptw_io.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(st)]; \
    assign pn``st``_io.data = {cache_ptw_io.vaddr[`TLB_VPN_BASE(st)-1: 0], cache_ptw_io.info}; \
    assign pn``st``_io.data_valid = rlast && (state == WALK_PN``st``); \
    assign pn``st``_io.ready = state == IDLE; \
    assign pn``st``_io.ctag = req_buf.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(st)]; \
    assign pn``st``_data = pn``st``_io.data_o; \
    assign pn``st``_wb_data = pn``st``_io.wb_data;

`define PN_WB_READY_DEF(st, stp) \
    assign pn``st``_io.wb_ready = (state == WB_PN``st``) &  \
                             ((pn_leaf | pn``st``_exception) & ptw_io.ready | \
                              ~pn_leaf & ~pn``st``_exception & ~pn``stp``_io.full &  \
                              ~(cache_ptw_io.req & cache_ptw_io.valid[st] & ~(|cache_ptw_io.valid[stp: 0]))) & ~flush_q;

assign pn0_io.wb_ready = (state == WB_PN0) & ptw_io.ready & ~flush_q;
`PN_BUF_DEF(0, 1)
`ifdef SV32
`PN_LAST_BUF_DEF(1)
`else
`PN_BUF_DEF(1, 2)
`endif
`PN_WB_READY_DEF(1, 0)
`ifdef SV39
`PN_LAST_BUF_DEF(2)
`PN_WB_READY_DEF(2, 1)
`endif

    assign pn_leaf = req_buf.wb_entry.r | req_buf.wb_entry.w | req_buf.wb_entry.x;
    assign pn1_unalign = pn_leaf & (|req_buf.wb_entry.ppn[0]);
    TLBExcDetect exc_detect (req_buf.wb_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, pn_exception);
    assign pn1_exception = pn_exception | pn1_unalign;
`ifdef SV39
    assign pn2_unalign = pn_leaf & (|req_buf.wb_entry.ppn[1: 0]);
    assign pn2_exception = pn_exception | pn2_unalign;
`endif

logic walk_state, wb_state;
    assign walk_state = 
`ifdef SV39
                        state == WALK_PN2 ||
`endif
                        state == WALK_PN1 || state == WALK_PN0;
    assign wb_state =
`ifdef SV39
                        state == WB_PN2 ||
`endif
                        state == WB_PN1 || state == WB_PN0;

    always_ff @(posedge clk)begin
        rlast <= axi_io.r_valid & axi_io.r_last;
        if(axi_io.r_valid & axi_io.r_ready)begin
            rdata[ridx] <= axi_io.r_data;
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            ridx <= 1'b0;
        end
        else begin
            if(axi_io.r_valid & axi_io.r_ready)begin
                ridx <= ridx + 1;
            end
        end
    end
    assign axi_io.ar_id = 0;
    assign axi_io.ar_valid = ar_valid;
    assign axi_io.ar_addr = {req_buf.paddr[`PADDR_SIZE-1: `DCACHE_LINE_WIDTH], {`DCACHE_LINE_WIDTH{1'b0}}};
    assign axi_io.ar_len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign axi_io.ar_size = $clog2(`DATA_BYTE);
    assign axi_io.ar_burst = 2'b01;
    assign axi_io.ar_user = 0;
    assign axi_io.ar_snoop = `ACEOP_READ_ONCE;
    assign axi_io.r_ready = 1'b1;

    assign ptw_io.waddr = wb_info.vaddr;
    assign ptw_io.info = wb_info.info;
    assign ptw_io.entry = wb_info.entry;
    always_comb begin
        case(state)
`ifdef SV39
        WB_PN2: begin
            ptw_io.wpn = 'b11;
            ptw_io.exception = pn2_exception;
            ptw_io.valid = (pn_leaf | pn2_exception) & ~flush_valid;
        end
`endif
        WB_PN1: begin
            ptw_io.wpn = 'b1;
            ptw_io.exception = pn1_exception;
            ptw_io.valid = (pn_leaf | pn1_exception) & ~flush_valid;
        end
        WB_PN0: begin
            ptw_io.wpn = 'b0;
            ptw_io.exception = pn_exception;
            ptw_io.valid = ~flush_valid;
        end
        default: begin
            ptw_io.wpn = 'b0;
            ptw_io.exception = 1'b0;
            ptw_io.valid = 0;
        end
        endcase
    end

    logic `N(`VADDR_SIZE) refill_vaddr;
    logic `N(`TLB_PN) refill_pn;
    logic wb_req;

    assign cache_ptw_io.full = pn0_io.full | pn1_io.full
`ifdef SV39
                                | pn2_io.full
`endif
    ;
    assign cache_ptw_io.refill_req = wb_req;
    assign cache_ptw_io.refill_pn = refill_pn;
    assign cache_ptw_io.refill_addr = refill_vaddr;
    assign cache_ptw_io.refill_data = rdata;

    always_ff @(posedge clk)begin
        if(rlast)begin
            refill_vaddr <= req_buf.vaddr;
            refill_pn <= {
`ifdef SV39
                state == WALK_PN2,
`endif
                state == WALK_PN1, state == WALK_PN0};
        end
    end

    assign flush_valid = flush | flush_q | fence_flush;
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            wb_req <= 0;
            flush_q <= 0;
            fence_flush_q <= 0;
            ptw_wb <= 1'b0;
        end
        else begin
            if(fence_flush | fence_flush_q)begin
                wb_req <= 1'b0;
            end
            else if(rlast)begin
                wb_req <= 1'b1;
            end
            else if(cache_ptw_io.refill_ready)begin
                wb_req <= 1'b0;
            end

            if(rlast & ~flush_valid)begin
                ptw_wb <= 1'b1;
            end
`ifdef SV39
            else if(state == WB_PN2 && !pn_leaf && !pn2_exception)begin
                ptw_wb <= 1'b0;
            end
`endif
            else if(state == WB_PN1 && !pn_leaf && !pn1_exception)begin
                ptw_wb <= 1'b0;
            end
            else if(!wb_state)begin
                ptw_wb <= 1'b0;
            end

            if(walk_state)begin
                if(flush | fence_flush)begin
                    flush_q <= 1'b1;
                end
                if(fence_flush)begin
                    fence_flush_q <= 1'b1;
                end
            end
            if(wb_state)begin
                flush_q <= 1'b0;
                fence_flush_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            wb_info <= 0;
        end
        else begin
            case(state)
`ifdef SV39
            WALK_PN2: begin
                if(rlast)begin
                    wb_info.vaddr <= req_buf.vaddr;
                    wb_info.info <= req_buf.info;
                    wb_info.valid <= 1'b1;
                    wb_info.entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(2) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WB_PN2: begin
                if(pn2_io.wb_valid & pn2_io.wb_ready)begin
                    wb_info.vaddr <= pn2_wb_data.vaddr;
                    wb_info.info <= pn2_wb_data.info;
                    wb_info.entry <= rdata[pn2_wb_data.vaddr[`TLB_VPN_BASE(2) +: `DCACHE_BANK_WIDTH]];
                end
            end 
`endif
            WALK_PN1: begin
                if(rlast)begin
                    wb_info.vaddr <= req_buf.vaddr;
                    wb_info.info <= req_buf.info;
                    wb_info.valid <= 1'b1;
                    wb_info.entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(1) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WB_PN1: begin
                if(pn1_io.wb_valid & pn1_io.wb_ready)begin
                    wb_info.vaddr <= pn1_wb_data.vaddr;
                    wb_info.info <= pn1_wb_data.info;
                    wb_info.entry <= rdata[pn1_wb_data.vaddr[`TLB_VPN_BASE(1) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WALK_PN0: begin
                if(rlast)begin
                    wb_info.vaddr <= req_buf.vaddr;
                    wb_info.info <= req_buf.info;
                    wb_info.valid <= 1'b1;
                    wb_info.entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(0) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WB_PN0: begin
                if(pn0_io.wb_valid & pn0_io.wb_ready)begin
                    wb_info.vaddr <= pn0_wb_data.vaddr;
                    wb_info.info <= pn0_wb_data.info;
                    wb_info.entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(0) +: `DCACHE_BANK_WIDTH]];
                end
            end
            default:begin
            end
            endcase
        end
    end

    // IDLE: select entry from pn0_buffer or pn1_buffer
    // WALK_PN1, WALK_PN0: lookup from memory
    // WB_PN1: writeback data in req_buf and pn1_buffer(if is leaf)
    //   1. if pn_leaf || pn1_exception, then writeback to lsu
    //   2. in ~pn_leaf & ~pn1_exception, write data to pn0_buffer
    //      if pn0_buffer is full, then switch state to WALK_PN0
    // WB_PN0: writeback data in req_buf and pn0_buffer

    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            req_buf <= '{default: 0};
            ar_valid <= 1'b0;
        end
        else begin
            if(axi_io.ar_ready)begin
                ar_valid <= 1'b0;
            end
            case(state)
            IDLE:begin
                if(flush | fence_flush)begin
                    
                end
`ifdef SV39
                else if(pn2_io.valid)begin
                    req_buf.vaddr <= pn2_data.vaddr;
                    req_buf.paddr <= {csr_io.ppn, pn2_data.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(2)], {`PTE_WIDTH{1'b0}}};
                    req_buf.info <= pn2_data.info;
                    state <= WALK_PN2;
                end
`endif
                else if(pn1_io.valid)begin
                    req_buf.vaddr <= pn1_data.vaddr;
`ifdef SV39
                    req_buf.paddr <= {pn1_data.ppn, pn1_data.vaddr[`TLB_VPN_BASE(1) +: `TLB_VPN], {`PTE_WIDTH{1'b0}}};
`else
                    req_buf.paddr <= {csr_io.ppn, pn1_data.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(1)], {`PTE_WIDTH{1'b0}}};
`endif
                    req_buf.info <= pn1_data.info;
                    state <= WALK_PN1;
                end
                else if(pn0_io.valid)begin
                    req_buf.vaddr <= pn0_data.vaddr;
                    req_buf.paddr <= {pn0_data.ppn, pn0_data.vaddr[`TLB_VPN_BASE(0) +: `TLB_VPN], {`PTE_WIDTH{1'b0}}};
                    req_buf.info <= pn0_data.info;
                    state <= WALK_PN0;
                end

                if((pn1_io.valid | pn0_io.valid
`ifdef SV39
                    | pn2_io.valid
`endif
                ) & ~flush & ~fence_flush)begin
                    ar_valid <= 1'b1;
                end
            end
`ifdef SV39
            WALK_PN2: begin
                if(rlast)begin
                    state <= WB_PN2;
                    req_buf.wb_entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(2) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WB_PN2: begin
                if(flush_valid)begin
                    state <= IDLE;
                end
                else if(pn2_io.wb_valid & ~(~pn_leaf & ~pn2_exception & pn1_io.full))begin
                end
                else if(pn_leaf | pn2_exception)begin
                    if(ptw_io.ready)begin
                        state <= IDLE;
                    end
                end
                else begin
                    req_buf.paddr <= {req_buf.wb_entry.ppn, req_buf.vaddr`TLB_VPN_BUS(1), {`PTE_WIDTH{1'b0}}};
                    ar_valid <= 1'b1;
                    state <= WALK_PN1;
                end
            end
`endif
            WALK_PN1: begin
                if(rlast)begin
                    state <= WB_PN1;
                    req_buf.wb_entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(1) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WB_PN1: begin
                if(flush_valid)begin
                    state <= IDLE;
                end
                else if(pn1_io.wb_valid & ~(~pn_leaf & ~pn1_exception & pn0_io.full))begin
                end
                else if(pn_leaf | pn1_exception)begin
                    if(ptw_io.ready)begin
                        state <= IDLE;
                    end
                end
                else begin
                    req_buf.paddr <= {req_buf.wb_entry.ppn, req_buf.vaddr`TLB_VPN_BUS(0), {`PTE_WIDTH{1'b0}}};
                    ar_valid <= 1'b1;
                    state <= WALK_PN0;
                end
            end
            WALK_PN0: begin
                if(rlast)begin
                    state <= WB_PN0;
                    req_buf.wb_entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(0) +: `DCACHE_BANK_WIDTH]];
                end
            end
            WB_PN0: begin
                if(flush_valid | ~pn0_io.wb_valid & ptw_io.ready)begin
                    state <= IDLE;
                end
            end
            endcase
        end
    end

    `PERF(ptw_miss, axi_io.ar_valid & axi_io.ar_ready)
endmodule

interface PTBufferIO #(
    parameter TAG_WIDTH=10,
    parameter DATA_WIDTH=10
);
    logic en;
    logic `N(TAG_WIDTH) tag;
    logic `N(DATA_WIDTH) data;
    logic data_valid;
    logic `N(TAG_WIDTH) ctag;
    logic flush;

    logic full;
    logic valid;
    logic ready;
    logic `N(TAG_WIDTH + DATA_WIDTH) data_o;
    logic wb_valid;
    logic wb_ready;
    logic `N(TAG_WIDTH + DATA_WIDTH) wb_data;

    modport buffer (input en, ready, data_valid, tag, ctag, flush, data, wb_ready, output full, valid, data_o, wb_valid, wb_data);
endinterface

module PTBuffer #(
    parameter TAG_WIDTH=10,
    parameter DATA_WIDTH=10,
    parameter DEPTH=8,
    parameter MULTI=0,
    parameter ADDR_WIDTH=$clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    PTBufferIO.buffer io
);
    logic `N(DEPTH) en;
    logic `N(TAG_WIDTH) tag `N(DEPTH);
    logic `N(DATA_WIDTH) data `N(DEPTH);
    
    logic `N(ADDR_WIDTH) free_idx;
    logic `N(ADDR_WIDTH) wb_idx;

    assign io.full = &en;
    PEncoder #(DEPTH) encoder_free(~en, free_idx);

    logic `N(ADDR_WIDTH) valid_idx;
    assign io.valid = |(en);
    PEncoder #(DEPTH) encoder_valid ((en), valid_idx);
    assign io.data_o = {tag[valid_idx], data[valid_idx]};

    always_ff @(posedge clk)begin
        if(io.en)begin
            tag[free_idx] <= io.tag;
            data[free_idx] <= io.data;
        end
    end


generate
    if(MULTI)begin
        logic `N(DEPTH) data_valid, wb_valid;
        logic `N(DEPTH) tag_cmp;
        logic `N(DEPTH) select_idx_dec;

        for(genvar i=0; i<DEPTH; i++)begin
            assign tag_cmp[i] = en[i] & (tag[i] == io.ctag);
        end
        assign io.wb_valid = |data_valid;
        PSelector #(DEPTH) selector_wb_valid (data_valid, wb_valid);
        Encoder #(DEPTH) encoder_wb_idx (wb_valid, wb_idx);
        assign io.wb_data = {tag[wb_idx], data[wb_idx]};
        always_ff @(posedge clk, negedge rst)begin
            if(rst == `RST)begin
                data_valid <= 0;
                en <= 0;
            end
            else if(io.flush)begin
                data_valid <= 0;
                en <= 0;
            end
            else begin
                if(io.en)begin
                    en[free_idx] <= 1'b1;
                end
                if(io.valid & io.ready)begin
                    en[valid_idx] <= 1'b0;
                end
                if(io.wb_valid & io.wb_ready)begin
                    en[wb_idx] <= 1'b0;
                end

                for(int i=0; i<DEPTH; i++)begin
                    data_valid[i] <= (data_valid[i] & ~io.data_valid | io.data_valid & tag_cmp[i]) &
                                  ~(io.wb_ready & wb_valid[i]);
                end 
            end
        end
    end
    else begin
        always_ff @(posedge clk)begin
            if(io.valid & io.ready)begin
                wb_idx <= valid_idx;
            end
        end
        always_ff @(posedge clk or negedge rst)begin
            if(rst == `RST)begin
                en <= 0;
            end
            else if(io.flush)begin
                en <= 0;
            end
            else begin
                if(io.en)begin
                    en[free_idx] <= 1'b1;
                end
                if(io.valid & io.ready)begin
                    en[valid_idx] <= 1'b0;
                end
            end
        end
    end
endgenerate

endmodule