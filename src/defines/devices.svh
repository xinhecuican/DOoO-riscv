`ifndef __DEVICES_SVH__
`define __DEVICES_SVH__
`include "global.svh"

`define UART_START      `PADDR_SIZE'h20000000
`define UART_END        `PADDR_SIZE'h20000004
`define MEM_START       `PADDR_SIZE'h80000000
`define MEM_END         `PADDR_SIZE'ha0000000

`endif