`include "../defines/defines.svh"

module SPRAM#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter READ_LATENCY = 0,
    parameter BYTE_WRITE = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic en,
    input logic `N(ADDR_WIDTH) addr,
    input logic [BYTES-1: 0] we,
    input logic [BYTES-1: 0][WIDTH/BYTES-1: 0] wdata,
    output logic `N(WIDTH) rdata
);
    (* ram_style="block" *)
    logic `ARRAY(BYTES, WIDTH / BYTES) data `N(DEPTH);
    generate;
        if(READ_LATENCY == 0)begin
            assign rdata = data[addr];
        end
        else if(READ_LATENCY == 1)begin
            always_ff @(posedge clk)begin
                if(en)begin
                    rdata <= data[addr];
                end
            end
        end
    endgenerate

    for(genvar j=0; j<BYTES; j++)begin
        always_ff @(posedge clk)begin
            if(we[j])begin
                data[addr][j] <= wdata[j];
            end
        end
    end
endmodule

module SDPRAM#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_VALUE = 0,
    parameter READ_LATENCY = 0,
    parameter BYTE_WRITE = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(ADDR_WIDTH) addr0,
    input logic `N(ADDR_WIDTH) addr1,
    input logic [BYTES-1: 0] we,
    input logic `ARRAY(BYTES, WIDTH / BYTES) wdata,
    output logic `N(WIDTH) rdata1
);

    logic `ARRAY(BYTES, WIDTH / BYTES) data `N(DEPTH);
    generate;
        if(READ_LATENCY == 0)begin
            assign rdata1 = data[addr1];
        end
        else if(READ_LATENCY == 1)begin
            always_ff @(posedge clk)begin
                if(en)begin
                    rdata1 <= data[addr1];
                end

            end
        end
    endgenerate

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            for(int i=0; i<DEPTH; i++)begin
                data[i] <= '{default: INIT_VALUE};
            end
        end
        else begin
            if(|we)begin
                for(int i=0; i<BYTES; i++)begin
                    data[addr0][i] <= wdata[i];
                end
            end
        end
    end
endmodule

// rw port use waddr to read
module MPREG #(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter READ_PORT = 4,
    parameter WRITE_PORT = 4,
    parameter RW_PORT = 0,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter READ_LATENCY = 1,
    parameter BYTE_WRITE = 0,
    parameter RESET = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic `N(READ_PORT+RW_PORT) en,
    input logic `ARRAY(READ_PORT, ADDR_WIDTH) raddr,
    input logic `ARRAY(WRITE_PORT+RW_PORT, ADDR_WIDTH) waddr,
    input logic [WRITE_PORT+RW_PORT-1: 0][BYTES-1: 0] we,
    input logic [WRITE_PORT+RW_PORT-1: 0][BYTES-1: 0][WIDTH/BYTES-1: 0] wdata,
    output logic `ARRAY(READ_PORT+RW_PORT, WIDTH) rdata,
    output logic ready
);
    (* ram_style="block" *)
    logic `ARRAY(BYTES, WIDTH / BYTES) mem `N(DEPTH);
    logic `N(ADDR_WIDTH) resetAddr;
    logic [BYTES-1: 0][WIDTH/BYTES-1: 0] resetData;
    logic `N(ADDR_WIDTH+1) counter;
    logic resetState;
