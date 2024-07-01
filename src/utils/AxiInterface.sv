`include "../defines/defines.svh"

module AxiInterface(
    input logic clk,
    input logic rst,
    ICacheAxi.axi icache_io,
    DCacheAxi.axi dcache_io,
    AxiIO.master axi
);

    typedef enum { ICACHE, DCACHE, UNCACHE, IUNCACHE } device_t;
`ifdef DIFFTEST
    typedef struct packed {
`else
    typedef struct {
`endif
        logic en;
        device_t device;
        AxiMAR mar;
    } ReadController_t;

    ReadController_t read_controller;
    logic arEnd, ar_en;

    assign arEnd = axi.mar.valid & axi.sar.ready;
    assign ar_en = (~read_controller.en) | arEnd;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            read_controller.en <= 1'b0;
            read_controller.device <= ICACHE;
            read_controller.mar <= 0;
        end
        else begin
            if(~read_controller.en)begin
                if(dcache_io.mar.valid)begin
                    read_controller.en <= 1'b1;
                    read_controller.device <= DCACHE;
                    read_controller.mar <= dcache_io.mar;
                end
                else if(icache_io.mar.valid)begin
                    read_controller.en <= 1'b1;
                    read_controller.device <= ICACHE;
                    read_controller.mar <= icache_io.mar;
                end
            end
            else if(arEnd)begin
                read_controller.en <= 1'b0;
                read_controller.mar.valid <= 1'b0;
            end
        end
    end

    assign icache_io.sar.ready = read_controller.en & (read_controller.device == ICACHE) & arEnd;
    assign dcache_io.sar.ready = read_controller.en & (read_controller.device == DCACHE) & arEnd;
    always_comb begin
        AxiSRCopy(axi.sr, axi.sr.id == icache_io.mar.id && axi.sr.valid, icache_io.sr);
        AxiSRCopy(axi.sr, axi.sr.id == dcache_io.mar.id && axi.sr.valid, dcache_io.sr);
    end

    assign axi.mar = read_controller.mar;
    assign axi.mr.ready = 1'b1;

    assign axi.maw = dcache_io.maw;
    assign axi.mw = dcache_io.mw;
    assign axi.mb.ready = 1'b1;

endmodule