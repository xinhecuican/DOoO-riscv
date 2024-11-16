`include "../../defines/defines.svh"

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
    logic flush0, flush1, flush2;

    logic `N(`LOAD_PIPELINE) lwb_pipeline;
    Decoder #(`LOAD_PIPELINE) decoder_load_pipe (tlb_l2_io0.info_o.idx[`TLB_IDX_SIZE-1: `LOAD_ISSUE_BANK_WIDTH], lwb_pipeline);
    logic `N(`STORE_PIPELINE) swb_pipeline;
    Decoder #(`STORE_PIPELINE) decoder_store_pipe (tlb_l2_io0.info_o.idx[`TLB_IDX_SIZE-1: `STORE_ISSUE_BANK_WIDTH], swb_pipeline);

    logic `N(`DTLB_SIZE) replace_en, replace_hit;
    logic `N(`VADDR_SIZE-`TLB_OFFSET) replace_vpn `N(`DTLB_SIZE);
    logic `N($clog2(`DTLB_SIZE)) tlb_widx, replace_widx;
    ReplaceD1IO #(.WAY_NUM(`DTLB_SIZE)) replace_io();
    RandomReplaceD1 #(1, `DTLB_SIZE) replace (.*);
    assign replace_io.hit_en = 0;
    assign replace_io.hit_way = 0;
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            replace_vpn <= '{default: 0};
            replace_en <= 0;
        end
        else if(tlb_lsu_io.flush)begin
            replace_en <= 0;
        end
        else begin
            if(tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception)begin
                replace_vpn[tlb_widx] <= tlb_l2_io0.waddr[`VADDR_SIZE-1: `TLB_OFFSET];
                replace_en[tlb_widx] <= 1'b1;
            end
        end
    end
generate
    for(genvar i=0; i<`DTLB_SIZE; i++)begin
        assign replace_hit[i] = replace_en[i] & (replace_vpn[i] == tlb_l2_io0.waddr[`VADDR_SIZE-1: `TLB_OFFSET]);
    end
endgenerate
    Encoder #(`DTLB_SIZE) encoder_replace_idx (replace_hit, replace_widx);
    assign tlb_widx = |replace_hit ? replace_widx : replace_io.miss_way;

    always_ff @(posedge clk)begin
        flush0 <= tlb_lsu_io.flush;
        flush1 <= tlb_lsu_io.flush;
        flush2 <= tlb_lsu_io.flush;
    end

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        TLB #(`DTLB_SIZE, 2'b01, 2'b01) ltlb(
            .*,
            .io(ltlb_io[i]),
            .csr_tlb_io(csr_ltlb_io)
        );
`ifdef RVA
        if(i == 0)begin
            assign ltlb_io[i].req = tlb_lsu_io.lreq[i] | tlb_lsu_io.amo_req;
            assign ltlb_io[i].vaddr = tlb_lsu_io.amo_req ? tlb_lsu_io.amo_addr : tlb_lsu_io.laddr[i];
        end
        else begin
`endif
        assign ltlb_io[i].req = tlb_lsu_io.lreq[i];
        assign ltlb_io[i].vaddr = tlb_lsu_io.laddr[i];
        assign ltlb_io[i].flush = tlb_lsu_io.flush;
`ifdef RVA
        end
`endif

        assign ltlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception;
        assign ltlb_io[i].widx = tlb_widx;
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
        TLB #(`DTLB_SIZE, 2'b01, 2'b10) stlb(
            .*,
            .io(stlb_io[i]),
            .csr_tlb_io(csr_stlb_io)
        );
        assign stlb_io[i].req = tlb_lsu_io.sreq[i];
        assign stlb_io[i].vaddr = tlb_lsu_io.saddr[i];
        assign stlb_io[i].flush = tlb_lsu_io.flush;

        assign stlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception;
        assign stlb_io[i].widx = tlb_widx;
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

    TLBRepeater repeater0(.*, .flush(flush0), .in(tlb_l2_io0), .out(tlb_l2_io1));
    TLBRepeater repeater1(.*, .flush(flush1), .in(tlb_l2_io1), .out(tlb_l2_io));