generate
    if(RESET)begin
        assign resetAddr = resetState ? counter : waddr[0];
        assign resetData = resetState ? 0 : wdata[0];
        always_ff @(posedge clk or posedge rst)begin
            if(rst == `RST)begin
                counter <= 0;
                resetState <= 1'b1;
                ready <= 1'b0;
            end
            else begin
                if(resetState)begin
                    counter <= counter + 1;
                    if(counter == DEPTH)begin
                        resetState <= 1'b0;
                        ready <= 1'b1;
                    end
                end
            end
        end
    end
    else begin
        assign resetAddr = waddr[0];
        assign resetData = wdata[0];
        assign resetState = 0;
        assign ready = 1'b1;
    end
endgenerate

generate;
    if(READ_LATENCY == 0)begin
        for(genvar i=0; i<READ_PORT; i++)begin
            assign rdata[i] = mem[raddr[i]];
        end
    end
    else if(READ_LATENCY == 1)begin
        if(RESET)begin
            for(genvar i=0; i<READ_PORT; i++)begin
                always_ff @(posedge clk)begin
                    if(!ready)begin
                        rdata[i] <= 0;
                    end
                    else if(en[i]) begin
                        rdata[i] <= mem[raddr[i]];
                    end
                end
            end
            for(genvar i=0; i<RW_PORT; i++)begin
                always_ff @(posedge clk)begin
                    if(!ready)begin
                        rdata[READ_PORT+i] <= 0;
                    end
                    else if(en[READ_PORT+i]) begin
                        rdata[READ_PORT+i] <= mem[waddr[i]];
                    end
                end
            end
        end
        else begin
            for(genvar i=0; i<READ_PORT; i++)begin
                always_ff @(posedge clk)begin
                    if(en[i])begin
                        rdata[i] <= mem[raddr[i]];
                    end
                end
            end
            for(genvar i=0; i<RW_PORT; i++)begin
                always_ff @(posedge clk)begin
                    if(en[READ_PORT+i])begin
                        rdata[READ_PORT+i] <= mem[waddr[i]];
                    end
                end
            end
        end
    end
endgenerate

generate
    always_ff @(posedge clk)begin
        for(int i=0; i<WRITE_PORT+RW_PORT; i++)begin
            if(i == 0 && RESET)begin
                for(int j=0; j<BYTES; j++)begin
                    if(we[i][j] | resetState)begin
                        mem[resetAddr][j] <= resetData[j];
                    end
                end
            end
            else begin
                for(int j=0; j<BYTES; j++)begin
                    if(we[i][j])begin
                        mem[waddr[i]][j] <= wdata[i][j];
                    end
                end
            end
        end
    end
endgenerate


endmodule

module MPRAMInner #(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter READ_PORT = 4,
    parameter WRITE_PORT = 4,
    parameter RW_PORT = 0,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter READ_LATENCY = 1,
    parameter BYTE_WRITE = 0,
    parameter RESET = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic `N(READ_PORT+RW_PORT) en,
    input logic `ARRAY(READ_PORT, ADDR_WIDTH) raddr,
    input logic `ARRAY(WRITE_PORT+RW_PORT, ADDR_WIDTH) waddr,
    input logic [WRITE_PORT+RW_PORT-1: 0][BYTES-1: 0] we,
    input logic [WRITE_PORT+RW_PORT-1: 0][BYTES-1: 0][WIDTH/BYTES-1: 0] wdata,
    output logic `ARRAY(READ_PORT+RW_PORT, WIDTH) rdata,
    output logic ready
);
    MPREG #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .READ_PORT(READ_PORT),
        .WRITE_PORT(WRITE_PORT),
        .RW_PORT(RW_PORT),
        .READ_LATENCY(READ_LATENCY),
        .BYTE_WRITE(BYTE_WRITE),
        .BYTES(BYTES),
        .RESET(RESET)
    ) regs (.*);

    // initial begin
	//     $display("%0dr%0dw%0drw_%0dx%0d%s", READ_PORT, WRITE_PORT, RW_PORT, WIDTH, DEPTH, BYTE_WRITE ? "_8" : "");
    // end
endmodule

module MPRAM #(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter READ_PORT = 4,
    parameter WRITE_PORT = 4,
    parameter RW_PORT = 0,
    parameter BANK_SIZE = DEPTH,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter READ_LATENCY = 1,
    parameter BYTE_WRITE = 0,
    parameter RESET = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic `N(READ_PORT+RW_PORT) en,
    input logic `ARRAY(READ_PORT, ADDR_WIDTH) raddr,
    input logic `ARRAY(WRITE_PORT+RW_PORT, ADDR_WIDTH) waddr,
    input logic [WRITE_PORT+RW_PORT-1: 0][BYTES-1: 0] we,
    input logic [WRITE_PORT+RW_PORT-1: 0][BYTES-1: 0][WIDTH/BYTES-1: 0] wdata,
    output logic `ARRAY(READ_PORT+RW_PORT, WIDTH) rdata,
    output logic ready
);
generate
    if(DEPTH > BANK_SIZE)begin
        localparam BANK = DEPTH / BANK_SIZE;
        localparam REMAIN = DEPTH % BANK_SIZE;
        localparam BANK_ALL = REMAIN != 0 ? BANK + 1 : BANK;
        logic `ARRAY(READ_PORT, BANK_ALL) bank_raddr_en;
        logic `ARRAY(WRITE_PORT+RW_PORT, BANK_ALL) bank_waddr_en;
        logic `ARRAY(BANK_ALL, READ_PORT+RW_PORT) bank_en;
        logic `ARRAY(BANK_ALL, WRITE_PORT+RW_PORT) bank_we;
        logic `ARRAY(READ_PORT, ADDR_WIDTH-$clog2(BANK_ALL)) raddr_bank;
        logic `ARRAY(WRITE_PORT+RW_PORT, ADDR_WIDTH-$clog2(BANK_ALL)) waddr_bank;
        logic `TENSOR(BANK_ALL, READ_PORT+RW_PORT, BYTES) we_bank;
        logic `TENSOR(BANK_ALL, READ_PORT+RW_PORT, WIDTH) rdata_bank;
        logic `N(BANK) ready_bank;
        logic `ARRAY(READ_PORT+RW_PORT, $clog2(BANK_ALL)) bank_idx, ridx;
        logic `ARRAY(WRITE_PORT+RW_PORT, BYTES*WIDTH) wdata_bank;

        logic `N(ADDR_WIDTH+1) counter;
        logic resetState;

        if(RESET)begin
            always_ff @(posedge clk or posedge rst)begin
                if(rst == `RST)begin
                    counter <= 0;
                    resetState <= 1'b1;
                    ready <= 1'b0;
                end
                else begin
                    if(resetState)begin
                        counter <= counter + 1;
                        if(counter == BANK_SIZE)begin
                            resetState <= 1'b0;
                            ready <= 1'b1;
                        end
                    end
                end
            end
        end
        else begin
            assign ready = ready_bank[0];
        end

        for(genvar i=0; i<READ_PORT; i++)begin
            Decoder #(BANK_ALL) decoder_bank (raddr[i][ADDR_WIDTH-1:ADDR_WIDTH-$clog2(BANK_ALL)], bank_raddr_en[i]);
            assign raddr_bank[i] = raddr[i][ADDR_WIDTH-$clog2(BANK_ALL)-1: 0];
            assign bank_idx[i] = raddr[i][ADDR_WIDTH-1: ADDR_WIDTH-$clog2(BANK_ALL)];
        end
        for(genvar i=0; i<RW_PORT; i++)begin
            assign bank_idx[i+READ_PORT] = waddr[WRITE_PORT+i][ADDR_WIDTH-1: ADDR_WIDTH-$clog2(BANK_ALL)];
        end
        for(genvar i=0; i<WRITE_PORT+RW_PORT; i++)begin
            if(RESET && i == 0)begin
                assign waddr_bank[i] = resetState ? counter : waddr[i][ADDR_WIDTH-$clog2(BANK_ALL)-1: 0];
                assign wdata_bank[i] = resetState ? 0 : wdata[i];
            end
            else begin
                assign waddr_bank[i] = waddr[i][ADDR_WIDTH-$clog2(BANK_ALL)-1: 0];
                assign wdata_bank[i] = wdata[i];
            end
            Decoder #(BANK_ALL) decoder_bank (waddr[i][ADDR_WIDTH-1:ADDR_WIDTH-$clog2(BANK_ALL)], bank_waddr_en[i]);
        end
        for(genvar i=0; i<BANK_ALL; i++)begin
            for(genvar j=0; j<READ_PORT; j++)begin
                assign bank_en[i][j] = bank_raddr_en[j][i];
            end
            for(genvar j=0; j<RW_PORT; j++)begin
                assign bank_en[i][j+READ_PORT] = bank_waddr_en[j+WRITE_PORT][i];
            end
            for(genvar j=0; j<WRITE_PORT+RW_PORT; j++)begin
                assign bank_we[i][j] = bank_waddr_en[j][i];
                for(genvar k=0; k<BYTES; k++)begin
                    if(RESET && j == 0)begin
                        assign we_bank[i][j][k] = resetState | we[j][k] & bank_we[i][j];
                    end
                    else begin
                        assign we_bank[i][j][k] = we[j][k] & bank_we[i][j];
                    end
                end
            end
        end

        if(READ_LATENCY == 0)begin
            assign ridx = bank_idx;
        end
        else if(READ_LATENCY == 1)begin
            logic `ARRAY(READ_PORT+RW_PORT, $clog2(BANK_ALL)) bank_idx_n;
            always_ff @(posedge clk)begin
                bank_idx_n <= bank_idx;
            end
            assign ridx = bank_idx_n;
        end
        for(genvar i=0; i<READ_PORT+RW_PORT; i++)begin
            assign rdata[i] = rdata_bank[ridx[i]][i];
        end
        for(genvar i=0; i<BANK; i++)begin
            MPRAMInner #(
                .WIDTH(WIDTH),
                .DEPTH(BANK_SIZE),
                .READ_PORT(READ_PORT),
                .WRITE_PORT(WRITE_PORT),
                .RW_PORT(RW_PORT),
                .READ_LATENCY(READ_LATENCY),
                .BYTE_WRITE(BYTE_WRITE),
                .BYTES(BYTES),
                .RESET(0)
            ) ram (
                .clk,
                .rst,
                .en((en & bank_en[i])),
                .raddr(raddr_bank),
                .waddr(waddr_bank),
                .we(we_bank[i]),
                .wdata(wdata_bank),
                .rdata(rdata_bank[i]),
                .ready(ready_bank[i])
            );
        end
        if(REMAIN > 0)begin
            MPRAMInner #(
                .WIDTH(WIDTH),
                .DEPTH(REMAIN),
                .READ_PORT(READ_PORT),
                .WRITE_PORT(WRITE_PORT),
                .RW_PORT(RW_PORT),
                .READ_LATENCY(READ_LATENCY),
                .BYTE_WRITE(BYTE_WRITE),
                .BYTES(BYTES),
                .RESET(0)
            ) ram (
                .clk,
                .rst,
                .en((en & bank_en[BANK])),
                .raddr(raddr_bank),
                .waddr(waddr_bank),
                .we(we_bank[BANK]),
                .wdata(wdata_bank),
                .rdata(rdata_bank[BANK]),
                .ready()
            );
        end
    end
    else begin
        MPRAMInner #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH),
            .READ_PORT(READ_PORT),
            .WRITE_PORT(WRITE_PORT),
            .RW_PORT(RW_PORT),
            .READ_LATENCY(READ_LATENCY),
            .BYTE_WRITE(BYTE_WRITE),
            .BYTES(BYTES),
            .RESET(RESET)
        ) ram (
            .*
        );
    end
endgenerate

endmodule

// multi bank fifo
// module MBFIFO #(
//     parameter WIDTH = 32,
//     parameter DEPTH = 8,
//     parameter BANK = 4,
//     parameter ADDR_WIDTH = $clog2(DEPTH),
//     parameter INIT_VALUE = 0,
//     parameter READ_LATENCY = 0,
//     parameter BYTE_WRITE = 0,
//     parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
// )(
//     input logic clk,
//     input logic rst,
//     input logic `N(BANK) en,
//     input logic `N(BANK) we,
//     input logic `N($clog2(BANK)) enNum,
//     input logic `N($clog2(BANK)) weNum,
//     input logic `ARRAY(BANK, WIDTH) wdata,
//     output logic `ARRAY(BANK, WIDTH) rdata
// );
//     typedef struct {
//         logic en;
//         logic we;
//         logic `N(ADDR_WIDTH) raddr;
//         logic `N(ADDR_WIDTH) waddr;
//         logic `N(WIDTH) wdata;
//         logic `N(WIDTH) rdata;
//     } BankCtrl;
//     BankCtrl ctrl `N(BANK);
//     logic `N($clog2(BANK)) head, tail;
//     logic `N(BANK * 2) shift_head, shift_tail;
//     assign shift_head = en << head;
//     assign shift_tail = we << tail;

