`include "../../../defines/defines.svh"

module DTLB(
    input logic clk,
    input logic rst,
    DTLBLsuIO.tlb tlb_lsu_io,
    CsrTlbIO.tlb csr_ltlb_io,
    CsrTlbIO.tlb csr_stlb_io,
    TlbL2IO.tlb tlb_l2_io,
    FenceBus.mmu fenceBus
);
    TLBIO #(`DTLB_SIZE) ltlb_io `N(`LOAD_PIPELINE) ();
    TLBIO #(`DTLB_SIZE) stlb_io `N(`LOAD_PIPELINE) ();
    TlbL2IO tlb_l2_io0();
    TlbL2IO tlb_l2_io1();

    logic `N(`LOAD_PIPELINE) lwb_pipeline;
    Decoder #(`LOAD_PIPELINE) decoder_load_pipe (tlb_l2_io0.info_o.idx[`TLB_IDX_SIZE-1: `LOAD_ISSUE_BANK_WIDTH], lwb_pipeline);
    logic `N(`STORE_PIPELINE) swb_pipeline;
    Decoder #(`STORE_PIPELINE) decoder_store_pipe (tlb_l2_io0.info_o.idx[`TLB_IDX_SIZE-1: `STORE_ISSUE_BANK_WIDTH], swb_pipeline);

    logic `N(`DTLB_SIZE) replace_en, replace_hit;
    logic `ARRAY(`DTLB_SIZE, `TLB_ASID+1) replace_asid;
    logic `ARRAY(`DTLB_SIZE, `TLB_PN) replace_pn_valid;
    VPNAddr replace_vpn `N(`DTLB_SIZE);
    logic `ARRAY(`DTLB_SIZE, `TLB_PN) replace_pn_hits;
    VPNAddr replace_cmp_vaddr;
    logic `N(`TLB_ASID) replace_cmp_asid;
    logic replace_cmp_g;
    logic `N($clog2(`DTLB_SIZE)) tlb_widx, replace_widx, replace_miss_idx;

    typedef enum  { IDLE, FENCE, FENCE_END } FenceState;
    FenceState fenceState;
    logic fenceReq, fenceWe;
    logic `N($clog2(`DTLB_SIZE)) fenceIdx, fenceAllIdx;
    VPNAddr fenceVaddr;
    logic `N(`TLB_ASID) fence_asid;
    logic fence_asid_all, fence_addr_all;

    ReplaceIO #(
        .DEPTH(1),
        .WAY_NUM(`DTLB_SIZE)
    ) replace_io();
    PLRU #(1, `DTLB_SIZE) replace (.*);
    assign replace_io.hit_en = tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception;
    assign replace_io.hit_invalid = 0;
    assign replace_io.hit_way = |replace_hit ? replace_hit : replace_io.miss_way;
    assign replace_io.miss_index = 0;
    assign replace_io.hit_index = 0;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        TLB #(`DTLB_SIZE, 2'b01, 2'b01, 1'b1) ltlb(
            .*,
            .io(ltlb_io[i]),
            .csr_tlb_io(csr_ltlb_io)
        );
`ifdef RVA
        if(i == 0)begin
            assign ltlb_io[i].req = tlb_lsu_io.lreq[i] | tlb_lsu_io.amo_req;
            assign ltlb_io[i].vaddr = tlb_lsu_io.amo_req ? tlb_lsu_io.amo_addr : tlb_lsu_io.laddr[i];
            assign ltlb_io[i].sel_tag = tlb_lsu_io.amo_req ? tlb_lsu_io.amo_addr[`VADDR_SIZE-1: `TLB_OFFSET] : tlb_lsu_io.lsel_tag[i];
            assign ltlb_io[i].sel = tlb_lsu_io.lsel[i] & {2*`TLB_PN{~tlb_lsu_io.amo_req}};
        end
        else begin
`endif
        assign ltlb_io[i].req = tlb_lsu_io.lreq[i];
        assign ltlb_io[i].vaddr = tlb_lsu_io.laddr[i];
        assign ltlb_io[i].flush = 1'b0;
        assign ltlb_io[i].sel = tlb_lsu_io.lsel[i];
        assign ltlb_io[i].sel_tag = tlb_lsu_io.lsel_tag[i];
`ifdef RVA
        end
`endif

        assign ltlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error | fenceWe;
        assign ltlb_io[i].wen = ~fenceWe;
        assign ltlb_io[i].wexc_static = tlb_l2_io0.exc_static;
        assign ltlb_io[i].widx = fenceWe ? fenceIdx : tlb_widx;
        assign ltlb_io[i].wbInfo = tlb_l2_io0.info_o;
        assign ltlb_io[i].wentry = tlb_l2_io0.entry;
        assign ltlb_io[i].wpn = tlb_l2_io0.wpn;
        assign ltlb_io[i].waddr = tlb_l2_io0.waddr;

        assign tlb_lsu_io.lmiss[i] = ltlb_io[i].miss;
        assign tlb_lsu_io.luncache[i] = ltlb_io[i].uncache;
        assign tlb_lsu_io.lexception[i] = ltlb_io[i].exception;
        assign tlb_lsu_io.lpaddr[i] = ltlb_io[i].paddr;
    end
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        TLB #(`DTLB_SIZE, 2'b01, 2'b10, 1'b1) stlb(
            .*,
            .io(stlb_io[i]),
            .csr_tlb_io(csr_stlb_io)
        );
        assign stlb_io[i].req = tlb_lsu_io.sreq[i];
        assign stlb_io[i].vaddr = tlb_lsu_io.saddr[i];
        assign stlb_io[i].flush = 1'b0;
        assign stlb_io[i].sel = tlb_lsu_io.ssel[i];
        assign stlb_io[i].sel_tag = tlb_lsu_io.ssel_tag[i];

        assign stlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error | fenceWe;
        assign stlb_io[i].wen = ~fenceWe;
        assign stlb_io[i].wexc_static = tlb_l2_io0.exc_static;
        assign stlb_io[i].widx = fenceWe ? fenceIdx : tlb_widx;
        assign stlb_io[i].wbInfo = tlb_l2_io0.info_o;
        assign stlb_io[i].wentry = tlb_l2_io0.entry;
        assign stlb_io[i].wpn = tlb_l2_io0.wpn;
        assign stlb_io[i].waddr = tlb_l2_io0.waddr;

        assign tlb_lsu_io.smiss[i] = stlb_io[i].miss;
        assign tlb_lsu_io.suncache[i] = stlb_io[i].uncache;
        assign tlb_lsu_io.sexception[i] = stlb_io[i].exception;
        assign tlb_lsu_io.spaddr[i] = stlb_io[i].paddr;
    end
endgenerate

    TLBRepeater repeater0(.*, .flush(1'b0), .in(tlb_l2_io0), .out(tlb_l2_io1));
    TLBRepeater repeater1(.*, .flush(1'b0), .in(tlb_l2_io1), .out(tlb_l2_io));

`ifdef RVA
    logic amo_req, amo_req_s2, amo_req_s3;
    logic `N(`TLB_VPN_SIZE) amo_vaddr;
    always_ff @(posedge clk)begin
        amo_req <= tlb_lsu_io.amo_req;
        amo_vaddr <= tlb_lsu_io.amo_addr[`VADDR_SIZE-1: `TLB_OFFSET];
        amo_req_s2 <= amo_req & ltlb_io[0].miss & ~ltlb_io[0].exception;
        amo_req_s3 <= amo_req_s2;
    end
`endif

    logic `N(`LOAD_PIPELINE) lreq, lreq_all_s2, lreq_cancel_s2, lreq_all_s3;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lvaddr;
    logic `N($clog2(`LOAD_PIPELINE)) lreq_idx;
    logic lreq_s2;
    logic `N(`TLB_VPN_SIZE) lreq_addr_s2;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) lidx;
    logic `N(`LOAD_ISSUE_BANK_WIDTH+$clog2(`LOAD_PIPELINE)) lidx_s2;
generate
    `UNPARAM(LOAD_PIPELINE, 2, "lreq_cancel_s2")
    assign lreq_cancel_s2[0] = 0;
    assign lreq_cancel_s2[1] = (ltlb_io[0].miss & ~ltlb_io[0].exception) & tlb_lsu_io.lreq_s2[0];
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
`ifdef RVA
        if(i == 0)begin
            assign lreq[i] = ltlb_io[i].miss & ~ltlb_io[i].exception & ~amo_req & tlb_lsu_io.lreq_s2[i];
        end
        else begin
`endif
        assign lreq[i] = ltlb_io[i].miss & ~ltlb_io[i].exception & tlb_lsu_io.lreq_s2[i];
`ifdef RVA
        end
`endif
        always_ff @(posedge clk)begin
            lvaddr[i] <= tlb_lsu_io.laddr[i];
            lidx[i] <= tlb_lsu_io.lidx[i];
        end
    end
    PREncoder #(`LOAD_PIPELINE) encoder_lreq (lreq, lreq_idx); 
    always_ff @(posedge clk)begin
        lreq_s2 <= |lreq;
        lreq_addr_s2 <= lvaddr[lreq_idx][`VADDR_SIZE-1: `TLB_OFFSET];
        lidx_s2 <= {lreq_idx, lidx[lreq_idx]};
        lreq_all_s2 <= lreq;
        lreq_all_s3 <= lreq_all_s2;
    end
endgenerate

    logic `N(`STORE_PIPELINE) sreq, sreq_all_s2, sreq_cancel_s2, sreq_all_s3;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) svaddr;
    logic `N($clog2(`STORE_PIPELINE)) sreq_idx;
    logic sreq_s2;
    logic `N(`TLB_VPN_SIZE) sreq_addr_s2;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sidx;
    logic `N(`STORE_ISSUE_BANK_WIDTH+$clog2(`STORE_PIPELINE)) sidx_s2;
generate
    assign sreq_cancel_s2[0] = 0;
    assign sreq_cancel_s2[1] = (stlb_io[0].miss & ~stlb_io[0].exception) & tlb_lsu_io.sreq_s2[0];
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign sreq[i] = stlb_io[i].miss & ~stlb_io[i].exception & tlb_lsu_io.sreq_s2[i];
        always_ff @(posedge clk)begin
            svaddr[i] <= tlb_lsu_io.saddr[i];
            sidx[i] <= tlb_lsu_io.sidx[i];
        end
    end
    PREncoder #(`STORE_PIPELINE) encoder_sreq (sreq, sreq_idx);
    always_ff @(posedge clk)begin
        sreq_s2 <= |sreq;
        sreq_addr_s2 <= svaddr[sreq_idx][`VADDR_SIZE-1: `TLB_OFFSET];
        sreq_all_s2 <= sreq;
        sidx_s2 <= {sreq_idx, sidx[sreq_idx]};
        sreq_all_s3 <= sreq_all_s2;
    end
