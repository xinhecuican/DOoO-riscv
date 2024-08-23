`include "../defines/devices.svh"
`include "../defines/defines.svh"

module SimUart(
    input logic clk,
    input logic rst,
    ApbIO.slave apb,
    output        io_uart_out_valid,
    output [7:0]  io_uart_out_ch,
    output        io_uart_in_valid,
    input  [7:0]  io_uart_in_ch
);

    logic apb_wr;
    logic apb_rd;

    logic tx_fifo_wr;
    logic rx_fifo_rd;

    assign apb_wr = ~apb.req.penable && apb.req.psel &&  apb.req.pwrite;
    assign apb_rd = ~apb.req.penable && apb.req.psel && ~apb.req.pwrite;

    assign tx_fifo_wr = apb_wr && apb.req.paddr[11:0] == `UART_TXFIFO && ~apb.req.pwdata[31];
    assign rx_fifo_rd = apb_rd && apb.req.paddr[11:0] == `UART_RXFIFO;

    assign io_uart_out_valid = tx_fifo_wr;
    assign io_uart_out_ch = apb.req.pwdata[`UART_DATA_WIDTH-1:0];
    assign io_uart_in_valid = rx_fifo_rd;
    assign apb.resp.prdata = io_uart_in_ch;
    assign apb.resp.pslverr = 1'b0;
    assign apb.resp.pready = 1'b1;
endmodule