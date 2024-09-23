module test(
	input logic clk,
	input logic rst,
	input logic  en,
	input logic [3: 0] we,
	input logic [5: 0] raddr,
	input logic [5: 0] waddr,
	input logic [31: 0] wdata,
	output logic [31: 0] rdata
);
	/* sky130_sram_1rw1r_80x64_8 ram( */
	/* 	.clk0(clk), */
	/* 	.csb0(!rst), */
	/* 	.web0(!we), */
	/* 	.wmask0(wmask), */
	/* 	.addr0(waddr), */
	/* 	.din0(wdata), */
	/* 	.dout0(rdata[79: 0]), */
	/* 	.clk1(clk), */
	/* 	.csb1(!rst), */
	/* 	.addr1(raddr), */
	/* 	.dout1(rdata[159: 80]) */
	/* ); */
	// MPRAM #(
	// 	.WIDTH(32),
	// 	.DEPTH(64),
	// 	.READ_PORT(1),
	// 	.WRITE_PORT(1),
	// 	.RW_PORT(0),
	// 	.RESET(0),
	// 	.BYTE_WRITE(1)
	// ) ram (
	// 	.*,
	// 	.ready()
	// );
	SPRAM #(
		.WIDTH(32),
		.DEPTH(64),
		.READ_LATENCY(1),
		.BYTE_WRITE(1)
	) bank (
		.clk(clk),
		.en(en),
		.addr(waddr),
		.we(we),
		.wdata(wdata),
		.rdata(rdata)
	);
endmodule

// module ramb(clk, we, en, addr, di, do, en1, addr1, do1);
// parameter ADDR_WIDTH = 2;
// parameter DATA_WIDTH = 1;
// input logic clk;
// input logic we;
// input logic en;
// input logic [ADDR_WIDTH-1:0] addr;
// input logic [DATA_WIDTH:0] di;
// output logic [DATA_WIDTH-1:0] do;
// input logic en1;
// input logic [ADDR_WIDTH-1: 0] addr1;
// output logic [DATA_WIDTH-1: 0] do1;
// logic [DATA_WIDTH-1:0] RAM [(1<<ADDR_WIDTH)-1:0];
// always @(posedge clk) begin
//     if (we1)
//         RAM[addr] <= di;
// 	if(en)
// 		do <= RAM[addr];
// 	if(en1)
// 		do1 <= RAM[addr1];
// end
// endmodule
