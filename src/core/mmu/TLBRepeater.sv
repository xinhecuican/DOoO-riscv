`include "../../defines/defines.svh"

module TLBRepeater #(
    parameter FRONT=0
)(
    input logic clk,
    input logic rst,
    input logic flush,
    TlbL2IO.l2 in,
    TlbL2IO.tlb out
);
generate
    if(FRONT)begin
        always_ff @(posedge clk)begin
            if(flush)begin
                out.req <= 1'b0;
            end
            else begin
                out.req <= in.req;
            end
            out.req_addr <= in.req_addr;
            out.info <= in.info;
        end
    end
endgenerate
    always_ff @(posedge clk)begin
        if(flush)begin
            in.ready <= 1'b1;
            in.dataValid <= 1'b0;
        end
        else begin
            in.ready <= out.ready;
            in.dataValid <= out.dataValid;
        end
        in.error <= out.error;
        in.exception <= out.exception;
        in.info_o <= out.info_o;
        in.entry <= out.entry;
        in.wpn <= out.wpn;
        in.waddr <= out.waddr;
    end
endmodule