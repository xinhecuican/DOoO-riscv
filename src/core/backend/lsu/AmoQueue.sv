`include "../../../defines/defines.svh"

module AmoQueue(
    input logic clk,
    input logic rst,
    DisIssueIO.issue dis_amo_io,
    input BackendCtrl backendCtrl,
    CommitBus.mem commitBus,
    IssueRegIO.issue amo_reg_io,

    output logic amo_valid,
    output RobIdx amo_idx,

    output logic tlb_req,
    output logic `N(`VADDR_SIZE) amo_vaddr,
    input logic tlb_valid,
    input logic tlb_error,
    input logic tlb_exception,
    input logic `N(`PADDR_SIZE) amo_paddr,

    output logic store_flush,
    input logic flush_end,

    DCacheAmoIO.buffer amo_io,

    input logic wb_ready,
    output WBData wbData
);
    typedef enum  { IDLE, LOOKUP, TLB_REQ, CACHE_REQ, WB } State;
    State state;
    logic `N(`PREG_WIDTH) rs1, rs2, rd;
    logic we;
    logic datav, waiting_data;
    logic `N(`XLEN) rs1_data, rs2_data;
    RobIdx robIdx;
    logic `N(`AMOOP_WIDTH) amoop;
    AmoIssueBundle bundle;
    logic `N(`PADDR_SIZE) paddr;
    logic misalign_pre;
    logic misalign, tlb_exc;
    logic islr;
    logic `N(`XLEN) rdata;
    logic flush_ready, tlb_ready;
    logic redirect_older;

    assign dis_amo_io.full = state != IDLE && !(state == WB && wb_ready);
    assign bundle = dis_amo_io.data[0];
    assign amo_valid = state != IDLE;
    assign amo_idx = robIdx;

    assign amo_reg_io.en[0] = state == LOOKUP && commitBus.robIdx == robIdx && !waiting_data && !datav;
    assign amo_reg_io.preg[0] = rs1;
    assign amo_reg_io.preg[1] = rs2;
    always_ff @(posedge clk)begin
        waiting_data <= amo_reg_io.en[0];
        if(datav && state == LOOKUP)begin
            rs1_data <= amo_reg_io.data[0];
            rs2_data <= amo_reg_io.data[1];
        end
        if(tlb_valid)begin
            paddr <= amo_paddr;
        end
        if(amo_io.success)begin
            rdata <= amo_io.rdata;
        end
    end
    assign amo_vaddr = rs1_data;
    MisalignDetect misalign_detect (2'b10, rs1_data[1: 0], misalign_pre);
    LoopCompare #(`ROB_WIDTH) cmp_bigger (backendCtrl.redirectIdx, robIdx, redirect_older);

    assign amo_io.paddr = paddr;
    assign amo_io.data = rs2_data;
    assign amo_io.op = amoop;
    assign amo_io.mask = {`DCACHE_BYTE{1'b1}};

    assign wbData.en = state == WB;
    assign wbData.we = we;
    assign wbData.robIdx = robIdx;
    assign wbData.rd = rd;
    assign wbData.exccode = misalign & islr ? `EXC_LAM :
                            misalign & ~islr ? `EXC_SAM :
                            tlb_exc & islr ? `EXC_LPF :
                            tlb_exc & ~islr ? `EXC_SPF : `EXC_NONE;
    assign wbData.res = rdata;

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            datav <= 1'b0;
            tlb_req <= 1'b0;
            misalign <= 1'b0;
            tlb_exc <= 1'b0;
            islr <= 1'b0;
            we <= 1'b0;
            store_flush <= 1'b0;
            flush_ready <= 1'b0;
            tlb_ready <= 1'b0;
        end
        else begin
            if(dis_amo_io.en & ~dis_amo_io.full)begin
                rs1 <= dis_amo_io.status[0].rs1;
                rs2 <= dis_amo_io.status[0].rs2;
                rd <= dis_amo_io.status[0].rd;
                robIdx <= dis_amo_io.status[0].robIdx;
                we <= dis_amo_io.status[0].we;
                amoop <= bundle.amoop;
                datav <= 1'b0;
                misalign <= 1'b0;
                tlb_exc <= 1'b0;
                islr <= bundle.amoop == `AMO_LR;
            end
            case(state)
            IDLE: begin
                if(dis_amo_io.en)begin
                    state <= LOOKUP;
                end
            end
            LOOKUP: begin
                if(waiting_data)begin
                    datav <= 1'b1;
                end
                if(datav)begin
                    if(misalign_pre)begin
                        misalign <= 1'b1;
                        state <= WB;
                    end
                    else begin
                        state <= TLB_REQ;
                        tlb_req <= 1'b1;
                        store_flush <= 1'b1;
                        tlb_ready <= 1'b0;
                        flush_ready <= 1'b0;
                    end
                end
                else if(backendCtrl.redirect & redirect_older)begin
                    state <= IDLE;
                end
            end
            TLB_REQ: begin
                if(tlb_req)begin
                    tlb_req <= 1'b0;
                end
                if(tlb_valid & tlb_exception)begin
                    state <= WB;
                    tlb_exc <= 1'b1;
                end
                else if(tlb_valid & tlb_error)begin
                    tlb_req <= 1'b1;
                end
                else if(tlb_valid)begin
                    tlb_ready <= 1'b1;
                end

                if(store_flush & flush_end)begin
                    store_flush <= 1'b0;
                    flush_ready <= 1'b1;
                end

                if(flush_ready & tlb_ready)begin
                    state <= CACHE_REQ;
                    amo_io.req <= 1'b1;
                end
            end
            CACHE_REQ: begin
                if(amo_io.req & amo_io.ready)begin
                    amo_io.req <= 1'b0;
                end
                if(amo_io.success)begin
                    state <= WB;
                end
                if(amo_io.refill)begin
                    amo_io.req <= 1'b1;
                end
            end
            WB: begin
                if(wb_ready)begin
                    if(dis_amo_io.en)begin
                        state <= LOOKUP;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
            end
            endcase
        end
    end
endmodule