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

    logic `ARRAY(BYTES, WIDTH / BYTES) data `N(DEPTH);
    generate;
        if(READ_LATENCY == 0)begin
            assign rdata = data[addr];
        end
        else if(READ_LATENCY == 1)begin
            always_ff @(posedge clk)begin
                if(en & ~(|we))begin
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

module TDPRAM#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_VALUE = 0,
    parameter READ_LATENCY0 = 0,
    parameter READ_LATENCY1 = 0
)(
    input logic clk,
    input logic rst,
    input logic en0,
    input logic en1,
    input logic `N(ADDR_WIDTH) addr0,
    input logic `N(ADDR_WIDTH) addr1,
    input logic we0,
    input logic we1,
    input logic `N(WIDTH) wdata0,
    input logic `N(WIDTH) wdata1,
    output logic `N(WIDTH) rdata0,
    output logic `N(WIDTH) rdata1
);

    logic `N(WIDTH) data `N(DEPTH);
    generate;
        if(READ_LATENCY0 == 0)begin
            assign rdata0 = data[addr0];
        end
        else if(READ_LATENCY0 == 1)begin
            always_ff @(posedge clk)begin
                if(en0)begin
                    rdata0 <= data[addr0];
                end

            end
        end
        if(READ_LATENCY1 == 0)begin
            assign rdata1 = data[addr1];
        end
        else if(READ_LATENCY1 == 1)begin
            always_ff @(posedge clk)begin
                if(en1)begin
                    rdata1 <= data[addr1];
                end

            end
        end
    endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            data <= '{default: INIT_VALUE};
        end
        else begin
            if(we0)begin
                data[addr0] <= wdata0;
            end
            if(we1)begin
                data[addr1] <= wdata1;
            end
        end
    end
endmodule

module DPRAM#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_VALUE = 0,
    parameter READ_LATENCY0 = 0,
    parameter READ_LATENCY1 = 0
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(ADDR_WIDTH) addr0,
    input logic `N(ADDR_WIDTH) addr1,
    input logic we,
    input logic `N(WIDTH) wdata,
    output logic `N(WIDTH) rdata0,
    output logic `N(WIDTH) rdata1
);

    logic `N(WIDTH) data `N(DEPTH);
    generate;
        if(READ_LATENCY0 == 0)begin
            assign rdata0 = data[addr0];
        end
        else if(READ_LATENCY0 == 1)begin
            always_ff @(posedge clk)begin
                if(en)begin
                    rdata0 <= data[addr0];
                end

            end
        end
        if(READ_LATENCY1 == 0)begin
            assign rdata1 = data[addr1];
        end
        else if(READ_LATENCY1 == 1)begin
            always_ff @(posedge clk)begin
                if(en)begin
                    rdata1 <= data[addr1];
                end

            end
        end
    endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<DEPTH; i++)begin
                data[i] <= INIT_VALUE;
            end
        end
        else begin
            if(we)begin
                data[addr0] <= wdata;
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

    always_ff @(posedge clk)begin
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

module MPRAM #(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter READ_PORT = 4,
    parameter WRITE_PORT = 4,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter READ_LATENCY = 1,
    parameter BYTE_WRITE = 0,
    parameter RESET = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic `N(READ_PORT) en,
    input logic `ARRAY(READ_PORT, ADDR_WIDTH) raddr,
    input logic `ARRAY(WRITE_PORT, ADDR_WIDTH) waddr,
    input logic [WRITE_PORT-1: 0][BYTES-1: 0] we,
    input logic [WRITE_PORT-1: 0][BYTES-1: 0][WIDTH/BYTES-1: 0] wdata,
    output logic `ARRAY(READ_PORT, WIDTH) rdata,
    output logic ready
);
    logic `ARRAY(BYTES, WIDTH / BYTES) mem `N(DEPTH);
    logic `N(ADDR_WIDTH) resetAddr;
    logic [BYTES-1: 0][WIDTH/BYTES-1: 0] resetData;
generate
    if(RESET)begin
        logic `N(ADDR_WIDTH+1) counter;
        logic resetState;
        assign resetAddr = resetState ? counter : waddr[0];
        assign resetData = resetState ? 0 : wdata[0];
        always_ff @(posedge clk)begin
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
            for(int i=0; i<BYTES; i++)begin
                if(we[0][i] | resetState)begin
                    mem[resetAddr][i] <= resetData[i];
                end
            end
        end
        
    end
    else begin
        assign resetAddr = waddr[0];
        assign resetData = wdata[0];
        assign ready = 1'b1;
        always_ff @(posedge clk)begin
            for(int i=0; i<BYTES; i++)begin
                if(we[0][i])begin
                    mem[resetAddr][i] <= resetData[i];
                end
            end
        end
    end
