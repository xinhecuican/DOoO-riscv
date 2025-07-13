`include "../../../defines/defines.svh"

interface TLBIO #(
    parameter DEPTH=16,
    parameter ADDR_WIDTH=$clog2(DEPTH)
);
    logic req;
    logic `VADDR_BUS vaddr;
    logic flush;
    logic [`TLB_PN-1: 0][1: 0] sel;
    VPNAddr sel_tag;

    logic miss;
    logic uncache;
    logic exception;
    logic `PADDR_BUS paddr;

    logic we;
    logic wen;
    logic wexc_static;
    logic `N(ADDR_WIDTH) widx;
    TLBInfo wbInfo;
    PTEEntry wentry;
    logic `N(2) wpn;
    logic `N(`TLB_VPN_SIZE) waddr;

    modport tlb(input req, flush, vaddr, sel, sel_tag, we, wen, wexc_static, wbInfo, wentry, wpn, widx, waddr, output miss, uncache, exception, paddr);
endinterface

module TLB #(
    parameter DEPTH=16,
    parameter SOURCE=0,
    parameter [1: 0] MODE=2'b00, //2'b00: x, 2'b01: r, 2'b10: w
    parameter SELV = 0,
    parameter FENCEV = MODE == 2'b00,
    parameter ADDR_WIDTH=$clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    TLBIO.tlb   io,
    CsrTlbIO.tlb csr_tlb_io,
    FenceBus.mmu fenceBus
);
    L1TLBEntry `N(DEPTH) entrys;
    L1TLBEntry hit_entry;
    logic `N(DEPTH) en;
    logic pmp_v, pmp_r, pmp_w, pmp_x, pma_uc;
    logic `N(`PADDR_SIZE-`TLB_OFFSET) pma_addr;

    typedef enum  { IDLE, FENCE, FENCE_END } FenceState;
    FenceState fenceState;
    logic fenceReq, fenceWe;
    logic `N(ADDR_WIDTH) fenceIdx, widx, fenceAllIdx;
    logic `N(`VADDR_SIZE-`TLB_OFFSET) fenceVaddr;
    logic `N(`TLB_ASID) fence_asid;
    logic fence_asid_all, fence_addr_all;

// lookup
    logic `N(DEPTH) hit;
    logic `N(DEPTH) asid_hit;
    logic `N(ADDR_WIDTH) hit_idx;
    logic mode_exc;
    logic `ARRAY(DEPTH, `TLB_PN) pn_hits, sel_pn_hits_n, sel_pn_hits_p;
    logic `N(`TLB_PN) hit_mask;
    logic `ARRAY(DEPTH, $bits(L1TLBEntry)+`TLB_PN) mask_entry;
    VPNAddr `N(DEPTH) sel_vaddrs_n, sel_vaddrs_p;
    VPNAddr sel_wvaddrs_n, sel_wvaddrs_p;
    logic `N(DEPTH) pn_hit;
    VPNAddr lookup_addr;
    PPNAddr lookup_paddr;
    logic lookup_hit;
    logic mmode;
    logic `N(`TLB_ASID) lookup_asid;
generate
    if(FENCEV)begin
        assign lookup_addr = fenceReq ? fenceVaddr : io.vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
        assign lookup_asid = fenceReq ? fence_asid : csr_tlb_io.asid;
    end
    else begin
        assign lookup_addr = io.vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
        assign lookup_asid = csr_tlb_io.asid;
    end
