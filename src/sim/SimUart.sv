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

    assign apb_wr = ~apb.penable && apb.psel &&  apb.pwrite;
    assign apb_rd = ~apb.penable && apb.psel && ~apb.pwrite;

    assign tx_fifo_wr = apb_wr && apb.paddr[5: 2] == `UART_THR;
    assign rx_fifo_rd = apb_rd && apb.paddr[5: 2] == `UART_RBR;

    assign io_uart_out_valid = tx_fifo_wr;
    assign io_uart_out_ch = apb.pwdata[7:0];
    assign io_uart_in_valid = rx_fifo_rd;
    assign apb.prdata = io_uart_in_ch;
    assign apb.pslverr = 1'b0;
    assign apb.pready = 1'b1;
endmodule