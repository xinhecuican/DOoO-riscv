`include "../../../defines/defines.svh"

module StoreCommitBuffer(
    input logic clk,
    input logic rst,
    input logic flush,
    StoreCommitIO.buffer io,
    LoadForwardIO.queue loadFwd,
    DCacheStoreIO.buffer wio,
    output logic empty
);

    logic `N(`STORE_COMMIT_SIZE) addr_en, writing;
    logic `N(`DCACHE_BLOCK_SIZE) addrs `N(`STORE_COMMIT_SIZE);
    // write back counter info
    logic `N(`STORE_COUNTER_WIDTH) counter `N(`STORE_COMMIT_SIZE);
    logic `N(`STORE_COMMIT_WIDTH+1) addr_num;
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
    logic `N(`STORE_PIPELINE) data_we, data_we_combine, weq_combine;
    logic `ARRAY(`STORE_PIPELINE, `STORE_PIPELINE) weq;
    logic `ARRAY(`STORE_PIPELINE, $clog2(`STORE_PIPELINE)) weq_idx;
    logic `N(`STORE_PIPELINE) write_en;

    always_ff @(posedge clk)begin
        if(!io.conflict)begin
            wen <= io.en & ~io.uncache;
            waddr <= io.addr;
            wmask <= io.mask;
            wdata <= io.data;
        end
    end

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_COMMIT_SIZE; j++)begin
            assign whit[i][j] = addr_en[j] & (addrs[j] == waddr[i][`PADDR_SIZE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BANK_WIDTH]);
            assign whit_writing[i][j] = whit[i][j] & addr_en[j] & writing[j];
        end
        Encoder #(`STORE_COMMIT_SIZE) encoder_whit (whit[i], whit_idx[i]);
    end

    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
            assign hit[i] = |whit[i];
            assign hit_writing[i] = |whit_writing[i];
            for(genvar j=0; j<`STORE_PIPELINE; j++)begin
                if(i <= j)begin
                    assign weq[i][j] = 0;
                end
                else begin
                    assign weq[i][j] = wen[i] & wen[j] & (waddr[i][`PADDR_SIZE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BANK_WIDTH] == waddr[j][`PADDR_SIZE-`DCACHE_BYTE_WIDTH-1: `DCACHE_BANK_WIDTH]);
                end
            end
            assign weq_combine[i] = |weq[i];
            Encoder #(`STORE_PIPELINE) encoder_weq (weq[i], weq_idx[i]);
    end
endgenerate


    logic full;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_SIZE) free_en;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_WIDTH) free_idx;
    logic `N(`STORE_PIPELINE) free_valid;
    assign full = &addr_en;
    assign empty = ~(|addr_en);
    `UNPARAM(STORE_PIPELINE, 2, "use encoder & rencoder")
    PSelector #(`STORE_COMMIT_SIZE) selector_free_en (~addr_en, free_en[0]);
    PRSelector #(`STORE_COMMIT_SIZE) selector_free_en_rev (~addr_en, free_en[1]);
    PEncoder #(`STORE_COMMIT_SIZE) encoder_free (~addr_en, free_idx[0]);
    PREncoder #(`STORE_COMMIT_SIZE) encoder_free_rev (~addr_en, free_idx[1]);
    assign free_valid[0] = ~full;
    assign free_valid[1] = ~full && ((free_idx[0] != free_idx[1]));

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign write_en[i] = wen[i] & ~(hit[i] | weq_combine[i]) & free_valid[i] & ~io.conflict;
        assign conflict[i] = wen[i] & (hit_writing[i] | (~free_valid[i] & ~(hit[i] | weq_combine[i])));
        assign data_we[i] = wen[i] & (hit[i] | weq_combine[i] | free_valid[i]) & ~hit_writing[i];
        assign data_we_combine[i] = data_we[i] & ~io.conflict;
        assign data_io.wen[i] = data_we_combine[i];
        assign data_io.we_new[i] = ~(hit[i]);
        assign data_io.windex[i] = hit[i] ? whit_idx[i] :
                                   weq_combine[i] ? free_idx[weq_idx[i]] : free_idx[i];
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
    logic `N(`STORE_COMMIT_SIZE) widx_valid_combine, select_en;
    logic thresh_write;
generate
    assign write_ready = select_en;
    DirectionSelector #(`STORE_COMMIT_SIZE, `STORE_PIPELINE) write_selector (
        .clk(clk),
        .rst(rst),
        .en(write_en),
        .idx(free_en),
        .ready(ready),
        .select(select_en)
    );
    PEncoder #(`STORE_COMMIT_SIZE) encoder_write_ready (write_ready, widx);
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        Decoder #(`STORE_COMMIT_SIZE) decoder_widx (data_io.windex[i], widx_decode[i]);
        assign widx_valid[i] = widx_decode[i] & {`STORE_COMMIT_SIZE{data_io.wen[i]}};
    end
    ParallelOR #(`STORE_COMMIT_SIZE, `STORE_PIPELINE) or_widx ( widx_valid, widx_valid_combine);
    for(genvar i=0; i<`STORE_COMMIT_SIZE; i++)begin
        assign ready[i] = ((counter[i] == 1) | thresh_write | flush) & addr_en[i] & ~writing[i];
        always_ff @(posedge clk or posedge rst)begin
            if(rst == `RST)begin
                counter[i] <= 1;
            end
            else if(|data_we_combine)begin
                if(widx_valid_combine[i])begin
                    counter[i] <= {`STORE_COUNTER_WIDTH{1'b1}};
                end
                else if(counter[i] != 1)begin
                    counter[i] <= counter[i] - 1;
                end
            end
        end
    end
endgenerate
    ParallelAdder #(1, `STORE_COMMIT_SIZE) adder_addr_num ( addr_en, addr_num);
    always_ff @(posedge clk)begin
        thresh_write <= addr_num > `STORE_COMMIT_THRESH;
    end

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
    assign data_io.cache_req = wio.valid;
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
            assign offset_vec[i][j] = loadFwd.fwdData[i].en & addr_en[j] &
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
        assign forward_vec[i] = ptag_vec[i] & fwd_offset_vec[i];
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
                if(write_en[i])begin
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
        logic `N(64) difftestData, expandMask;
        MaskExpand #(8) mask_expand(difftestMask, expandMask);
        assign difftestMask = {wmask[i] & {`DCACHE_BYTE{waddr[i][0]}},
                               wmask[i] & {`DCACHE_BYTE{~waddr[i][0]}}};
        assign difftestData = {wdata[i] & {`DCACHE_BITS{waddr[i][0]}},
                               wdata[i] & {`DCACHE_BITS{~waddr[i][0]}}} & expandMask;
        DifftestStoreEvent difftest_store_event(
            .clock(clk),
            .coreid(0),
            .index(i),
            .valid(data_we_combine[i]),
            .storeAddr((waddr[i] << `DCACHE_BYTE_WIDTH) & 32'hfffffffb),
            .storeData(difftestData),
            .storeMask(difftestMask)
        );
    end
endgenerate
    `Log(DLog::Debug, T_SCB, data_we_combine[0],
        $sformatf("store commit[0]. %h %h %b", waddr[0] << `DCACHE_BYTE_WIDTH, wdata[0], wmask[0]))
    `Log(DLog::Debug, T_SCB, data_we_combine[1],
        $sformatf("store commit[1]. %h %h %b", waddr[1] << `DCACHE_BYTE_WIDTH, wdata[1], wmask[1]))
`endif
endmodule

interface SCDataIO;
    logic `N(`STORE_PIPELINE) wen;
    logic `N(`STORE_PIPELINE) we_new;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_WIDTH) windex;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BANK_WIDTH) wbank;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BITS) wdata;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) wmask;

    logic `N(`LOAD_PIPELINE) fwd_req;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_COMMIT_WIDTH) fwd_idx;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BANK_WIDTH) fwd_bank;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) fwd_data;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) fwd_mask;

    logic cache_req;
    logic `N(`STORE_COMMIT_WIDTH) cacheIdx;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) cacheData;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BYTE) cacheMask;

    modport data (input wen, we_new, windex, wbank, wdata, wmask,
                  fwd_req, fwd_idx, fwd_bank, cache_req, cacheIdx,
                  output fwd_data, fwd_mask, cacheData, cacheMask); 
