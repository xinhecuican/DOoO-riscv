`include "../../../defines/defines.svh"

module ITLB(
    input logic clk,
    input logic rst,
    ITLBCacheIO.tlb itlb_cache_io,
    CsrTlbIO.tlb csr_itlb_io,
    TlbL2IO.tlb tlb_l2_io,
    FenceBus.mmu fenceBus
);
    typedef struct packed {
        logic `ARRAY(2, `VADDR_SIZE) vaddr;
        logic `N(2) miss;
        logic `N(2) exception;
        logic req,req_s2, req_s3;
        logic `N(`VADDR_SIZE) req_addr;
        logic `ARRAY(2, `PADDR_SIZE) paddr;
        logic `N(`TLB_IDX_SIZE) idx;
    } RequestBuffer;
    typedef enum {IDLE, WALK_ADDR0, WALK_ADDR1, WALK_ALL} State;
    State state;
    RequestBuffer req_buf;
    logic flush_n;
    TLBIO #(`ITLB_SIZE) itlb_io `N(2) ();
    logic miss_end;
    logic `N(2) exception, miss;
    VPNAddr vpn;
    PPNAddr wppn;

    TlbL2IO tlb_l2_io0();
    logic tlb_valid;
    assign tlb_l2_io0.req = req_buf.req & ~flush_n;
    assign tlb_l2_io0.info = req_buf.idx;
    assign tlb_l2_io0.req_addr = req_buf.req_addr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign tlb_valid = tlb_l2_io0.dataValid & tlb_l2_io0.waddr == req_buf.req_addr[`VADDR_SIZE-1: `TLB_OFFSET];
    TLBRepeater #(.FRONT(1)) repeater0(.*, .flush(itlb_cache_io.flush), .in(tlb_l2_io0), .out(tlb_l2_io));

    ReplaceD1IO #(.WAY_NUM(`ITLB_SIZE)) replace_io();
    RandomReplaceD1 #(1, `ITLB_SIZE) replace (.*);
    assign replace_io.hit_en = 0;
    assign replace_io.hit_way = 0;
generate
    for(genvar i=0; i<2; i++)begin
        assign itlb_io[i].req = itlb_cache_io.req[i] & ~itlb_cache_io.flush;
        // assign itlb_io.asid = itlb_cache_io.asid;
        assign itlb_io[i].vaddr = itlb_cache_io.vaddr[i];
        assign itlb_io[i].flush = itlb_cache_io.flush;

        assign itlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error;
        assign itlb_io[i].wen = 1'b1;
        assign itlb_io[i].wexc_static = tlb_l2_io0.exc_static;
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

    always_ff @(posedge clk)begin
        flush_n <= itlb_cache_io.flush;
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            req_buf <= 0;
            miss_end <= 0;
        end
        else if(itlb_cache_io.flush)begin
            state <= IDLE;
            miss_end <= 0;
            req_buf.req <= 0;
        end
        else begin
            case(state)
            IDLE:begin
                if(|miss)begin
                    req_buf.miss <= miss;
                    req_buf.paddr <= {itlb_io[1].paddr, itlb_io[0].paddr};
                    req_buf.exception <= 0;
                end
                if(miss[0] & miss[1] & ~(|exception) & 
                    (req_buf.vaddr[0][`VADDR_SIZE-1: `TLB_OFFSET] == req_buf.vaddr[1][`VADDR_SIZE-1: `TLB_OFFSET]))begin
                    state <= WALK_ALL;
                    req_buf.req <= 1'b1;
                    req_buf.req_addr <= req_buf.vaddr[0];
                    req_buf.idx <= req_buf.idx + 1;
                end
                else if(miss[0] & ~(|exception))begin
                    state <= WALK_ADDR0;
                    req_buf.req <= 1'b1;
                    req_buf.req_addr <= req_buf.vaddr[0];
                    req_buf.idx <= req_buf.idx + 1;
                end
                else if(miss[1] & ~(|exception))begin
                    state <= WALK_ADDR1;
                    req_buf.req <= 1'b1;
                    req_buf.idx <= req_buf.idx + 1;
                    req_buf.req_addr <= req_buf.vaddr[1];
                end
                else begin
                    req_buf.vaddr <= itlb_cache_io.vaddr;
                end
            end
            WALK_ALL:begin
                if((req_buf.req_s3 & ~tlb_l2_io0.ready) | 
                   (tlb_valid & tlb_l2_io0.error))begin
                    req_buf.req <= 1'b1;
                end
                if(tlb_valid & ~tlb_l2_io0.error & tlb_l2_io0.exception)begin
                    req_buf.exception[0] <= 1'b1;
                    req_buf.exception[1] <= 1'b1;
                end
                if(tlb_valid & ~tlb_l2_io0.exception & ~tlb_l2_io0.error)begin
                    req_buf.paddr[0] <= {wppn, req_buf.vaddr[0][`TLB_OFFSET-1: 0]};
                    req_buf.paddr[1] <= {wppn, req_buf.vaddr[1][`TLB_OFFSET-1: 0]};
                end

                if(tlb_valid & ~tlb_l2_io0.error)begin
                    state <= IDLE;
                    miss_end <= 1'b1;
                end
            end
            WALK_ADDR0: begin
                if((req_buf.req_s3 & ~tlb_l2_io0.ready) | 
                   (tlb_valid & tlb_l2_io0.error))begin
                    req_buf.req <= 1'b1;
                end
                if(tlb_valid & ~tlb_l2_io0.error & tlb_l2_io0.exception)begin
                    req_buf.exception[0] <= 1'b1; 
                end
                if(tlb_valid & ~tlb_l2_io0.exception & ~tlb_l2_io0.error)begin
                    req_buf.paddr[0] <= {wppn, req_buf.vaddr[0][`TLB_OFFSET-1: 0]};
                end
                if(tlb_valid & ~tlb_l2_io0.error)begin
                    if(req_buf.miss[1])begin
                        state <= WALK_ADDR1;
                        req_buf.req <= 1'b1;
                        req_buf.idx <= req_buf.idx + 1;
                        req_buf.req_addr <= req_buf.vaddr[1];
                    end
                    else begin
                        state <= IDLE;
                        miss_end <= 1'b1;
                    end
                end
            end
            WALK_ADDR1: begin
                if((req_buf.req_s3 & ~tlb_l2_io0.ready) | 
                   (tlb_valid & tlb_l2_io0.error))begin
                    req_buf.req <= 1'b1;
                end
                if(tlb_valid & ~tlb_l2_io0.exception & ~tlb_l2_io0.error)begin
                    req_buf.paddr[1] <= {wppn, req_buf.vaddr[1][`TLB_OFFSET-1: 0]};
                end
                if(tlb_valid & ~tlb_l2_io0.error & tlb_l2_io0.exception)begin
                    req_buf.exception[1] <= 1'b1; 
                end
                if(tlb_valid & ~tlb_l2_io0.error)begin
                    state <= IDLE;
                    miss_end <= 1'b1;
                end
            end
            endcase
            if(req_buf.req)begin
                req_buf.req <= 1'b0;
            end
            if(miss_end & itlb_cache_io.ready)begin
                miss_end <= 1'b0;
            end
            req_buf.req_s2 <= req_buf.req;
            req_buf.req_s3 <= req_buf.req_s2;
        end
    end


    assign vpn = tlb_l2_io0.waddr;
`ifdef SV39
    assign wppn.ppn2 = tlb_l2_io0.wpn[2] ? vpn.vpn[2] : tlb_l2_io0.entry.ppn.ppn2;
`endif
    assign wppn.ppn1 = tlb_l2_io0.wpn[1] ? vpn.vpn[1] : tlb_l2_io0.entry.ppn.ppn1;
    assign wppn.ppn0 = tlb_l2_io0.wpn[0] ? vpn.vpn[0] : tlb_l2_io0.entry.ppn.ppn0;

    `Log(DLog::Debug, T_ITLB, tlb_l2_io0.dataValid & ~tlb_l2_io0.error,
        $sformatf("ITLB[%d %b %b]: vaddr=%h, wpn=%b, entry=%h", replace_io.miss_way, tlb_l2_io0.exception, tlb_l2_io0.exc_static, tlb_l2_io0.waddr, tlb_l2_io0.wpn, tlb_l2_io0.entry), 1'b1, {tlb_l2_io0.waddr, 12'h0})
endmodule