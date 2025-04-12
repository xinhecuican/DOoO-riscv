`include "../../../../defines/defines.svh"

interface ReplaceQueueIO;
    logic en;
    logic refill_en;
    DirectoryState refill_state;
    logic entry_en;
    logic `N(`DCACHE_TAG+`DCACHE_SET_WIDTH) addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    logic `N(`DCACHE_REPLACE_WIDTH) idx;
    logic full;

    logic `N(`PADDR_SIZE) waddr;
    logic whit;

    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx;

    logic snoop_en;
    logic snoop_clean;
    logic snoop_hit;
    DirectoryState snoop_state;
    logic `N(`PADDR_SIZE) snoop_addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) snoop_data;

    modport queue (input en, refill_en, refill_state, entry_en, addr, data, replace_idx, waddr, snoop_en, snoop_clean, snoop_addr, output idx, whit, full, snoop_data, snoop_hit, snoop_state);
    modport miss (input full, idx, output replace_idx);
endinterface

module ReplaceQueue(
    input logic clk,
    input logic rst,
    ReplaceQueueIO.queue io,
    CacheBus.masterw w_axi_io
);
    localparam TRANSFER_BANK = `DCACHE_LINE / `DATA_BYTE;
    typedef struct packed {
        logic en;
        logic `N(`DCACHE_TAG+`DCACHE_SET_WIDTH) addr;
        logic `ARRAY(TRANSFER_BANK, `XLEN) data;
    } ReplaceEntry;
    typedef enum { IDLE, ADDRESS, WRITE, WAIT_B } ReplaceState;
    ReplaceState replace_state;

    ReplaceEntry entrys `N(`DCACHE_REPLACE_SIZE);
    logic `N(`DCACHE_REPLACE_SIZE) en, dataValid, prior;
    DirectoryState `N(`DCACHE_REPLACE_SIZE) state;
    logic `N(`DCACHE_REPLACE_SIZE) valid, prior_valid;
    logic `N(`DCACHE_REPLACE_WIDTH) freeIdx, validIdx, priorIdx, processIdx, processIdx_pre;
    logic full;
    logic `N(`DCACHE_REPLACE_SIZE) hit;
    logic `N(`PADDR_SIZE) waddr;
    ReplaceEntry newEntry;

    logic aw_valid;
    logic `N($clog2(TRANSFER_BANK)) widx;
    logic wvalid;
    logic wlast;
    logic aw_dirty;
    logic refill_invalid;
    ReplaceEntry processEntry;
    logic axi_snoop_conflict, snoop_conflict_wait;

    logic `N(`DCACHE_REPLACE_SIZE) snoop_addr_hit, snoop_hit;
    logic enqueue_hit;
    logic snoop_clean_hit;
    logic `N(`DCACHE_REPLACE_WIDTH) snoop_hit_idx, snoop_idx;
    logic `TENSOR(`DCACHE_REPLACE_SIZE, `DCACHE_BANK, `DCACHE_BITS) replace_data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) snoop_data;
    DirectoryState snoop_state;

    assign io.full = full;
    assign newEntry.en = io.entry_en;
    assign newEntry.addr = io.addr;
    assign newEntry.data = io.data;
    assign snoop_clean_hit = io.snoop_en & io.snoop_clean & ((|snoop_hit) | enqueue_hit);
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_free_idx (~en, freeIdx);
    always_ff @(posedge clk)begin
        full <= &en;
        if(io.refill_en)begin
            entrys[io.replace_idx] <= newEntry;
        end
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            dataValid <= 0;
            prior <= 0;
            en <= 0;
            state <= 0;
        end
        else begin
            if(io.en & ~(|hit) & ~(&en))begin
                en[freeIdx] <= 1'b1;
                prior[freeIdx] <= 1'b0;
                dataValid[freeIdx] <= 1'b0;
            end
            if(io.en & (|hit))begin
                prior[freeIdx] <= 1'b1;
            end

            if(io.refill_en)begin
                dataValid[io.replace_idx] <= 1'b1;
                state[io.replace_idx] <= io.refill_state;
            end

            if((w_axi_io.b_valid | refill_invalid) & ~axi_snoop_conflict & ~snoop_conflict_wait)begin
                en[processIdx] <= 1'b0;
            end
            if(snoop_clean_hit)begin
                en[snoop_idx] <= 1'b0;
            end
        end
    end

// write conflict detect
    assign waddr = io.snoop_en ? io.snoop_addr : io.waddr;
generate
    for(genvar i=0; i<`DCACHE_REPLACE_SIZE; i++)begin
        assign hit[i] = en[i] & dataValid[i] & entrys[i].en & (waddr`DCACHE_BLOCK_BUS == entrys[i].addr);
    end
    logic `N(`DCACHE_REPLACE_WIDTH) whit_idx;
    Encoder #(`DCACHE_REPLACE_SIZE) encoder_hit (hit, whit_idx);
    always_ff @(posedge clk)begin
        io.whit <= |hit;
        io.idx <= |hit ? whit_idx : freeIdx;
    end
endgenerate

// axi

    assign valid = en & dataValid;
    assign prior_valid = en & dataValid & prior;
    assign axi_snoop_conflict = snoop_clean_hit & (snoop_idx == processIdx);
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_valid_idx (valid, validIdx);
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_prior_idx (prior_valid, priorIdx);
    assign processIdx_pre = |prior_valid ? priorIdx : validIdx;
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            aw_valid <= 1'b0;
            widx <= 0;
            wlast <= 0;
            wvalid <= 0;
            processEntry <= 0;
            processIdx <= 0;
            replace_state <= IDLE;
            refill_invalid <= 1'b0;
            snoop_conflict_wait <= 1'b0;
        end
        else begin
            case(replace_state)
            IDLE: begin
                if(|valid & ~(snoop_clean_hit & (processIdx_pre == snoop_idx)))begin
                    aw_dirty <= state[processIdx_pre].dirty;
                    if (entrys[processIdx_pre].en)begin
                        replace_state <= ADDRESS;
                        aw_valid <= 1'b1;
                    end
                    else begin
                        replace_state <= WAIT_B;
                        refill_invalid <= 1'b1;
                    end
                    processEntry <= entrys[processIdx_pre];
                    processIdx <= processIdx_pre;
                end
            end
            ADDRESS: begin
                if(w_axi_io.aw_valid & w_axi_io.aw_ready)begin
                    aw_valid <= 1'b0;
                    replace_state <= WRITE;
                    wvalid <= 1'b1;
                end
                if(axi_snoop_conflict)begin
                    snoop_conflict_wait <= 1'b1;
                end
            end
            WRITE: begin
                if(w_axi_io.w_valid & w_axi_io.w_ready)begin
                    widx <= widx + 1;
                    if(wlast)begin
                        wvalid <= 1'b0;
                        replace_state <= WAIT_B;
                    end
                    if(widx == TRANSFER_BANK - 2)begin
                        wlast <= 1'b1;
                    end
                    else begin
                        wlast <= 1'b0;
                    end
                end
                if(axi_snoop_conflict)begin
                    snoop_conflict_wait <= 1'b1;
                end
            end
            WAIT_B: begin
                if(w_axi_io.b_valid | refill_invalid | axi_snoop_conflict | snoop_conflict_wait)begin
                    replace_state <= IDLE;
                    refill_invalid <= 1'b0;
                    snoop_conflict_wait <= 1'b0;
                end
            end
            endcase
        end
    end

    assign w_axi_io.aw_valid = aw_valid;
    assign w_axi_io.aw_id = 0;
    assign w_axi_io.aw_addr = {processEntry.addr, {`DCACHE_LINE_WIDTH{1'b0}}};
    assign w_axi_io.aw_len = `DCACHE_LINE / `DATA_BYTE - 1;
    assign w_axi_io.aw_size = $clog2(`DATA_BYTE);
    assign w_axi_io.aw_burst = 2'b01;
    assign w_axi_io.aw_user = 0;
    assign w_axi_io.aw_snoop = aw_dirty ? `ACEOP_WRITE_CLEAN : `ACEOP_WRITE_EVICT;

    assign w_axi_io.w_data = processEntry.data[widx];
    assign w_axi_io.w_strb = {`DATA_BYTE{1'b1}};
    assign w_axi_io.w_last = wlast;
    assign w_axi_io.w_valid = wvalid;
    assign w_axi_io.w_user = 0;

    assign w_axi_io.b_ready = 1'b1;

// snoop
generate
    for(genvar i=0; i<`DCACHE_REPLACE_SIZE; i++)begin
        assign snoop_addr_hit[i] = en[i] & (entrys[i].addr == io.snoop_addr`DCACHE_BLOCK_BUS);
        assign replace_data[i] = entrys[i].data;
    end
endgenerate
    assign snoop_hit = snoop_addr_hit & dataValid;
    assign enqueue_hit = io.refill_en & (io.snoop_addr`DCACHE_BLOCK_BUS == io.addr);
    Encoder #(`DCACHE_REPLACE_SIZE) encoder_snoop (snoop_hit, snoop_hit_idx);
    assign snoop_idx = enqueue_hit ? io.replace_idx : snoop_hit_idx;
    OldestSelect #(`DCACHE_REPLACE_SIZE, 1, `DCACHE_BANK * `DCACHE_BITS) select_snoop_data (snoop_hit, replace_data, , snoop_data);
    OldestSelect #(`DCACHE_REPLACE_SIZE, 1, $bits(DirectoryState)) select_snoop_state (snoop_hit, state, , snoop_state);
    always_ff @(posedge clk)begin
        if (io.snoop_en)begin
            io.snoop_hit <= (|snoop_hit) | enqueue_hit;
            io.snoop_data <= enqueue_hit ? io.data : snoop_data;
            io.snoop_state <= enqueue_hit ? io.refill_state : snoop_state;
        end
    end



`ifdef DIFFTEST
    `LOG_ARRAY(T_DCACHE, dbg_data, newEntry.data, TRANSFER_BANK)
    `Log(DLog::Debug, T_DCACHE, io.refill_en & io.entry_en,
        $sformatf("dcache replace. [%h] %s", newEntry.addr << `DCACHE_LINE_WIDTH, dbg_data))
`endif
endmodule