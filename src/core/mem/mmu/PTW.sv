`include "../../../defines/defines.svh"

interface PTWL2IO;
    logic valid;
    logic ready;
    logic exception;
    logic exc_static;
    TLBInfo info;
    PTEEntry entry;
    logic `N(`TLB_VPN_SIZE) waddr;
    logic `N(`TLB_PN) wpn;

    modport ptw (output valid, exception, exc_static, info, entry, waddr, wpn, input ready);
endinterface

module PTW(
    input logic clk,
    input logic rst,
    input logic fence_flush,
    CachePTWIO.ptw cache_ptw_io,
    CsrL2IO.tlb csr_io,
    CacheBus.masterr axi_io,
    PTWL2IO.ptw ptw_io
);

    typedef struct packed {
        logic `N(`TLB_PN) wpn;
        logic `N(`TLB_PN) conflict_pn;
        logic `N(`TLB_PPN) paddr;
    } PTWEntry;
    logic `N(`PTW_SIZE) en, waiting;
    PTWEntry `N(`PTW_SIZE) entrys;
    VPNAddr `N(`PTW_SIZE) vaddrs;
    TLBInfo `N(`PTW_SIZE) infos;
    PTWEntry entry_i, entry_w;
    logic `N(`PTW_WIDTH) free_idx;
    logic `N($clog2(`TLB_PN)) last_pn_idx;
    logic `N(`TLB_PN) cache_pn_mask;

    VPNAddr cache_vaddr;
    logic `ARRAY(`PTW_SIZE, `TLB_PN) pn_conflicts;
    logic `N(`TLB_PN) pn_conflict, pn_conflict_sel;
    logic `N(`PTW_SIZE) pn_same;

    
    logic `N(`PTW_SIZE) lookup_reqs;
    logic `N(`PTW_WIDTH) lookup_idx;
    PTWEntry lookup_entry;
    logic `N(`TLB_PN) lookup_pn, wpn_sel, lookup_pn_mask;
    logic `N($clog2(`TLB_PN)) lookup_pn_idx;
    VPNAddr lookup_vaddr, lookup_vaddr_p;
    logic `N(`PADDR_SIZE) lookup_paddr;

    typedef enum  { IDLE, LOOKUP, REFILL } RefillState;
    RefillState refill_state;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) rdata;
    logic `N($clog2(`DCACHE_BANK)) ridx;
    logic rlast, wvalid;
    logic `N(`PTW_SIZE) wvalids;
    PTWEntry wb_entry;
    logic `N(`PTW_WIDTH) wb_idx, wb_idx_n;
    logic `N($clog2(`TLB_PN)) wpn_idx;
    logic `N(`PTW_SIZE) wb_idx_dec;
    logic `N(`TLB_PN) pn_unalign, wpn;
    VPNAddr wb_vaddr;
    TLBInfo wb_info;
    PTEEntry wb_pte;
    logic wb_ready, wb_exception;
    logic `N(`DCACHE_BANK_WIDTH) wb_offset;
    logic pn_exception, pn_exc_static, pn_leaf;
    logic flush_q;

    assign cache_vaddr = cache_ptw_io.vaddr;
    PEncoder #(`PTW_SIZE) encoder_free_idx (~en, free_idx);
