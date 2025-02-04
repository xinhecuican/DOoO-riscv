`include "../../../defines/defines.svh"

// 目录写入时机:
// 在读目录后实际上便可以进行目录更新，因为同时mshr不会更新同一个set
// slave读: 
// 如果读slave hit,则更新local为shared,
// 如果l2 hit, 如果是L2 Cache且来自dcache，则更新local并且删除l2
// 如果来自icache则不改变目录
// 如果slave miss且l2 miss, 则更新l2和local(根据dcache)
// slave写:
// 如果是ReadUnique,并且命中l2(此时以l2中的状态为准,忽略dcache提供的SU信息)且当前状态为S,
// 那么需要转发给L3,请求变更为CleanUnique。如果是L2并且当前状态为U,则省略转发的步骤
// 无论是否命中l2,都需要更新local,并且删除l2 Directory(因为只有dcache会发ReadUnique)
// 如果是MakeUnique, 省略实际读数据的过程，但是仍然需要按照ReadUnique的过程转发请求和更新目录
// slave替换:
// 如果是l2并且命中那么写入l2 Directory,并且Shared状态根据l2,Dirty状态根据dcache
// 如果miss，那么正常写入替换路即可
// 如果是l3,正常写入Directory
// 所有替换都需要删除local，因为只有owner才会发出替换请求  

// 写入local时机:
// 当读取时，local命中，状态变为shared，directory命中，状态根据directory的状态
// 都没命中，根据master传过来的状态
// 如果local没有命中，则需要进行替换，根据替换路的信息决定是否要发送snoop，并且如果是owner还需要进行替换
// 当替换时，删除local
module LocalDirectory #(
    parameter SLAVE_NUM = 1,
    parameter WAY = 4,
    parameter SET = 64,
    parameter OFFSET = 32,
    parameter LLC = 1,
    parameter OFFSET_WIDTH = $clog2(OFFSET),
    parameter SET_WIDTH = $clog2(SET),
    parameter TAG_WIDTH = `PADDR_SIZE - OFFSET_WIDTH - SET_WIDTH,
    parameter SLAVE_WIDTH = idxWidth(SLAVE_NUM)
)(
    input logic clk,
    input logic rst,
    L2MSHRSlaveIO.slaver mshr_slave_io
);

    typedef struct packed {
        logic owned; // not llc
        logic `N(SLAVE_WIDTH) owner;
        logic `N(SLAVE_NUM) valid;
        logic share;
        logic `N(TAG_WIDTH) tag;
    } Entry;

    parameter ENTRY_SIZE = TAG_WIDTH + 1 + (LLC ? 0 : 1) + SLAVE_NUM + SLAVE_WIDTH;
    logic `ARRAY(WAY, ENTRY_SIZE) lookup_entry;
    logic `N(ENTRY_SIZE) select_entry, replace_data;
    logic select_hit;
    logic `N(WAY) tag_hits, wway_dec;
    logic en_n;
    logic `N(`PADDR_SIZE) raddr_n;

    always_ff @(posedge clk)begin
        raddr_n <= mshr_slave_io.raddr;
        en_n <= mshr_slave_io.request;
    end


    ReplaceIO #(.DEPTH(SET), .WAY_NUM(WAY)) replace_io();
    Replace #(
        .DEPTH(SET),
        .WAY_NUM(WAY)
    ) replace (.*);
    assign replace_io.miss_index = mshr_slave_io.raddr[OFFSET_WIDTH +: SET_WIDTH];
    assign replace_io.hit_en = select_hit & en_n | mshr_slave_io.we & ~mshr_slave_io.request;
    assign replace_io.hit_way = mshr_slave_io.we & ~mshr_slave_io.request ? 
        (|mshr_slave_io.wdata[TAG_WIDTH+1 +: SLAVE_NUM] ? mshr_slave_io.wway : ~mshr_slave_io.wway) : tag_hits;
    assign replace_io.hit_index = raddr_n[OFFSET_WIDTH +: SET_WIDTH];

generate
    for(genvar i=0; i<WAY; i++)begin
        logic `N(SET_WIDTH) addr;
        assign addr = mshr_slave_io.request ? mshr_slave_io.raddr[OFFSET_WIDTH +: SET_WIDTH] : mshr_slave_io.waddr;
        SPRAM #(
            .WIDTH(ENTRY_SIZE),
            .DEPTH(SET),
            .RESET(1),
            .READ_LATENCY(1)
        ) ram (
            .clk,
            .rst,
            .rst_sync(0),
            .en(mshr_slave_io.request),
            .addr(addr),
            .rdata(lookup_entry[i]),
            .we(~mshr_slave_io.request & mshr_slave_io.we & wway_dec[i]),
            .wdata(mshr_slave_io.wdata),
            .ready()
        );
        assign tag_hits[i] = (|lookup_entry[i][TAG_WIDTH+1 +: SLAVE_NUM]) & (lookup_entry[i][TAG_WIDTH-1: 0] == raddr_n[`PADDR_SIZE-1 -: TAG_WIDTH]);
    end

    FairSelect #(WAY, ENTRY_SIZE) select_lookup (tag_hits, lookup_entry, select_hit, select_entry);
    FairSelect #(WAY, ENTRY_SIZE) select_replace (replace_io.miss_way, lookup_entry, , replace_data);
    assign mshr_slave_io.hit = select_hit;
    assign mshr_slave_io.share = select_entry[TAG_WIDTH];
    assign mshr_slave_io.slave = select_entry[TAG_WIDTH + 1 +: SLAVE_NUM];
    if(!LLC)begin
        assign mshr_slave_io.owned = select_entry[ENTRY_SIZE-1];
        assign mshr_slave_io.owner = select_entry[ENTRY_SIZE-2 -: SLAVE_WIDTH];
        assign mshr_slave_io.replace_owned = replace_data[ENTRY_SIZE-1];
    end
    else begin
        assign mshr_slave_io.owned = 1'b1;
        assign mshr_slave_io.owner = select_entry[ENTRY_SIZE-1 -: SLAVE_WIDTH];
        assign mshr_slave_io.owned = 1'b1;
    end
    Encoder #(WAY) encoder_hit (tag_hits, mshr_slave_io.hit_way);
    Encoder #(WAY) encoder_miss (replace_io.miss_way, mshr_slave_io.replace_way);
    assign mshr_slave_io.replace_hit = (|replace_data[TAG_WIDTH+1 +: SLAVE_NUM]);
    

    Decoder #(WAY) decoder_wway (mshr_slave_io.wway, wway_dec);
    assign mshr_slave_io.wready = ~mshr_slave_io.request;
