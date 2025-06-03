`include "../../../defines/defines.svh"

module L2Cache #(
    parameter MSHR_SIZE = 8,
    parameter SLAVE_BANK = 16,
    parameter CACHE_BANK = 16, // CACHELINE BANK
    parameter DATA_BANK = 1, // CACHE SET BANK
    parameter ID_WIDTH=2,
    parameter ID_OFFSET=1,
    parameter MST_ID_WIDTH=1,
    parameter SLAVE = 1,
    parameter WAY_NUM = 4,
    parameter SET = 64,
    parameter OFFSET = 32,
    parameter ISL2 = 1,
    parameter LLC = 1,
    parameter PREPEND_PIPE = 0,
    parameter APPEND_PIPE = 0,
    parameter SLAVE_DIR_SET = 64,
    parameter SLAVE_DIR_WAY = 4,
    parameter type snoop_ac_chan_t = logic,
    parameter type snoop_cd_chan_t = logic,
    parameter type snoop_req_t = logic,
    parameter type snoop_resp_t = logic,
    parameter type mst_snoop_req_t = logic,
    parameter type mst_snoop_resp_t = logic,
    parameter MST_SNOOP_ID_WIDTH = 1
)(
    input logic clk,
    input logic rst,
    CacheBus.slave slave_io, // to l1
    CacheBus.master master_io, // to mem
    output snoop_req_t `N(SLAVE) snoop_req,
    input snoop_resp_t `N(SLAVE) snoop_resp,
    input snoop_req_t mst_snoop_req,
    output snoop_resp_t mst_snoop_resp
);
    L2MSHRSlaveIO #(
        .SLAVE(SLAVE),
        .LLC(LLC),
        .WAY(SLAVE_DIR_WAY),
        .OFFSET(OFFSET),
        .SET(SLAVE_DIR_SET)
    ) mshr_slave_io();
    L2MSHRDirIO #(
        .WAY(WAY_NUM),
        .OFFSET(OFFSET),
        .SET(SET)
    ) mshr_dir_io();
    L2MSHRDataIO #(
        .MSHR_SIZE(MSHR_SIZE),
        .DATA_BANK(DATA_BANK),
        .SET_SIZE(SET),
        .WAY_NUM(WAY_NUM)
    ) mshr_data_io();

    LocalDirectory #(
        .SLAVE_NUM(SLAVE),
        .WAY(SLAVE_DIR_WAY),
        .SET(SLAVE_DIR_SET),
        .OFFSET(OFFSET),
        .LLC(LLC)
    ) local_dir(.*);
    L2Directory #(
        .SET(SET),
        .WAY_NUM(WAY_NUM),
        .OFFSET(OFFSET),
        .ISL2(ISL2)
    ) l2_dir(.*);
    L2CacheData #(
        .MSHR_SIZE(MSHR_SIZE),
        .DATA_BANK(DATA_BANK),
        .WAY_NUM(WAY_NUM),
        .SET_SIZE(SET),
        .CACHE_BANK(CACHE_BANK),
        .PREPEND_PIPE(`L2PREPEND_PIPE),
        .APPEND_PIPE(`L2APPEND_PIPE)
    ) l2_data(.*);
    L2MSHR #(
        .MSHR_SIZE(MSHR_SIZE),
        .SLAVE_BANK(SLAVE_BANK),
        .CACHE_BANK(CACHE_BANK),
        .DATA_BANK(DATA_BANK),
        .ID_WIDTH(ID_WIDTH),
        .ID_OFFSET(ID_OFFSET),
        .MST_ID_WIDTH(MST_ID_WIDTH),
        .SLAVE(SLAVE),
        .WAY_NUM(WAY_NUM),
        .SET(SET),
        .OFFSET(OFFSET),
        .ISL2(ISL2),
        .LLC(LLC),
        .SLAVE_DIR_SET(SLAVE_DIR_SET),
        .SLAVE_DIR_WAY(SLAVE_DIR_WAY),
        .snoop_ac_chan_t(snoop_ac_chan_t),
        .snoop_cd_chan_t(snoop_cd_chan_t),
        .snoop_req_t(snoop_req_t),
        .snoop_resp_t(snoop_resp_t),
        .mst_snoop_req_t(mst_snoop_req_t),
        .mst_snoop_resp_t(mst_snoop_resp_t),
        .MST_SNOOP_ID_WIDTH(MST_SNOOP_ID_WIDTH)
    ) mshr(.*);
endmodule