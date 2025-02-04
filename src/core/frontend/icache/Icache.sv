`include "../../../defines/defines.svh"

module ICache(
    input logic clk,
    input logic rst,
    FsqCacheIO.cache fsq_cache_io,
    CachePreDecodeIO.cache cache_pd_io,
    CacheBus.masterr axi_io,
    TlbL2IO.tlb itlb_io,
    CsrTlbIO.tlb csr_itlb_io,
    FenceBus.mmu fenceBus
`ifdef EXT_FENCEI
    ,input logic fenceReq,
    output logic fenceEnd
`endif
);

    localparam PARTIAL_ADDR_WIDTH = `ICACHE_LINE_WIDTH-`INST_OFFSET+1;
    localparam BLOCK_DELTA = `ICACHE_BYTE / `INST_BYTE;
    localparam LINE_INST_NUM = `ICACHE_LINE / `INST_BYTE;
    typedef struct packed {
        logic `N(`ICACHE_SET_WIDTH) index1, index2;
        logic `ARRAY(2, `ICACHE_BANK) expand_en;

        logic `ARRAY(2, LINE_INST_NUM) expand_en_block;
        logic `N(PARTIAL_ADDR_WIDTH) start_offset;
        logic `N(2) span;
        logic multi_tag;
        FetchStream stream;
        logic `N(`VADDR_SIZE) start_addr;
        FsqIdx fsqIdx;
        logic `N(`PREDICTION_WIDTH) shiftOffset;
`ifdef RVC
        logic `N(`PREDICTION_WIDTH) shiftIdx;
        logic `N(`BLOCK_INST_SIZE+1) expand_en_shift;
`else
        logic `N(`BLOCK_INST_SIZE) expand_en_shift;
`endif
    } RequestBuffer;
    RequestBuffer request_buffer;

    typedef struct packed {
        logic `N(`ICACHE_TAG + `ICACHE_SET_WIDTH) paddr;
        logic `N(`ICACHE_TAG + `ICACHE_SET_WIDTH) addition_paddr;
        logic addition_request;
        logic flush;
        logic `N(`BLOCK_INST_WIDTH+1) current_index;
        logic `ARRAY(`BLOCK_INST_SIZE+BLOCK_DELTA, `INST_BITS) data;
        logic `ARRAY(`ICACHE_BANK, 32) replace_data;
        logic `N(`ICACHE_SET_WIDTH) windex;
        logic `N(`ICACHE_BANK_WIDTH) stream_index;
        logic line;
    } MissBuffer;
    MissBuffer miss_buffer;
    logic `N(`ICACHE_BANK_WIDTH) next_stream_index;
    assign next_stream_index = miss_buffer.stream_index + 1;

    typedef enum { IDLE, LOOKUP, MISS, REFILL } MainState;
    MainState main_state;
