`include "../../../defines/defines.svh"

// 替换：如果是LLC，那么dirty写回即可
// 如果不是，并且不是拥有者，则直接丢弃
// 如果是拥有者则写入下一级

// READ:
// READ_ONCE: icache tlb
// READ_SHARED: mem read
// READ_UNIQUE: mem write, don't owned
// MAKE_UNIQUE: mem full write or owned
// CLEAN_UNIQUE: mem write and owned, if owned after slave dir read, treat as MAKE_UNIQUE
//               otherwise, treat as READ_UNIQUE
// CLEAN_INVALID: snoop clean
// WRITE:
// WRITE_CLEAN: mem write and cache line is dirty
// WRITE_EVICT: mem write and cache line is clean
// SNOOP:
// READ_ONCE
// READ_SHARED
// READ_UNIQUE
// CLEAN_INVALID
module L2MSHR #(
    parameter MSHR_SIZE = 8,
    parameter SLAVE_BANK = 16,
    parameter CACHE_BANK = 16, // CACHELINE BANK
    parameter DATA_BANK = 1, // CACHE SET BANK
    parameter ID_WIDTH=2,
    parameter ID_OFFSET=1,
    parameter SLAVE = 1,
    parameter WAY_NUM = 4,
    parameter SET = 64,
    parameter OFFSET = 32,
    parameter ISL2 = 1,
    parameter LLC = 1,
    parameter SLAVE_DIR_SET = 64,
    parameter SLAVE_DIR_WAY = 4,
    parameter type snoop_ac_chan_t = logic,
    parameter type snoop_cd_chan_t = logic,
    parameter type snoop_req_t = logic,
    parameter type snoop_resp_t = logic,
    parameter type mst_snoop_req_t = logic,
    parameter type mst_snoop_resp_t = logic,
    parameter MST_SNOOP_ID_WIDTH = 4,
    parameter MSHR_WIDTH = $clog2(MSHR_SIZE),
    parameter SLAVE_BITS = (`CACHELINE_SIZE / SLAVE_BANK) * 8,
    parameter CACHE_BITS = (`CACHELINE_SIZE / CACHE_BANK) * 8,
    parameter SLAVE_WIDTH = idxWidth(SLAVE),
    parameter SLAVE_SET_WIDTH = $clog2(SLAVE_DIR_SET),
    parameter SLAVE_BANK_WIDTH = $clog2(SLAVE_BANK),
    parameter CACHE_BANK_WIDTH = $clog2(CACHE_BANK),
    parameter DATA_BANK_WIDTH = idxWidth(DATA_BANK),
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter SET_WIDTH = $clog2(SET),
    parameter OFFSET_WIDTH = $clog2(OFFSET),
    parameter SLAVE_WAY_WIDTH = $clog2(SLAVE_DIR_WAY),
    parameter SLAVE_TAG_WIDTH = `PADDR_SIZE - OFFSET_WIDTH - $clog2(SLAVE_DIR_SET),
    parameter TAG_WIDTH = `PADDR_SIZE - OFFSET_WIDTH - SET_WIDTH
)(
    input logic clk,
    input logic rst,
    CacheBus.slave slave_io,
    CacheBus.master master_io,
    output snoop_req_t `N(SLAVE) snoop_req,
    input snoop_resp_t `N(SLAVE) snoop_resp,

    input mst_snoop_req_t mst_snoop_req,
    output mst_snoop_resp_t mst_snoop_resp,

    L2MSHRSlaveIO.mshr mshr_slave_io,
    L2MSHRDirIO.mshr mshr_dir_io,
    L2MSHRDataIO.mshr mshr_data_io
);

    typedef struct packed {
        logic write;
        logic snoop;
        logic `N(ID_WIDTH) id;
        logic `N(4) op;
        logic `N(`PADDR_SIZE) paddr;
    } MSHREntry;

    // for snoop
    typedef struct packed {
        logic `N(SLAVE) slave;
        logic `N(SLAVE_WIDTH) slave_owner;
    } DirInfo;

    // for dir write
    typedef struct packed {
        logic `N(`PADDR_SIZE) waddr;
        logic `N(SLAVE_WAY_WIDTH) slave_replace_way;
        logic `N(WAY_WIDTH) replace_way;
        logic `N(SLAVE) slave;
        logic write;
        logic write_dirty;
        logic owned;
        logic dir_clean;
        logic require_owned; // READ_UNIQUE, MAKE_UNIQUE
        logic slave_share;
        logic slave_hit;
        logic dir_hit;
        logic `N(SLAVE_WIDTH) owner;
    } DirWInfo;

    MSHREntry `N(MSHR_SIZE) entrys;
    logic `N(MSHR_SIZE) entry_waiting;
    DirInfo `N(MSHR_SIZE) dir_infos;
    logic `ARRAY(MSHR_SIZE, WAY_WIDTH) lookup_hit_ways, lookup_replace_ways, lookup_data_ways;
    logic `ARRAY(MSHR_SIZE, `PADDR_SIZE) paddrs;
    logic `N(MSHR_SIZE) entry_snoop;
    logic `N(MSHR_SIZE) en, require_data, op_valid, data_valid;
    logic `N(MSHR_SIZE) req_ll, req_ll_op_valid; // needed if ISL2 == 1
    logic `N(MSHR_SIZE) snoop_request, snoop_replace_request;

    logic `N(MSHR_SIZE) free_en1, free_en2;
    logic `N(MSHR_SIZE) free_idx1, free_idx2;
    logic free_conflict, full, ar_free_conflict;
    logic `N(MSHR_SIZE) dir_requests, dir_request_select;
    logic `N(MSHR_SIZE) dir_resp_reqs; // need response state to fill directory
    logic `N(MSHR_WIDTH) dir_select_idx, dir_select_idx_n;
    logic `N(MSHR_SIZE) dir_request_select_n;
    logic dir_request, dir_request_n;
    DirWInfo `N(MSHR_SIZE) dir_winfos;
    logic `ARRAY(MSHR_SIZE, 4) dir_op;

    logic `ARRAY(MSHR_SIZE, SLAVE_BANK) refill_valids;
    logic `ARRAY(SLAVE_BANK, MSHR_SIZE) refill_valids_rev;
    logic `N(SLAVE_BANK) refill_valids_bank;
    logic `N(SLAVE_BANK_WIDTH) refill_bank_idx;
    logic `ARRAY(SLAVE_BANK, SLAVE_BITS) refill_data;
    logic `ARRAY(MSHR_SIZE, ID_WIDTH) refill_ids;
    DirectoryState `N(MSHR_SIZE) refill_resps;
    logic refill_snoop_resp_req, refill_l3_resp_req;
    logic `ARRAY(SLAVE_BANK, MSHR_SIZE) refill_valid;
    logic `N(MSHR_SIZE) refill_valid_select;
    logic `N(SLAVE_BANK) refill_bank_select;
    logic `N(MSHR_WIDTH) refill_idx, refill_direct_idx, refill_data_idx;
    logic refill_snoop;
    logic refill_r_valid;
    logic `N(SLAVE_BITS) refill_r_data;
    logic `ARRAY(DATA_BANK, MSHR_SIZE) data_bank_valids;
    logic `ARRAY(MSHR_SIZE, DATA_BANK) data_bank_valids_rev;
    logic `N(MSHR_SIZE) snoop_idx_dec, refill_idx_dec;
    logic `N(MSHR_SIZE) refill_finish, refill_no_rack, refill_direct;

    typedef enum {SNOOP_IDLE, SNOOP_REQUEST, SNOOP_REPLACE} SnoopState;
    typedef struct packed {
        logic `N(MSHR_WIDTH) idx;
        logic `N(SLAVE) target_slave;
        logic `N(SLAVE) slave_request;
        logic `N(`PADDR_SIZE) snoop_addr;
        logic `N(4) op;
        logic `N(SLAVE) response;
        DirectoryState response_state;
        logic require_data;
        logic slave_replace;
        logic replace_dir;
        logic state_change;
        logic `N(WAY_WIDTH) replace_way;
        logic `N(SLAVE_BANK_WIDTH) data_index;
        logic data_valid;
    } SnoopBuffer;
    SnoopState snoop_state;
    MSHREntry snoop_entry;
    logic `N(4) snoop_op;
    DirInfo snoop_dir_info;
    SnoopBuffer snoop_buffer;
    logic snoop_valid;
    logic `N(MSHR_WIDTH) snoop_idx;
    logic `N(SLAVE) owner_decode;
    logic `N(SLAVE) snoop_cd_valids;
    snoop_cd_chan_t `N(SLAVE) snoop_cd_datas;
    logic snoop_cd_valid;
    snoop_cd_chan_t snoop_cd_data;
    logic `ARRAY(MSHR_SIZE, SLAVE_TAG_WIDTH) snoop_replace_tag;
    logic snoop_replace_cond;
    logic `N(MSHR_SIZE) snoop_write_conflict, snoop_write_conflict_n;
    logic snoop_write_conflict_end;
    logic snoop_write_cond;

    logic `N(MSHR_SIZE) lookup_requests;
    logic `ARRAY(MSHR_SIZE, DATA_BANK) lookup_bank;
    logic `ARRAY(DATA_BANK, MSHR_SIZE) lookup_bank_rev;
    logic `N(DATA_BANK) lookup_data_req;
    logic `ARRAY(MSHR_SIZE, SET_WIDTH) lookup_addrs, lookup_write_addrs;

    typedef enum {L3_IDLE, L3_REQUEST} L3State;
    typedef struct packed {
        logic request;
        logic `N(MSHR_WIDTH) idx;
        logic `N(ID_WIDTH) id;
        logic `N(4) op;
        logic `N(`PADDR_SIZE) addr;
        logic `N(CACHE_BANK_WIDTH) data_index;
    } L3Buffer;
    L3State l3_state;
    MSHREntry l3_entry;
    L3Buffer l3_buffer;
    logic `N(MSHR_SIZE) l3_requests;
    logic `N(MSHR_SIZE) l3_idx_dec, l3_buffer_idx_dec;
    logic `N(MSHR_WIDTH) l3_idx;
    logic l3_request;

    logic `TENSOR(MSHR_SIZE, SLAVE_BANK, SLAVE_BITS) write_buffer;
    logic `N(MSHR_SIZE) write_data_valid, write_idx_dec;
    logic `N(MSHR_WIDTH) write_idx;
    logic `N(ID_WIDTH) write_id, slave_b_id;
    logic `N(SLAVE_BANK_WIDTH) write_data_index;
    logic write_waiting, slave_b_valid;
    logic `N(DATA_BANK) write_bank_req;
    logic `ARRAY(DATA_BANK, MSHR_WIDTH) write_bank_idx;
    logic `ARRAY(DATA_BANK, MSHR_SIZE) write_bank_idx_dec;
    logic `N(MSHR_SIZE) entry_write;
    logic `N(MSHR_SIZE) write_data_finish, write_finish;
    logic `N(MSHR_WIDTH) write_b_idx, write_data_finish_idx;
    logic `ARRAY(MSHR_SIZE, ID_WIDTH) write_b_ids;
    logic `N(ID_WIDTH) write_b_id;
    logic write_b_req;

    typedef struct packed {
        logic aw_valid;
        logic dirty;
        logic `N(`PADDR_SIZE) addr;
        logic replace_data_valid;
        logic `ARRAY(CACHE_BANK, CACHE_BITS) replace_data;
        logic `N(ID_WIDTH) id;
        logic `N(MSHR_WIDTH) idx;
        logic `N(WAY_WIDTH) way;
        logic `N(DATA_BANK) data_bank;
        logic `N(CACHE_BANK_WIDTH) data_index;
        logic w_last;
    } ReplaceBuffer;
    ReplaceBuffer replace_buffer;
    logic replace_busy;
    logic `N(MSHR_SIZE) replace_reqs, replace_data_valids;
    logic replace_req;
    logic `ARRAY(MSHR_SIZE, TAG_WIDTH+1) replace_tags; // tag, dirty
    MSHREntry replace_entry;
    logic `N(TAG_WIDTH+1) replace_tag;
    logic `N(MSHR_WIDTH) replace_idx;
    logic write_replace_cond, read_replace_cond, replace_cond_valid;
    logic replace_read_req, replace_read_conflict;
    logic `N(WAY_WIDTH) replace_way_select;
    logic `N(DATA_BANK) replace_data_bank;
    logic `N(DATA_BANK) replace_data_hits;
    logic replace_data_hit;
    logic `ARRAY(CACHE_BANK, CACHE_BITS) replace_read_data;

// enqueue
    logic renq_en, rw_conflict, rsnoop_conflict, wsnoop_conflict;
    logic wenq_en;
    logic snoop_enq_en;
    logic `N(MSHR_SIZE) renq_conflict, wenq_conflict, snoop_enq_conflict;
    logic `N(MSHR_SIZE) mshr_finish, dir_finish, mshr_finish_n, mshr_finish_select;
    logic `N(MSHR_WIDTH) mshr_widx, mshr_widx_n;
    logic `N(SET_WIDTH) mshr_wpaddr;
    logic `N(MSHR_SIZE) waiting_conflict, waiting_select;
    logic `N(MSHR_WIDTH) waiting_select_idx;
    PSelector #(MSHR_SIZE) select_free_en1 (~en, free_en1);
    PRSelector #(MSHR_SIZE) select_free_en2 (~en, free_en2);
    PEncoder #(MSHR_SIZE) encoder_free_idx1 (~en, free_idx1);
    PREncoder #(MSHR_SIZE) encoder_free_idx2 (~en, free_idx2);
    assign free_conflict = (|(free_en1 & free_en2));
    assign full = &en;

    assign ar_free_conflict = (slave_io.aw_valid | mst_snoop_req.ac_valid) & free_conflict;
    assign slave_io.ar_ready = ~full & ~ar_free_conflict;
    assign slave_io.aw_ready = ~full & ~write_waiting | wsnoop_conflict;
    assign mst_snoop_resp.ac_ready = ~full & ~(slave_io.aw_valid & ~write_waiting);

    // write > snoop > read
    assign renq_en = ~full & ~ar_free_conflict & slave_io.ar_valid;
    assign wenq_en = ~full & slave_io.aw_valid & ~write_waiting & ~wsnoop_conflict;
    assign snoop_enq_en = ~full & mst_snoop_req.ac_valid;
    assign rw_conflict = slave_io.aw_valid & ~write_waiting & (slave_io.ar_addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH] == slave_io.aw_addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH]);
    assign rsnoop_conflict = mst_snoop_req.ac_valid & (mst_snoop_req.ac.addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH] == slave_io.ar_addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH]);
    assign wsnoop_conflict = snoop_write_cond & (slave_io.aw_addr == snoop_buffer.snoop_addr);