// generate
//     for(genvar i=0; i<BANK; i++)begin
//         SDPRAM #(
//             .WIDTH(WIDTH),
//             .DEPTH(DEPTH),
//             .READ_LATENCY(READ_LATENCY)
//         ) ram (
//             .clk(clk),
//             .rst(rst),
//             .addr0(ctrl[i].waddr),
//             .addr1(ctrl[i].raddr),
//             .en(ctrl[i].en),
//             .we(ctrl[i].we),
//             .wdata(ctrl[i].wdata),
//             .rdata1(ctrl[i].rdata)
//         );
//         assign ctrl[i].en = shift_head[i] | shift_head[i + BANK];
//         assign ctrl[i].we = shift_tail[i] | shift_tail[i + BANK];
//         assign ctrl[i].wdata = wdata[tail + i];
//         assign rdata[i] = ctrl[head + i].rdata;
//     end
// endgenerate

//     always_ff @(posedge clk or posedge rst)begin
//         if(rst == `RST)begin
//             head <= 0;
//             tail <= 0;
//             for(int i=0; i<BANK; i++)begin
//                 ctrl[i].raddr <= 0;
//                 ctrl[i].waddr <= 0;
//             end
//         end
//         else begin
//             head <= head + enNum;
//             tail <= tail + weNum;
//             for(int i=0; i<BANK; i++)begin
//                 if(ctrl[i].en)begin
//                     ctrl[i].raddr <= ctrl[i].raddr + 1;
//                 end
//                 if(ctrl[i].we)begin
//                     ctrl[i].waddr <= ctrl[i].waddr + 1;
//                 end
//             end
//         end
//     end

