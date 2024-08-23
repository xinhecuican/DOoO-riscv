`include "../../defines/defines.svh"

module AxiInterface(
    input logic clk,
    input logic rst,
    ICacheAxi.axi icache_io,
    DCacheAxi.axi dcache_io,
    AxiIO.master axi
);

    typedef enum { ICACHE, DCACHE, UNCACHE, IUNCACHE } device_t;

    typedef struct packed {
        logic en;
        device_t device;
        AxiMAR mar;
    } ReadController_t;

    ReadController_t read_controller;
    logic arEnd, ar_en;

    assign arEnd = axi.ar_valid & axi.ar_ready;
    assign ar_en = (~read_controller.en) | arEnd;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            read_controller.en <= 1'b0;
            read_controller.device <= ICACHE;
            read_controller.mar <= 0;
        end
        else begin
            if(~read_controller.en)begin
                if(dcache_io.ar_valid)begin
                    read_controller.en <= 1'b1;
                    read_controller.device <= DCACHE;
                    read_controller.mar <= dcache_io.mar;
                end
                else if(icache_io.ar_valid)begin
                    read_controller.en <= 1'b1;
                    read_controller.device <= ICACHE;
                    read_controller.mar <= icache_io.mar;
                end
            end
            else if(arEnd)begin
                read_controller.en <= 1'b0;
            end
        end
    end

    assign icache_io.ar_ready = read_controller.en & (read_controller.device == ICACHE) & arEnd;
    assign dcache_io.ar_ready = read_controller.en & (read_controller.device == DCACHE) & arEnd;
    assign icache_io.sr = axi.sr;
    assign dcache_io.sr = axi.sr;
    assign icache_io.r_valid = axi.sr.id == icache_io.mar.id && axi.r_valid;
    assign dcache_io.r_valid = axi.sr.id == dcache_io.mar.id && axi.r_valid;

    assign axi.mar = read_controller.mar;
    assign axi.ar_valid = read_controller.en;
    assign axi.r_ready = 1'b1;

    assign axi.maw = dcache_io.maw;
    assign axi.aw_valid = dcache_io.aw_valid;
    assign axi.mw = dcache_io.mw;
    assign axi.w_valid = dcache_io.w_valid;
    assign axi.b_ready = 1'b1;

    assign dcache_io.sb = axi.sb;
    assign dcache_io.aw_ready = axi.aw_ready;
    assign dcache_io.w_ready = axi.w_ready;
    assign dcache_io.b_valid = axi.b_valid;

endmodule