generate
    for(genvar i=0; i<`PTW_SIZE; i++)begin
        logic `N(`TLB_PN) pn_equal, pn_equal_cmb;
        for(genvar j=0; j<`TLB_PN; j++)begin
            assign pn_equal[j] = cache_vaddr.vpn[j] == vaddrs[i].vpn[j];
            assign pn_equal_cmb[j] = &pn_equal[`TLB_PN-1: j];
            assign pn_conflicts[i][j] = en[i] & entrys[i].wpn[j] & pn_equal_cmb[j];
        end
        assign pn_same[i] = en[i] & (&pn_equal) & (infos[i].source == cache_ptw_io.info.source);
    end
    for(genvar i=0; i<`TLB_PN; i++)begin
        assign lookup_pn_mask[i] = |lookup_pn[i: 0];
    end
    ParallelOR #(`TLB_PN, `PTW_SIZE) or_pn_conflicts(pn_conflicts, pn_conflict);
    PRSelector #(`TLB_PN) selector_pn_conflict (pn_conflict, pn_conflict_sel);
endgenerate

    PREncoder #(`TLB_PN) encoder_last_pn (cache_ptw_io.valid, last_pn_idx);
    MaskGen #(`TLB_PN) maskgen_cache_pn (last_pn_idx, cache_pn_mask);
    assign cache_ptw_io.full = &en;
    assign entry_i.wpn = {`TLB_PN{~(|cache_ptw_io.valid)}} | cache_pn_mask;
    assign entry_i.conflict_pn = pn_conflict_sel;
    assign entry_i.paddr = |cache_ptw_io.valid ? cache_ptw_io.paddr[last_pn_idx][`PADDR_SIZE-1: `TLB_OFFSET] : csr_io.ppn;

    assign entry_w.wpn = wb_entry.wpn & ~lookup_pn_mask;
    assign entry_w.conflict_pn = wb_entry.conflict_pn & ~lookup_pn;
    assign entry_w.paddr = wb_pte.ppn;

    always_ff @(posedge clk)begin
        if(cache_ptw_io.req & ~cache_ptw_io.full & ~(|pn_same))begin
            entrys[free_idx] <= entry_i;
            vaddrs[free_idx] <= cache_ptw_io.vaddr;
            infos[free_idx] <= cache_ptw_io.info;
        end
        if(wvalid & wb_ready)begin
            entrys[wb_idx_n] <= entry_w;
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            waiting <= 0;
        end
        else if(fence_flush)begin
            en <= 0;
        end
        else begin
            if(cache_ptw_io.req & ~cache_ptw_io.full & ~(|pn_same))begin
                en[free_idx] <= 1'b1;
                waiting[free_idx] <= |pn_conflicts;
            end

            if(wvalid & wb_ready)begin
                en[wb_idx_n] <= ~(pn_leaf | wb_exception);
                waiting[wb_idx_n] <= waiting[wb_idx_n] & ~(|(wb_entry.conflict_pn & lookup_pn));
            end
        end
    end

    assign lookup_reqs = en & ~waiting & {`PTW_SIZE{refill_state == IDLE}};
    PEncoder #(`PTW_SIZE) encoder_lookup_idx (lookup_reqs, lookup_idx);
    PSelector #(`PTW_SIZE) select_wpn (lookup_entry.wpn, wpn_sel);
    PEncoder #(`PTW_SIZE) select_lookup_pn (lookup_entry.wpn, lookup_pn_idx);
    assign lookup_entry = entrys[lookup_idx];
    assign lookup_vaddr_p = vaddrs[lookup_idx];
    assign lookup_paddr = {lookup_entry.paddr, lookup_vaddr_p.vpn[lookup_pn_idx], {`PTE_WIDTH{1'b0}}};
    assign axi_io.ar_id = lookup_idx;
    assign axi_io.ar_valid = (|lookup_reqs) & ~fence_flush;
    assign axi_io.ar_addr = {lookup_paddr[`PADDR_SIZE-1: `DCACHE_LINE_WIDTH], {`DCACHE_LINE_WIDTH{1'b0}}};
    assign axi_io.ar_len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign axi_io.ar_size = $clog2(`DATA_BYTE);
    assign axi_io.ar_burst = 2'b01;
    assign axi_io.ar_user = 0;
    assign axi_io.ar_snoop = `ACEOP_READ_ONCE;
    assign axi_io.r_ready = 1'b1;

    assign cache_ptw_io.refill_req = rlast & ~fence_flush & ~flush_q;
    assign cache_ptw_io.refill_pn = lookup_pn;
    assign cache_ptw_io.refill_addr = lookup_vaddr;
    assign cache_ptw_io.refill_data = rdata;

    assign pn_unalign[0] = 0;
    assign pn_unalign[1] = pn_leaf & (|wb_pte.ppn.ppn0);
`ifdef SV39
    assign pn_unalign[2] = pn_leaf & ((|wb_pte.ppn.ppn1) | (|wb_pte.ppn.ppn0));
`endif
generate
    for(genvar i=0; i<`PTW_SIZE; i++)begin
        logic `N(`TLB_PN) pn_equal, pn_bank_equal, pn_equal_cmb;
        for(genvar j=0; j<`TLB_PN; j++)begin
            assign pn_equal[j] = lookup_vaddr.vpn[j] == vaddrs[i].vpn[j];
            assign pn_bank_equal[j] = lookup_vaddr.vpn[j][`TLB_VPN - 1 :`DCACHE_BANK_WIDTH] ==
                                      vaddrs[i].vpn[j][`TLB_VPN  - 1 : `DCACHE_BANK_WIDTH];
            if(j < `TLB_PN-1)begin
                assign pn_equal_cmb[j] = (&pn_equal[`TLB_PN-1: j+1]) & pn_bank_equal[j] & entrys[i].wpn[j];
            end
            else begin
                assign pn_equal_cmb[j] = pn_bank_equal[j] & entrys[i].wpn[j];
            end
        end
        assign wvalids[i] = en[i] & (|(pn_equal_cmb & lookup_pn)) & 
                            ~(wb_idx_dec[i] & wvalid & wb_ready);
    end
endgenerate
    PEncoder #(`PTW_SIZE) encoder_wb_idx (wvalids, wb_idx);
    Decoder #(`PTW_SIZE) decoder_wb_idx (wb_idx_n, wb_idx_dec);
    TLBExcDetect exc_detect (wb_pte, wb_info.source, csr_io.mxr, csr_io.sum, csr_io.mprv, csr_io.mpp, csr_io.mode, pn_exception, pn_exc_static);
    Encoder #(`TLB_PN) encoder_wpn (lookup_pn, wpn_idx);
    MaskGen #(`TLB_PN) maskgen_wpn (wpn_idx, wpn);
    assign wb_offset = vaddrs[wb_idx].vpn[wpn_idx][`DCACHE_BANK_WIDTH-1:0];
    assign pn_leaf = wb_pte.r | wb_pte.w | wb_pte.x;
    assign wb_ready = ~pn_leaf | ptw_io.ready;
    assign wb_exception = |(({`TLB_PN{pn_exception}} | pn_unalign) & lookup_pn);

    assign ptw_io.valid = wvalid & (pn_leaf | wb_exception);
    assign ptw_io.exception = wb_exception;
    assign ptw_io.exc_static = |(({`TLB_PN{pn_exc_static}} | pn_unalign) & lookup_pn);
    assign ptw_io.info = wb_info;
    assign ptw_io.entry = wb_pte;
    assign ptw_io.waddr = wb_vaddr;
    assign ptw_io.wpn = wpn;

    always_ff @(posedge clk)begin
        if(axi_io.r_valid & axi_io.r_ready)begin
            rdata[ridx] <= axi_io.r_data;
        end
        rlast <= axi_io.r_valid & axi_io.r_ready & axi_io.r_last;
        if(|wvalids)begin
            wb_idx_n <= wb_idx;
            wb_entry <= entrys[wb_idx];
            wb_vaddr <= vaddrs[wb_idx];
            wb_info <= infos[wb_idx];
            wb_pte <= rdata[wb_offset];
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            refill_state <= IDLE;
            ridx <= 0;
            wvalid <= 0;
            lookup_vaddr <= 0;
            lookup_pn <= 0;
            flush_q <= 0;
        end
        else begin
            if(axi_io.r_valid & axi_io.r_ready)begin
                ridx <= ridx + 1;
            end
            case(refill_state)
            IDLE:begin
                if(axi_io.ar_valid & axi_io.ar_ready & ~fence_flush)begin
                    refill_state <= LOOKUP;
                    lookup_vaddr <= vaddrs[lookup_idx];
                    lookup_pn <= wpn_sel;
                end
            end
            LOOKUP:begin
                if(axi_io.r_valid & axi_io.r_ready & axi_io.r_last)begin
                    refill_state <= REFILL;
                end
                if(fence_flush)begin
                    flush_q <= 1'b1;
                end
            end
            REFILL:begin
                if(fence_flush | flush_q)begin
                    refill_state <= IDLE;
                    flush_q <= 1'b0;
                end
                wvalid <= (|wvalids) & ~fence_flush & ~flush_q;
                if(~(|wvalids))begin
                    refill_state <= IDLE;
                end
            end
            endcase
        end
    end
endmodule