// endmodule

// module FIFO#(
//     parameter WIDTH = 32,
//     parameter DEPTH = 8,
//     parameter ADDR_WIDTH = $clog2(DEPTH),
//     parameter INIT_VALUE = 0,
//     parameter READ_LATENCY = 0
// )(
//     input logic clk,
//     input logic rst,
//     input logic rd_en,
//     input logic wr_en,
//     input logic `N(WIDTH) wdata,
//     output logic `N(WIDTH) rdata,
//     output logic full
// );
//     logic `N(WIDTH) queue `N(DEPTH);
//     logic `N($clog2(DEPTH)) head, tail;
//     logic `N($clog2(DEPTH)+1) remain_count, next_remain_count;


//     always_comb begin 
//         case({wr_en, rd_en})
//         2'b00, 2'b11: next_remain_count = remain_count;
//         2'b10: next_remain_count = remain_count - 1;
//         2'b01: next_remain_count = remain_count + 1;
//         endcase
//     end

//     generate;
//         if(READ_LATENCY == 0)begin
//             assign rdata = queue[head];
//         end
//         else if(READ_LATENCY == 1)begin
//             always_ff @(posedge clk)begin
//                 rdata <= queue[head];
//             end
//         end
//     endgenerate

//     always_ff @(posedge clk or posedge rst)begin
//         if(rst == `RST)begin
//             queue <= '{default: INIT_VALUE};
//             head <= 0;
//             tail <= 0;
//             remain_count <= INIT_VALUE;
//             full <= 0;
//         end
//         else begin
//             remain_count <= next_remain_count;
//             full <= next_remain_count == 0;
//             if(wr_en)begin
//                 tail <= tail + 1;
//                 queue[tail] <= wdata;
//             end
//             if(rd_en)begin
//                 head <= head + 1;
//             end
//         end
//     end
// endmodule