endgenerate

    logic `N(`LOAD_PIPELINE) lreq_cancel_s3, lreq_cancel_s4;
    logic `N(`STORE_PIPELINE) sreq_cancel_s3, sreq_cancel_s4;
    always_ff @(posedge clk)begin
        lreq_cancel_s3 <= lreq_cancel_s2;
        sreq_cancel_s3 <= sreq_cancel_s2;
`ifdef RVA
        lreq_cancel_s4 <= lreq_all_s2 & (lreq_cancel_s3 | {`LOAD_PIPELINE{sreq_s2 | amo_req_s2}});
        sreq_cancel_s4 <= sreq_all_s2 & (sreq_cancel_s3 | {`STORE_PIPELINE{amo_req_s2}});
`else
        lreq_cancel_s4 <= lreq_all_s2 & (lreq_cancel_s3 | {`LOAD_PIPELINE{sreq_s2}});
        sreq_cancel_s4 <= sreq_all_s2 & (sreq_cancel_s3);
`endif
`ifdef RVA
        tlb_l2_io.req <= (sreq_s2  | lreq_s2 | amo_req_s2);
        tlb_l2_io.info.source <= amo_req_s2 ? 2'b11 : sreq_s2 ? 2'b10 : 2'b01;
        tlb_l2_io.info.idx <= sreq_s2 ? sidx_s2 : lidx_s2;
        tlb_l2_io.req_addr <= amo_req_s2 ? amo_vaddr : sreq_s2 ? sreq_addr_s2 : lreq_addr_s2;
`else
        tlb_l2_io.req <= (sreq_s2 | lreq_s2);
        tlb_l2_io.info.source <= sreq_s2 ? 2'b10 : 2'b01;
        tlb_l2_io.info.idx <= sreq_s2 ? sidx_s2 : lidx_s2;
        tlb_l2_io.req_addr <= sreq_s2 ? sreq_addr_s2 : lreq_addr_s2;
`endif
    end
    assign tlb_lsu_io.lcancel = lreq_cancel_s4 | lreq_all_s3 & {`LOAD_PIPELINE{~tlb_l2_io.ready}};
    assign tlb_lsu_io.scancel = sreq_cancel_s4 | sreq_all_s3 & {`STORE_PIPELINE{~tlb_l2_io.ready}};

    always_ff @(posedge clk)begin
        tlb_lsu_io.lwb <= {`LOAD_PIPELINE{tlb_l2_io0.dataValid & (tlb_l2_io0.info_o.source == 2'b01)}} & lwb_pipeline;
        tlb_lsu_io.lwb_exception <= {`LOAD_PIPELINE{tlb_l2_io0.exception}};
        tlb_lsu_io.lwb_error <= {`LOAD_PIPELINE{tlb_l2_io0.error}};
        tlb_lsu_io.lwb_idx <= {`LOAD_PIPELINE{tlb_l2_io0.info_o.idx[`LOAD_ISSUE_BANK_WIDTH-1: 0]}};
        tlb_lsu_io.swb <= {`STORE_PIPELINE{tlb_l2_io0.dataValid & (tlb_l2_io0.info_o.source == 2'b10)}} & swb_pipeline;
        tlb_lsu_io.swb_exception <= {`STORE_PIPELINE{tlb_l2_io0.exception}};
        tlb_lsu_io.swb_error <= {`STORE_PIPELINE{tlb_l2_io0.error}};
        tlb_lsu_io.swb_idx <= {`STORE_PIPELINE{tlb_l2_io0.info_o.idx[`STORE_ISSUE_BANK_WIDTH-1: 0]}};
`ifdef RVA
        tlb_lsu_io.amo_valid <= amo_req & ~ltlb_io[0].miss | 
                                amo_req_s3 & ~tlb_l2_io.ready |
                                (tlb_l2_io0.info_o.source == 2'b11) & tlb_l2_io0.dataValid;
        tlb_lsu_io.amo_exception <= (tlb_l2_io0.info_o.source == 2'b11) & tlb_l2_io0.dataValid ? tlb_l2_io0.exception : ltlb_io[0].exception;
        // 只要是从l2发过来的并且没有exception就需要标记为error，让amo_queue重发请求
        tlb_lsu_io.amo_error <= (tlb_l2_io0.info_o.source == 2'b11) & tlb_l2_io0.dataValid &
                                (tlb_l2_io0.error | ~tlb_l2_io0.error & ~tlb_l2_io0.exception) |
                                amo_req_s3 & ~tlb_l2_io.ready;
        tlb_lsu_io.amo_paddr <= ltlb_io[0].paddr;
`endif
    end

    assign fenceWe = (fenceState == FENCE) & (|replace_hit) & ~(fence_addr_all & ~replace_hit[fenceAllIdx]);
    assign fenceIdx = fence_addr_all ? fenceAllIdx : replace_widx;

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            fenceState <= IDLE;
            fenceReq <= 0;
            fenceAllIdx <= 0;
        end
        else begin
            case(fenceState)
            IDLE: begin
                if(fenceBus.mmu_flush[1])begin
                    fenceReq <= 1'b1;
                    fenceState <= FENCE;
                    fenceAllIdx <= 0;
                end
            end
            FENCE: begin
                if(~fence_addr_all | (fenceAllIdx == {$clog2(`DTLB_SIZE){1'b1}}))begin
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

    always_ff @(posedge clk)begin
        if(fenceState == IDLE && fenceBus.mmu_flush[1])begin
            fenceVaddr <= fenceBus.vma_vaddr[1][`VADDR_SIZE-1: `TLB_OFFSET];
            fence_asid <= fenceBus.vma_asid[1];
            fence_addr_all <= fenceBus.mmu_flush_all[1];
            fence_asid_all <= fenceBus.mmu_asid_all[1];
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            replace_vpn <= '{default: 0};
            replace_en <= 0;
            replace_pn_valid <= 0;
        end
        else begin
            if(fenceWe)begin
                replace_en[fenceIdx] <= 1'b0;
            end
            else if(tlb_l2_io0.dataValid & ~tlb_l2_io0.error)begin
                replace_vpn[tlb_widx] <= tlb_l2_io0.waddr;
                replace_en[tlb_widx] <= 1'b1;
                replace_pn_valid[tlb_widx] <= tlb_l2_io0.wpn;
                replace_asid[tlb_widx] <= {csr_stlb_io.asid, tlb_l2_io0.entry.g};
            end
        end
    end
generate
    assign replace_cmp_vaddr = fenceState == FENCE ? fenceVaddr : tlb_l2_io0.waddr;
    assign replace_cmp_asid = fenceState == FENCE ? fence_asid : csr_stlb_io.asid;
    for(genvar i=0; i<`DTLB_SIZE; i++)begin
        assign replace_hit[i] = (replace_en[i] && 
                (replace_cmp_asid == replace_asid[i][`TLB_ASID: 1] || replace_asid[i][0] || fence_asid_all && fenceReq)) & 
                ((&(replace_pn_hits[i] | replace_pn_valid[i])) | fenceReq & fence_addr_all);
        for(genvar j=0; j<`TLB_PN; j++)begin
            assign replace_pn_hits[i][j] = replace_vpn[i].vpn[j] == replace_cmp_vaddr.vpn[j];
        end
    end
endgenerate
    Encoder #(`DTLB_SIZE) encoder_replace_idx (replace_hit, replace_widx);
    Encoder #(`DTLB_SIZE) encoder_miss_idx (replace_io.miss_way, replace_miss_idx);
    assign tlb_widx = |replace_hit ? replace_widx : replace_miss_idx;
endmodule