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
    logic `N(`BLOCK_INST_SIZE) redirect_mask_pre, redirect_mask, en_next;
    FsqIdx fsqIdx;
    logic `N(`PREDICTION_WIDTH) tailIdx;
    FetchStream stream_next;
    logic `N(`BLOCK_INST_WIDTH) selectIdx, jumpSelectIdx, jumpSelectIdx_pre;
    logic `N(`PREDICTION_WIDTH) selectOffset;
    PreDecodeBundle selectBundle;
    logic `ARRAY(`BLOCK_INST_SIZE, 32) data_next;
    logic `N($clog2(`BLOCK_INST_SIZE)+1) instNum, instNumNext;
    logic `N(`VADDR_SIZE) next_pc;
    logic `N(`PREDICTION_WIDTH) shiftOffset, shiftIdx;
    logic `N(`BLOCK_INST_SIZE) ipf;
    logic `N(`VADDR_SIZE) start_addr_n;

    logic `N(`BLOCK_INST_SIZE) jump_en_pre;
    logic redirect_en, jump_en;
    logic stream_valid;

generate;
    for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
        PreDecoder predecoder(
                            cache_pd_io.data[i + 4/`INST_BYTE - 1 : i], 
                            cache_pd_io.stream.start_addr+(i<<`INST_OFFSET),
                            bundles[i]);
    end
endgenerate

`ifdef RVC
    /* verilator lint_off UNOPTFLAT */
    logic `N(`BLOCK_INST_SIZE) rvc_mask, rvc_en, rvc_en_compress;
    logic `ARRAY(`BLOCK_INST_SIZE, `BLOCK_INST_WIDTH) rvc_idx, rvc_offset;
    logic `N(`BLOCK_INST_WIDTH+1) rvc_num;
    logic `N(`PREDICTION_WIDTH) tailIdx_pre, tail_rvi_idx;
    logic `N(`PREDICTION_WIDTH+1) stream_tail_idx;
    logic `ARRAY(`BLOCK_INST_SIZE, `VADDR_SIZE) addrs;
    logic half_rvi;
    assign rvc_mask[0] = half_rvi;
    assign addrs[0] = cache_pd_io.stream.start_addr + {~bundles[0].rvc, bundles[0].rvc, 1'b0};
generate
    for(genvar i=1; i<`BLOCK_INST_SIZE; i++)begin
        assign rvc_mask[i] = ~rvc_mask[i-1] & ~bundles[i-1].rvc;
        assign addrs[i] = cache_pd_io.stream.start_addr + (i<<`INST_OFFSET) + {~bundles[i].rvc, bundles[i].rvc, 1'b0};
    end
endgenerate
    assign rvc_en = ~rvc_mask & cache_pd_io.en;
    ParallelAdder #(1, `BLOCK_INST_SIZE) adder_rvc_en(rvc_en, rvc_num);
    CalValidNum #(`BLOCK_INST_SIZE) cal_rvc_idx(rvc_en, rvc_idx);
    MaskGen #(`BLOCK_INST_SIZE+1) mask_rvc_en(rvc_num, rvc_en_compress);
    PEncoder #(`BLOCK_INST_SIZE) encoder_tail_idx(rvc_en, tailIdx_pre);
    PEncoder #(`BLOCK_INST_SIZE+1) encoder_stream_idx(cache_pd_io.en, stream_tail_idx);
    // pipeline cal tail_rvi_idx if needed
    assign tail_rvi_idx = cache_pd_io.stream.size + {~cache_pd_io.stream.rvc, cache_pd_io.stream.rvc} - 1;
    // 如果恰好最后2 byte有效并且是RVI指令，那么需要获得后半条指令并下一个指令块前2 byte无效
    // 当BTB未命中时，获得的数量为BLOCK_INST_SIZE+1, half_rvi为最后一条指令为rvi指令
    // 当BTB命中时，
    // 1) BTB匹配错误, 如果出现跳转，并且错误的跳转地址是rvi,实际的跳转地址是rvc，
    // 并且跳转地址相同，这种情况下可能会多执行一条指令，因此需要重定向
    // 如果没有出现跳转，那么无论预测是否为rvi都不会影响
    // 2) BTB匹配正确，不存在half_rvi的情况，因为BTB每个slot中都有rvc位，
    // 如果匹配成功next pc都会加上rvc,也就是说可能一个块有34byte
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            half_rvi <= 0;
        end
        else if(pd_redirect.en || frontendCtrl.redirect)begin
            half_rvi <= 0;
        end
        else if(~frontendCtrl.ibuf_full & cache_pd_io.en[0])begin
            half_rvi <= rvc_en[tailIdx_pre] & (tail_rvi_idx == tailIdx_pre) & ~bundles[tailIdx_pre].rvc;
        end
    end
