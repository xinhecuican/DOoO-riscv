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
    logic `N(`DCACHE_REPLACE_SIZE) en, dataValid, replaced;
    DirectoryState `N(`DCACHE_REPLACE_SIZE) state;
    logic `N(`DCACHE_REPLACE_SIZE) valid;
    logic `N(`DCACHE_REPLACE_WIDTH) freeIdx, processIdx, processIdx_pre;
    logic `N(`DCACHE_REPLACE_SIZE) process_dec, process_pre_dec, replace_dec, free_dec;
    logic full, replace_valid_cond;
    logic `N(`DCACHE_REPLACE_SIZE) hit;
    logic `N(`PADDR_SIZE) waddr;
    ReplaceEntry newEntry;
    logic `ARRAY(`DCACHE_ID_SIZE, `DCACHE_REPLACE_WIDTH) id_map;
    logic `N(`DCACHE_ID_SIZE) id_valids, free_id, process_id_dec, b_id_dec;
    logic `N(`DCACHE_ID_WIDTH) free_id_idx, process_id;
    logic `N(`DCACHE_REPLACE_SIZE) refill_id_dec;

    logic aw_valid;
    logic `N($clog2(TRANSFER_BANK)) widx;
    logic wvalid;
    logic wlast;
    logic aw_dirty;
    logic refill_invalid;
    ReplaceEntry processEntry;
    logic axi_snoop_conflict, snoop_conflict_wait;

    logic `N(`DCACHE_REPLACE_SIZE) snoop_addr_hit, snoop_hit, snoop_hit_all;
    logic enqueue_hit;
    logic snoop_clean_hit;
    logic `TENSOR(`DCACHE_REPLACE_SIZE, `DCACHE_BANK, `DCACHE_BITS) replace_data;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) snoop_data;
    DirectoryState snoop_state;

    assign io.full = full;
    assign newEntry.en = io.entry_en;
    assign newEntry.addr = io.addr;
    assign newEntry.data = io.data;
    assign snoop_clean_hit = io.snoop_en & io.snoop_clean;
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_free_idx (~en, freeIdx);
    PSelector #(`DCACHE_REPLACE_SIZE) selector_free (~en, free_dec);
    always_ff @(posedge clk)begin
        full <= &en;
        if(io.refill_en)begin
            entrys[io.replace_idx] <= newEntry;
        end
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            dataValid <= 0;
            en <= 0;
            replaced <= 0;
            state <= 0;
        end
        else begin
            if(io.en & ~(|hit) & ~(&en))begin
                dataValid[freeIdx] <= 1'b0;
                replaced[freeIdx] <= 1'b0;
            end

            if(io.refill_en)begin
                dataValid[io.replace_idx] <= 1'b1;
                state[io.replace_idx] <= io.refill_state;
            end
            if((replace_state == IDLE) & replace_valid_cond)begin
                replaced[processIdx_pre] <= 1'b1;
            end

            for(int i=0; i<`DCACHE_REPLACE_SIZE; i++)begin
                en[i] <= (en[i] | io.en & ~(|hit) & ~(&en) & free_dec[i]) &
                        ~(w_axi_io.b_valid & refill_id_dec[i] | refill_invalid & process_dec[i]) &
                        ~(snoop_clean_hit & snoop_hit_all[i]);
            end
        end
    end

// write conflict detect
    assign waddr = io.waddr;
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

    assign valid = en & dataValid & ~replaced;
    assign axi_snoop_conflict = snoop_clean_hit & (|(snoop_hit & process_dec));
    DirectionSelector #(`DCACHE_REPLACE_SIZE) valid_selector (
        .clk,
        .rst,
        .en(io.en & ~(|hit) & ~(&en)),
        .idx(free_dec),
        .ready(valid),
        .select(process_pre_dec)
    );
    Encoder #(`DCACHE_REPLACE_SIZE) encoder_processIdx_pre (process_pre_dec, processIdx_pre);
    Decoder #(`DCACHE_REPLACE_SIZE) decoder_process (processIdx, process_dec);
    PEncoder #(`DCACHE_ID_SIZE) encoder_free_id (~id_valids, free_id_idx);
    PSelector #(`DCACHE_ID_SIZE) selector_free_id (~id_valids, free_id);
    Decoder #(`DCACHE_ID_SIZE) decoder_process_id (process_id, process_id_dec);
    Decoder #(`DCACHE_REPLACE_SIZE) decoder_refill_id (id_map[w_axi_io.b_id], refill_id_dec);
    Decoder #(`DCACHE_ID_SIZE) decoder_b_id (w_axi_io.b_id, b_id_dec);

    assign replace_valid_cond = |valid & |(~id_valids) & ~(snoop_clean_hit & (|(process_pre_dec & snoop_hit)));

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
            id_map <= 0;
            id_valids <= 0;
            process_id <= 0;
        end
        else begin
            case(replace_state)
            IDLE: begin
                if(replace_valid_cond)begin
                    aw_dirty <= state[processIdx_pre].dirty;
                    process_id <= free_id_idx;
                    if (entrys[processIdx_pre].en)begin
                        replace_state <= ADDRESS;
                        aw_valid <= 1'b1;
                        id_map[free_id_idx] <= processIdx_pre;
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
                    wlast <= widx == TRANSFER_BANK - 2;
                end
                if(axi_snoop_conflict)begin
                    snoop_conflict_wait <= 1'b1;
                end
            end
            WAIT_B: begin
                replace_state <= IDLE;
                refill_invalid <= 1'b0;
                snoop_conflict_wait <= 1'b0;
            end
            endcase
            for(int i=0; i<`DCACHE_ID_SIZE; i++)begin
                id_valids[i] <= (id_valids[i] | (replace_state == IDLE) & replace_valid_cond & entrys[processIdx_pre].en & free_id[i]) &
                               ~(w_axi_io.b_valid & w_axi_io.b_ready & b_id_dec[i]) &
                               ~(snoop_clean_hit & id_valids[i] & snoop_hit[id_map[i]]);
            end
        end
    end

    assign w_axi_io.aw_valid = aw_valid;
    assign w_axi_io.aw_id = process_id;
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
        assign snoop_addr_hit[i] = en[i] & entrys[i].en & (entrys[i].addr == io.snoop_addr`DCACHE_BLOCK_BUS);
        assign replace_data[i] = entrys[i].data;
    end
endgenerate
    assign snoop_hit = snoop_addr_hit & dataValid;
    assign enqueue_hit = io.refill_en & (io.snoop_addr`DCACHE_BLOCK_BUS == io.addr);
    Decoder #(`DCACHE_REPLACE_SIZE) decoder_replace (io.replace_idx, replace_dec);
    assign snoop_hit_all = {`DCACHE_REPLACE_SIZE{enqueue_hit}} & replace_dec | snoop_hit;
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