`ifdef EXT_FENCEI
    logic fenceValid;
    logic `N(`ICACHE_SET_WIDTH) fenceIdx;
`endif

    ITLBCacheIO itlb_cache_io();
    ITLB itlb(.*, .tlb_l2_io(itlb_io));



    logic `N(`ICACHE_BANK * 2) expand_en;
    logic `N(LINE_INST_NUM * 2) expand_exception;
    logic `N(LINE_INST_NUM * 2) expand_en_block, start_addr_mask, end_addr_mask;
    logic `N(`BLOCK_INST_SIZE) expand_en_shift;

    logic `N(PARTIAL_ADDR_WIDTH) end_addr, start_addr;
    logic `N(`PREDICTION_WIDTH+1) stream_size, block_stream_size;
    logic `ARRAY(`ICACHE_BANK, 32) rdata `N(`ICACHE_WAY);
    logic `N(`ICACHE_SET_WIDTH) index;
    logic `N(`ICACHE_SET_WIDTH+1) indexp1;
    logic `N(`VADDR_SIZE-`TLB_OFFSET) vtag1, vtag2;
    logic `N(`ICACHE_TAG) ptag1, ptag2;
    logic `N(2) span;
    logic `ARRAY(2, `ICACHE_WAY) hit;
    logic `ARRAY(2, `ICACHE_WAY_WIDTH) hit_index;
    logic [1: 0] cache_hit, cache_miss;
    logic refill_en; // refill data to cache
    logic miss_data_en; // send miss data to ifu
    logic abandon_lookup, abandon_idle;
    logic stall_wait;
    logic `N(`ICACHE_WAY) replace_way;
    logic cache_stall;

    assign start_addr = fsq_cache_io.stream.start_addr[`ICACHE_LINE_WIDTH-1: `INST_OFFSET] + fsq_cache_io.shiftOffset;
`ifdef RVC
    assign stream_size = fsq_cache_io.stream.size + {~fsq_cache_io.stream.rvc, fsq_cache_io.stream.rvc} + 1;
    assign block_stream_size = fsq_cache_io.stream.size + {~fsq_cache_io.stream.rvc, fsq_cache_io.stream.rvc} - fsq_cache_io.shiftOffset;
`else
    assign stream_size = fsq_cache_io.stream.size + 1;
    assign block_stream_size = fsq_cache_io.stream.size - fsq_cache_io.shiftOffset + 1;
`endif
    assign end_addr = fsq_cache_io.stream.start_addr[`ICACHE_LINE_WIDTH-1: `INST_OFFSET] + stream_size;
    assign span[1] = end_addr[PARTIAL_ADDR_WIDTH-1] & (|end_addr[PARTIAL_ADDR_WIDTH-2: 0]);
    assign span[0] = start_addr[PARTIAL_ADDR_WIDTH-1];
    MaskGen #((`ICACHE_LINE / `INST_BYTE)*2) mask_gen_start_addr (start_addr, start_addr_mask);
    MaskGen #((`ICACHE_LINE / `INST_BYTE)*2) mask_gen_end_addr (end_addr, end_addr_mask);
    MaskGen #(`BLOCK_INST_SIZE+1) mask_gen_shift_en (block_stream_size, expand_en_shift); 
    assign expand_en_block = start_addr_mask ^ end_addr_mask;
generate
    for(genvar i=0; i<`ICACHE_BANK*2; i++)begin
        assign expand_en[i] = |expand_en_block[i*BLOCK_DELTA +: BLOCK_DELTA];
    end
endgenerate
    assign expand_exception = {request_buffer.expand_en_block[1] & {LINE_INST_NUM{itlb_cache_io.exception[1]}},
                              request_buffer.expand_en_block[0] & {LINE_INST_NUM{itlb_cache_io.exception[0]}}};
    assign index = fsq_cache_io.stream.start_addr`ICACHE_SET_BUS;
    assign indexp1 = index + 1;
    assign refill_en = main_state == REFILL && axi_io.r_valid && next_stream_index == 0;
    assign abandon_lookup = fsq_cache_io.abandon &&
                            request_buffer.fsqIdx == fsq_cache_io.abandonIdx;
    assign abandon_idle = fsq_cache_io.abandon &&
                          fsq_cache_io.fsqIdx == fsq_cache_io.abandonIdx;

    assign itlb_cache_io.req = {span[1] & fsq_cache_io.en & ~fsq_cache_io.stall, ~span[0] & fsq_cache_io.en & ~fsq_cache_io.stall} & {2{fsq_cache_io.ready}};
    assign vtag1 = fsq_cache_io.stream.start_addr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign vtag2 = vtag1 + indexp1[`ICACHE_SET_WIDTH];
    assign itlb_cache_io.vaddr = {{vtag2, `TLB_OFFSET'b0}, {vtag1, `TLB_OFFSET'b0}};
    assign itlb_cache_io.flush = fsq_cache_io.flush | (main_state == LOOKUP) & abandon_lookup;
    assign itlb_cache_io.ready = ~fsq_cache_io.stall;
    assign ptag1 = itlb_cache_io.paddr[0][`PADDR_SIZE-1: `TLB_OFFSET];
    assign ptag2 = itlb_cache_io.paddr[1][`PADDR_SIZE-1: `TLB_OFFSET];
    assign cache_stall = fsq_cache_io.stall | ((main_state == LOOKUP) & (itlb_cache_io.miss & ~(|itlb_cache_io.exception)));

    logic `N(`ICACHE_WAY) tagv_we;
    logic `N(`ICACHE_SET_WIDTH) tagv_index, tagv_windex;
    logic `N(`ICACHE_TAG+1) tagv_wdata;
    logic `ARRAY(`ICACHE_WAY, `ICACHE_TAG+1) tagv0, tagv1;
    logic `N(`ICACHE_BANK) data_en;
    logic `ARRAY(`ICACHE_BANK, `ICACHE_WAY) data_we;
    logic `ARRAY(`ICACHE_BANK, `ICACHE_SET_WIDTH) data_index;
    logic `ARRAY(`ICACHE_BANK, `ICACHE_BITS) data_wdata;
    logic `TENSOR(`ICACHE_BANK, `ICACHE_WAY, `ICACHE_BITS) data_rdata;

    assign tagv_we = replace_way & {`ICACHE_WAY{refill_en}}
`ifdef EXT_FENCEI
    | {`ICACHE_WAY{fenceValid}}
`endif
    ;
    assign tagv_index = index;
    assign tagv_windex = 
`ifdef EXT_FENCEI
                        fenceValid ? fenceIdx :
`endif
                        miss_buffer.windex;
    assign tagv_wdata = 
`ifdef EXT_FENCEI
    {~fenceValid, miss_buffer.paddr[`ICACHE_TAG + `ICACHE_SET_WIDTH -1 : `ICACHE_SET_WIDTH]};
`else
    {1'b1, miss_buffer.paddr[`ICACHE_TAG + `ICACHE_SET_WIDTH -1 : `ICACHE_SET_WIDTH]};
`endif
    assign data_en = {`ICACHE_BANK{~cache_stall}};
    assign data_we = {`ICACHE_BANK{replace_way & {`ICACHE_WAY{refill_en}}}};
    ICacheData icache_data(
        .clk,
        .rst(rst),
        .tagv_en((fsq_cache_io.en & ~cache_stall)),
        .tagv_we,
        .tagv_index,
        .tagv_windex,
        .tagv_wdata,
        .tagv0,
        .tagv1,
        .en(data_en),
        .we(data_we),
        .index(data_index),
        .wdata(data_wdata),
        .data(data_rdata)
    );
    generate;
        for(genvar i=0; i<`ICACHE_BANK; i++)begin
            assign data_index[i] = refill_en ? miss_buffer.windex :
                                    expand_en[i] ? index : indexp1;
            for(genvar j=0; j<`ICACHE_WAY; j++)begin
                assign rdata[j][i] = data_rdata[i][j];
            end
        end
        for(genvar j=0; j<`ICACHE_BANK-1; j++)begin
            assign data_wdata[j] = miss_buffer.replace_data[j];
        end
        assign data_wdata[`ICACHE_BANK-1] = axi_io.r_data;
        for(genvar i=0; i<`ICACHE_WAY; i++)begin
            assign hit[0][i] = tagv0[i][`ICACHE_TAG] && (tagv0[i][(`ICACHE_TAG-1): 0] == ptag1);
            assign hit[1][i] = tagv1[i][`ICACHE_TAG] && (tagv1[i][`ICACHE_TAG-1: 0] == ptag2);
        end
    endgenerate
    Encoder #(`ICACHE_WAY) encoder_hit_index0(hit[0], hit_index[0]);
    Encoder #(`ICACHE_WAY) encoder_hit_index1(hit[1], hit_index[1]);
    assign cache_hit[0] = |hit[0];
    assign cache_hit[1] = (|hit[1]);
    assign cache_miss[0] = !request_buffer.span[0] && !cache_hit[0];
    assign cache_miss[1] = request_buffer.span[1] && !cache_hit[1];


    ReplaceIO #(.DEPTH(`ICACHE_SET),.WAY_NUM(`ICACHE_WAY)) replace_io();
    assign replace_io.hit_en = main_state == LOOKUP && (!cache_miss[0] && !cache_miss[1]) ||
                               refill_en;
    assign replace_io.hit_way = refill_en ? replace_io.miss_way : hit[0];
    assign replace_io.hit_index = refill_en ? miss_buffer.windex : request_buffer.index1;
    assign replace_io.miss_index = miss_buffer.windex;
    PLRU #(
        .DEPTH(`ICACHE_SET),
        .WAY_NUM(`ICACHE_WAY)
    ) replacement(
        .clk(clk),
        .rst(rst),
        .replace_io(replace_io)
    );
    assign replace_way = replace_io.miss_way;


    assign fsq_cache_io.ready = ((main_state == IDLE && ((!fsq_cache_io.stall))) ||
                                (main_state == LOOKUP && (((!(|cache_miss) && 
                                !(itlb_cache_io.miss && !(|itlb_cache_io.exception))) && 
                                !fsq_cache_io.stall) || (abandon_lookup))) ||
                                (abandon_idle && fsq_cache_io.en))
`ifdef EXT_FENCEI
                                & ~fenceValid
`endif
                                ;
    assign cache_pd_io.en = {`BLOCK_INST_SIZE+1{((main_state == LOOKUP) & 
                            ((~((|cache_miss) | itlb_cache_io.miss)) | 
                            (|itlb_cache_io.exception)) & ~abandon_lookup) | miss_data_en}} & 
                            request_buffer.expand_en_shift;
    assign cache_pd_io.exception = (main_state == LOOKUP) & (expand_exception >> request_buffer.start_offset);
    assign cache_pd_io.stream.start_addr = request_buffer.stream.start_addr;
    assign cache_pd_io.start_addr = request_buffer.start_addr;
    assign cache_pd_io.fsqIdx = request_buffer.fsqIdx;
    assign cache_pd_io.stream.taken = request_buffer.stream.taken;
`ifdef RVC
    assign cache_pd_io.stream.rvc = request_buffer.stream.rvc;
    assign cache_pd_io.shiftIdx = request_buffer.shiftIdx;
`endif
    assign cache_pd_io.stream.size = request_buffer.stream.size;
    assign cache_pd_io.stream.target = request_buffer.stream.target;
    assign cache_pd_io.shiftOffset = request_buffer.shiftOffset;
    localparam BANK_IDX_SIZE = $clog2(LINE_INST_NUM)+1;
    generate;
        logic `ARRAY(LINE_INST_NUM, `INST_BITS) rdata_way1, rdata_way0;
        assign rdata_way1 = rdata[hit_index[1]];
        assign rdata_way0 = rdata[hit_index[0]];
`ifdef RVC
        for(genvar bank=0; bank<`BLOCK_INST_SIZE+1; bank++)begin
`else
        for(genvar bank=0; bank<`BLOCK_INST_SIZE; bank++)begin
`endif
            logic `N(BANK_IDX_SIZE) bank_index;
            always_ff @(posedge clk)begin
                if(!cache_stall)begin
                    bank_index <= bank + start_addr;
                end
            end
            assign cache_pd_io.data[bank] = miss_data_en ? miss_buffer.data[bank] :
                                            bank_index[BANK_IDX_SIZE-1] ? 
                                            rdata_way1[bank_index[BANK_IDX_SIZE-2: 0]] :
                                            rdata_way0[bank_index[BANK_IDX_SIZE-2: 0]];
        end
    endgenerate
    assign axi_io.ar_id = 0;
    assign axi_io.ar_addr = {miss_buffer.paddr, {`ICACHE_BANK_WIDTH+2{1'b0}}};
    logic `N(5) len;
    assign len = `ICACHE_LINE / `ICACHE_BYTE - 1;
    assign axi_io.ar_len = {3'b0, len};
    assign axi_io.ar_size = $clog2(`ICACHE_BYTE);
    assign axi_io.ar_burst = 2'b01;
    assign axi_io.ar_valid = main_state == MISS;
    assign axi_io.ar_user = 0;
    assign axi_io.ar_snoop = `ACEOP_READ_ONCE;
    assign axi_io.r_ready = 1'b1;

`define REQ_DEF \
    request_buffer.span <= span; \
    request_buffer.start_offset <= start_addr; \
    request_buffer.index1 <= index; \
    request_buffer.index2 <= indexp1[`ICACHE_SET_WIDTH-1: 0]; \
    request_buffer.expand_en <= expand_en; \
    request_buffer.expand_en_shift <= expand_en_shift; \
    request_buffer.expand_en_block <= expand_en_block; \
    request_buffer.multi_tag <= indexp1[`ICACHE_SET_WIDTH]; \
    request_buffer.fsqIdx <= fsq_cache_io.fsqIdx; \
    request_buffer.stream.start_addr <= fsq_cache_io.stream.start_addr + {fsq_cache_io.shiftOffset, {`INST_OFFSET{1'b0}}}; \
    request_buffer.start_addr <= fsq_cache_io.stream.start_addr; \
    request_buffer.stream.size <= fsq_cache_io.stream.size - fsq_cache_io.shiftOffset; \
    request_buffer.stream.taken <= fsq_cache_io.stream.taken; \
    request_buffer.stream.target <= fsq_cache_io.stream.target; \
    request_buffer.shiftOffset <= fsq_cache_io.shiftOffset; \
`ifdef RVC \
    request_buffer.stream.rvc <= fsq_cache_io.stream.rvc; \
    request_buffer.shiftIdx <= fsq_cache_io.shiftIdx; \
`endif

    logic `ARRAY(BLOCK_DELTA, `ICACHE_BANK) miss_bank_en;
    logic `ARRAY(BLOCK_DELTA, `INST_BITS) r_data_inst;
    logic `N(BLOCK_DELTA) miss_bank_valid;
    logic `N($clog2(BLOCK_DELTA)+1) miss_bank_valid_num;
    logic `ARRAY(BLOCK_DELTA, $clog2(BLOCK_DELTA+1)) miss_bank_idx;

    assign r_data_inst = axi_io.r_data;
generate
    for(genvar i=0; i<BLOCK_DELTA; i++)begin
        for(genvar j=0; j<`ICACHE_BANK; j++)begin
            logic `N($clog2(LINE_INST_NUM)) offset;
            if(BLOCK_DELTA <= 1)begin
                assign offset = j;
            end
            else begin
                assign offset[$clog2(BLOCK_DELTA)-1: 0] = i;
                assign offset[$clog2(LINE_INST_NUM)-1: $clog2(BLOCK_DELTA)] = j;
            end
            assign miss_bank_en[i][j] = request_buffer.expand_en_block[miss_buffer.line][offset];
        end
        assign miss_bank_valid[i] = miss_bank_en[i][miss_buffer.stream_index];
    end
`ifdef RVC
    assign miss_bank_idx[0] = 0;
    assign miss_bank_idx[1] = miss_bank_valid[0];
`else
    assign miss_bank_idx = 0;
`endif
    ParallelAdder #(1, BLOCK_DELTA) adder_miss_bank (miss_bank_valid, miss_bank_valid_num);
endgenerate

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            request_buffer <= '{default: 0};
            main_state <= IDLE;
            miss_buffer <= '{default: 0};
            miss_data_en <= 1'b0;
            stall_wait <= 1'b0;
        end
        else begin
            case(main_state)
            IDLE:begin
                if(fsq_cache_io.en & ~fsq_cache_io.flush & ~fsq_cache_io.stall & ~abandon_idle)begin
                    `REQ_DEF
                    main_state <= LOOKUP;
                end
            end
            LOOKUP:begin
                if(fsq_cache_io.flush | abandon_lookup)begin
                    main_state <= IDLE;
                end
                else if(cache_stall)begin
                    
                end
                else if((|cache_miss) & ~(|itlb_cache_io.exception))begin
                    main_state <= MISS;
                    if(cache_miss[0])begin
                        miss_buffer.paddr <= {ptag1, request_buffer.index1};
                        miss_buffer.windex <= request_buffer.index1;
                        miss_buffer.line <= 0;
                    end
                    else begin
                        miss_buffer.paddr <= {ptag2, request_buffer.index2};
                        miss_buffer.windex <= request_buffer.index2;
                        miss_buffer.line <= 1;
                    end
                    miss_buffer.addition_paddr <= {ptag2, request_buffer.index2};
                    miss_buffer.addition_request <= (&cache_miss);
                    miss_buffer.data <= cache_pd_io.data;
                    miss_buffer.stream_index <= 0;
                    if(cache_miss[1] & ~cache_miss[0] & ~request_buffer.span[0])begin
                        miss_buffer.current_index <= LINE_INST_NUM - request_buffer.start_offset;
                    end
                    else begin
                        miss_buffer.current_index <= 0;
                    end
                end
                else if(fsq_cache_io.en & ~abandon_idle)begin
                    `REQ_DEF
                end
                else begin
                    main_state <= IDLE;
                end
            end
            MISS:begin
                if(axi_io.ar_ready)begin
                    main_state <= REFILL;
                end
            end
            REFILL:begin
                if(axi_io.r_valid)begin
                    miss_buffer.stream_index <= next_stream_index;
                    miss_buffer.replace_data[miss_buffer.stream_index] <= axi_io.r_data;
                    for(int i=0; i<BLOCK_DELTA; i++)begin
                        if(miss_bank_valid[i])begin
                            miss_buffer.data[miss_buffer.current_index+miss_bank_idx[i]] <= r_data_inst[i];
                        end
                    end
                    if(|miss_bank_valid)begin
                        miss_buffer.current_index <= miss_buffer.current_index + miss_bank_valid_num;
                    end
                    if(next_stream_index == 0)begin
                        miss_buffer.line <= 1;
                        miss_buffer.windex <= request_buffer.index2;
                    end
                end
                if(axi_io.r_valid && axi_io.r_last)begin
                    if(!miss_buffer.addition_request || miss_buffer.flush ||
                        fsq_cache_io.flush)begin
                        main_state <= IDLE;
                    end
                    else begin
                        main_state <= MISS;
                        miss_buffer.paddr <= miss_buffer.addition_paddr;
                        miss_buffer.addition_request <= 1'b0;
                    end
                end
            end
            endcase
            if(axi_io.r_valid & axi_io.r_last)begin
                miss_buffer.flush <= 1'b0;
            end
            else if(fsq_cache_io.flush && (main_state == MISS || main_state == REFILL))begin
                miss_buffer.flush <= 1'b1;
            end
            stall_wait <= miss_data_en || fsq_cache_io.flush ? 1'b0 :
                          fsq_cache_io.stall & main_state == REFILL ? 1'b1 : stall_wait;
            miss_data_en <= ((main_state == REFILL) & 
                            axi_io.r_valid & 
                            axi_io.r_last &
                            (~miss_buffer.addition_request) |
                            stall_wait) &
                            ~miss_buffer.flush &
                            ~fsq_cache_io.flush &
                            ~fsq_cache_io.stall;
        end
    end

`ifdef EXT_FENCEI
    logic `N(`ICACHE_SET_WIDTH) fenceIdx_n;
    assign fenceIdx_n = fenceIdx + 1;
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            fenceValid <= 1'b0;
            fenceIdx <= 0;
            fenceEnd <= 1'b0;
        end
        else begin
            if(fenceReq)begin
                fenceValid <= 1'b1;
            end
            if(fenceValid)begin
                fenceIdx <= fenceIdx_n;
                if(&fenceIdx)begin
                    fenceValid <= 1'b0;
                end
            end
            fenceEnd <= fenceValid & (&fenceIdx);
        end
    end
`endif

    `Log(DLog::Debug, T_ICACHE, axi_io.ar_valid & axi_io.ar_ready, $sformatf("icache req. %h %d", axi_io.ar_addr, axi_io.ar_len))
    `Log(DLog::Debug, T_ICACHE, refill_en, $sformatf("icache refill. %h %d %d", {miss_buffer.paddr, {`ICACHE_BANK_WIDTH+2{1'b0}}}, replace_io.miss_way, miss_buffer.windex))
endmodule