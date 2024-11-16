// Copyright (c) 2023 Beijing Institute of Open Source Chip
// clint is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`ifndef INC_CLINT_DEF_SV
`define INC_CLINT_DEF_SV

/* register mapping
 * CLINT_MSIP:
 * BITS:   | 31:1  | 0    |
 * FIELDS: | RES   | MSIP |
 * PERMS:  | NONE  | RW   |
 * ------------------------
 * CLINT_MTIMEL:
 * BITS:   | 31:0   |
 * FIELDS: | MTIMEL |
 * PERMS:  | RO     |
 * ------------------------
 * CLINT_MTIMEH:
 * BITS:   | 31:0   |
 * FIELDS: | MTIMEH |
 * PERMS:  | RO     |
 * ------------------------
 * CLINT_MTIMECMPL:
 * BITS:   | 31:0      |
 * FIELDS: | MTIMECMPL |
 * PERMS:  | RW        |
 * ------------------------
 * CLINT_MTIMECMPH:
 * BITS:   | 31:0      |
 * FIELDS: | MTIMECMPH |
 * PERMS:  | RW        |
 * ------------------------
*/

// verilog_format: off
`define CLINT_MSIP      16'h0000 // BASEADDR + 0x00
`define CLINT_MTIMEL    16'hbff8 // BASEADDR + 0x04
`define CLINT_MTIMEH    16'hbffc // BASEADDR + 0x08
`define CLINT_MTIMECMPL 16'h4000 // BASEADDR + 0x0C
`define CLINT_MTIMECMPH 16'h4004 // BASEADDR + 0x10


`define CLINT_MSIP_ADDR      {26'b0, `CLINT_MSIP     , 2'b00}
`define CLINT_MTIMEL_ADDR    {26'b0, `CLINT_MTIMEL   , 2'b00}
`define CLINT_MTIMEH_ADDR    {26'b0, `CLINT_MTIMEH   , 2'b00}
`define CLINT_MTIMECMPL_ADDR {26'b0, `CLINT_MTIMECMPL, 2'b00}
`define CLINT_MTIMECMPH_ADDR {26'b0, `CLINT_MTIMECMPH, 2'b00}

`define CLINT_MSIP_WIDTH     1
`define CLINT_MTIME_WIDTH    64
`define CLINT_MTIMECMP_WIDTH 64

// verilog_format: on
interface ClintIO;
    logic timer_irq;
    logic soft_irq;

    modport clint(output timer_irq, soft_irq);
    modport cpu(input timer_irq, soft_irq);
endinterface //ClintIO
`endif
