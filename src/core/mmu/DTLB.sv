`include "../../defines/defines.svh"

module DTLB(
    input logic clk,
    input logic rst,
    DTLBLsuIO.tlb tlb_lsu_io,
    CsrTlbIO.tlb csr_ltlb_io,
    CsrTlbIO.tlb csr_stlb_io,
    TlbL2IO.tlb tlb_l2_io
);
    TLBIO #(`DTLB_SIZE) ltlb_io `N(`LOAD_PIPELINE) ();
    TLBIO #(`DTLB_SIZE) stlb_io `N(`LOAD_PIPELINE) ();
    logic flush0, flush1, flush2;

    logic `N(`LOAD_PIPELINE) lwb_pipeline;
    Decoder #(`LOAD_PIPELINE) decoder_load_pipe (tlb_l2_io.info_o.idx[`TLB_IDX_SIZE-1: `LOAD_ISSUE_BANK_WIDTH], lwb_pipeline);
    logic `N(`STORE_PIPELINE) swb_pipeline;
    Decoder #(`STORE_PIPELINE) decoder_store_pipe (tlb_l2_io.info_o.idx[`TLB_IDX_SIZE-1: `LOAD_ISSUE_BANK_WIDTH], swb_pipeline);

    ReplaceD1IO #(.WAY_NUM(`DTLB_SIZE)) replace_io();
    RandomReplaceD1 #(1, `DTLB_SIZE) replace (.*);
    assign replace_io.hit_en = 0;
    assign replace_io.hit_way = 0;

    always_ff @(posedge clk)begin
        flush0 <= tlb_lsu_io.flush;
        flush1 <= tlb_lsu_io.flush;
        flush2 <= tlb_lsu_io.flush;
    end

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        TLB #(`DTLB_SIZE, 2'b01) ltlb(
            .*,
            .io(ltlb_io[i]),
            .csr_tlb_io(csr_ltlb_io)
        );
        assign ltlb_io[i].req = tlb_lsu_io.lreq[i];
        assign ltlb_io[i].vaddr = tlb_lsu_io.laddr[i];
        assign ltlb_io[i].flush = tlb_lsu_io.flush;
        
        assign ltlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception &  (tlb_l2_io0.info_o.source != 2'b00) & ~flush0;
        assign ltlb_io[i].widx = replace_io.miss_way;
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
        TLB #(`DTLB_SIZE, 2'b10) stlb(
            .*,
            .io(stlb_io[i]),
            .csr_tlb_io(csr_stlb_io)
        );
        assign stlb_io[i].req = tlb_lsu_io.sreq[i];
        assign stlb_io[i].vaddr = tlb_lsu_io.saddr[i];
        assign stlb_io[i].flush = tlb_lsu_io.flush;

        assign stlb_io[i].we = tlb_l2_io0.dataValid & ~tlb_l2_io0.error & ~tlb_l2_io0.exception & (tlb_l2_io0.info_o.source != 2'b00) & ~flush1;
        assign stlb_io[i].widx = replace_io.miss_way;
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

    TlbL2IO tlb_l2_io0();
    TlbL2IO tlb_l2_io1();
    TLBRepeater repeater0(.*, .flush(flush0), .in(tlb_l2_io0), .out(tlb_l2_io1));
    TLBRepeater repeater1(.*, .flush(flush1), .in(tlb_l2_io1), .out(tlb_l2_io));

    logic `N(`LOAD_PIPELINE) lreq, lreq_all_s2, lreq_cancel_s2;
    logic `ARRAY(`LOAD_PIPELINE, `VADDR_SIZE) lvaddr;
    logic `N($clog2(`LOAD_PIPELINE)) lreq_idx;
    logic lreq_s2;
    logic `N(`VADDR_SIZE) lreq_addr_s2;
    logic `ARRAY(`LOAD_PIPELINE, `LOAD_ISSUE_BANK_WIDTH) lidx;
    logic `N(`LOAD_ISSUE_BANK_WIDTH+$clog2(`LOAD_PIPELINE)) lidx_s2;
generate
    /* UNPARAM */
    assign lreq_cancel_s2[0] = 0;
    assign lreq_cancel_s2[1] = ~(ltlb_io[0].miss & ~ltlb_io[0].exception);
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        assign lreq[i] = ltlb_io[i].miss & ~ltlb_io[i].exception;
        always_ff @(posedge clk)begin
            lvaddr[i] <= tlb_lsu_io.laddr[i];
            lidx[i] <= tlb_lsu_io.lidx[i];
        end
    end
    PEncoder #(`LOAD_PIPELINE) encoder_lreq (lreq, lreq_idx);
    always_ff @(posedge clk)begin
        lreq_s2 <= |lreq;
        lreq_addr_s2 <= lvaddr[lreq_idx];
        lidx_s2 <= {lreq_idx, lvaddr[lreq_idx]};
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
    assign sreq_cancel_s2[1] = ~(stlb_io[0].miss & ~stlb_io[0].exception);
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign sreq[i] = stlb_io[i].miss & ~stlb_io[i].exception;
        always_ff @(posedge clk)begin
            svaddr[i] <= tlb_lsu_io.saddr[i];
            sidx[i] <= tlb_lsu_io.sidx[i];
        end
    end
    PEncoder #(`STORE_PIPELINE) encoder_sreq (sreq, sreq_idx);
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
        lreq_cancel_s4 <= lreq_all_s2 & (lreq_cancel_s3 | {`LOAD_PIPELINE{sreq_s2}}) & {`LOAD_PIPELINE{~flush0}};
        sreq_cancel_s4 <= sreq_all_s3 & sreq_cancel_s3 & {`LOAD_PIPELINE{~flush1}};
        lreq_all_s3 <= lreq_all_s2 & {`LOAD_PIPELINE{~flush0}};
        sreq_all_s3 <= sreq_all_s2 & {`LOAD_PIPELINE{~flush1}};
        tlb_l2_io.req <= (sreq_s2 | lreq_s2) & ~flush2;
        tlb_l2_io.info.source <= sreq_s2 ? 2'b10 : 2'b01;
        tlb_l2_io.info.idx <= sreq_s2 ? sidx_s2 : lidx_s2;
        tlb_l2_io.req_addr <= sreq_s2 ? sreq_addr_s2 : lreq_addr_s2;
    end
    assign tlb_lsu_io.lcancel = lreq_cancel_s4 & ~tlb_lsu_io.flush & ~flush2;
    assign tlb_lsu_io.scancel = sreq_cancel_s4 & ~tlb_lsu_io.flush & ~flush2;

    always_ff @(posedge clk)begin
        tlb_lsu_io.lwb <= {`LOAD_PIPELINE{tlb_l2_io0.dataValid & ~flush0 & (tlb_l2_io0.info_o.source == 2'b01)}} & lwb_pipeline;
        tlb_lsu_io.lwb_exception <= {`LOAD_PIPELINE{tlb_l2_io0.exception}};
        tlb_lsu_io.lwb_error <= {`LOAD_PIPELINE{tlb_l2_io0.error}};
        tlb_lsu_io.swb <= {`STORE_PIPELINE{tlb_l2_io0.dataValid & ~flush1 & (tlb_l2_io0.info_o.source == 2'b10)}} & swb_pipeline;
        tlb_lsu_io.swb_exception <= {`STORE_PIPELINE{tlb_l2_io0.exception}};
        tlb_lsu_io.swb_error <= {`STORE_PIPELINE{tlb_l2_io0.error}};
    end
endmodule