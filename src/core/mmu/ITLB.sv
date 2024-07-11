`include "../../defines/defines.svh"

module ITLB(
    input logic clk,
    input logic rst,
    ITLBCacheIO.tlb itlb_cache_io,
    CsrTlbIO.tlb csr_itlb_io,
    TlbL2IO.tlb tlb_l2_io
);
    typedef struct packed {
        logic `ARRAY(2, `VADDR_SIZE) vaddr;
        logic `N(2) miss;
        logic `N(2) exception;
        logic req,req_s2;
        logic `N(`VADDR_SIZE) req_addr;
        logic `ARRAY(2, `PADDR_SIZE) paddr;
    } RequestBuffer;
    typedef enum {IDLE, WALK_ADDR0, WALK_ADDR1} State;
    State state;
    RequestBuffer req_buf;
    TLBIO #(`ITLB_SIZE) itlb_io `N(2) ();
    logic miss_end;
    logic `N(2) exception, miss;
    logic `N(`PADDR_SIZE) wpaddr;

    TlbL2IO tlb_l2_io0();
    assign tlb_l2_io0.req = req_buf.req;
    assign tlb_l2_io0.info = 0;
    assign tlb_l2_io0.req_addr = req_buf.req_addr;
    TLBRepeater #(.FRONT(1)) repeater0(.*, .in(tlb_l2_io0), .out(tlb_l2_io));

    ReplaceIO #(.DEPTH(1), .WAY_NUM(`DTLB_SIZE)) replace_io();
    RandomReplace #(1, `DTLB_SIZE) replace (.*);
    assign replace_io.hit_en = 0;
    assign replace_io.hit_way = 0;
    assign replace_io.hit_index = 0;
    assign replace_io.miss_index = 0;
generate
    for(genvar i=0; i<2; i++)begin
        assign itlb_io[i].req = itlb_cache_io.req;
        // assign itlb_io.asid = itlb_cache_io.asid;
        assign itlb_io[i].vaddr = itlb_cache_io.vaddr;

        assign itlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception & (tlb_l2_io0.info_o.source == 2'b00);
        assign itlb_io[i].widx = replace_io.miss_way;
        assign itlb_io[i].wbInfo = tlb_l2_io0.info_o;
        assign itlb_io[i].wentry = tlb_l2_io0.entry;
        assign itlb_io[i].wpn = tlb_l2_io0.wpn;
        assign itlb_io[i].waddr = tlb_l2_io0.waddr;

        assign itlb_cache_io.paddr[i] = miss_end ? req_buf.paddr[i] : itlb_io[i].paddr;
        assign exception[i] = miss_end ? req_buf.exception[i] : itlb_io[i].exception;
        assign miss[i] = ~miss_end & itlb_io[i].miss;
        TLB #(`ITLB_SIZE) tlb(.*, .io(itlb_io[i]), .csr_tlb_io(csr_itlb_io));
    end
endgenerate

    assign itlb_cache_io.exception = exception & {2{state == IDLE}};
    assign itlb_cache_io.miss = (|miss) | (state != IDLE);

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            req_buf <= 0;
            miss_end <= 0;
        end
        else begin
            case(state)
            IDLE:begin
                if(|miss)begin
                    req_buf.miss <= miss;
                    req_buf.paddr <= {itlb_io[1].paddr, itlb_io[0].paddr};
                    req_buf.exception <= 0;
                end
                if(miss[0] & ~(|exception))begin
                    state <= WALK_ADDR0;
                    req_buf.req <= 1'b1;
                    req_buf.req_addr <= req_buf.vaddr[0];
                end
                else if(miss[1] & ~(|exception))begin
                    state <= WALK_ADDR1;
                    req_buf.req <= 1'b1;
                    req_buf.req_addr <= req_buf.vaddr[1];
                end
                else begin
                    req_buf.vaddr <= itlb_cache_io.vaddr;
                end
            end
            WALK_ADDR0: begin
                if((req_buf.req_s2 & ~tlb_l2_io.ready) | 
                   (tlb_l2_io.dataValid & tlb_l2_io.error))begin
                    req_buf.req <= 1'b1;
                end
                if(tlb_l2_io.dataValid & tlb_l2_io.exception)begin
                    req_buf.exception[0] <= 1'b1; 
                end
                if(tlb_l2_io.dataValid & ~tlb_l2_io.exception & ~tlb_l2_io.error)begin
                    req_buf.paddr[0] <= wpaddr;
                end
                if(tlb_l2_io.dataValid & ~tlb_l2_io.error)begin
                    if(req_buf.miss[1])begin
                        state <= WALK_ADDR1;
                        req_buf.req <= 1'b1;
                        req_buf.req_addr <= req_buf.vaddr[1];
                    end
                    else begin
                        state <= IDLE;
                        miss_end <= 1'b1;
                    end
                end
            end
            WALK_ADDR1: begin
                if((req_buf.req_s2 & ~tlb_l2_io.ready) | 
                   (tlb_l2_io.dataValid & tlb_l2_io.error))begin
                    req_buf.req <= 1'b1;
                end
                if(tlb_l2_io.dataValid & ~tlb_l2_io.exception & ~tlb_l2_io.error)begin
                    req_buf.paddr[1] <= wpaddr;
                end
                if(tlb_l2_io.dataValid & tlb_l2_io.exception)begin
                    req_buf.exception[1] <= 1'b1; 
                end
                if(tlb_l2_io.dataValid & ~tlb_l2_io.error)begin
                    state <= IDLE;
                    miss_end <= 1'b1;
                end
            end
            endcase
            if(req_buf.req)begin
                req_buf.req <= 1'b0;
            end
            if(miss_end)begin
                miss_end <= 1'b0;
            end
        end
    end
    always_ff @(posedge clk)begin
        req_buf.req_s2 <= req_buf.req;
    end

    VPNAddr vpn;
    PPNAddr wppn;
    assign vpn = tlb_l2_io0.waddr[`VADDR_SIZE-1: `TLB_OFFSET];
    always_comb begin
        if(tlb_l2_io0.wpn == 2'b01)begin
            wppn.ppn1 = tlb_l2_io0.entry.ppn.ppn1;
            wppn.ppn0 = vpn.vpn[0];
        end
        else begin
            wppn = tlb_l2_io0.entry.ppn;
        end
    end
    assign wpaddr = {wppn, tlb_l2_io0.waddr[`TLB_OFFSET-1: 0]};
endmodule