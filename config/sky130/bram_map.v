
`define RW_MODULE_GEN(WIDTH, DEPTH, ADDR_WIDTH) \
module RAM_``WIDTH``x``DEPTH``_1R1W ( \
    input CLK1, \
    input A1EN, \
    input [``ADDR_WIDTH``-1: 0] A1ADDR, \
    input [``WIDTH``-1: 0] A1DATA, \
    input B1EN, \
    input [``ADDR_WIDTH``-1: 0] B1ADDR, \
    output reg [``WIDTH``-1: 0] B1DATA \
); \
wire [``WIDTH``-1: 0] dout1; \
sky130_sram_1r1w0rw_``WIDTH``x``DEPTH`` ram( \
	.clk0(CLK1), \
	.csb0(!A1EN), \
	.addr0(A1ADDR), \
	.din0(A1DATA), \
	.clk1(CLK1), \
	.csb1(!B1EN), \
	.addr1(B1ADDR), \
	.dout1(dout1) \
); \
always @(posedge CLK1)begin \
	B1DATA <= dout1; \
end \
endmodule

`define RW_BYTE_MODULE_GEN(WIDTH, DEPTH, ADDR_WIDTH, BYTE) \
module RAM_``WIDTH``x``DEPTH``_1R1W_``BYTE`` ( \
    input CLK1, \
    input [``WIDTH``/``BYTE``-1: 0] A1EN, \
    input [``ADDR_WIDTH``-1: 0] A1ADDR, \
    input [``WIDTH``-1: 0] A1DATA, \
    input B1EN, \
    input [``ADDR_WIDTH``-1: 0] B1ADDR, \
    output reg [``WIDTH``-1: 0] B1DATA \
); \
wire [``WIDTH``-1: 0] dout1; \
sky130_sram_1r1w0rw_``WIDTH``x``DEPTH``_``BYTE`` ram( \
	.clk0(CLK1), \
	.csb0(!(|A1EN)), \
    .wmask0(A1EN), \
	.addr0(A1ADDR), \
	.din0(A1DATA), \
	.clk1(CLK1), \
	.csb1(!B1EN), \
	.addr1(B1ADDR), \
	.dout1(B1DATA) \
); \
always @(posedge CLK1)begin \
	B1DATA <= dout1; \
end \
endmodule

`RW_MODULE_GEN(11, 512, 9)
`RW_MODULE_GEN(156, 32, 5)
`RW_MODULE_GEN(32, 64, 6)
`RW_MODULE_GEN(4, 512, 9)
`RW_MODULE_GEN(54, 32, 5)
`RW_MODULE_GEN(60, 32, 5)
`RW_MODULE_GEN(68, 256, 8)
`RW_BYTE_MODULE_GEN(32, 64, 6, 8)
`RW_BYTE_MODULE_GEN(184, 64, 6, 23)
