`include "../../../defines/defines.svh"

module Freelist(
    input logic clk,
    input logic rst,
    FreelistIO.freelist fl_io
);
    typedef struct packed {
        logic en;
        logic `N(`PREG_WIDTH) rdata;
    } FLTCtrl;
    FLTCtrl fltCtrl `N(`FETCH_WIDTH);

    logic `N($clog2(`FREELIST_DEPTH)+1) remainCount;
    logic `N($clog2(`FETCH_WIDTH)) head;

generate;
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        FLTable #(
            32 + `FREELIST_DEPTH * i
        ) flTable(
            .clk(clk),
            .rst(rst),
            .en(fltCtrl[i].en),
            .rdata(fltCtrl[i].rdata)
        );
        assign fl_io.prd[i] = fltCtrl[head+i].rdata;
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            head <= 0;
            remainCount <= `FREELIST_DEPTH;
        end
        else begin
            
        end
    end
endmodule

module FLTable #(
    parameter START_VALUE = 0
)(
    input logic clk,
    input logic rst,
    input logic en,
    output logic `N(`PREG_WIDTH) rdata
);
    logic `N(`PREG_WIDTH) freelist `N(`FREELIST_DEPTH);
    logic `N($clog2(`FREELIST_DEPTH)) head, tail;

    assign rdata = freelist[head];
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<`FREELIST_DEPTH; i++)begin
                freelist[i] <= START_VALUE + i;
            end
            head <= 0;
            tail <= 0;
        end
        else begin
            if(en)begin
                head <= head == `FREELIST_DEPTH - 1 ? 0 : head + 1;
            end
        end
    end
endmodule