`ifdef RVA
    logic amo_req, amo_req_s2;
    logic `N(`VADDR_SIZE) amo_vaddr;
    always_ff @(posedge clk)begin
        amo_req <= tlb_lsu_io.amo_req;
        amo_vaddr <= tlb_lsu_io.amo_addr;
        amo_req_s2 <= amo_req & ltlb_io[0].miss & ~ltlb_io[0].exception;
    end
`endif

    logic `N(`LOAD_PIPELINE) lreq, lreq_all_s2, lreq_cancel_s2;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lvaddr;
    logic `N($clog2(`LOAD_PIPELINE)) lreq_idx;
    logic lreq_s2;
    logic `N(`VADDR_SIZE) lreq_addr_s2;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) lidx;
    logic `N(`LOAD_ISSUE_BANK_WIDTH+$clog2(`LOAD_PIPELINE)) lidx_s2;
generate
    `UNPARAM(LOAD_PIPELINE, 2, "lreq_cancel_s2")
    assign lreq_cancel_s2[0] = 0;
    assign lreq_cancel_s2[1] = (ltlb_io[0].miss & ~ltlb_io[0].exception);
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
`ifdef RVA
        if(i == 0)begin
            assign lreq[i] = ltlb_io[i].miss & ~ltlb_io[i].exception & ~amo_req;
        end
        else begin
`endif
        assign lreq[i] = ltlb_io[i].miss & ~ltlb_io[i].exception;
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
        lreq_addr_s2 <= lvaddr[lreq_idx];
        lidx_s2 <= {lreq_idx, lidx[lreq_idx]};
        lreq_all_s2 <= lreq;
    end
endgenerate

    logic `N(`STORE_PIPELINE) sreq, sreq_all_s2, sreq_cancel_s2;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) svaddr;
    logic `N($clog2(`STORE_PIPELINE)) sreq_idx;
    logic sreq_s2;
    logic `N(`VADDR_SIZE) sreq_addr_s2;
    logic `ARRAY(`STORE_PIPELINE, `STORE_ISSUE_BANK_WIDTH) sidx;
    logic `N(`STORE_ISSUE_BANK_WIDTH+$clog2(`STORE_PIPELINE)) sidx_s2;
generate
    assign sreq_cancel_s2[0] = 0;
    assign sreq_cancel_s2[1] = (stlb_io[0].miss & ~stlb_io[0].exception);
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign sreq[i] = stlb_io[i].miss & ~stlb_io[i].exception;
        always_ff @(posedge clk)begin
            svaddr[i] <= tlb_lsu_io.saddr[i];
            sidx[i] <= tlb_lsu_io.sidx[i];
        end
    end
    PREncoder #(`STORE_PIPELINE) encoder_sreq (sreq, sreq_idx);
    always_ff @(posedge clk)begin
        sreq_s2 <= |sreq;
        sreq_addr_s2 <= svaddr[sreq_idx];
        sreq_all_s2 <= sreq;
        sidx_s2 <= {sreq_idx, sidx[sreq_idx]};
    end
endgenerate

    logic `N(`LOAD_PIPELINE) lreq_cancel_s3, lreq_cancel_s4, lreq_all_s3;
    logic `N(`STORE_PIPELINE) sreq_cancel_s3, sreq_cancel_s4, sreq_all_s3;
    always_ff @(posedge clk)begin
        lreq_cancel_s3 <= lreq_cancel_s2 & {`LOAD_PIPELINE{~flush0}};
        sreq_cancel_s3 <= sreq_cancel_s2 & {`STORE_PIPELINE{~flush1}};
