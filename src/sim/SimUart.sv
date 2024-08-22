`include "../defines/defines.svh"

module SimUart(
    input logic clk,
    input logic rst,
    AxiIO.slave axi,
    output        io_uart_out_valid,
    output [7:0]  io_uart_out_ch,
    output        io_uart_in_valid,
    input  [7:0]  io_uart_in_ch
);
    logic `N(`AXI_ID_W) sr_id, sb_id;
    logic sar_ready, saw_ready, sw_ready, sb_valid, sr_valid;
    assign axi.sr.last = 1'b1;
    assign axi.sr.resp = 0;
    assign axi.sr.user = 0;
    assign axi.sb.resp = 0;
    assign axi.sb.user = 0;
    assign axi.sr.id = sr_id;
    assign axi.sb.id = sb_id;
    assign axi.sar.ready = sar_ready;
    assign axi.saw.ready = saw_ready;
    assign axi.sw.ready = sw_ready;
    assign axi.sb.valid = sb_valid;
    assign axi.sr.valid = sr_valid;

    assign io_uart_out_valid = axi.mw.valid & axi.sw.ready;
    assign io_uart_out_ch = axi.mw.data[7: 0];
    assign io_uart_in_valid = axi.mr.ready & axi.sr.valid;
    assign axi.sr.data = io_uart_in_ch;

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            sr_id <= 0;
            sar_ready <= 1'b1;
            saw_ready <= 1'b1;
            sw_ready <= 1'b1;
            sb_id <= 0;
            sb_valid <= 0;
            sr_valid <= 0;
        end
        else begin
            if(axi.maw.valid & axi.saw.ready)begin
                saw_ready <= 1'b0;
                sb_id <= axi.maw.id;
            end
            if(axi.mw.valid & axi.sw.ready)begin
                sw_ready <= 1'b0;
                sb_valid <= 1'b1;
            end
            if(axi.sb.valid & axi.mb.ready)begin
                saw_ready <= 1'b1;
                sw_ready <= 1'b1;
                sb_valid <= 1'b0;
            end

            if(axi.mar.valid & axi.sar.ready)begin
                sar_ready <= 1'b0;
                sr_valid <= 1'b1;
                sr_id <= axi.mar.id;
            end

            if(axi.sr.valid & axi.mr.ready)begin
                sar_ready <= 1'b1;
                sr_valid <= 1'b0;
            end
        end
    end
endmodule