`else
    ParallelAdder #(.DEPTH(`BLOCK_INST_SIZE)) adder_instnum (cache_pd_io.en, instNum);
`endif

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
            shiftOffset <= 0;
            ipf <= 0;
            start_addr_n <= 0;
            jump_en <= 0;
            jumpSelectIdx <= 0;
            selectOffset <= 0;
            stream_valid <= 0;
        end
        else if(pd_redirect.en || frontendCtrl.redirect)begin
            en_next <= 0;
            jump_en <= 0;
            stream_valid <= 0;
        end
        else if(!frontendCtrl.ibuf_full) begin
`ifdef RVC
            for(int i=0; i<`BLOCK_INST_SIZE; i++)begin
                if(rvc_en[i])begin
                    bundles_next[rvc_idx[i]] <= bundles[i];
                    data_next[rvc_idx[i]] <= cache_pd_io.data[i +: 2];
                    rvc_offset[rvc_idx[i]] <= i;
                end
            end
            en_next <= rvc_en_compress;
            instNumNext <= rvc_num;
            tailIdx <= rvc_num == 0 ? 0 : rvc_num-1;
            jump_en <= |jump_en_pre;
            jumpSelectIdx <= rvc_idx[jumpSelectIdx_pre];
            selectOffset <= jumpSelectIdx_pre;
            shiftIdx <= cache_pd_io.shiftIdx;
            // rvc_num == 0 说明上一条指令是rvi并且该指令块大小为1并且为rvc指令(BTB预测错误)
            next_pc <= rvc_num == 0 ? cache_pd_io.stream.start_addr + 2 : addrs[tailIdx_pre];
`else
            bundles_next <= bundles;
            en_next <= cache_pd_io.en;
            data_next <= cache_pd_io.data;
            instNumNext <= instNum;
            tailIdx <= cache_pd_io.stream.size;
            jump_en <= |jump_en_pre;
            jumpSelectIdx <= jumpSelectIdx_pre;
            selectOffset <= jumpSelectIdx_pre;
            shiftIdx <= cache_pd_io.shiftOffset;
            next_pc <= cache_pd_io.stream.start_addr + {cache_pd_io.stream.size, {`INST_OFFSET{1'b0}}} + 4;
`endif
            stream_valid <= cache_pd_io.en[0];
            fsqIdx <= cache_pd_io.fsqIdx;
            stream_next <= cache_pd_io.stream;
            shiftOffset <= cache_pd_io.shiftOffset;
            ipf <= cache_pd_io.exception;
            start_addr_n <= cache_pd_io.start_addr;
        end
    end

    assign selectIdx = jumpSelectIdx;
    assign selectBundle = bundles_next[selectIdx];

    logic nobranch_error, jump_error;
    assign nobranch_error = (stream_valid & stream_next.taken & (~bundles_next[tailIdx].branch
`ifdef RVC
    | ((bundles_next[tailIdx].rvc ^ stream_next.rvc) | half_rvi)
`endif
    ));
    assign jump_error = jump_en & ((~stream_next.taken) | // 存在直接跳转分支预测不跳转
                            (stream_next.taken & ((tailIdx != selectIdx) |
                            (bundles_next[tailIdx].direct & (stream_next.target != bundles_next[tailIdx].target)))));

    assign redirect_en = jump_error | nobranch_error;
    assign pd_redirect.en = redirect_en & ~frontendCtrl.ibuf_full;
    assign pd_redirect.exc_en = stream_valid;
    assign pd_redirect.size = jump_en ? selectIdx + shiftIdx :
                              nobranch_error ? tailIdx : tailIdx + shiftIdx;
    assign pd_redirect.direct = jump_en;
    assign pd_redirect.fsqIdx = fsqIdx;
    assign pd_redirect.stream.taken = ~nobranch_error;
    assign pd_redirect.stream.start_addr = start_addr_n;
    assign pd_redirect.stream.target = jump_en ? bundles_next[selectIdx].target : next_pc;
`ifdef RVC
    assign pd_redirect.stream.rvc = jump_en ? bundles_next[selectIdx].rvc : bundles_next[tailIdx].rvc;
    assign pd_redirect.last_offset = jump_en ? rvc_offset[selectIdx] + shiftOffset :
                                                rvc_offset[tailIdx] + shiftOffset;
    assign pd_redirect.empty = instNumNext == 0;
    assign pd_redirect.stream.size = jump_en ? selectOffset + shiftOffset : rvc_offset[tailIdx] + shiftOffset;
`else
    assign pd_redirect.stream.size = jump_en ? selectOffset + shiftOffset : stream_next.size;

`endif

    MaskGen #(`BLOCK_INST_SIZE) mask_gen_redirect (selectIdx, redirect_mask_pre);
    assign redirect_mask = {redirect_mask_pre[`BLOCK_INST_SIZE-2: 0], 1'b1};
    assign pd_ibuffer_io.en = ({`BLOCK_INST_SIZE{~pd_redirect.en}} | redirect_mask) & en_next;
    assign pd_ibuffer_io.num = redirect_en & jump_en ? selectIdx + 1 : 
                               redirect_en ? tailIdx + 1 : instNumNext;
    assign pd_ibuffer_io.inst = data_next;
    assign pd_ibuffer_io.fsqIdx = fsqIdx.idx;
    assign pd_ibuffer_io.iam = stream_next.start_addr[`INST_OFFSET-1: 0] != 0;
    assign pd_ibuffer_io.ipf = ipf;
    assign pd_ibuffer_io.shiftIdx = shiftIdx;

generate
    for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
`ifdef RVC
        assign pd_ibuffer_io.offset[i] = rvc_offset[i] + shiftOffset;
        assign jump_en_pre[i] = rvc_en[i] & bundles[i].direct;
`else
        assign pd_ibuffer_io.offset[i] = i + shiftOffset;
        assign jump_en_pre[i] = cache_pd_io.en[i] & bundles[i].direct;
`endif
    end
endgenerate
    PREncoder #(`BLOCK_INST_SIZE) encoder_jump_idx(jump_en_pre, jumpSelectIdx_pre);
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

`ifdef RVC
    logic `N(16) cinst;
    logic `N(5) full_rd, full_rs2;
    logic `N(3) funct3;
    logic `VADDR_BUS cjal_imm;
    logic sign1, sign2;
    logic full_rd_0, full_rs2_0;
    logic funct3_0, funct3_1, funct3_2, funct3_3, funct3_4, funct3_5, funct3_6, funct3_7;
    logic normal;

    assign cinst = inst[15: 0];
    assign funct3 = cinst[15: 13];
    assign sign1 = ~cinst[1] & cinst[0];
    assign sign2 = cinst[1] & ~cinst[0];
    assign normal = cinst[1] & cinst[0];
    assign funct3_0 = ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign funct3_1 = ~funct3[2] & ~funct3[1] & funct3[0];
    assign funct3_2 = ~funct3[2] & funct3[1] & ~funct3[0];
    assign funct3_3 = ~funct3[2] & funct3[1] & funct3[0];
    assign funct3_4 = funct3[2] & ~funct3[1] & ~funct3[0];
    assign funct3_5 = funct3[2] & ~funct3[1] & funct3[0];
    assign funct3_6 = funct3[2] & funct3[1] & ~funct3[0];
    assign funct3_7 = funct3[2] & funct3[1] & funct3[0];
    assign full_rd_0 = ~full_rd[4] & ~full_rd[3] & ~full_rd[2] & ~full_rd[1] & ~full_rd[0];
    assign full_rs2_0 = ~full_rs2[4] & ~full_rs2[3] & ~full_rs2[2] & ~full_rs2[1] & ~full_rs2[0];

    assign cjal_imm = {{`VADDR_SIZE-12{cinst[12]}}, cinst[12], cinst[8], cinst[10: 9], cinst[6], cinst[7], cinst[2], cinst[11], cinst[5: 3], 1'b0};

    logic cj, cjal, cjr, cjalr, cbeqz, cbnez;
    assign cjal = sign1 & funct3_1;
    assign cj = sign1 & funct3_5;
    assign cbeqz = sign1 & funct3_6;
    assign cbnez = sign1 & funct3_7;
    assign cjr = sign2 & funct3_4 & ~cinst[12] & ~full_rd_0 & full_rs2_0;
    assign cjalr = sign2 & funct3_4 & cinst[12] & ~full_rd_0 & full_rs2_0;

    logic `VADDR_BUS offset_o;
    assign offset_o = normal ? offset : cjal_imm;
    assign pdBundle.rvc = ~normal;
    assign pdBundle.branch = jal | jalr | branch | cj | cjal | cjr | cjalr | cbeqz | cbnez;
    assign pdBundle.target = addr + offset_o;
    assign pdBundle.direct = jal | cj | cjal;
`else
    assign pdBundle.branch = jal | jalr | branch;
    assign pdBundle.target = addr + offset;
    assign pdBundle.direct = jal;
`endif
endmodule