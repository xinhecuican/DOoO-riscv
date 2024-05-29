`include "../../defines/defines.svh"

module PreDecode(
    input logic clk,
    input logic rst,
    CachePreDecodeIO.pd cache_pd_io,
    PreDecodeRedirect.predecode pd_redirect,
    PreDecodeIBufferIO.predecode pd_ibuffer_io,
    FrontendCtrl frontendCtrl
);
    PreDecodeBundle bundles`N(`BLOCK_INST_SIZE);
    PreDecodeBundle bundles_next `N(`BLOCK_INST_SIZE);
    logic `N(`BLOCK_INST_SIZE) en_next;
    logic `N(`FSQ_WIDTH) fsqIdx;
    logic `N(`PREDICTION_WIDTH) tailIdx;
    FetchStream stream_next;
    logic `N(`ICACHE_BANK_WIDTH) selectIdx, jumpSelectIdx;
    PreDecodeBundle selectBundle;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) data_next;
    logic `N($clog2(`BLOCK_INST_SIZE)+1) instNum, instNumNext;

    generate;
        for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
            PreDecoder predecoder(
                                cache_pd_io.data[i], 
                                cache_pd_io.stream.start_addr+(i<<2),
                                bundles[i]);
        end
    endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST || pd_redirect.en || frontendCtrl.redirect)begin
            bundles_next <= '{default: 0};
            en_next <= 0;
            fsqIdx <= 0;
            tailIdx <= 0;
            stream_next <= 0;
            data_next <= 0;
            instNumNext <= 0;
        end
        else if(!frontendCtrl.ibuf_full) begin
            bundles_next <= bundles;
            en_next <= cache_pd_io.en;
            data_next <= cache_pd_io.data;
            fsqIdx <= cache_pd_io.fsqIdx;
            tailIdx <= cache_pd_io.stream.size;
            stream_next <= cache_pd_io.stream;
            instNumNext <= instNum;
        end
    end

    logic `N(`BLOCK_INST_SIZE) jump_en;
    assign pd_redirect.en = (~stream_next.taken & (|jump_en)) |
                            (stream_next.taken & ((tailIdx != jumpSelectIdx) |
                            bundles_next[tailIdx].direct & (stream_next.target != bundles_next[tailIdx].target)));
    assign pd_redirect.fsqIdx = fsqIdx;
    assign selectIdx = jumpSelectIdx;
    assign selectBundle = bundles_next[selectIdx];
    assign pd_redirect.offset = selectIdx;
    assign pd_redirect.br_type = bundles_next[selectIdx].br_type;
    assign pd_redirect.ras_type = bundles_next[selectIdx].ras_type;
    assign pd_redirect.pc = stream_next.start_addr;
    assign pd_redirect.redirect_addr = bundles_next[selectIdx].target;

    assign pd_ibuffer_io.en = {`BLOCK_INST_SIZE{~pd_redirect.en}} & en_next;
    assign pd_ibuffer_io.num = instNumNext;
    assign pd_ibuffer_io.inst = data_next;
    assign pd_ibuffer_io.fsqIdx = fsqIdx;

    generate;
        for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
            assign jump_en[i] = en_next[i] & bundles_next[i].direct;
        end
    endgenerate
    ParallelAdder #(.DEPTH(`BLOCK_INST_SIZE)) adder_instnum (cache_pd_io.en, instNum);
    PEncoder #(`BLOCK_INST_SIZE) encoder_jump_idx(jump_en, jumpSelectIdx);

endmodule

module PreDecoder(
    input logic `N(32) inst,
    input logic `VADDR_BUS addr,
    output PreDecodeBundle pdBundle
);
    logic [6: 0] op;
    logic [4: 0] rs, rd;
    logic push, pop;
    logic `VADDR_BUS offset;
    assign op = inst[6: 0];
    assign rs = inst[19: 15];
    assign rd = inst[11: 7];

    logic jal, jalr, branch;
    assign jal = op[6] & op[5] & ~op[4] & op[3] & op[2] & op[1] & op[0];
    assign jalr = op[6] & op[5] & ~op[4] & ~op[3] & op[2] & op[1] & op[0];
    assign branch = op[6] & op[5] & ~op[4] & ~op[3] & ~op[2] & op[1] & op[0];
    assign offset = {{(`VADDR_SIZE-21){inst[31]}}, inst[31], inst[19: 12], inst[20], inst[30: 21], 1'b0};
    assign pdBundle.branch = jal | jalr | branch;
    assign pdBundle.target = addr + offset;
    assign pdBundle.direct = jal | jalr;
    assign push = rd == 5'h1 || rd == 5'h5;
    assign pop = rs == 5'h1 || rs == 5'h5;
    always_comb begin
        case({push, pop})
        2'b00: pdBundle.ras_type = NONE;
        2'b01: pdBundle.ras_type = POP;
        2'b10: pdBundle.ras_type = PUSH;
        2'b11: pdBundle.ras_type = POP_PUSH;
        endcase
        unique if(jal)begin
            pdBundle.br_type = DIRECT;
        end
        else if(jalr)begin
            unique if(push | pop)begin
                pdBundle.br_type = CALL;
            end
            else begin
                pdBundle.br_type = INDIRECT;
            end
        end
        else begin
            pdBundle.br_type = CONDITION;
        end
    end
endmodule