`include "../../../defines/defines.svh"

module StoreCommitBuffer(
    input logic clk,
    input logic rst,
    StoreCommitIO.buffer io,
    LoadForwardIO.queue loadFwd,
    DCacheStoreIO.buffer wio
);

    logic `N(`STORE_COMMIT_SIZE) addr_en, writing;
    logic `N(`DCACHE_BLOCK_SIZE) addrs `N(`STORE_COMMIT_SIZE);
    // write back counter info
    logic `N(`STORE_COUNTER_WIDTH) counter `N(`STORE_COMMIT_SIZE);
    SCDataIO data_io();
    SCDataModule data_module (.*, .io(data_io));

// write
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_SIZE) whit, whit_writing;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_WIDTH) whit_idx;
    logic `N(`STORE_PIPELINE) hit, hit_writing, wen;
    logic `ARRAY(`STORE_PIPELINE, `PADDR_SIZE-`DCACHE_BYTE_WIDTH) waddr;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) wmask;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BITS) wdata;
    logic `N(`STORE_PIPELINE) conflict;

    always_ff @(posedge clk)begin
        if(!io.conflict)begin
            wen <= io.en;
            waddr <= io.addr;
            wmask <= io.mask;
            wdata <= io.data;
        end
    end

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_COMMIT_SIZE; j++)begin
            assign whit[i][j] = addr_en[j] & (addrs[j] == waddr[i][`VADDR_SIZE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BANK_WIDTH]);
            assign whit_writing[i][j] = whit[i][j] & writing[j];
        end
        Encoder #(`STORE_COMMIT_SIZE) encoder_whit (whit[i], whit_idx[i]);
    end

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
            assign hit[i] = |whit[i];
            assign hit_writing[i] = |whit_writing[i];
    end
endgenerate


    logic full;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_WIDTH) free_idx;
    logic `N(`STORE_PIPELINE) free_valid;
    assign full = &addr_en;
    /* UNPARAM */
    PEncoder #(`STORE_COMMIT_SIZE) encoder_free (~addr_en, free_idx[0]);
    PREncoder #(`STORE_COMMIT_SIZE) encoder_free_rev (~addr_en, free_idx[1]);
    assign free_valid[0] = ~full;
    assign free_valid[1] = ~full && free_idx[0] != free_idx[1];

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign conflict[i] = wen[i] & (whit_writing[i] | (~free_valid[i] & ~hit[i]));
        assign data_io.wen[i] = wen[i] & (hit[i] | free_valid[i]) & ~whit_writing[i];
        assign data_io.we_new[i] = ~hit[i];
        assign data_io.windex[i] = hit[i] ? whit_idx[i] : free_idx[i];
        assign data_io.wbank[i] = waddr[i][`DCACHE_BANK_WIDTH-1: 0];
        assign data_io.wdata[i] = wdata[i];
        assign data_io.wmask[i] = wmask[i];
    end
endgenerate
    assign io.conflict = |conflict;

// write to dcache
    logic `N(`STORE_COMMIT_SIZE) ready, write_ready;
    logic `N(`STORE_COMMIT_WIDTH) widx, widx_next, cache_scIdx;
    logic `N(`VADDR_SIZE) cache_addr, cache_addr_n;
    logic wreq, wreq_n;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_SIZE) widx_decode, widx_valid;
    logic `N(`STORE_COMMIT_SIZE) widx_valid_combine;
generate
    assign write_ready = ready & addr_en & ~writing;
    PEncoder #(`STORE_COMMIT_SIZE) encoder_write_ready (write_ready, widx);
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        Decoder #(`STORE_COMMIT_SIZE) decoder_widx (data_io.windex[i], widx_decode[i]);
        assign widx_valid[i] = widx_decode[i] & {`STORE_COMMIT_SIZE{data_io.wen[i]}};
    end
    ParallelOR #(`STORE_COMMIT_SIZE, `STORE_PIPELINE) or_widx ( widx_valid, widx_valid_combine);
    for(genvar i=0; i<`STORE_COMMIT_SIZE; i++)begin
        assign ready[i] = counter[i][0];
        always_ff @(posedge clk or posedge rst)begin
            if(rst == `RST)begin
                counter[i] <= 1;
            end
            else begin
                if(widx_valid_combine[i])begin
                    counter[i] <= {1'b1, {`STORE_COUNTER_WIDTH-1{1'b0}}};
                end
                else if(~counter[i][0])begin
                    counter[i] <= counter[i] >> 1;
                end
            end
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        if(wio.valid)begin
            widx_next <= widx;
            cache_scIdx <= widx_next;
            wreq <= |write_ready;
            wreq_n <= wreq;
            cache_addr <= {addrs[widx], {`DCACHE_BANK_WIDTH+`DCACHE_BYTE_WIDTH{1'b0}}};
            cache_addr_n <= cache_addr;
        end

    end
    assign data_io.cacheIdx = widx_next;
    assign wio.req = wreq_n;
    assign wio.scIdx = cache_scIdx;
    assign wio.paddr = cache_addr_n;
    assign wio.data = data_io.cacheData;
    assign wio.mask = data_io.cacheMask;

// forward
    logic `ARRAY(`LOAD_PIPELINE, `STORE_COMMIT_SIZE) offset_vec, fwd_offset_vec;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_COMMIT_SIZE) ptag_vec, forward_vec;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_COMMIT_WIDTH) fwd_idx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK_WIDTH) fwd_bank;
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_COMMIT_SIZE; j++)begin
            assign offset_vec[i][j] = loadFwd.fwdData[i].en &
                (loadFwd.fwdData[i].vaddrOffset[`TLB_OFFSET-1: `DCACHE_LINE_WIDTH] == 
                                      addrs[j][`TLB_OFFSET-`DCACHE_LINE_WIDTH-1: 0]);
        end
    end
endgenerate 
    always_ff @(posedge clk)begin
        fwd_offset_vec <= offset_vec;
        for(int i=0; i<`LOAD_PIPELINE; i++)begin
            fwd_bank[i] <= loadFwd.fwdData[i].vaddrOffset[`DCACHE_BANK_WIDTH+`DCACHE_BYTE_WIDTH-1: `DCACHE_BYTE_WIDTH];
        end
    end
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_COMMIT_SIZE; j++)begin
            assign ptag_vec[i][j] = loadFwd.fwdData[i].ptag == addrs[j][`DCACHE_BLOCK_SIZE-1: `TLB_OFFSET-`DCACHE_LINE_WIDTH];
        end
        assign forward_vec[i] = ptag_vec[i] & fwd_offset_vec[i] & addr_en;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        Encoder #(`STORE_COMMIT_SIZE) encoder_fwd_idx (forward_vec[i], fwd_idx[i]);
        assign data_io.fwd_req[i] = |forward_vec[i];
        assign data_io.fwd_idx[i] = fwd_idx[i];
        assign data_io.fwd_bank[i] = fwd_bank[i];
        assign loadFwd.mask[i] = data_io.fwd_mask[i];
        assign loadFwd.data[i] = data_io.fwd_data[i];
    end
endgenerate

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            addr_en <= 0;
            writing <= 0;
        end
        else begin
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                if(wen[i] & ~hit[i] & free_valid[i])begin
                    addr_en[free_idx[i]] <= 1'b1;
                    addrs[free_idx[i]] <= waddr[i][`PADDR_SIZE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BANK_WIDTH];
                    writing[free_idx[i]] <= 0;
                end
            end

            if(|write_ready & wio.valid)begin
                writing[widx] <= 1'b1;
            end

            if(wio.conflict)begin
                writing[wio.conflictIdx] <= 1'b0;
            end

            if(wio.success)begin
                addr_en[wio.conflictIdx] <= 1'b0;
            end

            if(wio.refill)begin
                addr_en[wio.refillIdx] <= 1'b0;
            end
        end
    end

// difftest
`ifdef DIFFTEST
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic `N(8) difftestMask;
        logic `N(64) difftestData;
        assign difftestMask = {wmask[i] & {`DCACHE_BYTE{waddr[i][0]}},
                               wmask[i] & {`DCACHE_BYTE{~waddr[i][0]}}};
        assign difftestData = {wdata[i] & {`DCACHE_BITS{waddr[i][0]}},
                               wdata[i] & {`DCACHE_BITS{~waddr[i][0]}}};
        DifftestStoreEvent difftest_store_event(
            .clock(clk),
            .coreid(0),
            .index(i),
            .valid(wen[i] & (hit[i] | free_valid[i]) & ~whit_writing[i]),
            .storeAddr((waddr[i] << `DCACHE_BYTE_WIDTH) & 32'hfffffffb),
            .storeData(difftestData),
            .storeMask(difftestMask)
        );
    end
endgenerate
`endif

endmodule

interface SCDataIO;
    logic `N(`STORE_PIPELINE) wen;
    logic `N(`STORE_PIPELINE) we_new;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_WIDTH) windex;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BANK_WIDTH) wbank;
    logic `ARRAY(`STORE_PIPELINE, 32) wdata;
    logic `ARRAY(`STORE_PIPELINE, 4) wmask;

    logic `N(`LOAD_PIPELINE) fwd_req;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_COMMIT_WIDTH) fwd_idx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK_WIDTH) fwd_bank;
    logic `ARRAY(`LOAD_PIPELINE, 32) fwd_data;
    logic `ARRAY(`LOAD_PIPELINE, 4) fwd_mask;

    logic `N(`STORE_COMMIT_WIDTH) cacheIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) cacheData;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) cacheMask;

    modport data (input wen, we_new, windex, wbank, wdata, wmask,
                  fwd_req, fwd_idx, fwd_bank, cacheIdx,
                  output fwd_data, fwd_mask, cacheData, cacheMask); 
endinterface

module SCDataModule(
    input logic clk,
    input logic rst,
    SCDataIO.data io
);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data `N(`STORE_COMMIT_SIZE);
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) mask `N(`STORE_COMMIT_SIZE);


    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BANK) wbank_decode;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        Decoder #(`DCACHE_BANK) decoder_bank(io.wbank[i], wbank_decode[i]);
        logic `N(`DCACHE_BITS) expand_mask;
        MaskExpand #(`DCACHE_BYTE) expand_wmask (io.wmask[i], expand_mask);
        always_ff @(posedge clk)begin
            if(io.wen[i])begin
                for(int j=0; j<`DCACHE_BYTE; j++)begin
                    if(io.wmask[i][j])begin
                        data[io.windex[i]][io.wbank[i]] <= io.wdata[i] & expand_mask | data[io.windex[i]][io.wbank[i]] & ~expand_mask;
                    end
                end
                for(int j=0; j<`DCACHE_BANK; j++)begin
                    mask[io.windex[i]][j] <= (mask[io.windex[i]][j] & {`DCACHE_BYTE{~io.we_new[i]}}) | 
                                             ({`DCACHE_BYTE{wbank_decode[i][j]}} & io.wmask[i]);
                end
            end
        end
        
        always_ff @(posedge clk)begin
            if(io.fwd_req[i])begin
                io.fwd_data[i] <= data[io.fwd_idx[i]][io.fwd_bank[i]];
                io.fwd_mask[i] <= mask[io.fwd_idx[i]][io.fwd_bank[i]];
            end
            else begin
                io.fwd_mask[i] <= 0;
            end
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        io.cacheData <= data[io.cacheIdx];
        io.cacheMask <= mask[io.cacheIdx];
    end
endmodule