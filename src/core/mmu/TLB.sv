`include "../../defines/defines.svh"

interface TLBIO #(
    parameter DEPTH=16,
    parameter ADDR_WIDTH=$clog2(DEPTH)
);
    logic req;
    logic `VADDR_BUS vaddr;
    logic flush;

    logic miss;
    logic uncache;
    logic exception;
    logic `PADDR_BUS paddr;

    logic we;
    logic `N(ADDR_WIDTH) widx;
    TLBInfo wbInfo;
    PTEEntry wentry;
    logic `N(2) wpn;
    logic `N(`VADDR_SIZE) waddr;

    modport tlb(input req, flush, vaddr, we, wbInfo, wentry, wpn, widx, waddr, output miss, uncache, exception, paddr);
endinterface

module TLB #(
    parameter DEPTH=16,
    parameter SOURCE=0,
    parameter [1: 0] MODE=2'b00, //2'b00: x, 2'b01: r, 2'b10: w
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

    typedef enum  { IDLE, FENCE, FENCE_ALL, FENCE_END } FenceState;
    FenceState fenceState;
    logic fenceReq, fenceWe;
    logic `N(ADDR_WIDTH) fenceIdx;
    logic `N(`VADDR_SIZE-`TLB_OFFSET) fenceVaddr;

// lookup
    logic `N(DEPTH) hit, hit_n;
    logic `N(DEPTH) asid_hit;
    logic mode_exc;
    logic `ARRAY(DEPTH, `TLB_PN) pn_hits, pn_mask;
    logic `N(`TLB_PN) hit_mask;
    logic `ARRAY(DEPTH, $bits(L1TLBEntry)+`TLB_PN) mask_entry;
    logic `N(DEPTH) pn_hit;
    VPNAddr lookup_addr;
    PPNAddr lookup_paddr;
    logic lookup_hit;
    logic mmode;

    assign lookup_addr = fenceReq ? fenceVaddr : io.vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign mmode = (csr_tlb_io.mode == 2'b11) | (csr_tlb_io.satp_mode == 0);
generate
    for(genvar i=0; i<DEPTH; i++)begin
        // assign asid_hit[i] = en[i] & (entrys[i].asid == csr_tlb_io.asid || entrys[i].g);
        assign asid_hit[i] = en[i];
        
        always_comb begin
            case(entrys[i].size)
            2'b00: pn_mask[i] = {`TLB_PN{1'b1}};
            2'b01: pn_mask[i] = {1'b0, {`TLB_PN-1{1'b1}}};
`ifdef SV39
            2'b10: pn_mask[i] = {2'b0, {`TLB_PN-2{1'b1}}};
`endif
            default: pn_mask[i] = 0;
            endcase
        end
        for(genvar j=0; j<`TLB_PN; j++)begin
            assign pn_hits[i][j] = entrys[i].vpn.vpn[j] == lookup_addr.vpn[j];
        end
        assign pn_hit[i] = &(pn_hits[i] | pn_mask[i]);
        assign mask_entry[i] = {entrys[i], pn_mask[i]};
    end
endgenerate
    assign hit = asid_hit & pn_hit;
    FairSelect #(DEPTH, $bits(L1TLBEntry)+`TLB_PN) select_hit (hit, mask_entry, lookup_hit, {hit_entry, hit_mask});

`define L1_PPN_ASSIGN(i) assign lookup_paddr.ppn``i = hit_mask[`TLB_PN-1-i] ? hit_entry.ppn.ppn``i : lookup_addr.vpn[``i];

    `L1_PPN_ASSIGN(0)
    `L1_PPN_ASSIGN(1)
generate
    if(SOURCE == 2'b01)begin
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
        io.miss <= ~mmode & ~lookup_hit & io.req & ~io.flush;
        io.exception <= ~mmode & io.req & ~io.flush & lookup_hit & mode_exc;
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
    assign wentry.size = io.wpn;
    assign wentry.vpn = io.waddr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign wentry.ppn = io.wentry.ppn;
    assign wentry.uc = pma_uc;
    logic r, w, x;
    assign x = SOURCE == 2'b00;
    assign r = SOURCE == 2'b01;
    assign w = SOURCE == 2'b10;
generate
    if(SOURCE == 2'b00)begin
        assign wentry.exc = ~io.wentry.x | pmp_v  & ~pmp_x;
    end
    else if(SOURCE == 2'b01)begin
        assign wentry.exc = pmp_v & ~pmp_r;
    end
    else if(SOURCE == 2'b10)begin
        assign wentry.exc = (~io.wentry.w) | (~io.wentry.d) | pmp_v & ~pmp_w;
    end
endgenerate


    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            entrys <= '{default: 0};
        end
        else begin
            if(fenceWe)begin
                en[fenceIdx] <= 1'b0;
            end
            else if(io.we)begin
                entrys[io.widx] <= wentry;
                en[io.widx] <= 1'b1;
            end
        end
    end

// fence
    always_ff @(posedge clk)begin
        hit_n <= hit;
    end
    logic `N(ADDR_WIDTH) hit_n_idx;
    PEncoder #(DEPTH) encoder_fence_idx (hit_n, hit_n_idx);
    always_ff @(posedge clk)begin
        if(fenceState == IDLE && fenceBus.mmu_flush[SOURCE])begin
            fenceVaddr <= fenceBus.vma_vaddr[SOURCE][`VADDR_SIZE-1: `TLB_OFFSET];
        end
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            fenceState <= IDLE;
            fenceReq <= 0;
            fenceWe <= 0;
            fenceIdx <= 0;
        end
        else begin
            case(fenceState)
            IDLE: begin
                if(fenceBus.mmu_flush[SOURCE])begin
                    if(fenceBus.mmu_flush_all[SOURCE])begin
                        fenceIdx <= 0;
                        fenceWe <= 1'b1;
                        fenceState <= FENCE_ALL;
                    end
                    else begin
                        fenceReq <= 1'b1;
                        fenceState <= FENCE;
                    end
                end
            end
            FENCE: begin
                fenceWe <= |hit_n;
                fenceIdx <= hit_n_idx;
                fenceState <= FENCE_END;
            end
            FENCE_ALL: begin
                fenceIdx <= fenceIdx + 1;
                if(fenceIdx == {{ADDR_WIDTH-1{1'b1}}, 1'b0})begin
                    fenceState <= FENCE_END;
                end
            end
            FENCE_END:begin
                fenceWe <= 0;
                fenceReq <= 0;
                fenceState <= IDLE;
            end
            endcase
        end
    end
endmodule