endinterface

module SCDataModule(
    input logic clk,
    input logic rst,
    SCDataIO.data io
);
    localparam RPORT = `STORE_PIPELINE+1;
    logic `TENSOR(`DCACHE_BANK, `STORE_PIPELINE, `DCACHE_BYTE) wen;
    logic `TENSOR(`DCACHE_BANK, RPORT, `STORE_COMMIT_WIDTH) raddr;
    logic `TENSOR(`DCACHE_BANK, `STORE_PIPELINE, `STORE_COMMIT_WIDTH) waddr;
    logic `TENSOR(`DCACHE_BANK, RPORT, `DCACHE_BITS) rdata;
    logic `TENSOR(`DCACHE_BANK, RPORT, `DCACHE_BYTE) rmask;
    logic `TENSOR(`DCACHE_BANK, `STORE_PIPELINE, `DCACHE_BITS) wdata;

    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BANK) fwd_bank_dec;
    logic `ARRAY(`STORE_PIPELINE, `DCACHE_BANK) wbank_decode;
    logic `N(`STORE_PIPELINE) we_new;
    
    assign we_new = io.we_new & io.wen;
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        Decoder #(`DCACHE_BANK) decoder_fwd_bank (io.fwd_bank[i], fwd_bank_dec[i]);
        Decoder #(`DCACHE_BANK) decoder_bank(io.wbank[i], wbank_decode[i]);
        always_ff @(posedge clk)begin
            if(io.fwd_req[i])begin
                io.fwd_data[i] <= rdata[io.fwd_bank[i]][i];
                io.fwd_mask[i] <= rmask[io.fwd_bank[i]][i];
            end
            else begin
                io.fwd_mask[i] <= 0;
            end
        end
    end

    for(genvar i=0; i<`DCACHE_BANK; i++)begin
        SCDataBank data_bank(
            .clk(clk),
            .rst(rst),
            .raddr(raddr[i]),
            .we_new(we_new),
            .wmask(wen[i]),
            .waddr(waddr[i]),
            .wdata(wdata[i]),
            .rdata(rdata[i]),
            .rmask(rmask[i])
        );
        for(genvar j=0; j<`STORE_PIPELINE; j++)begin
            assign raddr[i][j] = io.fwd_idx[j];
        end
        assign raddr[i][`STORE_PIPELINE] = io.cacheIdx;

        for(genvar j=0; j<`STORE_PIPELINE; j++)begin
            assign wen[i][j] = {`DCACHE_BYTE{io.wen[j] & wbank_decode[j][i]}} & io.wmask[j];
            assign waddr[i][j] = io.windex[j];
            assign wdata[i][j] = io.wdata[j];
        end

        always_ff @(posedge clk)begin
            if(io.cache_req)begin
                io.cacheData[i] <= rdata[i][`STORE_PIPELINE];
                io.cacheMask[i] <= rmask[i][`STORE_PIPELINE];
            end
        end
    end
endgenerate

endmodule

module SCDataBank(
    input logic clk,
    input logic rst,
    input logic `ARRAY(`STORE_PIPELINE+1, `STORE_COMMIT_WIDTH) raddr,
    input logic `N(`STORE_PIPELINE) we_new,
    input logic `ARRAY(`STORE_PIPELINE, `DCACHE_BYTE) wmask,
    input logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_WIDTH) waddr,
    input logic `ARRAY(`STORE_PIPELINE, `DCACHE_BITS) wdata,
    output logic `ARRAY(`STORE_PIPELINE+1, `DCACHE_BITS) rdata,
    output logic `ARRAY(`STORE_PIPELINE+1, `DCACHE_BYTE) rmask
);
    typedef struct packed {
        logic [7: 0] d;
        logic v;
    } ByteMask;
    logic `ARRAY(`DCACHE_BYTE, 8) d `N(`STORE_COMMIT_SIZE);
    logic `N(`DCACHE_BYTE) v `N(`STORE_COMMIT_SIZE);
    logic wconflict;
    logic `ARRAY(`STORE_PIPELINE, `STORE_COMMIT_SIZE) waddr_decode;
    logic `N(`STORE_COMMIT_SIZE) waddr_combine;
    logic `ARRAY(`STORE_COMMIT_SIZE, `DCACHE_BYTE) wmask_map;

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        Decoder #(`STORE_COMMIT_SIZE) decoder_waddr (waddr[i], waddr_decode[i]);
    end

    for(genvar i=0; i<`STORE_COMMIT_SIZE; i++)begin
        for(genvar j=0; j<`DCACHE_BYTE; j++)begin
            always_ff @( posedge clk ) begin
                if(waddr_decode[1][i] & wmask[1][j])begin
                    d[i][j] <= wdata[1][j*8 +: 8];
                end
                else if(waddr_decode[0][i] & wmask[0][j])begin
                    d[i][j] <= wdata[0][j*8 +: 8];
                end
                if(waddr_decode[1][i] & wmask[1][j] |
                   waddr_decode[0][i] & wmask[0][j])begin
                    v[i][j] <= 1'b1;
                end
                else if(waddr_decode[1][i] & we_new[1] |
                        waddr_decode[0][i] & we_new[0])begin
                    v[i][j] <= 1'b0;
                end
            end
        end
    end
endgenerate

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        for(genvar j=0; j<`DCACHE_BYTE; j++)begin
            assign rdata[i][(j+1)*8-1: j*8] = d[raddr[i]][j];
            assign rmask[i][j] = v[raddr[i]][j];
        end
    end
    for(genvar i=0; i<`DCACHE_BYTE; i++)begin
        assign rdata[`STORE_PIPELINE][(i+1)*8-1: i*8] = d[raddr[`STORE_PIPELINE]][i];
        assign rmask[`STORE_PIPELINE][i] = v[raddr[`STORE_PIPELINE]][i];
    end

endgenerate
endmodule