generate
    for(genvar i=0; i<MSHR_SIZE; i++)begin
        assign renq_conflict[i] = en[i] & (slave_io.ar_addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH] == paddrs[i][OFFSET_WIDTH +: SLAVE_SET_WIDTH]);
        assign wenq_conflict[i] = en[i] & (slave_io.aw_addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH] == paddrs[i][OFFSET_WIDTH +: SLAVE_SET_WIDTH]);
        assign snoop_enq_conflict[i] = en[i] & (mst_snoop_req.ac.addr[OFFSET_WIDTH +: SLAVE_SET_WIDTH] == paddrs[i][OFFSET_WIDTH +: SLAVE_SET_WIDTH]);
        assign waiting_conflict[i] = en[i] & entry_waiting[i] & (|mshr_finish_n) & (paddrs[i][OFFSET_WIDTH +: SLAVE_SET_WIDTH] == mshr_wpaddr);
    end
endgenerate

    assign mshr_finish = en & dir_finish & ~dir_slave_wreq & ~dir_wreq & ~snoop_request & 
                        ~snoop_replace_request & ~l3_requests & (~require_data | refill_finish) & 
                        ~replace_reqs & ~lookup_requests & (~entry_write | write_finish);
    PEncoder #(MSHR_SIZE) encoder_mshr_widx (mshr_finish, mshr_widx);
    PSelector #(MSHR_SIZE) selector_mshr_finish (mshr_finish, mshr_finish_select);
    always_ff @(posedge clk)begin
        mshr_widx_n <= mshr_widx;
        mshr_finish_n <= mshr_finish_select;
        if(mshr_finish)begin
            mshr_wpaddr <= paddrs[mshr_widx][OFFSET_WIDTH +: SLAVE_SET_WIDTH];
        end
    end
    DirectionSelector #(MSHR_SIZE, 2) selector_mshr_waiting (
        .clk,
        .rst,
        .en({renq_en, wenq_en | snoop_enq_en}),
        .idx({free_idx2, free_idx1}),
        .ready(waiting_conflict),
        .select(waiting_select)
    );
    Encoder #(MSHR_SIZE) encoder_waiting_select (waiting_select, waiting_select_idx);

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            en <= 0;
            dir_requests <= 0;
            entrys <= 0;
            entry_waiting <= 0;
        end
        else begin
            for(int i=0; i<MSHR_SIZE; i++)begin
                en[i] <= (en[i] | free_en1[i] & (wenq_en | snoop_enq_en) |
                          free_en2[i] & renq_en) &
                         ~mshr_finish_select[i] & ~snoop_write_conflict_n[i];
            end
            if(wenq_en)begin
                entrys[free_idx1] <= {1'b1, 1'b0, slave_io.aw_id[ID_OFFSET +: ID_WIDTH], 1'b0, slave_io.aw_snoop, slave_io.aw_addr};
                dir_requests[free_idx1] <= ~(|wenq_conflict);
                entry_waiting[free_idx1] <= |wenq_conflict;
            end
            else if(snoop_enq_en)begin
                entrys[free_idx1] <= {1'b0, 1'b1, {ID_WIDTH{1'b0}}, mst_snoop_req.ac.snoop, mst_snoop_req.ac.addr};
                dir_requests[free_idx1] <= ~(|snoop_enq_conflict);
                entry_waiting[free_idx1] <= |snoop_enq_conflict;
            end
            if(renq_en)begin
                entrys[free_idx2] <= {1'b0, 1'b0, slave_io.ar_id[ID_OFFSET +: ID_WIDTH], slave_io.ar_snoop, slave_io.ar_addr};
                dir_requests[free_idx2] <= ~(|renq_conflict) & ~rw_conflict & ~rsnoop_conflict;
                entry_waiting[free_idx2] <= (|renq_conflict) | rw_conflict | rsnoop_conflict;
            end

            if(|dir_requests)begin
                dir_requests[dir_select_idx] <= 1'b0;
            end

            if(|waiting_conflict)begin
                dir_requests[waiting_select_idx] <= 1'b1;
                entry_waiting[waiting_select_idx] <= 1'b0;
            end
        end
    end

// refill buffer
    logic `TENSOR(MSHR_SIZE, SLAVE_BANK, SLAVE_BITS) refill_buffer_data;
generate
    for(genvar i=0; i<DATA_BANK; i++)begin
        logic `N(MSHR_SIZE) mshr_idx_dec;
        Decoder #(MSHR_SIZE) decoder_data_valid (mshr_data_io.mshr_idx_o[i], mshr_idx_dec);
        assign data_bank_valids[i] = {MSHR_SIZE{mshr_data_io.rvalid[i] & ~(replace_busy & replace_data_hits[i])}} & mshr_idx_dec;
        for(genvar j=0; j<MSHR_SIZE; j++)begin
            assign data_bank_valids_rev[j][i] = data_bank_valids[i][j];
        end
    end
    Decoder #(MSHR_SIZE) decoder_snoop_idx (snoop_buffer.idx, snoop_idx_dec);
    Decoder #(MSHR_SIZE) decoder_l3_buffer_idx (l3_buffer.idx, l3_buffer_idx_dec);
    
    localparam PARTITION = CACHE_BITS / SLAVE_BITS;
    for(genvar i=0; i<SLAVE_BANK; i++)begin : refill_buffer
        logic `ARRAY(MSHR_SIZE, SLAVE_BITS) data, cache_data;
        logic `ARRAY(DATA_BANK, CACHE_BITS) bank_data;
        logic `N(MSHR_SIZE) data_valid;
        logic `N(MSHR_SIZE) we;
        logic `N(MSHR_SIZE) data_we, snoop_we;
        logic `ARRAY(MSHR_SIZE, SLAVE_BITS) wdata;
        assign snoop_we = {MSHR_SIZE{snoop_cd_valid & ~snoop_buffer.slave_replace &
                            (snoop_buffer.data_index == i)}} & snoop_idx_dec;
        assign we = data_we | snoop_we |
                    {MSHR_SIZE{master_io.r_valid & (l3_buffer.data_index == (i / PARTITION))}} & l3_buffer_idx_dec;
        for(genvar j=0; j<DATA_BANK; j++)begin
            assign bank_data[j] = mshr_data_io.rdata[j][i];
        end
        for(genvar j=0; j<MSHR_SIZE; j++)begin
            logic `N(CACHE_BITS) bank_select_data;
            logic `ARRAY(PARTITION, SLAVE_BITS) bank_select_data_part, mst_data_part;
            assign refill_valids[j][i] = data_valid[j];
            assign refill_valids_rev[i][j] = data_valid[j];
            assign wdata[j] = data_we[j] ? bank_select_data_part[i % PARTITION] : 
                            snoop_we[j] ? snoop_cd_data.data : mst_data_part[i % PARTITION];
            FairSelect #(DATA_BANK, CACHE_BITS) select_data (data_bank_valids_rev[j], bank_data, data_we[j], bank_select_data);
            assign bank_select_data_part = bank_select_data;
            assign mst_data_part = master_io.r_data;
            assign refill_buffer_data[j][i] = data[j];
        end
        OldestSelect #(MSHR_SIZE, 1, SLAVE_BITS) select_data (data_valid, data, , refill_data[i]);

        always_ff @(posedge clk, posedge rst)begin
            if(rst == `RST)begin
                data <= 0;
                data_valid <= 0;
            end
            else begin
                for(int j=0; j<MSHR_SIZE; j++)begin
                    if(we[j])begin
                        data[j] <= wdata[j];
                    end
                end
                data_valid <= (data_valid | we & ~entry_snoop) & 
                              ~(refill_valid_select & {MSHR_SIZE{refill_bank_select[i] & (slave_io.r_valid & slave_io.r_ready) & ~(|refill_direct)}});

            end
        end
        PSelector #(MSHR_SIZE) encoder_refill_valid (refill_valids_rev[i], refill_valid[i]);
    end
    ParallelOR #(SLAVE_BANK, MSHR_SIZE) or_refill_valids(refill_valids, refill_valids_bank);
    PRSelector #(SLAVE_BANK) selector_refill_bank (refill_valids_bank, refill_bank_select);
    PREncoder #(SLAVE_BANK) encoder_refill_bank (refill_valids_bank, refill_bank_idx);
    assign refill_valid_select = refill_valid[refill_bank_idx];
    Encoder #(MSHR_SIZE) encoder_refill_idx(refill_valid_select, refill_data_idx);
    PEncoder #(MSHR_SIZE) encoder_direct_idx(refill_direct, refill_direct_idx);
    assign refill_idx = |refill_direct ? refill_direct_idx : refill_data_idx;
endgenerate
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            refill_ids <= 0;
            refill_resps <= 0;
            refill_snoop_resp_req <= 0;
            refill_l3_resp_req <= 0;
            dir_resp_reqs <= 0;
            refill_finish <= 0;
            refill_no_rack <= 0;
            refill_direct <= 0;
        end
        else begin
            if(dir_request_n)begin
                refill_ids[dir_select_idx_n] <= dir_entry_n.id;
                dir_resp_reqs[dir_select_idx_n] <= ~mshr_dir_io.hit & ~dir_entry_n.write & ~dir_make_unique_all;
                refill_no_rack[dir_select_idx_n] <= dir_read_once | dir_entry_n.snoop;
                refill_finish[dir_select_idx_n] <= 1'b0;
                refill_direct[dir_select_idx_n] <= dir_make_unique_all;
            end

            if(dir_read & mshr_dir_io.hit)begin
                refill_resps[dir_select_idx_n] <= mshr_dir_io.hit_state;
            end

            if((snoop_state == SNOOP_IDLE) & (|(snoop_request & dir_resp_reqs)))begin
                refill_snoop_resp_req <= 1'b1;
            end
            if((|snoop_buffer.response) & refill_snoop_resp_req)begin
                refill_resps[snoop_buffer.idx] <= snoop_buffer.response_state;
                dir_resp_reqs[snoop_buffer.idx] <= 1'b0;
                refill_snoop_resp_req <= 1'b0;
            end

            if((l3_state == L3_IDLE) & (l3_request))begin
                refill_l3_resp_req <= 1'b1;
            end
            if(master_io.r_valid & refill_l3_resp_req)begin
                refill_l3_resp_req <= 1'b0;
                if(LLC)begin
                    refill_resps[l3_buffer.idx] <= 3'b100;
                end
                else begin
                    refill_resps[l3_buffer.idx] <= master_io.r_resp[4: 2];
                end
                dir_resp_reqs[l3_buffer.idx] <= 1'b0;
            end

            if(slave_io.r_valid & slave_io.r_ready & slave_io.r_last & (|refill_direct))begin
                refill_direct[refill_direct_idx] <= 1'b0;
            end

            if(ISL2 & slave_io.r_valid &  slave_io.r_ready & 
                slave_io.r_last & refill_no_rack[refill_idx])begin
                refill_finish[refill_idx] <= 1'b1;
            end

            for(int i=0; i<SLAVE; i++)begin
                if(snoop_resp[i].rack)begin
                    refill_finish[snoop_resp[i].r_snoop_id] <= 1'b1;
                end
            end

        end
    end
    OldestSelect #(SLAVE_BANK, 1, SLAVE_BITS, 1) select_refill_data (refill_valids_bank, refill_data, refill_r_valid, refill_r_data);
    assign slave_io.r_valid = (|refill_direct) | (|refill_valids_bank);
    assign slave_io.r_id = {refill_ids[refill_idx], 1'b0};
    assign slave_io.r_data = refill_r_data;
    assign slave_io.r_resp = {refill_resps[refill_idx], 2'b00};
    assign slave_io.r_last = (|refill_direct) | refill_bank_select[SLAVE_BANK-1];
    assign slave_io.r_user = 0;
generate
    for(genvar i=0; i<SLAVE; i++)begin
        assign snoop_req[i].ar_snoop_id = refill_idx;
    end
endgenerate


// dir request
    MSHREntry dir_entry, dir_entry_n;
    logic dir_read_once, dir_read_share, dir_read_unique, dir_make_unique, dir_clean_invalid;
    logic dir_clean_unique, dir_unique_req, dir_clean_unique_nodata, dir_clean_read;
    logic dir_clean_req, dir_write_clean;
    logic dir_make_unique_all, dir_read_unique_all;
    logic dir_read, dir_write;
    logic `N(MSHR_SIZE) dir_slave_wreq, dir_slave_we;
    logic `N(MSHR_SIZE) dir_wreq, dir_we;
    logic dir_slave_wvalid, dir_wvalid;
    logic `N(SLAVE) dir_lookup_owner;
    logic `N(SLAVE) dir_lookup_owner_dec;
    DirectoryState dir_slave_state, dir_state, dir_wstate;
    DirWInfo dir_slave_winfo, dir_winfo;
    logic `N(MSHR_WIDTH) dir_slave_widx, dir_widx;
generate
    for(genvar i=0; i<MSHR_SIZE; i++)begin
        assign paddrs[i] = entrys[i].paddr;
        assign entry_snoop[i] = entrys[i].snoop;
    end
    if(ISL2)begin
        always_ff @(posedge clk)begin
            dir_lookup_owner <= 0;
            dir_lookup_owner_dec <= 1;
        end
    end
    else begin
        logic `N(SLAVE) dir_id_dec;
        Decoder #(SLAVE) decode_dir_id (dir_entry.id[ID_WIDTH-1 -: SLAVE_WIDTH], dir_id_dec);
        always_ff @(posedge clk)begin
            dir_lookup_owner <= dir_entry.id[ID_WIDTH-1 -: SLAVE_WIDTH];
            dir_lookup_owner_dec <= dir_id_dec;
        end
    end
endgenerate
    OldestSelect #(MSHR_SIZE, 1, $bits(MSHREntry)) select_dir_paddr (dir_requests, entrys, dir_request, dir_entry);
    assign mshr_slave_io.request = dir_request;
    assign mshr_slave_io.raddr = dir_entry.paddr;
    assign mshr_dir_io.request = dir_request;
    assign mshr_dir_io.raddr = dir_entry.paddr;
    PSelector #(MSHR_SIZE) select_dir_request (dir_requests, dir_request_select);
    PEncoder #(MSHR_SIZE) encoder_dir_request (dir_requests, dir_select_idx);
    `SIG_N(dir_request, dir_request_n)
    `SIG_N(dir_entry, dir_entry_n)
    `SIG_N(dir_select_idx, dir_select_idx_n)
    `SIG_N(dir_request_select, dir_request_select_n)
    always_ff @(posedge clk)begin
        if(dir_request_n)begin
            dir_infos[dir_select_idx_n] <= {mshr_slave_io.slave & ~dir_lookup_owner_dec, mshr_slave_io.owner};
            lookup_hit_ways[dir_select_idx_n] <= mshr_dir_io.hit_way;
            lookup_replace_ways[dir_select_idx_n] <= mshr_dir_io.replace_way;
            lookup_data_ways[dir_select_idx_n] <= mshr_dir_io.hit ? mshr_dir_io.hit_way : mshr_dir_io.replace_way; // if l2 hit and l1 need replace, then replace l1 data to hit way
        end
        dir_read <= dir_request & ~dir_entry.write;
        dir_write <= dir_request & dir_entry.write;
        dir_read_once <= ~dir_entry.write & (dir_entry.op == `ACEOP_READ_ONCE);
        dir_read_share <= ~dir_entry.write & (dir_entry.op == `ACEOP_READ_SHARED);
        dir_read_unique <= ~dir_entry.write & (dir_entry.op == `ACEOP_READ_UNIQUE);
        dir_make_unique <= ~dir_entry.write & (dir_entry.op == `ACEOP_MAKE_UNIQUE);
        dir_clean_unique <= ~dir_entry.write & (dir_entry.op == `ACEOP_CLEAN_UNIQUE);
        dir_unique_req <= ~dir_entry.write & ((dir_entry.op == `ACEOP_READ_UNIQUE) | 
                            (dir_entry.op == `ACEOP_CLEAN_UNIQUE) | 
                            (dir_entry.op == `ACEOP_MAKE_UNIQUE));
        dir_clean_invalid <= ~dir_entry.write & (dir_entry.op == `ACEOP_CLEAN_INVALID);
        dir_write_clean <= dir_entry.write & (dir_entry.op == `ACEOP_WRITE_CLEAN);
        dir_clean_req <= ~dir_entry.write & ((dir_entry.op == `ACEOP_CLEAN_INVALID) | 
                        (dir_entry.op == `ACEOP_MAKE_UNIQUE));
    end
    assign dir_clean_unique_nodata = dir_clean_unique & (mshr_slave_io.hit & mshr_slave_io.owned & 
                                    (mshr_slave_io.owner == dir_lookup_owner));
    assign dir_clean_read = dir_clean_unique & ~dir_clean_unique_nodata;
    assign dir_read_unique_all = dir_read_unique | dir_clean_read;
    assign dir_make_unique_all = dir_make_unique | dir_clean_unique_nodata;

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            require_data <= 0;
            dir_slave_wreq <= 0;
            dir_winfos <= 0;
            dir_wreq <= 0;
            dir_finish <= 0;
            dir_op <= 0;
        end
        else begin
            for(int i=0; i<MSHR_SIZE; i++)begin
                dir_finish[i] <= (dir_finish[i] | dir_request_select_n[i]) &
                                ~mshr_finish_select[i] & ~snoop_write_conflict_n[i];
            end
            if(dir_request_n)begin
                require_data[dir_select_idx_n] <= ~dir_entry_n.write & ~dir_clean_req & ~dir_clean_unique_nodata;
                dir_slave_wreq[dir_select_idx_n] <= ~dir_read_once & ~((dir_clean_invalid | dir_read_unique_all & dir_entry_n.snoop) & ~mshr_slave_io.hit) & ~(dir_entry_n.write & mshr_dir_io.hit);
                // TODO: 如果slave需要替换并且l2 命中，那么dir_wreq不需要（snoop会写入dir中）
                dir_wreq[dir_select_idx_n] <= dir_entry_n.write & ~mshr_dir_io.hit | 
                    dir_read_once & ~mshr_dir_io.hit & ~mshr_slave_io.hit | // icache
                    (dir_clean_req | dir_clean_unique | dir_read_unique_all |
                    dir_read_share & ~dir_entry_n.snoop) & mshr_dir_io.hit; // read | clean
                dir_winfos[dir_select_idx_n] <= '{
                    waddr: dir_entry_n.paddr,
                    slave_replace_way: mshr_slave_io.hit ? mshr_slave_io.hit_way : mshr_slave_io.replace_way,
                    replace_way: mshr_dir_io.hit ? mshr_dir_io.hit_way : mshr_dir_io.replace_way,
                    slave: dir_entry_n.write | dir_read_unique_all & dir_entry_n.snoop | dir_clean_invalid ? 0 : // only owner will write
                           dir_read_share & mshr_slave_io.hit ? mshr_slave_io.slave | dir_lookup_owner_dec : 
                           dir_unique_req | dir_read_share ? dir_lookup_owner_dec : mshr_slave_io.slave,
                    dir_clean: dir_clean_req | dir_clean_unique | dir_read_unique_all | 
                               dir_read_share & ~dir_entry_n.snoop,
                    slave_share: mshr_slave_io.share,
                    write: dir_entry_n.write,
                    write_dirty: dir_write_clean,       
                    require_owned: dir_unique_req,
                    slave_hit: mshr_slave_io.hit,
                    dir_hit: mshr_dir_io.hit,
                    owned: (dir_unique_req | mshr_slave_io.owned),
                    owner: mshr_slave_io.hit ? mshr_slave_io.owner : dir_lookup_owner
                };
                dir_op[dir_select_idx_n] <= dir_clean_unique_nodata ? `ACEOP_MAKE_UNIQUE : 
                                        dir_clean_read ? `ACEOP_READ_UNIQUE : dir_entry_n.op;
            end

            if(mshr_slave_io.we & mshr_slave_io.wready)begin
                dir_slave_wreq[dir_slave_widx] <= 1'b0;
            end
            if(dir_wvalid & mshr_dir_io.wready)begin
                dir_wreq[dir_widx] <= 1'b0;
            end
        end
    end

    PEncoder #(MSHR_SIZE) encoder_slave_widx (dir_slave_we, dir_slave_widx);
    assign dir_slave_we = dir_slave_wreq & ~dir_resp_reqs;
    OldestSelect #(MSHR_SIZE, 1, $bits(DirectoryState)) select_slave_dir_resp (dir_slave_we, refill_resps, dir_slave_wvalid, dir_slave_state);
    OldestSelect #(MSHR_SIZE, 1, $bits(DirWInfo)) select_slave_winfo (dir_slave_we, dir_winfos, , dir_slave_winfo);
    assign mshr_slave_io.we = dir_slave_wvalid;
    assign mshr_slave_io.waddr = dir_slave_winfo.waddr[OFFSET_WIDTH +: $clog2(SLAVE_DIR_SET)];
    assign mshr_slave_io.wway = dir_slave_winfo.slave_replace_way;
    assign mshr_slave_io.wdata[SLAVE_TAG_WIDTH-1: 0] = dir_slave_winfo.waddr[OFFSET_WIDTH + $clog2(SLAVE_DIR_SET) +: SLAVE_TAG_WIDTH]; // tag
    assign mshr_slave_io.wdata[SLAVE_TAG_WIDTH] = ~dir_slave_winfo.require_owned & (dir_slave_winfo.slave_hit | dir_slave_state.share); // share
    // if write, slave must hit. if read and slave not hit, valid num is 1
    assign mshr_slave_io.wdata[SLAVE_TAG_WIDTH + 1 +: SLAVE] = dir_slave_winfo.slave; // valid
    assign mshr_slave_io.wdata[SLAVE_TAG_WIDTH + 1 + SLAVE +: SLAVE_WIDTH] = dir_slave_winfo.owner; // owner
generate
    if(!LLC)begin
        assign mshr_slave_io.wdata[SLAVE_TAG_WIDTH + 1 + SLAVE + SLAVE_WIDTH - 1] = 
        ~dir_slave_winfo.slave_hit ? dir_slave_state.owned : dir_slave_winfo.owned; // owned
    end
endgenerate

    assign dir_we = dir_wreq & ~dir_resp_reqs;
    PEncoder #(MSHR_SIZE) encoder_dir_widx (dir_we, dir_widx);
    OldestSelect #(MSHR_SIZE, 1, $bits(DirectoryState)) select_dir_resp (dir_we, refill_resps, dir_wvalid, dir_state);
    OldestSelect #(MSHR_SIZE, 1, $bits(DirWInfo)) select_dir_winfo (dir_we, dir_winfos, , dir_winfo);
    assign mshr_dir_io.we = dir_wvalid | ((snoop_state == SNOOP_REPLACE) & ~snoop_buffer.replace_dir);
    assign mshr_dir_io.waddr = dir_wvalid ? dir_winfo.waddr[OFFSET_WIDTH +: SET_WIDTH] : snoop_buffer.snoop_addr[OFFSET_WIDTH +: SET_WIDTH];
    assign mshr_dir_io.wway = dir_wvalid ? dir_winfo.replace_way : snoop_buffer.replace_way;
    assign mshr_dir_io.wdata[0] = ~dir_winfo.dir_clean & dir_wvalid | ~dir_wvalid; // valid
    assign mshr_dir_io.wdata[TAG_WIDTH: 1] = dir_wvalid ? dir_winfo.waddr[OFFSET_WIDTH + SET_WIDTH +: TAG_WIDTH] : snoop_buffer.snoop_addr[OFFSET_WIDTH + SET_WIDTH +: TAG_WIDTH]; // tag
generate
    // dir_wvalid & ~dir_winfo.write only valid on READ_ONCE
    if(ISL2)begin
        assign dir_wstate.dirty = dir_wvalid ? (dir_winfo.write ? dir_winfo.write_dirty : dir_state.dirty) : snoop_buffer.response_state.dirty;
        assign dir_wstate.share = dir_wvalid ? (dir_winfo.write ? dir_winfo.slave_share : dir_state.share) : snoop_buffer.response_state.share;
        assign dir_wstate.owner = dir_wvalid ? (dir_winfo.write ? dir_winfo.owned : dir_state.owner) : snoop_buffer.response_state.owner;
    end
    else begin
        assign dir_wstate.dirty = dir_wvalid ? dir_winfo.write_dirty : snoop_buffer.response_state.dirty;
        assign dir_wstate.share = dir_wvalid ? dir_winfo.slave_share : snoop_buffer.response_state.share;
        assign dir_wstate.owner = dir_wvalid ? dir_winfo.owned : snoop_buffer.response_state.owner;
    end
endgenerate
    assign mshr_dir_io.wdata[TAG_WIDTH + 1 +: $bits(DirectoryState)] = dir_wstate; // state


// snoop
    OldestSelect #(MSHR_SIZE, 1, $bits(MSHREntry)) select_snoop_entry (snoop_request, entrys, snoop_valid, snoop_entry);
    OldestSelect #(MSHR_SIZE, 1, 4) select_snoop_op(snoop_request, dir_op, , snoop_op);
    OldestSelect #(MSHR_SIZE, 1, $bits(DirInfo)) select_snoop_dir (snoop_request, dir_infos, , snoop_dir_info);
    PEncoder #(MSHR_SIZE) encoder_snoop_idx (snoop_request, snoop_idx);
generate
    if(SLAVE == 1)begin
        assign owner_decode = 1'b1;
    end
    else begin
        Decoder #(SLAVE) decode_owner (snoop_dir_info.slave_owner, owner_decode);
    end

    for(genvar i=0; i<SLAVE; i++)begin
        assign snoop_req[i].ac_valid = snoop_buffer.slave_request[i];
        assign snoop_req[i].ac.snoop = snoop_buffer.op;
        assign snoop_req[i].ac.addr = snoop_buffer.snoop_addr;
        assign snoop_req[i].ac.prot = 0;
        assign snoop_req[i].cr_ready = 1'b1;
        assign snoop_req[i].cd_ready = 1'b1;
        assign snoop_cd_valids[i] = snoop_resp[i].cd_valid;
        assign snoop_cd_datas[i] = snoop_resp[i].cd;
    end
endgenerate
    OldestSelect #(SLAVE, 1, $bits(snoop_cd_chan_t)) select_cd (
        snoop_cd_valids, snoop_cd_datas, snoop_cd_valid, snoop_cd_data
    );
    
    always_ff @(posedge clk)begin
        if(dir_request_n)begin
            snoop_replace_tag[dir_select_idx_n] <= mshr_slave_io.replace_tag;
        end
    end
    assign snoop_replace_cond = ~dir_entry_n.write & (dir_make_unique_all | dir_read_share | dir_read_unique_all) &
                    ~mshr_slave_io.hit & mshr_slave_io.replace_hit & mshr_slave_io.replace_owned & ~dir_entry_n.snoop;
    assign snoop_write_cond = (snoop_state == SNOOP_REQUEST) & snoop_buffer.state_change & ~snoop_write_conflict_end &
         ((snoop_buffer.response & snoop_buffer.target_slave) == snoop_buffer.target_slave);
generate
    for(genvar i=0; i<MSHR_SIZE; i++)begin
        assign snoop_write_conflict[i] = snoop_write_cond & en[i] & entrys[i].write &
                                        (entrys[i].paddr == snoop_buffer.snoop_addr);
    end
endgenerate
    `SIG_N(snoop_write_conflict, snoop_write_conflict_n)
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            snoop_request <= 0;
            snoop_replace_request <= 0;
            snoop_state <= SNOOP_IDLE;
            snoop_buffer <= 0;
            snoop_write_conflict_end <= 0;
        end
        else begin
            if(dir_read & ((dir_read_share | dir_read_unique_all | dir_read_once | dir_clean_invalid | 
            (dir_make_unique_all & ~(|(dir_lookup_owner_dec ^ mshr_slave_io.slave)))) & mshr_slave_io.hit | // make unique and other slave hit
              (dir_make_unique_all | dir_read_share | dir_read_unique_all) &
              ~mshr_slave_io.hit & mshr_slave_io.replace_hit & mshr_slave_io.replace_owned))begin
                snoop_request[dir_select_idx_n] <= 1'b1;
            end
            if(dir_request_n)begin
                snoop_replace_request[dir_select_idx_n] <= snoop_replace_cond;
            end

            for(int i=0; i<DATA_BANK; i++)begin
                if(mshr_data_io.wvalid[i])begin
                    snoop_replace_request[mshr_data_io.wmshr_idx_o[i]] <= 1'b0;
                end
            end
            case(snoop_state)
            SNOOP_IDLE:begin
                if(|snoop_request)begin
                    snoop_state <= SNOOP_REQUEST;
                    snoop_buffer.idx <= snoop_idx;
                    snoop_buffer.target_slave <= snoop_op == `ACEOP_CLEAN_INVALID || (snoop_op == `ACEOP_MAKE_UNIQUE && ~snoop_replace_request[snoop_idx]) ? 
                                                snoop_dir_info.slave : owner_decode;
                    snoop_buffer.slave_request <= snoop_op == `ACEOP_CLEAN_INVALID || (snoop_op == `ACEOP_MAKE_UNIQUE && ~snoop_replace_request[snoop_idx]) ? 
                                                snoop_dir_info.slave : owner_decode;
                    snoop_buffer.snoop_addr <= snoop_replace_request[snoop_idx] ? {snoop_replace_tag[snoop_idx], 
                                        snoop_entry.paddr[OFFSET_WIDTH +: $clog2(SLAVE_DIR_SET)], 
                                        {OFFSET_WIDTH{1'b0}}} : snoop_entry.paddr;
                    snoop_buffer.op <= snoop_replace_request[snoop_idx] ? `ACEOP_READ_UNIQUE : 
                                       snoop_op == `ACEOP_MAKE_UNIQUE ? `ACEOP_CLEAN_INVALID : snoop_op;
                    snoop_buffer.state_change <= snoop_replace_request[snoop_idx] || (snoop_op != `ACEOP_READ_ONCE && snoop_op != `ACEOP_READ_SHARED);
                    snoop_buffer.response <= 0;
                    snoop_buffer.require_data <= snoop_op != `ACEOP_CLEAN_INVALID && !(snoop_op == `ACEOP_MAKE_UNIQUE && ~snoop_replace_request[snoop_idx]);
                    snoop_buffer.slave_replace <= snoop_replace_request[snoop_idx];
                    snoop_buffer.data_valid <= 0;
                    snoop_buffer.data_index <= 0;
                    snoop_buffer.replace_way <= lookup_data_ways[snoop_idx];
                    snoop_write_conflict_end <= 1'b0;
                end
            end
            SNOOP_REQUEST:begin
                for(int i=0; i<SLAVE; i++)begin
                    if(snoop_req[i].ac_valid & snoop_resp[i].ac_ready)begin
                        snoop_buffer.slave_request[i] <= 1'b0;
                    end
                    if(snoop_req[i].cr_ready & snoop_resp[i].cr_valid)begin
                        snoop_buffer.response[i] <= 1'b1;
                        if (snoop_buffer.require_data)begin
                            snoop_buffer.response_state <= snoop_resp[i].cr_resp[4: 2];
                        end
                    end
                end
                if(snoop_cd_valid)begin
                    snoop_buffer.data_index <= snoop_buffer.data_index + 1;
                end
                if(snoop_cd_valid & snoop_cd_data.last)begin
                    snoop_buffer.data_valid <= 1'b1;
                end
                if((snoop_buffer.require_data & snoop_buffer.data_valid & ~snoop_buffer.slave_replace | ~snoop_buffer.require_data) & 
                ((snoop_buffer.response & snoop_buffer.target_slave) == snoop_buffer.target_slave))begin
                    snoop_state <= SNOOP_IDLE;
                    snoop_request[snoop_buffer.idx] <= 1'b0;
                end
                if(snoop_buffer.require_data & snoop_buffer.data_valid & snoop_buffer.slave_replace)begin
                    snoop_state <= SNOOP_REPLACE;
                    snoop_buffer.replace_dir <= 1'b0;
                end
                if(snoop_write_cond)begin
                    snoop_write_conflict_end <= 1'b1;
                end
            end
            SNOOP_REPLACE: begin
                if(snoop_buffer.replace_dir)begin
                    snoop_state <= SNOOP_IDLE;
                    snoop_request[snoop_buffer.idx] <= 1'b0;
                end
                if(~dir_wvalid & mshr_dir_io.wready)begin
                    snoop_buffer.replace_dir <= 1'b1;
                end
            end
            endcase
        end
    end

// mst snoop
    logic mst_snoop_busy, mst_snoop_need_data;
    logic mst_cr_valid, mst_cd_valid;
    logic mst_snoop_data_valid;
    logic `N(MSHR_SIZE) mst_snoop_reqs;
    logic `N(MSHR_WIDTH) mst_snoop_idx;
    logic `N(4) mst_snoop_op;
    logic `N(CACHE_BANK_WIDTH) mst_snoop_data_idx;
    logic `ARRAY(CACHE_BANK, CACHE_BITS) mst_snoop_data;

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            mst_snoop_op <= 0;
            mst_snoop_idx <= 0;
            mst_snoop_reqs <= 0;
            mst_snoop_need_data <= 0;
            mst_cr_valid <= 0;
            mst_cd_valid <= 0;
            mst_snoop_data_idx <= 0;
            mst_snoop_data <= 0;
            mst_snoop_data_valid <= 0;
        end
        else begin
            if(mst_snoop_req.ac_valid & mst_snoop_resp.ac_ready)begin
                mst_snoop_op <= mst_snoop_req.ac.snoop;
                mst_snoop_idx <= free_idx1;
                mst_snoop_reqs[free_idx1] <= 1'b1;
                mst_snoop_need_data <= mst_snoop_req.ac.snoop != `ACEOP_CLEAN_INVALID;
                mst_cr_valid <= 1'b1;
                mst_snoop_data_valid <= 1'b0;
            end
            if(mst_snoop_resp.cr_valid & mst_snoop_req.cr_ready)begin
                mst_cr_valid <= 1'b0;
                mst_cd_valid <= mst_snoop_need_data;
                mst_snoop_data_idx <= mst_snoop_data_idx + 1;
            end

            if(mst_snoop_resp.cd_valid & mst_snoop_req.cd_ready & mst_snoop_resp.cd.last)begin
                mst_cd_valid <= 1'b0;
            end

            for(int i=0; i<DATA_BANK; i++)begin
                if(mshr_data_io.wvalid[i] & mshr_data_io.wmshr_idx_o[i] == mst_snoop_idx)begin
                    mst_snoop_data <= mshr_data_io.wdata[i];
                end
            end

        end
    end

    assign mst_snoop_resp.cr_valid = mst_cr_valid & (mst_snoop_need_data & ~dir_resp_reqs[mst_snoop_idx] | ~mst_snoop_need_data & ~dir_slave_wreq[mst_snoop_idx] & ~dir_wreq[mst_snoop_idx]);
    assign mst_snoop_resp.cr_resp = {refill_resps[mst_snoop_idx], 1'b0, mst_snoop_need_data};
    assign mst_snoop_resp.cd_valid = mst_cd_valid & mst_snoop_data_valid;
    assign mst_snoop_resp.cd.data = mst_snoop_data[mst_snoop_data_idx];
    assign mst_snoop_resp.cd.last = mst_snoop_data_idx == CACHE_BANK - 1;

// to l3
    logic l3_req_last, l3_req_write, l3_req_write_end, l3_data_valid;
    logic l3_read_once;
    logic `ARRAY(CACHE_BANK, CACHE_BITS) l3_data;
    logic `N(DATA_BANK) l3_data_bank, l3_write_data_bank;
    logic `N(MST_SNOOP_ID_WIDTH) mst_r_id;
    logic mst_r_ack;
    logic `N(4) l3_op;
    OldestSelect #(MSHR_SIZE, 1, $bits(MSHREntry)) select_l3_entry (l3_requests, entrys, l3_request, l3_entry);
    OldestSelect #(MSHR_SIZE, 1, 4) select_l3_op (l3_requests, dir_op, , l3_op);
    PSelector #(MSHR_SIZE) selector_l3_idx (l3_requests, l3_idx_dec);
    PEncoder #(MSHR_SIZE) encoder_l3_idx (l3_requests, l3_idx);

generate
    if(ISL2)begin
        always_ff @(posedge clk, posedge rst)begin
            if(master_io.r_valid & master_io.r_ready)begin
                l3_data[l3_buffer.data_index] <= master_io.r_data;
            end
        end
        always_ff @(posedge clk, posedge rst)begin
            if(rst == `RST)begin
                l3_req_write <= 0;
                l3_req_write_end <= 0;
                l3_data_valid <= 0;
                mst_r_id <= 0;
                mst_r_ack <= 0;
            end
            else begin
                if((l3_state == L3_REQUEST) & l3_data_valid & l3_read_once &
                   (~replace_reqs[l3_buffer.idx] | replace_busy & 
                   replace_buffer.replace_data_valid & (replace_buffer.idx == l3_buffer.idx)))begin
                    l3_req_write <= 1'b1;
                end
                if(~(|(l3_data_bank & write_bank_req)) & l3_req_write)begin 
                    l3_req_write <= 1'b0;
                    l3_data_valid <= 1'b0;
                end
                if(l3_state == L3_IDLE && l3_request)begin
                    l3_req_write_end <= 1'b0;
                end
                else if(|l3_write_data_bank | (l3_state == L3_REQUEST) & ~l3_read_once)begin
                    l3_req_write_end <= 1'b1;
                end
                if(l3_state == L3_IDLE && l3_request)begin
                    l3_data_valid <= 1'b0;
                end
                else if(master_io.r_valid & master_io.r_last)begin
                    l3_data_valid <= 1'b1;
                end
                if(master_io.r_valid & master_io.r_last)begin
                    mst_r_id <= mst_snoop_req.ar_snoop_id;
                    mst_r_ack <= 1'b1;
                end
                if(mst_r_ack)begin
                    mst_r_ack <= 1'b0;
                end
            end
        end

        for(genvar i=0; i<DATA_BANK; i++)begin
            assign l3_write_data_bank[i] = mshr_data_io.wvalid[i] & (mshr_data_io.wmshr_idx_o[i] == l3_buffer.idx);
        end
    end
endgenerate
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            l3_requests <= 0;
            l3_state <= L3_IDLE;
            l3_req_last <= 1'b0;
            l3_buffer <= 0;
            l3_read_once <= 1'b0;
        end
        else begin
            if(dir_read & (~mshr_dir_io.hit & ~mshr_slave_io.hit & 
            ~(dir_make_unique_all & LLC)) &  & ~dir_clean_invalid)begin
                l3_requests[dir_select_idx_n] <= 1'b1;
            end
            case(l3_state)
            L3_IDLE: begin
                if(l3_request)begin
                    l3_state <= L3_REQUEST;
                    l3_buffer.idx <= l3_idx;
                    l3_buffer.addr <= l3_entry.paddr;
                    l3_buffer.request <= 1'b1;
                    l3_buffer.id <= l3_entry.id;
                    l3_buffer.op <= l3_op == `ACEOP_READ_ONCE ? `ACEOP_READ_SHARED : l3_op;
                    l3_buffer.data_index <= 0;
                    l3_read_once <= l3_op == `ACEOP_READ_ONCE;
                    l3_req_last <= 1'b0;
                end
            end
            L3_REQUEST: begin
                if(master_io.ar_valid & master_io.ar_ready)begin
                    l3_buffer.request <= 1'b0;
                end
                if(master_io.r_valid)begin
                    l3_buffer.data_index <= l3_buffer.data_index + 1;
                end
                if(master_io.r_valid & master_io.r_last & ISL2)begin
                    l3_req_last <= 1'b1;
                end
                // if is l2 and req from icache, then we need to place data to data bank
                if((master_io.r_valid & master_io.r_last | l3_req_last & ISL2) &
                   (~ISL2 | ISL2 & ~replace_reqs[l3_buffer.idx] & l3_req_write_end))begin
                    l3_state <= L3_IDLE;
                    l3_requests[l3_buffer.idx] <= 1'b0;
                end
            end
            endcase
        end
    end

    assign master_io.ar_valid = l3_buffer.request;
    assign master_io.ar_id = l3_buffer.id;
    assign master_io.ar_addr = l3_buffer.addr;
    assign master_io.ar_len = CACHE_BANK - 1;
    assign master_io.ar_size = $clog2(`CACHELINE_SIZE / CACHE_BANK);
    assign master_io.ar_burst = 2'b01;
    assign master_io.ar_user = 0;
    assign master_io.ar_snoop = l3_buffer.op;
    assign master_io.r_ready = 1'b1;
    assign mst_snoop_resp.r_snoop_id = mst_r_id;
    assign mst_snoop_resp.rack = mst_r_ack;

// write
    logic `N(MSHR_SIZE) write_reqs_combine;
    logic write_conflict_wait;
    always_ff @(posedge clk)begin
        if(slave_io.w_valid & slave_io.w_ready & ~write_conflict_wait)begin
            write_buffer[write_idx][write_data_index] <= slave_io.w_data;
        end
        if(snoop_cd_valid & snoop_buffer.slave_replace)begin
            write_buffer[snoop_buffer.idx][snoop_buffer.data_index] <= snoop_cd_data.data;
        end
    end

    PEncoder #(MSHR_SIZE) encoder_write_b_idx(write_data_finish, write_data_finish_idx);
    Decoder #(MSHR_SIZE) decoder_write_idx (write_idx, write_idx_dec);
    OldestSelect #(MSHR_SIZE, 1, ID_WIDTH) select_b_id (write_data_finish, write_b_ids, write_b_req, write_b_id);
    ParallelOR #(MSHR_SIZE, DATA_BANK) or_write_bank (write_bank_idx_dec, write_reqs_combine);

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            write_idx <= 0;
            write_data_index <= 0;
            write_waiting <= 0;
            slave_b_valid <= 1'b0;
            write_id <= 0;
            slave_b_id <= 0;
            write_data_valid <= 0;
            write_b_idx <= 0;
            write_data_finish <= 0;
            write_b_ids <= 0;
            entry_write <= 0;
            write_finish <= 0;
        end
        else begin
            if(slave_io.aw_valid & slave_io.aw_ready)begin
                write_idx <= free_idx1;
                write_waiting <= 1'b1;
                write_conflict_wait <= wsnoop_conflict;
                write_id <= slave_io.aw_id[ID_OFFSET +: ID_WIDTH];
                write_data_index <= 0;
                write_finish[free_idx1] <= 1'b0;
            end
            if(dir_request_n)begin
                entry_write[dir_select_idx_n] <= dir_entry_n.write;
            end
            
            if(slave_io.w_valid & slave_io.w_ready)begin
                write_data_index <= write_data_index + 1;
            end
            if(slave_io.w_valid & slave_io.w_ready & slave_io.w_last)begin
                write_waiting <= 1'b0;
                write_b_ids[write_idx] <= write_id;
                write_conflict_wait <= 1'b0;
            end
            else if(write_waiting & (|(snoop_write_conflict_n & write_idx_dec)))begin
                write_conflict_wait <= 1'b1;
            end

            if(write_b_req & ~slave_b_valid)begin
                slave_b_valid <= 1'b1;
                slave_b_id <= write_b_id;
                write_b_idx <= write_data_finish_idx;
            end

            if(slave_io.b_valid & slave_io.b_ready)begin
                slave_b_valid <= 1'b0;
                write_data_finish[write_b_idx] <= 1'b0;
                write_finish[write_b_idx] <= 1'b1;
            end

            for(int i=0; i<DATA_BANK; i++)begin
                if(mshr_data_io.wvalid[i] & (entrys[mshr_data_io.wmshr_idx_o[i]].write))begin
                    write_data_finish[mshr_data_io.wmshr_idx_o[i]] <= 1'b1;
                end
            end

            for(int i=0; i<MSHR_SIZE; i++)begin
                write_data_valid[i] <= (write_data_valid[i] | write_idx_dec[i] & slave_io.w_valid & slave_io.w_ready & slave_io.w_last & ~write_conflict_wait |
                    snoop_cd_valid & snoop_cd_data.last & snoop_buffer.slave_replace & snoop_idx_dec[i]) &
                        ~write_reqs_combine[i] & ~snoop_write_conflict_n[i];
            end
        end
    end
    assign slave_io.w_ready = write_waiting;
    assign slave_io.b_valid = slave_b_valid;
    assign slave_io.b_id = {slave_b_id, 1'b0};
    assign slave_io.b_resp = 0;
    assign slave_io.b_user = 0;


// lookup
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            lookup_addrs <= 0;
            lookup_write_addrs <= 0;
        end
        else begin
            if(dir_request_n)begin
                // dir hit
                lookup_addrs[dir_select_idx_n] <= dir_entry_n.paddr[OFFSET_WIDTH +: SET_WIDTH];
                // slave write
                lookup_write_addrs[dir_select_idx_n] <= dir_entry_n.paddr[OFFSET_WIDTH +: SET_WIDTH];
            end
            if(snoop_cd_valid & snoop_cd_data.last & snoop_buffer.slave_replace)begin
                // snoop replace
                lookup_write_addrs[snoop_buffer.idx] <= snoop_buffer.snoop_addr[OFFSET_WIDTH +: SET_WIDTH];
            end
        end
    end
    
generate
    if(DATA_BANK == 1)begin
        assign lookup_bank = {MSHR_SIZE{1'b1}};
        assign lookup_bank_rev = lookup_bank;
        assign l3_data_bank = 1;
    end
    else begin
        for(genvar i=0; i<MSHR_SIZE; i++)begin
            Decoder #(DATA_BANK) decoder_bank (lookup_addrs[i][0 +: DATA_BANK_WIDTH], lookup_bank[i]);
            for(genvar j=0; j<DATA_BANK; j++)begin
                assign lookup_bank_rev[j][i] = lookup_bank[i][j];
            end
        end
        Decoder #(DATA_BANK) decoder_l3_bank (l3_buffer.addr[OFFSET_WIDTH +: DATA_BANK_WIDTH], l3_data_bank);
    end

    for(genvar i=0; i<DATA_BANK; i++)begin : lookup
        logic `N(MSHR_SIZE) lookup_bank_request;
        logic `N(SET_WIDTH) lookup_data_addr;
        logic `N(WAY_WIDTH) lookup_way;
        logic `N(MSHR_WIDTH) lookup_idx;

        assign lookup_bank_request = lookup_requests & lookup_bank_rev[i];
        OldestSelect #(MSHR_SIZE, 1, SET_WIDTH) select_lookup (lookup_bank_request, lookup_addrs, lookup_data_req[i], lookup_data_addr);
        OldestSelect #(MSHR_SIZE, 1, WAY_WIDTH) select_rway (lookup_bank_request, lookup_hit_ways, , lookup_way);
        PEncoder #(MSHR_SIZE) encoder_lookup_idx (lookup_bank_request, lookup_idx);

        assign mshr_data_io.req = lookup_data_req[i] | replace_read_req & replace_buffer.data_bank[i];
        assign mshr_data_io.rway = lookup_data_req[i] ? lookup_way : replace_buffer.way;
        if(DATA_BANK == 1)begin
            assign mshr_data_io.raddr = lookup_data_req[i] ? lookup_data_addr : replace_buffer.addr[`CACHELINE_WIDTH +: SET_WIDTH];
        end
        else begin
            assign mshr_data_io.raddr = lookup_data_req[i] ? lookup_data_addr[SET_WIDTH-1: DATA_BANK_WIDTH] : replace_buffer.addr[`CACHELINE_WIDTH +: SET_WIDTH - DATA_BANK_WIDTH];
        end
        assign mshr_data_io.mshr_idx = lookup_data_req[i] ? lookup_idx : replace_buffer.idx;

        logic `N(MSHR_SIZE) write_bank_requests;
        logic `N(SET_WIDTH) write_addr;
        logic `N(WAY_WIDTH) write_way;
        logic `ARRAY(SLAVE_BANK, SLAVE_BITS) write_data;
        assign write_bank_requests = write_data_valid & (~replace_reqs | replace_data_valids) & dir_finish & lookup_bank_rev[i];
        PEncoder #(MSHR_SIZE) encoder_write_bank_idx (write_bank_requests, write_bank_idx[i]);
        PSelector #(MSHR_SIZE) selector_write_bank_idx (write_bank_requests, write_bank_idx_dec[i]);
        OldestSelect #(MSHR_SIZE, 1, SET_WIDTH) select_write_addr (write_bank_requests, lookup_write_addrs, write_bank_req[i], write_addr);
        OldestSelect #(MSHR_SIZE, 1, WAY_WIDTH) select_write_way (write_bank_requests, lookup_data_ways, , write_way);
        assign write_data = write_buffer[write_bank_idx[i]];

        if(!ISL2)begin
            assign mshr_data_io.we[i] = write_bank_req[i];
            assign mshr_data_io.wway[i] = write_way;
            assign mshr_data_io.wmshr_idx[i] = write_bank_idx[i];
            if(DATA_BANK == 1)begin
                assign mshr_data_io.waddr[i] = write_addr;
            end
            else begin
                assign mshr_data_io.waddr[i] = write_addr[SET_WIDTH-1: DATA_BANK_WIDTH];
            end
            assign mshr_data_io.wdata[i] = write_data;
        end
        else begin
            assign mshr_data_io.we[i] = write_bank_req[i] | l3_req_write & l3_data_bank[i];
            assign mshr_data_io.wway[i] = write_bank_req[i] ? write_way : lookup_replace_ways[l3_buffer.idx];
            assign mshr_data_io.wmshr_idx[i] = write_bank_req[i] ? write_bank_idx[i] : l3_buffer.idx;
            if(DATA_BANK == 1)begin
                assign mshr_data_io.waddr[i] = write_bank_req[i] ? write_addr : l3_buffer.addr[OFFSET_WIDTH +: SET_WIDTH];
            end
            else begin
                assign mshr_data_io.waddr[i] = write_bank_req[i] ? write_addr[SET_WIDTH-1: DATA_BANK_WIDTH] : l3_buffer.addr[OFFSET_WIDTH +: SET_WIDTH - DATA_BANK_WIDTH];
            end
            assign mshr_data_io.wdata[i] = write_bank_req[i] ? write_data : l3_data;
        end
    end
endgenerate

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            lookup_requests <= 0;
        end
        else begin
            if(dir_read & mshr_dir_io.hit & ~dir_clean_invalid & ~dir_make_unique_all)begin
                lookup_requests[dir_select_idx_n] <= 1'b1;
            end
            for(int i=0; i<DATA_BANK; i++)begin
                if(mshr_data_io.req[i] & mshr_data_io.ready[i])begin
                    lookup_requests[mshr_data_io.mshr_idx[i]] <= 1'b0;
                end
            end
        end
    end


// replace
    always_ff @(posedge clk)begin
        if(dir_request_n)begin
            replace_tags[dir_select_idx_n] <= {mshr_dir_io.replace_tagv[TAG_WIDTH: 1], mshr_dir_io.replace_state.dirty};
        end
    end
generate
    if(LLC)begin
        assign replace_cond_valid = mshr_dir_io.replace_tagv[0] & mshr_dir_io.replace_state.dirty; // dirty
    end
    else begin
        assign replace_cond_valid = mshr_dir_io.replace_tagv[0] & mshr_dir_io.replace_state.owner; // owner
    end
    assign write_replace_cond = dir_request_n & ~mshr_dir_io.hit & dir_entry_n.write & replace_cond_valid;
    if(ISL2)begin
        // icache is inclusive, replace is needed, and it doesn't affect slave directory
        assign read_replace_cond = dir_read & ~mshr_dir_io.hit & replace_cond_valid &
                                    (snoop_replace_cond | dir_read_once & ~mshr_slave_io.hit);
    end
    else begin
        // if slave directory need replace, slave data is replaced to l2
        // so l2 also need to replace
        assign read_replace_cond = dir_read & ~mshr_dir_io.hit & replace_cond_valid & snoop_replace_cond;
    end

    if(DATA_BANK == 1)begin
        assign replace_data_bank = 1;
    end
    else begin
        Decoder #(DATA_BANK) decoder_replace_bank (replace_entry.paddr[`DCACHE_LINE_WIDTH +: DATA_BANK_WIDTH], replace_data_bank);
    end

    for(genvar i=0; i<DATA_BANK; i++)begin
        assign replace_data_hits[i] = mshr_data_io.rvalid[i] & (mshr_data_io.mshr_idx_o == replace_buffer.idx);
    end
endgenerate
    OldestSelect #(MSHR_SIZE, 1, $bits(MSHREntry)) select_replace_entry (replace_reqs, entrys, replace_req, replace_entry);
    OldestSelect #(MSHR_SIZE, 1, TAG_WIDTH+1) select_replace_tag (replace_reqs, replace_tags, , replace_tag);
    PEncoder #(MSHR_SIZE) encoder_replace_idx (replace_reqs, replace_idx);
    OldestSelect #(MSHR_SIZE, 1, WAY_WIDTH) select_replace_way(replace_reqs, lookup_replace_ways, , replace_way_select);
    assign replace_read_conflict = |(replace_buffer.data_bank & (lookup_data_req | ~mshr_data_io.ready));
    FairSelect #(DATA_BANK, `DCACHE_BITS * `DCACHE_BANK) select_replace_data (replace_data_hits, mshr_data_io.rdata, replace_data_hit, replace_read_data);

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            replace_reqs <= 0;
            replace_data_valids <= 0;
            replace_busy <= 0;
            replace_buffer <= 0;
            replace_read_req <= 0;
        end
        else begin
            if(write_replace_cond | read_replace_cond)begin
                replace_reqs[dir_select_idx_n] <= 1'b1;
            end

            if(~replace_busy)begin
                if(replace_req)begin
                    replace_busy <= 1'b1;
                    replace_buffer.aw_valid <= 1'b1;
                    replace_buffer.addr <= {replace_tag[TAG_WIDTH: 1], replace_entry.paddr[OFFSET_WIDTH +: SET_WIDTH], {OFFSET_WIDTH{1'b0}}};
                    replace_buffer.id <= replace_entry.id;
                    replace_buffer.dirty <= replace_tag[0];
                    replace_buffer.idx <= replace_idx;
                    replace_buffer.way <= replace_way_select;
                    replace_buffer.data_bank <= replace_data_bank;
                    replace_buffer.replace_data_valid <= 1'b0;
                    replace_buffer.data_index <= 0;
                    replace_read_req <= 1'b1;
                end
            end
            else begin
                if(master_io.aw_valid & master_io.aw_ready)begin
                    replace_buffer.aw_valid <= 1'b0;
                end
                if(replace_read_req & ~replace_read_conflict)begin
                    replace_read_req <= 1'b0;
                end
                if(replace_data_hit)begin
                    replace_buffer.replace_data_valid <= 1'b1;
                    replace_buffer.replace_data <= replace_read_data;
                    replace_data_valids[replace_buffer.idx] <= 1'b1;
                end
                if(master_io.w_valid & master_io.w_ready)begin
                    replace_buffer.data_index <= replace_buffer.data_index + 1;
                    if(replace_buffer.w_last)begin
                        replace_buffer.w_last <= 1'b0;
                        replace_buffer.replace_data_valid <= 1'b0;
                    end
                    else if(replace_buffer.data_index == `DCACHE_BANK - 2)begin
                        replace_buffer.w_last <= 1'b1;
                    end
                end
                if(master_io.b_valid & master_io.b_ready)begin
                    replace_busy <= 1'b0;
                    replace_reqs[replace_buffer.idx] <= 1'b0;
                    replace_data_valids[replace_buffer.idx] <= 1'b0;
                end
            end
        end
    end

    assign master_io.aw_valid = replace_buffer.aw_valid;
    assign master_io.aw_id = replace_buffer.id;
    assign master_io.aw_addr = replace_buffer.addr;
    assign master_io.aw_burst = 2'b01;
    assign master_io.aw_size = $clog2(`DCACHE_BYTE);
    assign master_io.aw_len = `DCACHE_BANK - 1;
    assign master_io.aw_user = 0;
    assign master_io.aw_snoop = replace_buffer.dirty ? `ACEOP_WRITE_CLEAN : `ACEOP_WRITE_EVICT;

    assign master_io.w_valid = replace_busy & ~replace_buffer.aw_valid & replace_buffer.replace_data_valid;
    assign master_io.w_data = replace_buffer.replace_data[replace_buffer.data_index];
    assign master_io.w_strb = {`DCACHE_BYTE{1'b1}};
    assign master_io.w_last = replace_buffer.w_last;
    assign master_io.w_user = 0;

    assign master_io.b_ready = 1'b1;
`ifdef DIFFTEST
    logic `ARRAY(MSHR_SIZE, 2) dbg_rsource;
    logic dbg_wend;

    `SIG_N(slave_io.w_valid & slave_io.w_last & ~write_conflict_wait, dbg_wend)
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            dbg_rsource <= 0;
        end
        else begin
            if(dir_request_n & ~dir_entry_n.write)begin
                if(mshr_dir_io.hit)begin
                    dbg_rsource[dir_select_idx_n] <= 2'b01;
                end
                else if(mshr_slave_io.hit)begin
                    dbg_rsource[dir_select_idx_n] <= 2'b10;
                end
                else begin
                    dbg_rsource[dir_select_idx_n] <= 2'b00;
                end
            end
        end
    end
    `LOG_ARRAY(T_L2CACHE, dbg_rdata_str, refill_buffer_data[refill_idx], SLAVE_BANK)
    `LOG_ARRAY(T_L2CACHE, dbg_wdata_str, write_buffer[write_idx], SLAVE_BANK)
    `Log(DLog::Debug, T_L2CACHE, slave_io.r_valid & slave_io.r_last,
        $sformatf("l2cache refill. [%h %d %d] %s", entrys[refill_idx].paddr, slave_io.r_id, dbg_rsource[refill_idx], dbg_rdata_str));
    `Log(DLog::Debug, T_L2CACHE, master_io.w_valid & master_io.w_last,
        $sformatf("l2cache replace. [%h]", replace_buffer.addr));
    `Log(DLog::Debug, T_L2CACHE, dbg_wend,
    $sformatf("l2cache write. [%h] %s", entrys[write_idx].paddr, dbg_wdata_str));

    `PERF(l2_hit, dir_request_n & dir_read & mshr_dir_io.hit)
    `PERF(l2_snoop_replace, (|snoop_request) & (snoop_state == SNOOP_IDLE) & snoop_replace_request[snoop_idx])
`endif
endmodule