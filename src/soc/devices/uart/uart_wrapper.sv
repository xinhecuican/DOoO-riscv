`include "../../../defines/defines.svh"

module UartWrapper(
    input logic clk,
    input logic rst,
    AxiIO.slave axi,
    input logic rxd,
    output logic txd,
);

    logic tx_busy, rx_busy, overrun, frame_error;
    logic write;

    assign axi.sr.last = 1'b1;
    assign axi.sr.resp = 0;
    assign axi.sr.user = 0;
    assign axi.sb.resp = 0;
    assign axi.sb.user = 0;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            axi.sr.id <= 0;
            axi.sar.ready <= 1'b0;
            axi.saw.ready <= 1'b0;
            axi.sb.id <= 0;
            axi.sb.valid <= 0;
            write <= 0;
        end
        else begin
            if(axi.mar.valid & axi.sar.ready)begin
                axi.sr.id <= axi.mar.id;
            end
            axi.sar.ready <= ~rx_busy;
            axi.saw.ready <= ~tx_busy;
            if(axi.mw.valid & axi.sw.ready)begin
                write <= 1'b1;
            end
            else if(axi.sb.valid & axi.mb.ready)begin
                write <= 1'b0;
            end
            axi.sb.valid <= write & ~tx_busy;
        end
    end

    uart #(8) uart_inst (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(axi.mw.data[7: 0]),
        .s_axis_tvalid(axi.mw.valid),
        .s_axis_tready(axi.sw.ready),
        .m_axis_tdata(axi.sr.data[7: 0]),
        .m_axis_tvalid(axi.sr.valid),
        .m_axis_tready(axi.mr.ready),
        .rxd(rxd),
        .txd(txd),
        .tx_busy(tx_busy),
        .rx_busy(rx_busy),
        .rx_overrun_error(overrun),
        .rx_frame_error(frame_error),
        .prescale(12000000/(9600*8))
    );
endmodule