`include "../../../defines/defines.svh"

module ICacheCtrl(
    input logic clk,
    input logic rst,
    FsqCacheIO.cache fsq_cache_io,
    CtrlICacheIO.ctrl ctrl_icache_io,
    CachePreDecodeIO.cache cache_pd_io
);

    FetchStream stream_s1;
    logic `N(`PREDICTION_WIDTH+1) stream_size_s1;
    logic `N(`BLOCK_INST_SIZE+1) en_s1;

    logic `N(`BLOCK_INST_SIZE) en_s2;
    FetchStream stream_s2;
    logic `N(`PREDICTION_WIDTH) shiftIdx_s2, shiftOffset_s2;
    logic `N(`VADDR_SIZE) addr_s2;
    FsqIdx fsqIdx_s2;
    logic abandon_idle_hsk;
    logic abandon_lookup_hsk;

    assign ctrl_icache_io.req = fsq_cache_io.en;
    assign ctrl_icache_io.vaddr = fsq_cache_io.stream.start_addr;
    assign ctrl_icache_io.shiftOffset = fsq_cache_io.shiftOffset;
    assign ctrl_icache_io.flush = fsq_cache_io.flush;
    assign ctrl_icache_io.stall = fsq_cache_io.stall;
    assign ctrl_icache_io.abandonIdle = fsq_cache_io.abandon & (fsq_cache_io.fsqIdx == fsq_cache_io.abandonIdx);
    assign ctrl_icache_io.abandonLookup = fsq_cache_io.abandon & (fsq_cache_io.abandonIdx == fsqIdx_s2);
    assign fsq_cache_io.ready = ctrl_icache_io.ready;

    assign stream_size_s1 = fsq_cache_io.stream.size + {~fsq_cache_io.stream.rvc, fsq_cache_io.stream.rvc} - fsq_cache_io.shiftOffset;
    MaskGen #(`BLOCK_INST_SIZE+1) mask_gen_en (stream_size_s1, en_s1);

    always_comb begin
        stream_s1 = fsq_cache_io.stream;
        stream_s1.start_addr = stream_s1.start_addr + {fsq_cache_io.shiftOffset, {`INST_OFFSET{1'b0}}};
        stream_s1.size = stream_s1.size - fsq_cache_io.shiftOffset;
    end

    always_ff @(posedge clk)begin
        if(ctrl_icache_io.req & ctrl_icache_io.ready & ~fsq_cache_io.stall & ~ctrl_icache_io.abandonIdle)begin
            stream_s2 <= stream_s1;
            shiftOffset_s2 <= fsq_cache_io.shiftOffset;
            addr_s2 <= fsq_cache_io.stream.start_addr;
            fsqIdx_s2 <= fsq_cache_io.fsqIdx;
    `ifdef RVC
            shiftIdx_s2 <= fsq_cache_io.shiftIdx;
    `endif
        end
    end

    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            en_s2 <= 0;
        end
        else if(fsq_cache_io.flush | abandon_lookup_hsk)begin
            en_s2 <= 0;
        end
        else if(~fsq_cache_io.stall & ctrl_icache_io.req & ctrl_icache_io.ready &
                ~(ctrl_icache_io.abandonIdle & ~ctrl_icache_io.stateIdle)) begin
            en_s2 <= en_s1 & {`BLOCK_INST_SIZE{~abandon_idle_hsk}};
        end
    end

    assign abandon_lookup_hsk = ctrl_icache_io.stateLookup & ctrl_icache_io.abandonLookup;
    assign abandon_idle_hsk = ctrl_icache_io.stateIdle & ctrl_icache_io.abandonIdle;
    assign cache_pd_io.en = en_s2 & {`BLOCK_INST_SIZE{ctrl_icache_io.dataValid & ~abandon_lookup_hsk}};
    assign cache_pd_io.exception = ctrl_icache_io.exception;
    assign cache_pd_io.data = ctrl_icache_io.data;
    assign cache_pd_io.start_addr = addr_s2;
    assign cache_pd_io.stream = stream_s2;
    assign cache_pd_io.fsqIdx = fsqIdx_s2;
    assign cache_pd_io.shiftOffset = shiftOffset_s2;
`ifdef RVC
    assign cache_pd_io.shiftIdx = shiftIdx_s2;
`endif





endmodule