endgenerate

endmodule


// 写入时机:
// L2 READ_ONCE并且需要从master中获得时或L2替换时
module L2Directory #(
    parameter SET = 64,
    parameter WAY_NUM = 8,
    parameter OFFSET = 32,
    parameter OFFSET_WIDTH = $clog2(OFFSET),
    parameter ISL2 = 1,
    parameter SET_WIDTH = $clog2(SET),
    parameter TAG_WIDTH = `PADDR_SIZE - OFFSET_WIDTH - SET_WIDTH,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter DIRECTORY_SIZE = TAG_WIDTH+1+$bits(DirectoryState)
)(
    input logic clk,
    input logic rst,
    L2MSHRDirIO.dir mshr_dir_io
);
    logic `ARRAY(WAY_NUM, TAG_WIDTH+1) tagvs;
    DirectoryState `N(WAY_NUM) dir_states;
    logic `N(TAG_WIDTH) cmp_tag;
    logic `N(WAY_NUM) tagv_hits;
    logic `N(SET_WIDTH) lookup_idx;
    logic `ARRAY(WAY_NUM, DIRECTORY_SIZE) rdata;
    logic `N(DIRECTORY_SIZE) replace_data;
    logic en_n;
    logic `N(WAY_NUM) wway_dec;

    ReplaceIO #(.DEPTH(SET), .WAY_NUM(WAY_NUM)) replace_io();
    Replace #(
        .DEPTH(SET),
        .WAY_NUM(WAY_NUM)
    ) replace (.*);
    assign replace_io.miss_index = mshr_dir_io.raddr[OFFSET_WIDTH +: SET_WIDTH];
    assign replace_io.hit_en = mshr_dir_io.hit & en_n | mshr_dir_io.we & ~mshr_dir_io.request;
    assign replace_io.hit_way = mshr_dir_io.we & ~mshr_dir_io.request ? 
                    (mshr_dir_io.wdata[0] ? mshr_dir_io.wway : ~mshr_dir_io.wway) : tagv_hits;
    assign replace_io.hit_index = mshr_dir_io.we & ~mshr_dir_io.request ? mshr_dir_io.waddr : lookup_idx;
    always_ff @(posedge clk)begin
        if(mshr_dir_io.request)begin
            cmp_tag <= mshr_dir_io.raddr[`PADDR_SIZE-1 -: TAG_WIDTH];
            lookup_idx <= mshr_dir_io.raddr[OFFSET_WIDTH +: SET_WIDTH];
        end
        en_n <= mshr_dir_io.request;
    end
generate
    for(genvar i=0; i<WAY_NUM; i++)begin
        logic `N(SET_WIDTH) addr;
        assign addr = mshr_dir_io.request ? mshr_dir_io.raddr[OFFSET_WIDTH +: SET_WIDTH] : mshr_dir_io.waddr;
        SPRAM #(
            .WIDTH(DIRECTORY_SIZE),
            .DEPTH(SET),
            .READ_LATENCY(1),
            .RESET(1)
        ) directory (
            .clk,
            .rst,
            .rst_sync(0),
            .en(mshr_dir_io.request),
            .addr(addr),
            .rdata(rdata[i]),
            .we(mshr_dir_io.we & ~mshr_dir_io.request & wway_dec[i]),
            .wdata(mshr_dir_io.wdata),
            .ready()
        );
        assign tagvs[i] = rdata[i][TAG_WIDTH: 0];
        assign dir_states[i] = rdata[i][TAG_WIDTH+1 +: $bits(DirectoryState)];
        assign tagv_hits[i] = tagvs[i][0] & (tagvs[i][TAG_WIDTH: 1] == cmp_tag);
    end
endgenerate

    Encoder #(WAY_NUM) encoder_hit (tagv_hits, mshr_dir_io.hit_way);
    Encoder #(WAY_NUM) encoder_miss (replace_io.miss_way, mshr_dir_io.replace_way);
    FairSelect #(WAY_NUM, $bits(DirectoryState)) select_hit (tagv_hits, dir_states, mshr_dir_io.hit, mshr_dir_io.hit_state);
    FairSelect #(WAY_NUM, DIRECTORY_SIZE) select_replace (replace_io.miss_way, rdata, , replace_data);
    assign mshr_dir_io.replace_tagv = replace_data[TAG_WIDTH: 0];
    assign mshr_dir_io.replace_state = replace_data[TAG_WIDTH+1 +: $bits(DirectoryState)];

    Decoder #(WAY_NUM) decoder_wway (mshr_dir_io.wway, wway_dec);
    assign mshr_dir_io.wready = ~mshr_dir_io.request;
endmodule