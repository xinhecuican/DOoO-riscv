`include "../../defines/defines.svh"

interface PTWL2IO;
    logic valid;
    logic ready;
    logic exception;
    TLBInfo info;
    PTEEntry entry;
    logic `N(`VADDR_SIZE) waddr;
    logic `N(2) wpn;

    modport ptw (output valid, exception, info, entry, waddr, wpn, input ready);
endinterface

module PTW(
    input logic clk,
    input logic rst,
    input logic flush,
    CachePTWIO.ptw cache_ptw_io,
    CsrL2IO.tlb csr_io,
    AxiIO.masterr axi_io,
    PTWL2IO.ptw ptw_io
);
    typedef enum  { IDLE, WALK_PN1, WB_PN1, WALK_PN0, WB_PN0 } State;
`ifdef DIFFTEST
    typedef struct packed {
`else
    typedef struct {
`endif
        logic `N(`PADDR_SIZE) paddr;
        logic `N(`VADDR_SIZE) vaddr;
        TLBInfo info;
        logic wb_valid;
        PTEEntry wb_entry;
    } RequestBuffer;
    State state;
    RequestBuffer req_buf;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) rdata;
    logic `N($clog2(`DCACHE_BANK)) ridx;
    logic rlast;

    logic pn1_exception, pn0_exception;
    logic pn1_leaf;
    logic `N(`PADDR_SIZE) wb_addr;

    localparam PN0_TAG_SIZE = `TLB_VPN * `TLB_PN - $clog2(`TLB_P0_BANK);
    localparam PN0_BIT_SIZE = `VADDR_SIZE + $bits(TLBInfo) + `PADDR_SIZE;
    PTBufferIO #(
        .TAG_WIDTH(PN0_TAG_SIZE),
        .DATA_WIDTH(PN0_BIT_SIZE - PN0_TAG_SIZE)
    ) pn0_io();
    PTBuffer #(
        .TAG_WIDTH(`TLB_VPN * `TLB_PN),
        .DATA_WIDTH($bits(TLBInfo) + `TLB_OFFSET + `PADDR_SIZE),
        .DEPTH(`TLB_PTB0_SIZE),
        .MULTI(1)
    ) pn0_buffer (.*, .io(pn0_io));

    localparam PN1_TAG_SIZE = `TLB_VPN * (`TLB_PN - 1) - $clog2(`TLB_P1_BANK);
    localparam PN1_BIT_SIZE = `VADDR_SIZE + $bits(TLBInfo);
    PTBufferIO #(
        .TAG_WIDTH(PN1_TAG_SIZE),
        .DATA_WIDTH(PN1_BIT_SIZE - PN1_TAG_SIZE)
    ) pn1_io();
    PTBuffer #(
        .TAG_WIDTH(`TLB_VPN * (`TLB_PN - 1)),
        .DATA_WIDTH($bits(TLBInfo) + `TLB_OFFSET + `TLB_VPN),
        .DEPTH(`TLB_PTB1_SIZE)
    ) pn1_buffer (.*, .io(pn1_io));

    assign pn0_io.flush = flush;
    assign pn0_io.en = cache_ptw_io.req & cache_ptw_io.valid[1] |
                       (state == WB_PN1 && (~pn1_leaf & ~pn1_exception & ~pn0_io.full));
    assign pn0_io.tag = cache_ptw_io.req & cache_ptw_io.valid[1] ? cache_ptw_io.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(0)+`DCACHE_BANK_WIDTH] :
                        req_buf.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(0)+`DCACHE_BANK_WIDTH];
    assign pn0_io.data = cache_ptw_io.req & cache_ptw_io.valid[1] ? {cache_ptw_io.vaddr[`TLB_OFFSET+`DCACHE_BANK_WIDTH-1: 0], cache_ptw_io.info, cache_ptw_io.paddr[1]} :
                         {req_buf.vaddr[`TLB_OFFSET+`DCACHE_BANK_WIDTH-1: 0], cache_ptw_io.info, wb_addr};
    assign pn0_io.data_valid = rlast && (state == WALK_PN0);
    assign pn0_io.ctag = req_buf.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(0)+`DCACHE_BANK_WIDTH];
    assign pn0_io.wb_ready = (state == WB_PN0) & ptw_io.valid & ptw_io.ready;

    assign pn1_io.flush = flush;
    assign pn1_io.en = cache_ptw_io.req & (~cache_ptw_io.valid[1] & ~cache_ptw_io.valid[0]);
    assign pn1_io.tag = cache_ptw_io.vaddr[`VADDR_SIZE-1: `TLB_VPN_BASE(1)+`DCACHE_BANK_WIDTH];
    assign pn1_io.data = {cache_ptw_io.vaddr[`TLB_VPN_BASE(1)+`DCACHE_BANK_WIDTH-1: 0], cache_ptw_io.info};
    assign pn1_io.data_valid = rlast && (state == WALK_PN1);
    assign pn1_io.ready = state == IDLE;

    always_ff @(posedge clk)begin
        rlast <= axi_io.r_valid & axi_io.r_last;
        if(axi_io.r_valid & axi_io.r_ready)begin
            rdata[ridx] <= axi_io.r_data;
        end
    end
    always_ff @(posedge clk, posedge rst)begin
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
    assign axi_io.ar_addr = req_buf.paddr;
    assign axi_io.ar_len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign axi_io.ar_size = $clog2(`DATA_BYTE);
    assign axi_io.ar_burst = 2'b01;
    assign axi_io.ar_lock = 2'b00;
    assign axi_io.ar_cache = 4'b0;
    assign axi_io.ar_prot = 3'b0;
    assign axi_io.ar_qos = 0;
    assign axi_io.ar_region = 0;
    assign axi_io.ar_user = 0;
    assign axi_io.r_ready = 1'b1;

    assign pn1_leaf = req_buf.wb_entry.r | req_buf.wb_entry.w | req_buf.wb_entry.x;
    PAddrGen gen_wb_addr (req_buf.wb_entry, req_buf.vaddr, wb_addr);

    logic pn1_unalign;
    assign pn1_unalign = pn1_leaf & (|req_buf.wb_entry.ppn[0]);
    TLBExcDetect exc_detect1 (req_buf.wb_entry, req_buf.info.source, csr_io.mxr, csr_io.sum, csr_io.mode, pn0_exception);
    assign pn1_exception = pn0_exception | pn1_unalign;

    assign ptw_io.waddr = req_buf.vaddr;
    assign ptw_io.info = req_buf.info;
    assign ptw_io.entry = req_buf.wb_entry;
    always_comb begin
        case(state)
        WB_PN1: begin
            ptw_io.wpn = 2'b01;
            ptw_io.exception = pn1_exception;
            ptw_io.valid = pn1_leaf | pn1_exception;
        end
        WB_PN0: begin
            ptw_io.wpn = 2'b00;
            ptw_io.exception = pn0_exception;
            ptw_io.valid = req_buf.wb_valid;
        end
        default: begin
            ptw_io.wpn = 2'b00;
            ptw_io.exception = 1'b0;
            ptw_io.valid = 0;
        end
        endcase
    end

    logic `N(`VADDR_SIZE) refill_vaddr;
    logic `N(`TLB_PN) refill_pn;
    logic wb_req, refill_data_valid;
    logic ar_valid;
    assign cache_ptw_io.full = pn0_io.full | pn1_io.full;
    assign cache_ptw_io.refill_req = wb_req;
    assign cache_ptw_io.refill_pn = refill_pn;
    assign cache_ptw_io.refill_addr = refill_vaddr;
    assign cache_ptw_io.refill_data = rdata;

    always_ff @(posedge clk)begin
        refill_data_valid <= rlast;
        if(rlast)begin
            refill_vaddr <= req_buf.vaddr;
            refill_pn <= {state == WALK_PN1, state == WALK_PN0};
        end
    end

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            wb_req <= 0;
        end
        else begin
            if(refill_data_valid &&
              ((state == WB_PN1 && !pn1_exception) ||
               (state == WB_PN0 && !pn0_exception)))begin
                wb_req <= 1'b1;
            end
            else if(cache_ptw_io.refill_ready)begin
                wb_req <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            req_buf <= '{default: 0};
            ar_valid <= 1'b0;
        end
        else if(flush)begin
            state <= IDLE;
            ar_valid <= 1'b0;
        end
        else begin
            case(state)
            IDLE:begin
                if(pn1_io.valid)begin
                    req_buf.vaddr <= pn1_io.data_o[PN1_BIT_SIZE-1: PN1_BIT_SIZE - `VADDR_SIZE];
                    req_buf.paddr <= {csr_io.ppn, {`TLB_OFFSET-`TLB_VPN-2{1'b0}}, pn1_io.data_o[PN1_BIT_SIZE-1: PN1_BIT_SIZE - `TLB_VPN], 2'b00};
                    req_buf.info <= pn1_io.data_o[$bits(TLBInfo)-1: 0];
                    state <= WALK_PN1;
                end
                else if(pn0_io.valid)begin
                    req_buf.vaddr <= pn0_io.data_o[PN0_BIT_SIZE-1: PN0_BIT_SIZE - `VADDR_SIZE];
                    req_buf.paddr <= pn0_io.data_o[`PADDR_SIZE-1: 0];
                    req_buf.info <= pn0_io.data_o[`PADDR_SIZE+$bits(TLBInfo)-1: `PADDR_SIZE];
                    state <= WALK_PN0;
                end

                if(pn1_io.valid | pn0_io.valid)begin
                    ar_valid <= 1'b1;
                end
                req_buf.wb_valid <= 1'b0;
            end
            WALK_PN1: begin
                if(axi_io.ar_ready)begin
                    ar_valid <= 1'b0;
                end
                if(rlast)begin
                    state <= WB_PN1;
                    req_buf.wb_entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(1)+`DCACHE_BANK_WIDTH-1: `TLB_VPN_BASE(1)]];
                end
            end
            WB_PN1: begin
                if(pn1_leaf | pn1_exception)begin
                    if(ptw_io.ready)begin
                        state <= IDLE;
                    end
                end
                else if(~(cache_ptw_io.req & cache_ptw_io.valid[1]) & ~pn0_io.full)begin
                    req_buf.vaddr <= pn0_io.data_o[PN0_BIT_SIZE-1: PN0_BIT_SIZE - `VADDR_SIZE];
                    req_buf.paddr <= pn0_io.data_o[`PADDR_SIZE-1: 0];
                    req_buf.info <= pn0_io.data_o[`PADDR_SIZE+$bits(TLBInfo)-1: `PADDR_SIZE];
                    ar_valid <= 1'b1;
                    state <= WALK_PN0;
                end
            end
            WALK_PN0: begin
                if(axi_io.ar_ready)begin
                    ar_valid <= 1'b0;
                end
                if(rlast)begin
                    state <= WB_PN0;
                    req_buf.wb_entry <= rdata[req_buf.vaddr[`TLB_VPN_BASE(1)+`DCACHE_BANK_WIDTH-1: `TLB_VPN_BASE(1)]];
                end
            end
            WB_PN0: begin
                if(pn0_io.wb_valid & ptw_io.ready)begin
                    req_buf.wb_valid <= 1'b1;
                    req_buf.vaddr <= pn0_io.wb_data[PN0_BIT_SIZE-1: PN0_BIT_SIZE - `VADDR_SIZE];
                    req_buf.paddr <= pn0_io.wb_data[`PADDR_SIZE-1: 0];
                    req_buf.info <= pn0_io.wb_data[`PADDR_SIZE+$bits(TLBInfo)-1: `PADDR_SIZE];
                    req_buf.wb_entry <= rdata[pn0_io.wb_data[PN0_BIT_SIZE-PN0_TAG_SIZE-1: PN0_BIT_SIZE-PN0_TAG_SIZE-`DCACHE_BANK_WIDTH]];
                end
                if(~pn0_io.wb_valid & req_buf.wb_valid & ptw_io.ready)begin
                    req_buf.wb_valid <= 1'b0;
                end
                if(~pn0_io.wb_valid & ~req_buf.wb_valid)begin
                    state <= IDLE;
                end
            end
            endcase
        end
    end
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
        logic `N(DEPTH) data_valid;
        logic `N(DEPTH) tag_cmp;
        logic `N(DEPTH) valid_idx_decode;

        Decoder #(DEPTH) decoder_valid_idx (valid_idx, valid_idx_decode);

        for(genvar i=0; i<DEPTH; i++)begin
            assign tag_cmp[i] = en[i] & (tag[i] == io.ctag);
        end
        assign io.wb_valid = |data_valid;
        PEncoder #(DEPTH) encoder_wb_idx (data_valid, wb_idx);
        assign io.wb_data = {tag[wb_idx], data[wb_idx]};
        always_ff @(posedge clk, posedge rst)begin
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
                if(io.data_valid)begin
                    data_valid <= tag_cmp & ~valid_idx_decode;
                end
                if(io.wb_valid & io.wb_ready)begin
                    data_valid[wb_idx] <= 1'b0;
                    en[wb_idx] <= 1'b0;
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
        always_ff @(posedge clk or posedge rst)begin
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
                if(io.data_valid)begin
                    en[wb_idx] <= 1'b0;
                end
            end
        end
    end
endgenerate

endmodule