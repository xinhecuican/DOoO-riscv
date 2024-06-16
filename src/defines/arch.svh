`ifndef ARCH_H
`define ARCH_H

`define RV32I
`define ZICSR
`define DIFFTEST

`ifdef ZICSR
parameter HAS_ZICSR=1
`else
parameter HAS_ZICSR=0
`endif
`endif
