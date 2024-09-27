`include "../../defines/defines.svh"

module PreDecode(
    input logic clk,
    input logic rst,
    CachePreDecodeIO.pd cache_pd_io,
    PreDecodeRedirect.predecode pd_redirect,
    PreDecodeIBufferIO.predecode pd_ibuffer_io,
    input FrontendCtrl frontendCtrl
);
    PreDecodeBundle bundles`N(`BLOCK_INST_SIZE);
    PreDecodeBundle bundles_next `N(`BLOCK_INST_SIZE);
    logic `N(`BLOCK_INST_SIZE) redirect_mask, en_next;
    FsqIdx fsqIdx;
    logic `N(`PREDICTION_WIDTH) tailIdx;
    FetchStream stream_next;
    logic `N(`BLOCK_INST_WIDTH) selectIdx, jumpSelectIdx;
    PreDecodeBundle selectBundle;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) data_next;
    logic `N($clog2(`BLOCK_INST_SIZE)+1) instNum, instNumNext;
    logic `N(`VADDR_SIZE) next_pc;
    logic `N(`PREDICTION_WIDTH+1) shiftIdx;
    logic `N(`BLOCK_INST_SIZE) ipf;
    logic `N(`VADDR_SIZE) start_addr_n;

    generate;
        for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
            PreDecoder predecoder(
                                cache_pd_io.data[i], 
                                cache_pd_io.stream.start_addr+(i<<2),
                                bundles[i]);
        end
    endgenerate

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            bundles_next <= '{default: 0};
            en_next <= 0;
            fsqIdx <= 0;
            tailIdx <= 0;
            stream_next <= 0;
            data_next <= 0;
            instNumNext <= 0;
            next_pc <= 0;
            shiftIdx <= 0;
            ipf <= 0;
            start_addr_n <= 0;
        end
        else if(pd_redirect.en || frontendCtrl.redirect)begin
            en_next <= 0;
        end
        else if(!frontendCtrl.ibuf_full) begin
            bundles_next <= bundles;
            en_next <= cache_pd_io.en;
            data_next <= cache_pd_io.data;
            fsqIdx <= cache_pd_io.fsqIdx;
            tailIdx <= cache_pd_io.stream.size;
            stream_next <= cache_pd_io.stream;
            instNumNext <= instNum;
            next_pc <= cache_pd_io.stream.start_addr + cache_pd_io.stream.size + 4;
            shiftIdx <= cache_pd_io.shiftIdx;
            ipf <= cache_pd_io.exception;
            start_addr_n <= cache_pd_io.start_addr;
        end
    end

    logic `N(`BLOCK_INST_SIZE) jump_en;
    logic redirect_en;

    assign selectIdx = jumpSelectIdx;
    assign selectBundle = bundles_next[selectIdx];

    assign redirect_en = (|jump_en) & ((~stream_next.taken) | // 存在直接跳转分支预测不跳转
                            (stream_next.taken & ((tailIdx != jumpSelectIdx) |
                            (bundles_next[tailIdx].br_type != stream_next.branch_type) |
                            (bundles_next[tailIdx].direct & (stream_next.target != bundles_next[tailIdx].target))))) |
                         (en_next[0] & stream_next.taken & ~bundles_next[tailIdx].branch);
    assign pd_redirect.en = redirect_en & ~frontendCtrl.ibuf_full;
    assign pd_redirect.exc_en = |en_next;
    assign pd_redirect.direct = ~(stream_next.taken & ~bundles_next[tailIdx].branch) & (|jump_en);
    assign pd_redirect.fsqIdx = fsqIdx;
    assign pd_redirect.stream.taken = ~(stream_next.taken & ~bundles_next[tailIdx].branch);
    assign pd_redirect.stream.start_addr = start_addr_n;
    assign pd_redirect.stream.branch_type = stream_next.branch_type;
    assign pd_redirect.stream.ras_type = stream_next.ras_type;
    assign pd_redirect.stream.target = en_next[0] & stream_next.taken & ~bundles_next[tailIdx].branch ? next_pc : bundles_next[selectIdx].target;
    assign pd_redirect.stream.size = en_next[0] & stream_next.taken & ~bundles_next[tailIdx].branch ? stream_next.size : selectIdx + shiftIdx;
    assign pd_redirect.ras_type = en_next[0] & stream_next.taken & ~bundles_next[tailIdx].branch ? NONE : bundles_next[selectIdx].ras_type;

    always_comb begin
        case (selectIdx)
            3'b000: redirect_mask = 8'h01;
            3'b001: redirect_mask = 8'h03;
            3'b010: redirect_mask = 8'h07;
            3'b011: redirect_mask = 8'h0f;
            3'b100: redirect_mask = 8'h1f;
            3'b101: redirect_mask = 8'h3f;
            3'b110: redirect_mask = 8'h7f;
            3'b111: redirect_mask = 8'hff;
        endcase
    end
    assign pd_ibuffer_io.en = ({`BLOCK_INST_SIZE{~pd_redirect.en}} | redirect_mask) & en_next;
    assign pd_ibuffer_io.num = redirect_en & (|jump_en) ? selectIdx + 1 : 
                               redirect_en ? tailIdx + 1 : instNumNext;
    assign pd_ibuffer_io.inst = data_next;
    assign pd_ibuffer_io.fsqIdx = fsqIdx.idx;
    assign pd_ibuffer_io.iam = stream_next.start_addr[1: 0] != 0;
    assign pd_ibuffer_io.ipf = ipf;
    assign pd_ibuffer_io.shiftIdx = shiftIdx;

    generate;
        for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
            assign jump_en[i] = en_next[i] & bundles_next[i].direct;
        end
    endgenerate
    ParallelAdder #(.DEPTH(`BLOCK_INST_SIZE)) adder_instnum (cache_pd_io.en, instNum);
    PREncoder #(`BLOCK_INST_SIZE) encoder_jump_idx(jump_en, jumpSelectIdx);

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
    RasType ras_type;
    assign jal = op[6] & op[5] & ~op[4] & op[3] & op[2] & op[1] & op[0];
    assign jalr = op[6] & op[5] & ~op[4] & ~op[3] & op[2] & op[1] & op[0];
    assign branch = op[6] & op[5] & ~op[4] & ~op[3] & ~op[2] & op[1] & op[0];
    assign offset = {{(`VADDR_SIZE-21){inst[31]}}, inst[31], inst[19: 12], inst[20], inst[30: 21], 1'b0};
    assign pdBundle.branch = jal | jalr | branch;
    assign pdBundle.target = addr + offset;
    assign pdBundle.direct = jal;
    assign push = rd == 5'h1 || rd == 5'h5;
    assign pop = rs == 5'h1 || rs == 5'h5;
    always_comb begin
        case({push, pop})
        2'b00: ras_type = NONE;
        2'b01: ras_type = POP;
        2'b10: ras_type = PUSH;
        2'b11: ras_type = POP_PUSH;
        endcase
        pdBundle.ras_type = jal & push ? PUSH :
                            jalr ? ras_type : NONE;
        unique if(jal)begin
            pdBundle.br_type = DIRECT;
        end
        else if(jalr)begin
            pdBundle.br_type = INDIRECT;
        end
        else begin
            pdBundle.br_type = CONDITION;
        end
    end
endmodule