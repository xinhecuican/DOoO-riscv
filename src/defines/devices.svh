`ifndef __DEVICES_SVH__
`define __DEVICES_SVH__
`include "global.svh"

`define IRQ_NUM 1

`define IRQ_START           `PADDR_SIZE'h08000000
`define IRQ_END             `PADDR_SIZE'h10000000
`define CLINT_START         `PADDR_SIZE'h08000000
`define CLINT_END           `PADDR_SIZE'h08001000
`define PLIC_START          `PADDR_SIZE'h0c000000
`define PLIC_END            `PADDR_SIZE'h0c001000

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

/* register mapping
 * UART_LCR:
 * BITS:   | 31:9 | 8:7 | 6   | 5   | 4:3 | 2    | 1    | 0    |
 * FIELDS: | RES  | PS  | PEN | STB | WLS | PEIE | TXIE | RXIE |
 * PERMS:  | NONE | RW  | RW  | RW  | RW  | RW   | RW   | RW   |
  * --------------------------------------------------------------------------
 * UART_DIV:
 * BITS:   | 31:16 | 15:0 |
 * FIELDS: | RES   | DIV  |
 * PERMS:  | NONE  | RW   |
  * --------------------------------------------------------------------------
 * UART_TRX:
 * BITS:   | 31:8 | 7:0 || BITS:   | 31:8 | 7:0 |
 * FIELDS: | RES  | RX  || FIELDS: | RES  | TX  |
 * PERMS:  | NONE | RO  || PERMS:  | NONE | WO  |
  * --------------------------------------------------------------------------
 * UART_FCR:
 * BITS:   | 31:4 | 3:2         | 1      | 0      |
 * FIELDS: | RES  | RX_TRG_LEVL | TF_CLR | RF_CLR |
 * PERMS:  | NONE | WO          | WO     | WO     |
 * ---------------------------------------------------------------------------
 * UART_LSR:
 * BITS:   | 31:9 | 8    | 7    | 6    | 5    | 4  | 3  | 2    | 1    | 0    |
 * FIELDS: | RES  | FULL | EMPT | TEMT | THRE | PE | DR | PEIP | TXIP | RXIP |
 * PERMS:  | NONE | RO   | RO   | RO   | RO   | RO | RO | RO   | RO   | RO   |
 * ---------------------------------------------------------------------------
*/

// verilog_format: off
`define UART_RBR 4'b0000
`define UART_THR 4'b0000
`define UART_DLL 4'b0000
`define UART_DLM 4'b0001
`define UART_IER 4'b0001
`define UART_IIR 4'b0010
`define UART_FCR 4'b0010
`define UART_LCR 4'b0011
`define UART_MCR 4'b0100
`define UART_LSR 4'b0101
`define UART_MSR 4'b0110
`define UART_SCR 4'b0111

`define UART_LCR_WIDTH 8
`define UART_DIV_WIDTH 16
`define UART_TRX_WIDTH 8
`define UART_FCR_WIDTH 8
`define UART_LSR_WIDTH 8
`define UART_IER_WIDTH 3
`define UART_IIR_WIDTH 4

`define UART_DLL_MIN_VAL  8'd2
`define UART_LSR_RESET_VAL 9'h0E0
`endif