endgenerate

generate;
    if(READ_LATENCY == 0)begin
        for(genvar i=0; i<READ_PORT; i++)begin
            assign rdata[i] = mem[raddr[i]];
        end
        
    end
    else if(READ_LATENCY == 1)begin
        always_ff @(posedge clk)begin
            for(int i=0; i<READ_PORT; i++)begin
                if(en[i])begin
                    rdata[i] <= mem[raddr[i]];
                end
            end


        end
    end
endgenerate

generate
    for(genvar i=1; i<WRITE_PORT; i++)begin
        for(genvar j=0; j<BYTES; j++)begin
            always_ff @(posedge clk)begin
                if(we[i][j])begin
                    mem[waddr[i]][j] <= wdata[i][j];
                end
            end
        end
    end
endgenerate


endmodule

// multi bank fifo
module MBFIFO #(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter BANK = 4,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_VALUE = 0,
    parameter READ_LATENCY = 0,
    parameter BYTE_WRITE = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic `N(BANK) en,
    input logic `N(BANK) we,
    input logic `N($clog2(BANK)) enNum,
    input logic `N($clog2(BANK)) weNum,
    input logic `ARRAY(BANK, WIDTH) wdata,
    output logic `ARRAY(BANK, WIDTH) rdata
);
    typedef struct {
        logic en;
        logic we;
        logic `N(ADDR_WIDTH) raddr;
        logic `N(ADDR_WIDTH) waddr;
        logic `N(WIDTH) wdata;
        logic `N(WIDTH) rdata;
    } BankCtrl;
    BankCtrl ctrl `N(BANK);
    logic `N($clog2(BANK)) head, tail;
    logic `N(BANK * 2) shift_head, shift_tail;
    assign shift_head = en << head;
    assign shift_tail = we << tail;

generate
    for(genvar i=0; i<BANK; i++)begin
        SDPRAM #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH),
            .READ_LATENCY(READ_LATENCY)
        ) ram (
            .clk(clk),
            .rst(rst),
            .addr0(ctrl[i].waddr),
            .addr1(ctrl[i].raddr),
            .en(ctrl[i].en),
            .we(ctrl[i].we),
            .wdata(ctrl[i].wdata),
            .rdata1(ctrl[i].rdata)
        );
        assign ctrl[i].en = shift_head[i] | shift_head[i + BANK];
        assign ctrl[i].we = shift_tail[i] | shift_tail[i + BANK];
        assign ctrl[i].wdata = wdata[tail + i];
        assign rdata[i] = ctrl[head + i].rdata;
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            for(int i=0; i<BANK; i++)begin
                ctrl[i].raddr <= 0;
                ctrl[i].waddr <= 0;
            end
        end
        else begin
            head <= head + enNum;
            tail <= tail + weNum;
            for(int i=0; i<BANK; i++)begin
                if(ctrl[i].en)begin
                    ctrl[i].raddr <= ctrl[i].raddr + 1;
                end
                if(ctrl[i].we)begin
                    ctrl[i].waddr <= ctrl[i].waddr + 1;
                end
            end
        end
    end

endmodule

module FIFO#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_VALUE = 0,
    parameter READ_LATENCY = 0
)(
    input logic clk,
    input logic rst,
    input logic rd_en,
    input logic wr_en,
    input logic `N(WIDTH) wdata,
    output logic `N(WIDTH) rdata,
    output logic full
);
    logic `N(WIDTH) queue `N(DEPTH);
    logic `N($clog2(DEPTH)) head, tail;
    logic `N($clog2(DEPTH)+1) remain_count, next_remain_count;


    always_comb begin 
        case({wr_en, rd_en})
        2'b00, 2'b11: next_remain_count = remain_count;
        2'b10: next_remain_count = remain_count - 1;
        2'b01: next_remain_count = remain_count + 1;
        endcase
    end

    generate;
        if(READ_LATENCY == 0)begin
            assign rdata = queue[head];
        end
        else if(READ_LATENCY == 1)begin
            always_ff @(posedge clk)begin
                rdata <= queue[head];
            end
        end
    endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            queue <= '{default: INIT_VALUE};
            head <= 0;
            tail <= 0;
            remain_count <= INIT_VALUE;
            full <= 0;
        end
        else begin
            remain_count <= next_remain_count;
            full <= next_remain_count == 0;
            if(wr_en)begin
                tail <= tail + 1;
                queue[tail] <= wdata;
            end
            if(rd_en)begin
                head <= head + 1;
            end
        end
    end
endmodule