endgenerate
    assign mmode = (csr_tlb_io.mode == 2'b11) | (csr_tlb_io.satp_mode == 0);
generate
    for(genvar i=0; i<DEPTH; i++)begin
        if(FENCEV)begin
            assign asid_hit[i] = en[i] & (entrys[i].asid == lookup_asid || entrys[i].g || fenceReq && fence_asid_all);
        end
        else begin
            assign asid_hit[i] = en[i] & (entrys[i].asid == lookup_asid || entrys[i].g);
        end
        // assign asid_hit[i] = en[i];
        for(genvar j=0; j<`TLB_PN; j++)begin
            if(SELV)begin
                assign sel_pn_hits_p[i][j] = sel_vaddrs_p[i].vpn[j] == io.sel_tag.vpn[j];
                assign sel_pn_hits_n[i][j] = sel_vaddrs_n[i].vpn[j] == io.sel_tag.vpn[j];
                assign pn_hits[i][j] = io.sel[j][1] ? sel_pn_hits_p[i][j] : 
                        io.sel[j][0] ? sel_pn_hits_n[i][j] : entrys[i].vpn.vpn[j] == io.sel_tag.vpn[j];
            end
            else begin
                assign pn_hits[i][j] = entrys[i].vpn.vpn[j] == lookup_addr.vpn[j];
            end
        end
        if(FENCEV)begin
            assign pn_hit[i] = (&(pn_hits[i] | entrys[i].size)) | fenceReq & fence_addr_all;
        end
        else begin
            assign pn_hit[i] = (&(pn_hits[i] | entrys[i].size));
        end
        assign mask_entry[i] = {entrys[i], entrys[i].size};
    end
    // if(SOURCE == 2'b00)begin
    //     PEncoder #(DEPTH) encoder_hit (hit, hit_idx);
    // end
    // else begin
        Encoder #(DEPTH) encoder_hit (hit, hit_idx);
    // end
endgenerate
    assign hit = asid_hit & pn_hit;
    FairSelect #(DEPTH, $bits(L1TLBEntry)+`TLB_PN) select_hit (hit, mask_entry, lookup_hit, {hit_entry, hit_mask});

`define L1_PPN_ASSIGN(i) assign lookup_paddr.ppn``i = hit_mask[i] ? lookup_addr.vpn[``i] : hit_entry.ppn.ppn``i;

    `L1_PPN_ASSIGN(0)
    `L1_PPN_ASSIGN(1)
`ifdef SV39
    `L1_PPN_ASSIGN(2)
`endif
generate
    if(MODE == 2'b10)begin
        assign mode_exc = ((csr_tlb_io.mode == 2'b01) & ~csr_tlb_io.sum & hit_entry.u) |
                                ((csr_tlb_io.mode == 2'b00) & ~hit_entry.u) |
                                (~hit_entry.r & ~(hit_entry.x & csr_tlb_io.mxr)) |
                                ~hit_entry.d | hit_entry.exc;
    end
    else if(MODE == 2'b01)begin
        assign mode_exc = ((csr_tlb_io.mode == 2'b01) & ~csr_tlb_io.sum & hit_entry.u) |
                                ((csr_tlb_io.mode == 2'b00) & ~hit_entry.u) |
                                (~hit_entry.r & ~(hit_entry.x & csr_tlb_io.mxr)) |
                                hit_entry.exc;
    end
    else begin
        assign mode_exc = ((csr_tlb_io.mode == 2'b01) & ~csr_tlb_io.sum & hit_entry.u) |
                            ((csr_tlb_io.mode == 2'b00) & ~hit_entry.u) | hit_entry.exc;
    end
endgenerate

    always_ff @(posedge clk)begin
        if(io.req)begin
            io.paddr <= mmode ? io.vaddr : {lookup_paddr, io.vaddr[`TLB_OFFSET-1: 0]};
        end
        io.miss <= ~mmode & ~lookup_hit & io.req;
        io.exception <= ~mmode & io.req & lookup_hit & mode_exc;
        pma_addr <= mmode ? io.vaddr[`VADDR_SIZE-1: `TLB_OFFSET] : lookup_paddr;
    end
    assign io.uncache = pma_uc;

// pmp
    `PMA_ASSIGN
    PMPCheck pmp_check(
        .paddr(io.wentry.ppn),
        .pmpcfg(csr_tlb_io.pmpcfg),
        .pmpaddr(csr_tlb_io.pmpaddr),
        .paddr_pma(pma_addr),
        .pmacfg(pmacfg),
        .pmaaddr(pmaaddr),
        .pmp_v,
        .pmp_r,
        .pmp_w,
        .pmp_x,
        .pma_uc
    );


// update
    L1TLBEntry wentry;
    
    assign wentry.g = io.wentry.g;
    assign wentry.u = io.wentry.u;
    assign wentry.r = io.wentry.r;
    assign wentry.x = io.wentry.x;
    assign wentry.d = io.wentry.d;
    assign wentry.size = io.wpn & {`TLB_PN{~io.wexc_static}};
    assign wentry.vpn = io.waddr;
    assign wentry.ppn = io.wentry.ppn;
    assign wentry.uc = pma_uc;
    assign wentry.asid = csr_tlb_io.asid;
    logic r, w, x;
    assign x = SOURCE == 2'b00;
    assign r = SOURCE == 2'b01;
    assign w = SOURCE == 2'b10;
generate
    if(SOURCE == 2'b00)begin
        assign wentry.exc = ~io.wentry.x | pmp_v  & ~pmp_x | io.wexc_static;
    end
    else if(SOURCE == 2'b01)begin
        assign wentry.exc = pmp_v & ~pmp_r | io.wexc_static;
    end
    else if(SOURCE == 2'b10)begin
        assign wentry.exc = (~io.wentry.w) | (~io.wentry.d) | pmp_v & ~pmp_w | io.wexc_static;
    end
endgenerate


generate
    if(FENCEV)begin
        assign widx = fenceWe ? fenceIdx : io.widx;
        always_ff @(posedge clk, negedge rst)begin
            if(rst == `RST)begin
                en <= 0;
                entrys <= '{default: 0};
            end
            else begin
                if(fenceWe)begin
                    en[widx] <= 1'b0;
                end
                else if(io.we)begin
                    entrys[widx] <= wentry;
                    en[widx] <= 1'b1;
                end
            end
        end
    end
    else begin
        always_ff @(posedge clk, negedge rst)begin
            if(rst == `RST)begin
                en <= 0;
                entrys <= '{default: 0};
            end
            else begin
                if(io.we)begin
                    entrys[io.widx] <= wentry;
                    en[io.widx] <= io.wen;
                end
            end
        end
    end

    if(SELV)begin
        for(genvar i=0; i<`TLB_PN; i++)begin
            logic `N(`TLB_VPN) sel_vpn;
            assign sel_vpn = wentry.vpn.vpn[i];
            assign sel_wvaddrs_n.vpn[i] = sel_vpn + 1;
            assign sel_wvaddrs_p.vpn[i] = sel_vpn - 1;
        end
        always_ff @(posedge clk, negedge rst)begin
            if(rst == `RST)begin
                sel_vaddrs_p <= 0;
                sel_vaddrs_n <= 0;
            end
            else begin
                if(io.we)begin
                    sel_vaddrs_p[io.widx] <= sel_wvaddrs_p;
                    sel_vaddrs_n[io.widx] <= sel_wvaddrs_n;
                end
            end
        end
    end
endgenerate

// fence
generate
    if(FENCEV)begin
        always_ff @(posedge clk)begin
            if(fenceState == IDLE && fenceBus.mmu_flush[SOURCE])begin
                fenceVaddr <= fenceBus.vma_vaddr[SOURCE][`VADDR_SIZE-1: `TLB_OFFSET];
                fence_asid <= fenceBus.vma_asid[SOURCE];
                fence_addr_all <= fenceBus.mmu_flush_all[SOURCE];
                fence_asid_all <= fenceBus.mmu_asid_all[SOURCE];
            end
        end

        assign fenceWe = (fenceState == FENCE) & (|hit) & ~(fence_addr_all & ~hit[fenceAllIdx]);
        assign fenceIdx = fence_addr_all ? fenceAllIdx : hit_idx;

        always_ff @(posedge clk, negedge rst)begin
            if(rst == `RST)begin
                fenceState <= IDLE;
                fenceReq <= 0;
                fenceAllIdx <= 0;
            end
            else begin
                case(fenceState)
                IDLE: begin
                    if(fenceBus.mmu_flush[SOURCE])begin
                        fenceAllIdx <= 0;
                        fenceState <= FENCE;
                        fenceReq <= 1'b1;
                    end
                end
                FENCE: begin
                    if(~fence_addr_all | (fenceAllIdx == {ADDR_WIDTH{1'b1}}))begin
                        fenceState <= FENCE_END;
                        fenceReq <= 1'b0;
                    end
                    else begin
                        fenceAllIdx <= fenceAllIdx + 1;
                    end
                end
                FENCE_END:begin
                    fenceState <= IDLE;
                end
                endcase
            end
        end
    end
endgenerate
endmodule