`ifdef RVA
        lreq_cancel_s4 <= lreq_all_s2 & (lreq_cancel_s3 | {`LOAD_PIPELINE{sreq_s2 | amo_req_s2}}) & {`LOAD_PIPELINE{~flush0}};
        sreq_cancel_s4 <= sreq_all_s2 & (sreq_cancel_s3 | {`STORE_PIPELINE{amo_req_s2}}) & {`STORE_PIPELINE{~flush1}};
`else
        lreq_cancel_s4 <= lreq_all_s2 & (lreq_cancel_s3 | {`LOAD_PIPELINE{sreq_s2}}) & {`LOAD_PIPELINE{~flush0}};
        sreq_cancel_s4 <= sreq_all_s2 & sreq_cancel_s3 & {``STORE_PIPELINE{~flush1}};
`endif
        lreq_all_s3 <= lreq_all_s2 & {`LOAD_PIPELINE{~flush0}};
        sreq_all_s3 <= sreq_all_s2 & {`STORE_PIPELINE{~flush1}};
`ifdef RVA
        tlb_l2_io.req <= (sreq_s2 | lreq_s2 | amo_req_s2) & ~flush2;
        tlb_l2_io.info.source <= amo_req_s2 ? 2'b11 : sreq_s2 ? 2'b10 : 2'b01;
        tlb_l2_io.info.idx <= sreq_s2 ? sidx_s2 : lidx_s2;
        tlb_l2_io.req_addr <= amo_req_s2 ? amo_vaddr : sreq_s2 ? sreq_addr_s2 : lreq_addr_s2;
`else
        tlb_l2_io.req <= (sreq_s2 | lreq_s2) & ~flush2;
        tlb_l2_io.info.source <= sreq_s2 ? 2'b10 : 2'b01;
        tlb_l2_io.info.idx <= sreq_s2 ? sidx_s2 : lidx_s2;
        tlb_l2_io.req_addr <= sreq_s2 ? sreq_addr_s2 : lreq_addr_s2;
`endif
    end
    assign tlb_lsu_io.lcancel = lreq_cancel_s4 & ~tlb_lsu_io.flush & ~flush2;
    assign tlb_lsu_io.scancel = sreq_cancel_s4 & ~tlb_lsu_io.flush & ~flush2;

    always_ff @(posedge clk)begin
        tlb_lsu_io.lwb <= {`LOAD_PIPELINE{tlb_l2_io0.dataValid & ~flush0 & (tlb_l2_io0.info_o.source == 2'b01)}} & lwb_pipeline;
        tlb_lsu_io.lwb_exception <= {`LOAD_PIPELINE{tlb_l2_io0.exception}};
        tlb_lsu_io.lwb_error <= {`LOAD_PIPELINE{tlb_l2_io0.error}};
        tlb_lsu_io.lwb_idx <= {`LOAD_PIPELINE{tlb_l2_io0.info_o.idx[`LOAD_ISSUE_BANK_WIDTH-1: 0]}};
        tlb_lsu_io.swb <= {`STORE_PIPELINE{tlb_l2_io0.dataValid & ~flush1 & (tlb_l2_io0.info_o.source == 2'b10)}} & swb_pipeline;
        tlb_lsu_io.swb_exception <= {`STORE_PIPELINE{tlb_l2_io0.exception}};
        tlb_lsu_io.swb_error <= {`STORE_PIPELINE{tlb_l2_io0.error}};
        tlb_lsu_io.swb_idx <= {`STORE_PIPELINE{tlb_l2_io0.info_o.idx[`STORE_ISSUE_BANK_WIDTH-1: 0]}};
`ifdef RVA
        tlb_lsu_io.amo_valid <= amo_req & ~ltlb_io[0].miss | 
                                (tlb_l2_io0.info_o.source == 2'b11) & tlb_l2_io0.dataValid;
        tlb_lsu_io.amo_exception <= (tlb_l2_io0.info_o.source == 2'b11) & tlb_l2_io0.dataValid ? tlb_l2_io0.exception : ltlb_io[0].exception;
        tlb_lsu_io.amo_error <= (tlb_l2_io0.info_o.source == 2'b11) & tlb_l2_io0.dataValid;
        tlb_lsu_io.amo_paddr <= ltlb_io[0].paddr;
`endif
    end
endmodule