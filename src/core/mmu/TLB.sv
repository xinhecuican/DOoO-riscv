`include "../../defines/defines.svh"

interface TLBIO #(
    parameter DEPTH=16,
    parameter ADDR_WIDTH=$clog2(DEPTH)
);
    logic req;
    logic `VADDR_BUS vaddr;

    logic miss;
    logic exception;
    logic `PADDR_BUS paddr;

    logic we;
    logic `N(ADDR_WIDTH) widx;
    TLBInfo wbInfo;
    PTEEntry wentry;
    logic `N(2) wpn;
    logic `N(`VADDR_SIZE) waddr;

    modport tlb(input req, vaddr, we, wbInfo, wentry, wpn, widx, waddr, output miss, exception, paddr);
endinterface

module TLB #(
    parameter DEPTH=16,
    parameter ADDR_WIDTH=$clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    TLBIO.tlb   io,
    CsrTlbIO.tlb csr_tlb_io
);
    L1TLBEntry entrys `N(DEPTH);
    logic `N(DEPTH) en;
// lookup
    logic `N(DEPTH) hit;
    logic `N(DEPTH) asid_hit;
    logic `N(DEPTH) mode_exc;
    logic `ARRAY(DEPTH, `TLB_PN) pn_hits, pn_mask;
    logic `N(DEPTH) pn_hit;
    logic `N(ADDR_WIDTH) hit_idx;
    VPNAddr lookup_addr;
    PPNAddr lookup_paddr;
    logic mmode;

    assign lookup_addr = io.vaddr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign mmode = (csr_tlb_io.mode == 2'b11) | (csr_tlb_io.satp_mode == 0);
generate
    for(genvar i=0; i<DEPTH; i++)begin
        // assign asid_hit[i] = en[i] & (entrys[i].asid == csr_tlb_io.asid || entrys[i].g);
        assign asid_hit[i] = en[i];
        assign mode_exc[i] = ((csr_tlb_io.mode == 2'b01) & ~csr_tlb_io.sum & entrys[i].u) |
                             ((csr_tlb_io.mode == 2'b00) & ~entrys[i].u);
        always_comb begin
            case(entrys[i].size)
            2'b00: pn_mask[i] = {`TLB_PN{1'b1}};
            2'b01: pn_mask[i] = {1'b0, {`TLB_PN-1{1'b1}}};
            2'b10: pn_mask[i] = {2'b0, {`TLB_PN-2{1'b1}}};
            default: pn_mask[i] = 0;
            endcase
        end
        for(genvar j=0; j<`TLB_PN; j++)begin
            assign pn_hits[i][j] = entrys[i].vpn[j] == lookup_addr.vpn[j];
        end
        assign pn_hit[i] = &(pn_hits[i] | pn_mask[i]);
    end
endgenerate
    assign hit = asid_hit & pn_hit;
    Encoder #(DEPTH) encoder_hit (hit, hit_idx);


`define L1_PPN_ASSIGN(i) assign lookup_paddr.ppn``i = pn_mask[hit_idx][i] ? entrys[hit_idx].ppn.ppn``i : lookup_addr.vpn[``i];

    `L1_PPN_ASSIGN(0)
    `L1_PPN_ASSIGN(1)


    always_ff @(posedge clk)begin
        io.paddr <= mmode ? io.vaddr : {lookup_paddr, io.vaddr[`TLB_OFFSET-1: 0]};
        io.miss <= ~mmode & ~(|hit) & io.req;
        io.exception <= ~mmode & io.req & (|hit) & mode_exc[hit_idx];
    end

// update
    L1TLBEntry wentry;
    
    assign wentry.g = io.wentry.g;
    assign wentry.u = io.wentry.u;
    assign wentry.size = io.wpn;
    assign wentry.vpn = io.waddr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign wentry.ppn = io.wentry.ppn;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            entrys <= '{default: 0};
        end
        else begin
            if(io.we)begin
                entrys[io.widx] <= wentry;
                en[io.widx] <= 1'b1;
            end
        end
    end
endmodule