`include "../../../../defines/defines.svh"

interface ReplaceQueueIO;
    logic en;
    logic refill_en;
    logic refill_dirty;
    logic `N(`DCACHE_TAG+`DCACHE_SET_WIDTH) addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    logic `N(`DCACHE_REPLACE_WIDTH) idx;
    logic full;

    logic `N(`PADDR_SIZE) waddr;
    logic whit;

    logic `N(`DCACHE_REPLACE_WIDTH) replace_idx;

    logic snoop_en;
    logic snoop_ready;
    logic snoop_hit;
    logic `N(`PADDR_SIZE) snoop_addr;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) snoop_data;

    modport queue (input en, refill_en, refill_dirty, addr, data, replace_idx, waddr, snoop_data, snoop_ready, output idx, whit,  full, snoop_en, snoop_addr);
    modport miss (input full, idx, output replace_idx);
endinterface

module ReplaceQueue(
    input logic clk,
    input logic rst,
    ReplaceQueueIO.queue io,
    AxiIO.masterw w_axi_io,
    NativeSnoopIO.master snoop_io
);
    localparam TRANSFER_BANK = `DCACHE_LINE / `DATA_BYTE;
    typedef struct packed {
        logic `N(`DCACHE_TAG+`DCACHE_SET_WIDTH) addr;
        logic `ARRAY(TRANSFER_BANK, `XLEN) data;
    } ReplaceEntry;
    typedef enum { IDLE, ADDRESS, WRITE, WAIT_B, RETIRE } ReplaceState;
    ReplaceState replace_state;

    ReplaceEntry entrys `N(`DCACHE_REPLACE_SIZE);
    logic `N(`DCACHE_REPLACE_SIZE) en, dataValid, dirty, prior;
    logic `N(`DCACHE_REPLACE_SIZE) valid, prior_valid;
    logic `N(`DCACHE_REPLACE_WIDTH) freeIdx, validIdx, priorIdx, processIdx, processIdx_pre;
    logic full;
    logic `N(`DCACHE_REPLACE_SIZE) hit;
    logic `N(`PADDR_SIZE) waddr;
    logic retire_last;
    ReplaceEntry newEntry;

    assign io.full = full;
    assign newEntry.addr = io.addr;
    assign newEntry.data = io.data;
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_free_idx (~en, freeIdx);
    always_ff @(posedge clk)begin
        full <= &en;
        if(io.refill_en)begin
            entrys[io.replace_idx] <= newEntry;
        end
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            dataValid <= 0;
            prior <= 0;
            en <= 0;
            dirty <= 0;
        end
        else begin
            if(io.en & ~(|hit) & ~full)begin
                en[freeIdx] <= 1'b1;
            end
            if(io.en & (|hit))begin
                prior[freeIdx] <= 1'b1;
            end

            if(io.refill_en)begin
                dataValid[io.replace_idx] <= 1'b1;
                dirty[io.replace_idx] <= io.refill_dirty;
            end

            if(retire_last)begin
                en[processIdx] <= 1'b0;
                dataValid[processIdx] <= 1'b0;
                prior[processIdx] <= 1'b0;
            end
        end
    end

// write conflict detect
    assign waddr = io.snoop_en ? io.snoop_addr : io.waddr;
generate
    for(genvar i=0; i<`DCACHE_REPLACE_SIZE; i++)begin
        assign hit[i] = dataValid[i] & (waddr`DCACHE_BLOCK_BUS == entrys[i].addr);
    end
    logic `N(`DCACHE_REPLACE_WIDTH) whit_idx;
    Encoder #(`DCACHE_REPLACE_SIZE) encoder_hit (hit, whit_idx);
    always_ff @(posedge clk)begin
        io.whit <= |hit;
        io.idx <= |hit ? whit_idx : freeIdx;
    end
endgenerate

// axi
    logic aw_valid;
    logic `N($clog2(TRANSFER_BANK)) widx;
    logic wvalid;
    logic wlast;
    logic aw_dirty;
    ReplaceEntry processEntry;

    assign valid = en & dataValid;
    assign prior_valid = en & dataValid & prior;
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_valid_idx (valid, validIdx);
    PEncoder #(`DCACHE_REPLACE_SIZE) encoder_prior_idx (prior_valid, priorIdx);
    assign processIdx_pre = |prior_valid ? priorIdx : validIdx;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            aw_valid <= 1'b0;
            widx <= 0;
            wlast <= 0;
            wvalid <= 0;
            processEntry <= 0;
            processIdx <= 0;
            replace_state <= IDLE;
            retire_last <= 1'b0;
        end
        else begin
            case(replace_state)
            IDLE: begin
                if(|valid)begin
                    aw_valid <= 1'b1;
                    aw_dirty <= dirty[processIdx_pre];
                    replace_state <= ADDRESS;
                    processEntry <= entrys[processIdx_pre];
                    processIdx <= processIdx_pre;
                end
            end
            ADDRESS: begin
                if(w_axi_io.aw_valid & w_axi_io.aw_ready)begin
                    aw_valid <= 1'b0;
                    if(aw_dirty)begin
                        replace_state <= WRITE;
                        wvalid <= 1'b1;
                    end
                    else begin
                        replace_state <= RETIRE;
                    end
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
            end
            WAIT_B: begin
                if(w_axi_io.b_valid)begin
                    replace_state <= RETIRE;
                end
            end
            RETIRE: begin
                if(retire_last)begin
                    replace_state <= IDLE;
                    retire_last <= 1'b0;
                end
                else begin
                    retire_last <= 1'b1;
                end
            end
            endcase
        end
    end

    assign w_axi_io.aw_valid = aw_valid;
    assign w_axi_io.aw_id = 0;
    assign w_axi_io.aw_addr = {processEntry.addr, {`DCACHE_LINE_WIDTH{1'b0}}};
    assign w_axi_io.aw_len = ~aw_dirty ? 0 : `DCACHE_LINE / `DATA_BYTE - 1;
    assign w_axi_io.aw_size = $clog2(`DATA_BYTE);
    assign w_axi_io.aw_burst = 2'b01;
    assign w_axi_io.aw_lock = 2'b0;
    assign w_axi_io.aw_cache = 4'b0;
    assign w_axi_io.aw_prot = 0;
    assign w_axi_io.aw_qos = 0;
    assign w_axi_io.aw_region = 0;
    assign w_axi_io.aw_user = aw_dirty;
    assign w_axi_io.aw_atop = 0;

    assign w_axi_io.w_data = processEntry.data[widx];
    assign w_axi_io.w_strb = {`DATA_BYTE{1'b1}};
    assign w_axi_io.w_last = wlast;
    assign w_axi_io.w_valid = wvalid;
    assign w_axi_io.w_user = 0;

    assign w_axi_io.b_ready = 1'b1;

// snoop
    typedef struct packed {
        logic `N(`DCACHE_SNOOP_ID_WIDTH) id;
        logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) data;
    } SnoopEntry;
    logic `N(`DCACHE_SNOOP_SIZE) snoop_en, snoop_data_valid, snoop_valid, snoop_issue;
    logic `N(`PADDR_SIZE) snoop_addr `N(`DCACHE_SNOOP_SIZE);
    SnoopEntry `N(`DCACHE_SNOOP_SIZE) snoopEntrys;
    logic snoop_en_s2, snoop_en_s3;
    logic snoop_replace_hit;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) snoop_replace_data;
    logic `N(`DCACHE_SNOOP_WIDTH) snoop_valid_idx, snoop_process_idx, snoop_free_idx, snoop_busy_idx;
    logic `N(`DCACHE_SNOOP_WIDTH) snoop_busy_idx_s2, snoop_busy_idx_s3;
    logic snoop_process;
    logic cd_valid, cd_last;
    logic `N(`DCACHE_SNOOP_ID_WIDTH) cd_user;
    logic `ARRAY(`DCACHE_BANK, `DCACHE_BITS) snoop_data;
    logic `N($clog2(TRANSFER_BANK)) snoopIdx;

    assign snoop_valid = snoop_en & snoop_data_valid;
    PEncoder #(`DCACHE_SNOOP_SIZE) encoder_snoop_idx (snoop_valid, snoop_valid_idx);
    PEncoder #(`DCACHE_SNOOP_SIZE) encoder_snoop_free_idx (~snoop_en, snoop_free_idx);
    PEncoder #(`DCACHE_SNOOP_SIZE) encoder_snoop_busy_idx (snoop_en & ~snoop_issue, snoop_busy_idx);
    assign io.snoop_en = |(snoop_en & ~snoop_issue);
    assign io.snoop_addr = snoop_addr[snoop_busy_idx];

    always_ff @(posedge clk)begin
        snoop_en_s2 <= io.snoop_en & io.snoop_ready;
        snoop_en_s3 <= snoop_en_s2;
        snoop_busy_idx_s2 <= snoop_busy_idx;
        snoop_busy_idx_s3 <= snoop_busy_idx_s2;
        snoop_replace_hit <= io.whit;
        snoop_replace_data <= entrys[io.idx].data;
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            snoop_en <= 0;
            snoop_data_valid <= 0;
            snoop_issue <= 0;
        end
        else begin
            if(snoop_io.ac_valid & snoop_io.ac_ready)begin
                snoop_en[snoop_free_idx] <= 1'b1;
                snoopEntrys[snoop_free_idx].id <= snoop_io.ac_user;
                snoop_issue[snoop_free_idx] <= 1'b0;
                snoop_addr[snoop_free_idx] <= snoop_io.ac_addr;
            end
            if(snoop_en_s3)begin
                snoop_data_valid[snoop_busy_idx_s3] <= 1'b1;
                snoopEntrys[snoop_busy_idx_s3].data <= snoop_replace_hit ? snoop_replace_data : io.snoop_data;
            end
            if(io.snoop_en & io.snoop_ready)begin
                snoop_issue[snoop_busy_idx] <= 1'b1;
            end
            if(cd_last)begin
                snoop_en[snoop_process_idx] <= 1'b0;
                snoop_data_valid[snoop_process_idx] <= 1'b0;
            end
        end
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            cd_valid <= 1'b0;
            cd_last <= 1'b0;
            snoopIdx <= 0;
            cd_user <= 0;
            snoop_process <= 1'b0;
            snoop_data <= 0;
            snoop_process_idx <= 0;
        end
        else begin
            if(!snoop_process && (|snoop_valid))begin
                snoop_data <= snoopEntrys[snoop_valid_idx].data;
                snoop_process_idx <= snoop_valid_idx;
                cd_valid <= 1'b1;
                cd_user <= snoopEntrys[snoop_valid_idx].id;
            end
            if(snoop_io.cd_valid & snoop_io.cd_ready)begin
                snoopIdx <= snoopIdx + 1;
                if(snoopIdx == TRANSFER_BANK - 2)begin
                    cd_last <= 1'b1;
                end
                else begin
                    cd_last <= 1'b0;
                end
                if(cd_last)begin
                    snoop_process <= 1'b0;
                    cd_valid <= 1'b0;
                end
            end
        end
    end

    assign snoop_io.ac_ready = ~(&snoop_en);
    assign snoop_io.cd_valid = cd_valid;
    assign snoop_io.cd_last = cd_last;
    assign snoop_io.cd_data = snoop_data[snoopIdx];
    assign snoop_io.cd_user = cd_user;

`ifdef DIFFTEST
    `LOG_ARRAY(T_DCACHE, dbg_data, newEntry.data, TRANSFER_BANK)
    `Log(DLog::Debug, T_DCACHE, io.refill_en & io.refill_dirty,
        $sformatf("dcache replace. [%h] %s", newEntry.addr << `DCACHE_LINE_WIDTH, dbg_data))
`endif
endmodule