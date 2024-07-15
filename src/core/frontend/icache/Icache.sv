`include "../../../defines/defines.svh"

module ICache(
    input logic clk,
    input logic rst,
    FsqCacheIO.cache fsq_cache_io,
    CachePreDecodeIO.cache cache_pd_io,
    ICacheAxi.cache axi_io,
    TlbL2IO.tlb itlb_io,
    CsrTlbIO.tlb csr_itlb_io
);
`ifdef DIFFTEST
    typedef struct packed {
`else
    typedef struct {
`endif
        logic `N(`ICACHE_SET_WIDTH) index1, index2;
        logic `ARRAY(2, `ICACHE_BANK) expand_en;
        logic `N(`BLOCK_INST_SIZE) expand_en_shift;
        logic `N(`ICACHE_BANK_WIDTH+1) start_offset;
        logic `N(2) span;
        logic multi_tag;
        FetchStream stream;
        FsqIdx fsqIdx;
        logic `N(`PREDICTION_WIDTH+1) shiftIdx;
    } RequestBuffer;
    RequestBuffer request_buffer;
`ifdef DIFFTEST
    typedef struct packed {
`else
    typedef struct {
`endif
        logic `N(`ICACHE_TAG + `ICACHE_SET_WIDTH) paddr;
        logic `N(`ICACHE_TAG + `ICACHE_SET_WIDTH) addition_paddr;
        logic addition_request;
        logic flush;
        logic [4: 0] length;
        logic `N(`ICACHE_WAY) replace_way;
        logic `N(`BLOCK_INST_WIDTH) current_index;
        logic `ARRAY(`BLOCK_INST_SIZE, 32) data;
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

    ICacheWayIO way_io [`ICACHE_WAY-1: 0]();
    ITLBCacheIO itlb_cache_io();
    ITLB itlb(.*, .tlb_l2_io(itlb_io));
    logic `N(`ICACHE_BANK * 2) expand_en, expand_exception;
    logic `N(`BLOCK_INST_SIZE) expand_en_shift;
    logic `N(`ICACHE_BANK_WIDTH+1) end_addr, start_addr;
    logic `N(`PREDICTION_WIDTH+1) stream_size;
    logic `N(`ICACHE_BANK * 2) start_addr_mask;
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

    assign start_addr = fsq_cache_io.stream.start_addr[`ICACHE_LINE_WIDTH-1: 2] + fsq_cache_io.shiftIdx;
    assign stream_size = fsq_cache_io.stream.size + 1;
    assign end_addr = fsq_cache_io.stream.start_addr[`ICACHE_LINE_WIDTH-1: 2] + stream_size;
    assign span[1] = end_addr[`ICACHE_BANK_WIDTH] & (|end_addr[`ICACHE_BANK_WIDTH-1: 0]);
    assign span[0] = start_addr[`ICACHE_BANK_WIDTH];
    assign start_addr_mask = (1 << start_addr) - 1;
    assign expand_en = ((1 << end_addr) - 1) ^ start_addr_mask;
    assign expand_en_shift = expand_en >> (start_addr);
    assign expand_exception = request_buffer.expand_en[0] & {`ICACHE_BANK{itlb_cache_io.exception[0]}} |
                              request_buffer.expand_en[1] & {`ICACHE_BANK{itlb_cache_io.exception[1]}};
    assign index = fsq_cache_io.stream.start_addr`ICACHE_SET_BUS;
    assign indexp1 = index + 1;
    assign refill_en = main_state == REFILL && axi_io.sr.valid && next_stream_index == 0;
    assign abandon_lookup = main_state == LOOKUP && 
                             fsq_cache_io.abandon &&
                             request_buffer.fsqIdx.idx == fsq_cache_io.abandonIdx;
    assign abandon_idle = main_state == IDLE &&
                          fsq_cache_io.abandon &&
                          fsq_cache_io.fsqIdx.idx == fsq_cache_io.abandonIdx;

    assign itlb_cache_io.req = {span[1] & fsq_cache_io.en & ~fsq_cache_io.stall, ~span[0] & fsq_cache_io.en & ~fsq_cache_io.stall};
    assign vtag1 = fsq_cache_io.stream.start_addr[`VADDR_SIZE-1: `TLB_OFFSET];
    assign vtag2 = vtag1 + indexp1[`ICACHE_SET_WIDTH];
    assign itlb_cache_io.vaddr = {{vtag2, `TLB_OFFSET'b0}, {vtag1, `TLB_OFFSET'b0}};
    assign itlb_cache_io.flush = fsq_cache_io.flush;
    assign ptag1 = itlb_cache_io.paddr[0][`PADDR_SIZE-1: `TLB_OFFSET];
    assign ptag2 = itlb_cache_io.paddr[1][`PADDR_SIZE-1: `TLB_OFFSET];

    generate;
        for(genvar i=0; i<`ICACHE_WAY; i++)begin
            ICacheWay way(
                .clk(clk),
                .rst(rst),
                .io(way_io[i])
            );
            assign way_io[i].tagv_en = fsq_cache_io.en & ~fsq_cache_io.stall;
            assign way_io[i].tagv_we = {`ICACHE_BANK{miss_buffer.replace_way[i] & refill_en}};
            assign way_io[i].tagv_windex = miss_buffer.windex;
            assign way_io[i].tagv_wdata = {1'b1, miss_buffer.paddr[`ICACHE_TAG + `ICACHE_SET_WIDTH -1 : `ICACHE_SET_WIDTH]};
            assign way_io[i].tagv_index = index;
            assign way_io[i].span = span[1];
            // assign way_io[i].en = {`ICACHE_BANK{fsq_cache_io.en}} &
            //                       (({`ICACHE_BANK{span}} &
            //                       expand_en[`ICACHE_BANK * 2 - 1: `ICACHE_BANK]) |
            //                       expand_en[`ICACHE_BANK-1: 0]);
            assign way_io[i].en = {`ICACHE_BANK{~fsq_cache_io.stall}};
            for(genvar j=0; j<`ICACHE_BANK; j++)begin
                assign way_io[i].index[j] = expand_en[j] ? index : indexp1;
                assign way_io[i].windex[j] = miss_buffer.windex;
            end
            for(genvar j=0; j<`ICACHE_BANK-1; j++)begin
                assign way_io[i].wdata[j] = miss_buffer.replace_data[j];
            end
            assign way_io[i].wdata[`ICACHE_BANK-1] = axi_io.sr.data;
            assign way_io[i].we = {`ICACHE_BANK{miss_buffer.replace_way[i] & refill_en}};

            assign hit[0][i] = way_io[i].tagv[0][`ICACHE_TAG] && (way_io[i].tagv[0][`ICACHE_TAG-1: 0] == ptag1);
            assign hit[1][i] = way_io[i].tagv[1][`ICACHE_TAG] && (way_io[i].tagv[1][`ICACHE_TAG-1: 0] == ptag2);

            assign rdata[i] = way_io[i].data;
        end
    endgenerate
    Encoder #(`ICACHE_WAY) encoder_hit_index0(hit[0], hit_index[0]);
    Encoder #(`ICACHE_WAY) encoder_hit_index1(hit[1], hit_index[1]);
    assign cache_hit[0] = |hit[0];
    assign cache_hit[1] = (|hit[1]);
    assign cache_miss[0] = !request_buffer.span[0] && !cache_hit[0];
    assign cache_miss[1] = request_buffer.span[1] && !cache_hit[1];


    ReplaceIO #(.DEPTH(`ICACHE_SET),.WAY_NUM(`ICACHE_WAY)) replace_io();
    logic `N(`ICACHE_WAY) replace_way;
    assign replace_io.hit_en = main_state == LOOKUP && (!cache_miss[0] && !cache_miss[1]);
    assign replace_io.hit_way = hit_index[0];
    assign replace_io.hit_index = request_buffer.index1;
    assign replace_io.miss_index = cache_miss[0] ? request_buffer.index1 : request_buffer.index2;
    PLRU #(
        .DEPTH(`ICACHE_SET),
        .WAY_NUM(`ICACHE_WAY)
    ) replacement(
        .clk(clk),
        .rst(rst),
        .replace_io(replace_io)
    );
    Decoder #(`ICACHE_WAY) decoder_way(replace_io.miss_way, replace_way);


    assign fsq_cache_io.ready = (main_state == IDLE) ||
                                (main_state == LOOKUP && (!(|cache_miss) &&
                                !(itlb_cache_io.miss && !(|itlb_cache_io.exception))));
    assign cache_pd_io.en = {`ICACHE_BANK{((main_state == LOOKUP) & (~(|cache_miss)) & ~abandon_lookup) | miss_data_en}}
                             & request_buffer.expand_en_shift;
    assign cache_pd_io.exception = (main_state == LOOKUP) & (expand_exception >> request_buffer.start_offset);
    assign cache_pd_io.stream.start_addr = request_buffer.stream.start_addr;
    assign cache_pd_io.fsqIdx = request_buffer.fsqIdx;
    assign cache_pd_io.stream.taken = request_buffer.stream.taken;
    assign cache_pd_io.stream.branch_type = request_buffer.stream.branch_type;
    assign cache_pd_io.stream.ras_type = request_buffer.stream.ras_type;
    assign cache_pd_io.stream.size = request_buffer.stream.size;
    assign cache_pd_io.stream.target = request_buffer.stream.target;
    assign cache_pd_io.shiftIdx = request_buffer.shiftIdx;
    localparam BANK_IDX_SIZE = $clog2(`ICACHE_BANK)+1;
    generate;
        for(genvar bank=0; bank<`BLOCK_INST_SIZE; bank++)begin
            logic `N(BANK_IDX_SIZE) bank_index;
            always_ff @(posedge clk)begin
                if(!fsq_cache_io.stall)begin
                    bank_index <= bank + fsq_cache_io.stream.start_addr[`ICACHE_LINE_WIDTH-1: 2] + fsq_cache_io.shiftIdx;
                end
            end
            assign cache_pd_io.data[bank] = miss_data_en ? miss_buffer.data[bank] :
                                            bank_index[BANK_IDX_SIZE-1] ? 
                                            rdata[hit_index[1]][bank_index[BANK_IDX_SIZE-2: 0]] :
                                            rdata[hit_index[0]][bank_index[BANK_IDX_SIZE-2: 0]];
        end
    endgenerate
    assign axi_io.mar.id = 0;
    assign axi_io.mar.addr = {miss_buffer.paddr, {`ICACHE_BANK_WIDTH+2{1'b0}}};
    assign axi_io.mar.len = {3'b0, miss_buffer.length};
    assign axi_io.mar.size = 3'b010;
    assign axi_io.mar.burst = 2'b01;
    assign axi_io.mar.lock = 0;
    assign axi_io.mar.cache = 0;
    assign axi_io.mar.prot = 0;
    assign axi_io.mar.valid = main_state == MISS;
    assign axi_io.mar.qos = 0;
    assign axi_io.mar.region = 0;
    assign axi_io.mar.user = 0;

`define REQ_DEF \
    request_buffer.span <= span; \
    request_buffer.start_offset <= fsq_cache_io.stream.start_addr[`ICACHE_LINE_WIDTH-1: 2] + fsq_cache_io.shiftIdx; \
    request_buffer.index1 <= index; \
    request_buffer.index2 <= indexp1[`ICACHE_SET_WIDTH-1: 0]; \
    request_buffer.expand_en <= expand_en; \
    request_buffer.expand_en_shift <= expand_en_shift; \
    request_buffer.multi_tag <= indexp1[`ICACHE_SET_WIDTH]; \
    request_buffer.fsqIdx <= fsq_cache_io.fsqIdx; \
    request_buffer.stream.start_addr <= fsq_cache_io.stream.start_addr + {fsq_cache_io.shiftIdx, 2'b00}; \
    request_buffer.stream.size <= fsq_cache_io.stream.size - fsq_cache_io.shiftIdx; \
    request_buffer.stream.taken <= fsq_cache_io.stream.taken; \
    request_buffer.stream.branch_type <= fsq_cache_io.stream.branch_type; \
    request_buffer.stream.ras_type <= fsq_cache_io.stream.ras_type; \
    request_buffer.stream.target <= fsq_cache_io.stream.target; \
    request_buffer.shiftIdx <= fsq_cache_io.shiftIdx; \

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
                if(fsq_cache_io.flush | abandon_lookup | abandon_idle)begin
                    main_state <= IDLE;
                end
                else if(fsq_cache_io.stall | (itlb_cache_io.miss & ~(|itlb_cache_io.exception)))begin
                    
                end
                else if((|cache_miss) & ~(|itlb_cache_io.exception))begin
                    main_state <= MISS;
                    miss_buffer.replace_way <= replace_way;
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
                    if((&cache_miss) & ~request_buffer.multi_tag)begin
                        miss_buffer.length <= 2 * (`DCACHE_LINE / `DATA_BYTE) - 1;
                    end
                    else begin
                        miss_buffer.length <= `DCACHE_LINE / `DATA_BYTE - 1;
                    end
                    miss_buffer.addition_request <= (&cache_miss) & request_buffer.multi_tag;
                    miss_buffer.data <= cache_pd_io.data;
                    miss_buffer.stream_index <= 0;
                    if(cache_miss[1] & ~cache_miss[0] & ~request_buffer.span[0])begin
                        miss_buffer.current_index <= `ICACHE_BANK - request_buffer.start_offset;
                    end
                    else begin
                        miss_buffer.current_index <= 0;
                    end
                end
                else if(fsq_cache_io.en)begin
                    `REQ_DEF
                end
                else begin
                    main_state <= IDLE;
                end
            end
            MISS:begin
                if(axi_io.sar.ready)begin
                    main_state <= REFILL;
                end
            end
            REFILL:begin
                if(axi_io.sr.valid)begin
                    miss_buffer.stream_index <= next_stream_index;
                    miss_buffer.replace_data[miss_buffer.stream_index] <= axi_io.sr.data;
                    if(request_buffer.expand_en[miss_buffer.line][miss_buffer.stream_index])begin
                        miss_buffer.current_index <= miss_buffer.current_index + 1;
                        miss_buffer.data[miss_buffer.current_index] <= axi_io.sr.data;
                    end
                    if(next_stream_index == 0)begin
                        miss_buffer.line <= 1;
                        miss_buffer.windex <= request_buffer.index2;
                    end
                end
                if(axi_io.sr.valid && axi_io.sr.last)begin
                    if(!miss_buffer.addition_request)begin
                        main_state <= IDLE;
                    end
                    else begin
                        main_state <= MISS;
                        miss_buffer.paddr <= miss_buffer.addition_paddr;
                        miss_buffer.length <= 4'h7;
                        miss_buffer.addition_request <= 1'b0;
                    end
                end
            end
            endcase
            if(axi_io.sr.valid & axi_io.sr.last)begin
                miss_buffer.flush <= 1'b0;
            end
            else if(fsq_cache_io.flush && (main_state == MISS || main_state == REFILL))begin
                miss_buffer.flush <= 1'b1;
            end
            stall_wait <= miss_data_en || fsq_cache_io.flush ? 1'b0 :
                          fsq_cache_io.stall & main_state == REFILL ? 1'b1 : stall_wait;
            miss_data_en <= ((main_state == REFILL) & 
                            axi_io.sr.valid & 
                            axi_io.sr.last &
                            (~miss_buffer.addition_request) |
                            stall_wait) &
                            ~miss_buffer.flush &
                            ~fsq_cache_io.flush &
                            ~fsq_cache_io.stall;
        end
    end
endmodule