
`define RW_MODULE_GEN(WIDTH, DEPTH, ADDR_WIDTH) \
module RAM_``WIDTH``x``DEPTH``_1R1W_ ( \
    input CLK_clk, \
    input PORT_W_CLK, \
    input PORT_W_WR_EN, \
    input [``ADDR_WIDTH``-1: 0] PORT_W_ADDR, \
    input [``WIDTH``-1: 0] PORT_W_WR_DATA, \
    input PORT_R_CLK, \
    input PORT_R_RD_EN, \
    input [``ADDR_WIDTH``-1: 0] PORT_R_ADDR, \
    output reg [``WIDTH``-1: 0] PORT_R_RD_DATA \
); \
sky130_sram_1r1w0rw_``WIDTH``x``DEPTH`` ram( \
	.clk0(CLK_clk), \
	.csb0(!PORT_W_WR_EN), \
	.addr0(PORT_W_ADDR), \
	.din0(PORT_W_WR_DATA), \
	.clk1(CLK_clk), \
	.csb1(!PORT_R_RD_EN), \
	.addr1(PORT_R_ADDR), \
	.dout1(PORT_R_RD_DATA) \
); \
endmodule

`define RW_BYTE_MODULE_GEN(WIDTH, DEPTH, ADDR_WIDTH) \
module RAM_``WIDTH``x``DEPTH``_1R1W_8 ( \
    input CLK_clk, \
    input PORT_W_CLK, \
    input PORT_W_WR_EN, \
    input [``WIDTH``/8-1: 0] PORT_W_WR_BE, \
    input [``ADDR_WIDTH``-1: 0] PORT_W_ADDR, \
    input [``WIDTH``-1: 0] PORT_W_WR_DATA, \
    input PORT_R_CLK, \
    input PORT_R_RD_EN, \
    input [``ADDR_WIDTH``-1: 0] PORT_R_ADDR, \
    output reg [``WIDTH``-1: 0] PORT_R_RD_DATA \
); \
sky130_sram_1r1w0rw_``WIDTH``x``DEPTH``_8 ram( \
	.clk0(CLK_clk), \
	.csb0(!PORT_W_WR_EN), \
    .wmask0(PORT_W_WR_BE), \
	.addr0(PORT_W_ADDR), \
	.din0(PORT_W_WR_DATA), \
	.clk1(CLK_clk), \
	.csb1(!PORT_R_RD_EN), \
	.addr1(PORT_R_ADDR), \
	.dout1(PORT_R_RD_DATA) \
); \
endmodule

`RW_MODULE_GEN(11, 2048, 11)
`RW_MODULE_GEN(156, 32, 5)
`RW_MODULE_GEN(32, 64, 6)
`RW_MODULE_GEN(4, 4096, 12)
`RW_MODULE_GEN(54, 32, 5)
`RW_MODULE_GEN(60, 32, 5)
`RW_MODULE_GEN(68, 256, 8)

`RW_BYTE_MODULE_GEN(32, 64, 6)