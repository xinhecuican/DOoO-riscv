`ifndef __DEVICES_SVH__
`define __DEVICES_SVH__
`include "global.svh"


`define IRQ_START           `PADDR_SIZE'h08000000
`define IRQ_END             `PADDR_SIZE'h10000000
`define CLINT_START         `PADDR_SIZE'h08000000
`define CLINT_END           `PADDR_SIZE'h08001000

`define PERIPHERAL_SIZE 1
`define PERIPHERAL_START    `PADDR_SIZE'h10000000
`define PERIPHERAL_END      `PADDR_SIZE'h10010000
`define UART_START          `PADDR_SIZE'h10000000
`define UART_END            `PADDR_SIZE'h10001000

`define MEM_START           `PADDR_SIZE'h80000000
`define MEM_END             `PADDR_SIZE'ha0000000

typedef struct packed {
    logic [$clog2(`PERIPHERAL_SIZE): 0] idx;
    logic [`PADDR_SIZE-1: 0] start_addr;
    logic [`PADDR_SIZE-1: 0] end_addr;
} addr_rule_t;


// uart
`define UART_FIFO_DEPTH 16
`define UART_DATA_WIDTH 8
`define UART_N_SYNC     2

`define UART_TXFIFO 12'h00
`define UART_RXFIFO 12'h04
`define UART_TXCTRL 12'h08
`define UART_RXCTRL 12'h0C
`define UART_IE     12'h10
`define UART_IP     12'h14
`define UART_IC     12'h18
`define UART_DIV    12'h1C
`define UART_LCR    12'h20
`endif