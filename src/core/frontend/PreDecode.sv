`include "../../defines/defines.svh"

module PreDecode(
    input logic clk,
    input logic rst,
    CachePreDecodeIO.pd cache_pd_io,
    PreDecodeRedirect.predecode pd_redirect,
    PreDecodeIBufferIO.predecode pd_ibuffer_io,
`ifdef FEAT_MEMPRED
    input logic ssit_en,
    input logic [1: 0][`FSQ_WIDTH-1: 0] ssit_raddr,
    output logic [1: 0][`SSIT_WIDTH-1: 0] ssit_ridx,
`endif
    input FrontendCtrl frontendCtrl
);
    PreDecodeBundle bundles`N(`BLOCK_INST_SIZE);
    PreDecodeBundle bundles_next `N(`BLOCK_INST_SIZE);
    logic `N(`BLOCK_INST_SIZE) redirect_mask_pre, redirect_mask, en_next;
    FsqIdx fsqIdx;
    logic `N(`FSQ_WIDTH) fsqIdx_n, redirect_fsqIdx_n;
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
    logic exc_valid;
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
    logic `N(`BLOCK_INST_SIZE) rvc_mask /*verilator split_var*/;
    logic `N(`BLOCK_INST_SIZE) rvc_en, rvc_en_n;
    logic `N(`BLOCK_INST_SIZE+1) rvc_en_compress;
    logic `ARRAY(`BLOCK_INST_SIZE, `BLOCK_INST_WIDTH) rvc_idx_n, rvc_offset;
    logic `ARRAY(`BLOCK_INST_SIZE/2, `BLOCK_INST_WIDTH-1) rvc_idx_low, rvc_idx_high, rvc_idx_low_n, rvc_idx_high_n;
    logic `N(`BLOCK_INST_WIDTH) rvc_num_half, rvc_num_half_n;
    logic `N(`BLOCK_INST_WIDTH+1) rvc_num;
    logic `N(`PREDICTION_WIDTH) tailIdx_pre, tail_rvi_idx;
    logic `ARRAY(`BLOCK_INST_SIZE, `VADDR_SIZE) addrs;
    logic half_rvi;
    logic `N(`FSQ_SIZE) redirect_half_rvi;
    assign rvc_mask[0] = half_rvi;
    assign addrs[0] = cache_pd_io.stream.start_addr + {~bundles[0].rvc, bundles[0].rvc, 1'b0};
generate
    for(genvar i=1; i<`BLOCK_INST_SIZE; i++)begin
        assign rvc_mask[i] = ~rvc_mask[i-1] & ~bundles[i-1].rvc;
        assign addrs[i] = cache_pd_io.stream.start_addr + (i<<`INST_OFFSET) + {~bundles[i].rvc, bundles[i].rvc, 1'b0};
    end
    for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
        localparam MAX = 2 * (i + 1) < `BLOCK_INST_SIZE ? 2 * (i + 1) : `BLOCK_INST_SIZE;
        localparam NUM = MAX - i;
        logic `N(NUM) equal;
        logic `ARRAY(NUM, `BLOCK_INST_WIDTH) offset;
        logic valid;
        for(genvar j=i; j<MAX; j++)begin
            assign equal[j-i] = rvc_idx_n[j] == i;
            assign offset[j-i] = j;
        end
        OldestSelect #(NUM, 1, `BLOCK_INST_WIDTH) select_offset (
            equal, offset, valid, rvc_offset[i]
        );
    end
    for(genvar i=0; i<`BLOCK_INST_SIZE/2; i++)begin
        assign rvc_idx_n[i] = {1'b0, rvc_idx_low_n[i]};
        assign rvc_idx_n[i+`BLOCK_INST_SIZE/2] = rvc_idx_high_n[i] + rvc_num_half_n;
    end
endgenerate
    assign rvc_en = ~rvc_mask & cache_pd_io.en;
    ParallelAdder #(1, `BLOCK_INST_SIZE) adder_rvc_en(rvc_en, rvc_num);
    ParallelAdder #(1, `BLOCK_INST_SIZE/2) adder_rvc_half(rvc_en[`BLOCK_INST_SIZE/2-1: 0], rvc_num_half);
    CalValidNum #(`BLOCK_INST_SIZE/2) cal_rvc_idx_low(rvc_en[`BLOCK_INST_SIZE/2-1: 0], rvc_idx_low);
    CalValidNum #(`BLOCK_INST_SIZE/2) cal_rvc_idx_high(rvc_en[`BLOCK_INST_SIZE-1: `BLOCK_INST_SIZE/2], rvc_idx_high);
    MaskGen #(`BLOCK_INST_SIZE+1) mask_rvc_en(rvc_num, rvc_en_compress);
    PEncoder #(`BLOCK_INST_SIZE) encoder_tail_idx(rvc_en, tailIdx_pre);
    // pipeline cal tail_rvi_idx if needed
    assign tail_rvi_idx = cache_pd_io.stream.size + {~cache_pd_io.stream.rvc, cache_pd_io.stream.rvc} - 1;
    assign redirect_fsqIdx_n = frontendCtrl.redirectInfo.idx + 1;
    // 如果恰好最后2 byte有效并且是RVI指令，那么需要获得后半条指令并下一个指令块前2 byte无效
    // 当BTB未命中时，获得的数量为BLOCK_INST_SIZE+1, half_rvi为最后一条指令为rvi指令
    // 当BTB命中时，
    // 1) BTB匹配错误, 如果出现跳转，并且错误的跳转地址是rvi,实际的跳转地址是rvc，
    // 并且跳转地址相同，这种情况下可能会多执行一条指令，因此需要重定向
    // 如果没有出现跳转，那么无论预测是否为rvi都不会影响
    // 2) BTB匹配正确，不存在half_rvi的情况，因为BTB每个slot中都有rvc位，
    // 如果匹配成功next pc都会加上rvc,也就是说可能一个块有34byte
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            half_rvi <= 0;
        end
        else if(frontendCtrl.redirect)begin
            half_rvi <= (frontendCtrl.redirectInfo.offset == 0) & frontendCtrl.redirect_mem &
                        redirect_half_rvi[frontendCtrl.redirectInfo.idx];
        end
        else if(pd_redirect.en)begin
            if(jump_en)begin
                half_rvi <= 0;
            end
            else begin
                half_rvi <= redirect_half_rvi[pd_redirect.fsqIdx.idx];
            end
        end
        else if(~frontendCtrl.ibuf_full & cache_pd_io.en[0])begin
            half_rvi <= rvc_en[tailIdx_pre] & (tail_rvi_idx == tailIdx_pre) & ~bundles[tailIdx_pre].rvc;
        end
    end
    assign fsqIdx_n = fsqIdx.idx + 1;
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            redirect_half_rvi <= 0;
        end
        else if(frontendCtrl.redirect & ~frontendCtrl.redirect_mem)begin
            redirect_half_rvi[redirect_fsqIdx_n] <= 1'b0;
        end
        else if(~frontendCtrl.ibuf_full & stream_valid)begin
            redirect_half_rvi[fsqIdx_n] <= half_rvi & ~pd_redirect.en;
        end
    end
`else
    ParallelAdder #(.DEPTH(`BLOCK_INST_SIZE)) adder_instnum (cache_pd_io.en, instNum);
`endif


    always_ff @(posedge clk or negedge rst)begin
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
            exc_valid <= 0;
            start_addr_n <= 0;
            jump_en <= 0;
            jumpSelectIdx <= 0;
            selectOffset <= 0;
            stream_valid <= 0;
`ifdef RVC
            rvc_idx_low_n <= 0;
            rvc_idx_high_n <= 0;
            rvc_num_half_n <= 0;
            rvc_en_n <= 0;
`endif
        end
        else if(pd_redirect.en || frontendCtrl.redirect)begin
            en_next <= 0;
            jump_en <= 0;
            stream_valid <= 0;
        end
        else if(!frontendCtrl.ibuf_full) begin
`ifdef RVC
            for(int i=0; i<`BLOCK_INST_SIZE; i++)begin
                if(cache_pd_io.en[0])begin
                    bundles_next[i] <= bundles[i];
                    data_next[i] <= {cache_pd_io.data[i+1], cache_pd_io.data[i]};
                end
            end
            rvc_idx_low_n <= rvc_idx_low;
            rvc_idx_high_n <= rvc_idx_high;
            rvc_num_half_n <= rvc_num_half;
            en_next <= rvc_en_compress;
            instNumNext <= rvc_num;
            tailIdx <= tailIdx_pre;
            jump_en <= |jump_en_pre;
            jumpSelectIdx <= jumpSelectIdx_pre;
            selectOffset <= jumpSelectIdx_pre;
            shiftIdx <= cache_pd_io.shiftIdx;
            rvc_en_n <= rvc_en;
            exc_valid <= (|cache_pd_io.exception);
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
            exc_valid <= (|cache_pd_io.exception) | (stream.start_addr[1: 0] != 0);
`endif
            stream_valid <= cache_pd_io.en[0];
            fsqIdx <= cache_pd_io.fsqIdx;
            stream_next <= cache_pd_io.stream;
            shiftOffset <= cache_pd_io.shiftOffset;
            ipf <= cache_pd_io.exception;
            
            start_addr_n <= cache_pd_io.start_addr;
            next_pc <= cache_pd_io.stream.start_addr + `BLOCK_SIZE;
        end
    end

    assign selectIdx = jumpSelectIdx;
    assign selectBundle = bundles_next[selectIdx];

    // if nobranch_error is set, redirect this stream as nobranch stream and execute again
    logic nobranch_error, jump_error, entry_error, jump_unmatch;
`ifdef RVC
    assign nobranch_error = (stream_valid & ~exc_valid & (stream_next.taken & 
                            (~bundles_next[tailIdx].branch | 
                            ((bundles_next[tailIdx].rvc ^ stream_next.rvc) | half_rvi)) | 
                            (instNumNext == 0)));
`else
    assign nobranch_error = (stream_valid & stream_next.taken & ~exc_valid & (~bundles_next[tailIdx].branch));
`endif
    logic `N(`VADDR_SIZE) ras_addr;
    assign ras_addr = pd_redirect.ras_addr;

    assign jump_unmatch = (stream_next.taken & ((tailIdx != selectIdx) |
                (bundles_next[tailIdx].jump & (stream_next.target != bundles_next[tailIdx].target))));
    assign jump_error = jump_en & ~exc_valid & ((~stream_next.taken) | jump_unmatch);

    assign entry_error = nobranch_error | jump_en & ~exc_valid & jump_unmatch;

    assign redirect_en = jump_error | nobranch_error;
    assign pd_redirect.en = redirect_en & ~frontendCtrl.ibuf_full;
    assign pd_redirect.exc_en = stream_valid;
    assign pd_redirect.entry_error = entry_error;
    assign pd_redirect.size = jump_en ? rvc_idx_n[selectIdx] + shiftIdx : rvc_idx_n[tailIdx] + shiftIdx;
    assign pd_redirect.direct = jump_en;
    assign pd_redirect.fsqIdx = fsqIdx;
    assign pd_redirect.fsqIdx_pre = cache_pd_io.fsqIdx.idx;
    assign pd_redirect.stream.taken = ~nobranch_error;
    assign pd_redirect.stream.start_addr = start_addr_n;
    assign pd_redirect.stream.target = jump_en ? (
        bundles_next[selectIdx].br_type == POP || bundles_next[selectIdx].br_type == POP_PUSH ? 
            ras_addr : bundles_next[selectIdx].target) : next_pc;
    assign pd_redirect.br_type = jump_en ? bundles_next[selectIdx].br_type : DIRECT;
`ifdef RVC
    assign pd_redirect.stream.rvc = jump_en ? bundles_next[selectIdx].rvc : 0;
    assign pd_redirect.last_offset = jump_en ? selectIdx + shiftOffset :
                                                tailIdx + shiftOffset;
    assign pd_redirect.stream.size = jump_en ? selectOffset + shiftOffset : `BLOCK_INST_SIZE - 2;
`else
    assign pd_redirect.stream.size = jump_en ? selectOffset + shiftOffset : `BLOCK_INST_SIZE - 1;

`endif

    MaskGen #(`BLOCK_INST_SIZE) mask_gen_redirect (rvc_idx_n[selectIdx], redirect_mask_pre);
    assign redirect_mask = jump_en ? {redirect_mask_pre[`BLOCK_INST_SIZE-2: 0], 1'b1} : 0;
    assign pd_ibuffer_io.en = ({`BLOCK_INST_SIZE{~pd_redirect.en}} | redirect_mask) & en_next;
    assign pd_ibuffer_io.num = redirect_en & jump_en ? rvc_idx_n[jumpSelectIdx] + 1 : instNumNext;
    assign pd_ibuffer_io.fsqIdx = fsqIdx.idx;
`ifdef RVC
    // rvc will never raise iam
    assign pd_ibuffer_io.iam = 0;
generate
    for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
        assign pd_ibuffer_io.inst[i] = data_next[rvc_offset[i]];
    end
endgenerate
`else
    assign pd_ibuffer_io.iam = stream_next.start_addr[`INST_OFFSET-1: 0] != 0;
    assign pd_ibuffer_io.inst = data_next;
`endif
    assign pd_ibuffer_io.ipf = ipf;
    assign pd_ibuffer_io.shiftIdx = shiftIdx;
    assign pd_ibuffer_io.start_addr = stream_next.start_addr;
`ifdef FEAT_MEMPRED
    logic ssit_we;
    logic `N(`FSQ_WIDTH) ssit_waddr;
    logic `N(`SSIT_WIDTH) ssit_wdata;
    always_ff @(posedge clk) begin
        ssit_we <= |pd_ibuffer_io.en;
        ssit_waddr <= fsqIdx.idx;
        ssit_wdata <= ssitFoldPC(stream_next.start_addr);
    end
    MPRAM #(
        .WIDTH(`SSIT_WIDTH),
        .DEPTH(`FSQ_SIZE),
        .READ_PORT(2),
        .WRITE_PORT(1)
    ) ssit_ram (
        .clk,
        .rst,
        .rst_sync(1'b0),
        .we(ssit_we),
        .waddr(ssit_waddr),
        .wdata(ssit_wdata),
        .en({2{ssit_en}}),
        .raddr(ssit_raddr),
        .rdata(ssit_ridx),
        .ready()
    );
`endif

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

`ifdef DIFFTEST
    `Log(DLog::Debug, T_PREDECODE, jump_error & ~frontendCtrl.ibuf_full, "ifu jump error")
    `Log(DLog::Debug, T_PREDECODE, nobranch_error & ~frontendCtrl.ibuf_full, "ifu nobranch error")
`endif

endmodule

module PreDecoder(
    input logic `N(32) inst,
    input logic `VADDR_BUS addr,
    output PreDecodeBundle pdBundle
);
    logic [6: 0] op;
    logic [4: 0] rs, rd;
    logic push, pop;
    logic push_valid, pop_valid;
    logic `VADDR_BUS offset;
    assign op = inst[6: 0];
    assign rs = inst[19: 15];
    assign rd = inst[11: 7];
    assign push = rd == 1 || rd == 5;
    assign pop = (rs == 1 || rs == 5) && (rs != rd);

    logic jal, jalr, branch;
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
    logic full_rd_1, full_rd_5;
    logic funct3_0, funct3_1, funct3_2, funct3_3, funct3_4, funct3_5, funct3_6, funct3_7;
    logic normal;

    assign cinst = inst[15: 0];
    assign funct3 = cinst[15: 13];
    assign sign1 = ~cinst[1] & cinst[0];
    assign sign2 = cinst[1] & ~cinst[0];
    assign normal = cinst[1] & cinst[0];
    assign full_rd = cinst[11: 7];
    assign full_rs2 = cinst[6: 2];
    assign funct3_0 = ~funct3[2] & ~funct3[1] & ~funct3[0];
    assign funct3_1 = ~funct3[2] & ~funct3[1] & funct3[0];
    assign funct3_2 = ~funct3[2] & funct3[1] & ~funct3[0];
    assign funct3_3 = ~funct3[2] & funct3[1] & funct3[0];
    assign funct3_4 = funct3[2] & ~funct3[1] & ~funct3[0];
    assign funct3_5 = funct3[2] & ~funct3[1] & funct3[0];
    assign funct3_6 = funct3[2] & funct3[1] & ~funct3[0];
    assign funct3_7 = funct3[2] & funct3[1] & funct3[0];
    assign full_rd_0 = ~full_rd[4] & ~full_rd[3] & ~full_rd[2] & ~full_rd[1] & ~full_rd[0];
    assign full_rd_1 = ~full_rd[4] & ~full_rd[3] & ~full_rd[2] & ~full_rd[1] & full_rd[0];
    assign full_rd_5 = ~full_rd[4] & ~full_rd[3] & full_rd[2] & ~full_rd[1] & full_rd[0];
    assign full_rs2_0 = ~full_rs2[4] & ~full_rs2[3] & ~full_rs2[2] & ~full_rs2[1] & ~full_rs2[0];

    assign cjal_imm = {{`VADDR_SIZE-12{cinst[12]}}, cinst[12], cinst[8], cinst[10: 9], cinst[6], cinst[7], cinst[2], cinst[11], cinst[5: 3], 1'b0};

    logic cj, cjal, cjr, cjalr, cbeqz, cbnez;
`ifdef RV32I
    assign cjal = sign1 & funct3_1;
`else
    assign cjal = 0;
`endif
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
    assign pdBundle.direct = jal | cj | cjal | jalr & pop | 
                             cjr & (full_rd_1 | full_rd_5) | cjalr & full_rd_5;
    assign pdBundle.jump = jal | cj | cjal;
    assign push_valid = (jal | jalr) & push | cjal | cjalr;
    assign pop_valid = jalr & pop | cjr & (full_rd_1 | full_rd_5) | cjalr & full_rd_5;
    assign pdBundle.br_type = jalr & push & ~pop | cjalr & (full_rd == 1) ? INDIRECT_CALL :
                              push_valid & pop_valid ? POP_PUSH :
                              push_valid ? PUSH : pop_valid ? POP : DIRECT;
`else
    assign pdBundle.branch = jal | jalr | branch;
    assign pdBundle.target = addr + offset;
    assign pdBundle.direct = jal | jalr & pop;
    assign pdBudnle.jump = jal;
    assign push_valid = (jal | jalr) & push;
    assign pop_valid = jalr & pop;
    assign pdBundle.br_type = jalr & push & ~pop ? INDIRECT_CALL :
                              push_valid & pop_valid ? POP_PUSH :
                              push_valid ? PUSH : pop_valid ? POP : DIRECT;
`endif
endmodule