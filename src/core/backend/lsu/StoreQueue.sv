`include "../../../defines/defines.svh"

interface StoreQueueIO;
    logic `N(`STORE_PIPELINE) en;
    StoreIssueData `N(`STORE_PIPELINE) data;
    logic `ARRAY(`STORE_PIPELINE, `VADDR_SIZE) paddr;
    logic `ARRAY(`STORE_PIPELINE, 4) mask;
    StoreIdx sqIdx;

    modport queue(input en, data, paddr, mask, output sqIdx);
endinterface

module StoreQueue(
    input logic clk,
    input logic rst,
    input logic `ARRAY(`STORE_PIPELINE, `XLEN) store_data,
    StoreQueueIO.queue io,
    StoreUnitIO.queue issue_queue_io,
    StoreCommitIO.queue queue_commit_io,
    LoadForwardIO.queue loadFwd,
    CommitBus.mem commitBus,
    BackendCtrl backendCtrl,
    output logic `N(`LOAD_PIPELINE) fwd_data_invalid
);
    logic `N(`STORE_QUEUE_WIDTH) head, tail, head_n, tail_n, commitHead;
    logic hdir, tdir, hdir_n;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_WIDTH) addr_eqIdx, data_eqIdx;
    logic `N($clog2(`STORE_DIS_PORT)+1) disNum;
    logic `N($clog2(`STORE_PIPELINE)+1) commitNum;
    logic `ARRAY(`STORE_DIS_PORT, `STORE_QUEUE_WIDTH) disWIdx;
    logic `ARRAY(`COMMIT_WIDTH, `STORE_QUEUE_WIDTH) commitIdx;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_WIDTH) headCommitIdx;

    StoreIdx redirectIdx;
    logic `ARRAY(`STORE_PIPELINE, `STORE_QUEUE_WIDTH) redirectRobIdx;
    StoreIdx `N(`STORE_PIPELINE) redirectSqIdx;
    logic `N(`STORE_QUEUE_SIZE) head_n_mask, redirect_mask;
    logic redirect_next;

generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign addr_eqIdx[i] = io.data[i].sqIdx.idx;
        assign data_eqIdx[i] = issue_queue_io.data_sqIdx[i].idx;
        assign headCommitIdx[i] = head + i;
    end
    for(genvar i=0; i<`STORE_DIS_PORT; i++)begin
        assign disWIdx[i] = tail + i;
    end
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        assign commitIdx[i] = commitHead + i;
    end
endgenerate

    ParallelAdder #(1, `STORE_DIS_PORT) adder_dis_num (issue_queue_io.dis_en, disNum);
    ParallelAdder #(1, `STORE_PIPELINE) addr_commit_num (queue_commit_io.en, commitNum);
    assign io.sqIdx.idx = tail;
    assign io.sqIdx.dir = tdir;
    assign head_n = queue_commit_io.conflict ? head : head + commitNum;
    assign tail_n = tail + disNum;
    assign hdir_n = head[`STORE_QUEUE_WIDTH-1] & ~head_n[`STORE_QUEUE_WIDTH-1] ? ~hdir : hdir;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            commitHead <= 0;
            hdir <= 0;
            tdir <= 0;
        end
        else begin
            head <= head_n;
            hdir <= head[`STORE_QUEUE_WIDTH-1] & ~head_n[`STORE_QUEUE_WIDTH-1] ? ~hdir : hdir;
            if(redirect_next)begin
                tail <= redirectIdx.idx;
                tdir <= redirectIdx.dir;
            end
            else begin
                tail <= tail_n;
                tdir <= tail[`STORE_QUEUE_WIDTH-1] & ~tail_n[`STORE_QUEUE_WIDTH-1] ? ~tdir : tdir;
            end

            commitHead <= commitHead + commitBus.storeNum;
        end
    end

    logic `N(`STORE_QUEUE_SIZE) valid, addrValid, dataValid, commited;

    logic `N(`VADDR_SIZE+`DCACHE_BYTE_WIDTH) addr_mask `N(`LOAD_QUEUE_SIZE);
    logic `N(`STORE_QUEUE_SIZE) data_dir;
    logic `ARRAY(`LOAD_QUEUE_SIZE, `DCACHE_BITS) data;

    always_ff @(posedge clk)begin
        redirect_next <= backendCtrl.redirect;
    end
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            addr_mask <= '{default: 0};
            valid <= 0;
            addrValid <= 0;
            dataValid <= 0;
            commited <= 0;
        end
        else begin
            for(int i=0; i<`STORE_DIS_PORT; i++)begin
                if(issue_queue_io.dis_en[i])begin
                    addrValid[disWIdx[i]] <= 1'b0;
                    dataValid[disWIdx[i]] <= 1'b0;
                    commited[disWIdx[i]] <= 1'b0;
                    valid[disWIdx[i]] <= 1'b1;
                end
            end
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                if(io.en[i])begin
                    addr_mask[addr_eqIdx[i]] <= {io.paddr[i][`VADDR_SIZE-1: `DCACHE_BYTE_WIDTH], io.mask[i]};
                    addrValid[addr_eqIdx[i]] <= 1'b1;
                    data_dir[addr_eqIdx[i]] <= io.data[i].sqIdx.dir;
                end
                if(issue_queue_io.data_en[i])begin
                    dataValid[data_eqIdx[i]] <= 1'b1;
                    data[data_eqIdx[i]] <= store_data[i];
                end
            end
            for(int i=0; i<`COMMIT_WIDTH; i++)begin
                if(i < commitBus.storeNum)begin
                    commited[commitIdx] <= 1'b1;
                end
            end
            for(int i=0; i<`STORE_PIPELINE; i++)begin
                valid[headCommitIdx[i]] <= 1'b0;
            end
            if(redirect_next)begin
                valid <= hdir_n ^ redirectIdx.dir ? ~(head_n_mask ^ redirect_mask) : head_n_mask ^ redirect_mask;
            end
        end
    end

// redirect

    MaskGen #(`STORE_QUEUE_SIZE) mask_gen_redirect (redirectIdx.idx, redirect_mask);
    MaskGen #(`STORE_QUEUE_SIZE) mask_gen_head (head_n, head_n_mask);
    logic `ARRAY(`STORE_DIS_PORT, `ROB_WIDTH) dis_rob_idx;
generate
    for(genvar i=0; i<`STORE_DIS_PORT; i++)begin
        assign dis_rob_idx[i] = issue_queue_io.dis_rob_idx[i].idx;
    end
endgenerate
    MPRAM #(
        .WIDTH($bits(StoreIdx)),
        .DEPTH(`ROB_SIZE),
        .READ_PORT(1),
        .WRITE_PORT(`STORE_PIPELINE)
    ) rob_redirect_ram (
        .clk(clk),
        .rst(rst),
        .en(backendCtrl.redirect),
        .raddr(backendCtrl.redirectIdx.idx),
        .rdata(redirectIdx),
        .we(issue_queue_io.dis_en),
        .waddr(dis_rob_idx),
        .wdata(issue_queue_io.dis_sq_idx),
        .ready()
    );

// write to commit
generate
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        logic `N(`STORE_QUEUE_WIDTH) queue_idx;
        assign queue_idx = head + i;
        assign queue_commit_io.en[i] = valid[queue_idx] & addrValid[queue_idx] & dataValid[queue_idx] & commited[queue_idx];
        assign queue_commit_io.addr[i] = addr_mask[queue_idx][`VADDR_SIZE+1: `DCACHE_BYTE];
        assign queue_commit_io.mask[i] = addr_mask[queue_idx][`DCACHE_BYTE-1: 0];
        assign queue_commit_io.data[i] = data[queue_idx];
    end
endgenerate

// forward
    logic `N(`STORE_QUEUE_SIZE) head_mask;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_QUEUE_SIZE) valid_vec, offset_vec, fwd_offset_vec;
    logic `ARRAY(`LOAD_PIPELINE, `STORE_QUEUE_SIZE) ptag_vec, forward_vec;
    logic [`LOAD_PIPELINE-1: 0][`STORE_QUEUE_SIZE-1: 0][`DCACHE_BYTE-1: 0] forward_mask;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BYTE) forward_mask_o, forward_data_valid_o;
    logic `ARRAY(`LOAD_PIPELINE, `DCACHE_BITS) forward_data_o;

    MaskGen #(`STORE_QUEUE_SIZE) maskgen_head (head, head_mask);
generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_QUEUE_SIZE; j++)begin
            assign offset_vec[i][j] = loadFwd.fwdData[i].en &
                                      (loadFwd.fwdData[i].vaddrOffset[11: `DCACHE_BYTE_WIDTH] == addr_mask[j][`DCACHE_BYTE+9: `DCACHE_BYTE]);
        end
        logic `N(`STORE_QUEUE_SIZE) store_mask;
        MaskGen #(`STORE_QUEUE_SIZE) maskgen_store (loadFwd.fwdData[i].sqIdx.idx, store_mask);
        logic span;
        assign valid_vec[i] = span ? ~(head_mask ^ store_mask) : head_mask ^ store_mask;
    end

    always_ff @(posedge clk)begin
        fwd_offset_vec <= valid_vec & offset_vec;
    end

    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        for(genvar j=0; j<`STORE_QUEUE_SIZE; j++)begin
            assign ptag_vec[i][j] = loadFwd.fwdData[i].ptag == addr_mask[j][`VADDR_SIZE-1: `TLB_TAG+`DCACHE_BYTE_WIDTH];
            assign forward_mask[i][j] = {`DCACHE_BYTE{forward_vec[i][j]}} & addr_mask[j][`DCACHE_BYTE-1: 0];
        end
        assign forward_vec[i] = ptag_vec[i] & fwd_offset_vec[i] & addrValid;
        ForwardSelect #(`STORE_QUEUE_SIZE) forward_select (
            .dir(data_dir),
            .mask(forward_mask[i]),
            .data(data),
            .dataValid(dataValid),
            .mask_o(forward_mask_o[i]),
            .data_o(forward_data_o[i]),
            .dataValid_o(forward_data_valid_o[i]),
            .dir_o()
        );
    end
    always_ff @(posedge clk)begin
        loadFwd.mask <= forward_mask_o;
        loadFwd.data <= forward_data_o;
        for(int i=0; i<`LOAD_PIPELINE; i++)begin
            fwd_data_invalid[i] <= (forward_data_valid_o[i] & forward_mask_o[i]) != forward_mask_o[i];
        end
        
    end
    
endgenerate
endmodule

module ForwardSelect #(
    parameter DEPTH = 32
)(
    input logic `N(DEPTH) dir,
    input logic `ARRAY(DEPTH, `DCACHE_BYTE) mask,
    input logic `ARRAY(DEPTH, `DCACHE_BITS) data,
    input logic `N(DEPTH) dataValid,
    output logic dir_o,
    output logic `N(`DCACHE_BYTE) mask_o,
    output logic `N(`DCACHE_BITS) data_o,
    output logic `N(`DCACHE_BYTE) dataValid_o
);
generate
    if(DEPTH == 1)begin
        assign mask_o = mask;
        assign data_o = data;
        assign dir_o = dir;
    end
    else if(DEPTH == 2)begin
        logic older;
        assign older = dir[1] ^ dir[0];
        assign dir_o = older ? dir[1] : dir[0];
        for(genvar i=0; i<`DCACHE_BYTE; i++)begin
            assign mask_o[i] = ((older | (~mask[0][i])) & mask[1][i]) | ((~older | (~mask[1][i])) & mask[0][i]);
            assign data_o[(i+1)*8-1: i*8] = ({8{older | (~mask[0][i])}} & data[1][(i+1)*8-1: i*8]) |
                                    ({8{~older | (~mask[1][i])}} & data[0][(i+1)*8-1: i*8]);
            assign dataValid_o[i] = ((older | (~mask[0][i])) & dataValid[1]) | ((~older | (~mask[1][i])) & dataValid[0]);
        end
    end
    else begin
        logic `N(2) dir1;
        logic `ARRAY(2, `DCACHE_BYTE) mask1, dataValid1;
        logic `ARRAY(2, `DCACHE_BITS) data1;
        ForwardSelect #(DEPTH/2) select1 (
            .dir(dir[DEPTH/2-1: 0]),
            .mask(mask[DEPTH/2-1: 0]),
            .data(data[DEPTH/2-1: 0]),
            .dataValid(dataValid[DEPTH/2-1: 0]),
            .dir_o(dir1[0]),
            .mask_o(mask1[0]),
            .data_o(data1[0]),
            .dataValid_o(dataValid1[0])
        );
        localparam REMAIN = DEPTH-DEPTH/2;
        ForwardSelect #(REMAIN) select2 (
            .dir(dir[DEPTH-1: DEPTH/2]),
            .mask(mask[DEPTH-1: DEPTH/2]),
            .data(data[DEPTH-1: DEPTH/2]),
            .dataValid(dataValid[DEPTH-1: DEPTH/2]),
            .dir_o(dir1[1]),
            .mask_o(mask1[1]),
            .data_o(data1[1]),
            .dataValid_o(dataValid1[1])
        );
        logic older;
        assign older = dir1[1] ^ dir1[0];
        assign dir_o = older ? dir1[1] : dir1[0];
        for(genvar i=0; i<`DCACHE_BYTE; i++)begin
            assign mask_o[i] = ((older | (~mask1[0][i])) & mask1[1][i]) | ((~older | (~mask1[1][i])) & mask1[0][i]);
            assign data_o[(i+1)*8-1: i*8] = ({8{older | (~mask1[0][i])}} & data1[1][(i+1)*8-1: i*8]) |
                                    ({8{~older | (~mask1[1][i])}} & data1[0][(i+1)*8-1: i*8]);
            assign dataValid_o[i] = ((older | (~mask1[0][i])) & dataValid1[1][i]) | ((~older | (~mask1[1][i])) & dataValid1[0][i]);
        end
    end
endgenerate

endmodule