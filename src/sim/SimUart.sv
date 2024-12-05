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
    logic rx_fifo_rd, fifo_rd_n;
    logic lsr_rd, lsr_rd_n;
    logic [7: 0] rdata;
    logic [7: 0] data [15: 0];

    assign apb_wr = ~apb.penable && apb.psel &&  apb.pwrite;
    assign apb_rd = ~apb.penable && apb.psel && ~apb.pwrite;

    assign tx_fifo_wr = apb_wr && apb.paddr[3: 0] == `THR_ADR;
    assign rx_fifo_rd = apb_rd && apb.paddr[3: 0] == `RBR_ADR;
    assign lsr_rd = apb_rd && apb.paddr[3: 0] == `LSR_ADR;

    always_ff @(posedge clk)begin
        fifo_rd_n <= rx_fifo_rd;
        lsr_rd_n <= lsr_rd;
        rdata <= data[apb.paddr[3: 0]];
    end

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            data <= '{default: 0};
        end
        else begin
            if(apb_wr)begin
                data[apb.paddr[3: 0]] <= apb.pwdata[7: 0];
            end
        end
    end

    assign io_uart_out_valid = tx_fifo_wr;
    assign io_uart_out_ch = apb.pwdata[7:0];
    assign io_uart_in_valid = rx_fifo_rd;
    assign apb.prdata = fifo_rd_n ? io_uart_in_ch :
                        lsr_rd_n ? 8'h60 : rdata;
    assign apb.pslverr = 1'b0;
    assign apb.pready = 1'b1;
endmodule