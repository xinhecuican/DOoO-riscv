`include "../defines/defines.svh"

module SPRAM#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter READ_LATENCY = 0,
    parameter BYTE_WRITE = 0,
    parameter RESET = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(ADDR_WIDTH) addr,
    input logic [BYTES-1: 0] we,
    input logic [BYTES-1: 0][WIDTH/BYTES-1: 0] wdata,
    output logic `N(WIDTH) rdata,
    output logic ready
);
`ifdef SYNTH_VIVADO
generate
    if(1)begin
        localparam BYTE_WRITE_WIDTH = BYTES == 1 ? WIDTH : 8;
        localparam WIDTH_LOCAL = WIDTH + BYTES * ((WIDTH/BYTES) % BYTE_WRITE_WIDTH);
        localparam BYTES_LOCAL = WIDTH_LOCAL / BYTE_WRITE_WIDTH;
        localparam DELTA = BYTES_LOCAL / BYTES;
        logic [BYTES_LOCAL-1: 0] we_local;
        logic [BYTES_LOCAL-1: 0][BYTE_WRITE_WIDTH-1: 0] wdata_local;
        for(genvar i=0; i<BYTES; i++)begin
            assign we_local[i*DELTA +: DELTA] = {DELTA{we[i]}};
            assign wdata_local[i*DELTA +: DELTA] = wdata[i];
        end
        assign ready = 1'b1;
        
        wire sbiterra;
        wire dbiterra;
        xpm_memory_spram #(
            .ADDR_WIDTH_A(ADDR_WIDTH),
            .AUTO_SLEEP_TIME(0),
            .BYTE_WRITE_WIDTH_A(BYTE_WRITE_WIDTH),
            .CASCADE_HEIGHT(0),
            .ECC_MODE("no_ecc"),
            .MEMORY_INIT_FILE("none"),
            .MEMORY_INIT_PARAM("0"),
            .MEMORY_OPTIMIZATION("true"),
            .MEMORY_PRIMITIVE("auto"),
            .MEMORY_SIZE(WIDTH_LOCAL * DEPTH),
            .MESSAGE_CONTROL(0),
            .READ_DATA_WIDTH_A(WIDTH_LOCAL),
            .READ_LATENCY_A(READ_LATENCY),
            .READ_RESET_VALUE_A("0"),
            .RST_MODE_A("SYNC"),
            .SIM_ASSERT_CHK(0),
            .USE_MEM_INIT(1),
            .WAKEUP_TIME("disable_sleep"),
            .WRITE_DATA_WIDTH_A(WIDTH_LOCAL),
            .WRITE_MODE_A("read_first")
        ) xpm_memory_spram_inst (
            .douta(rdata),
            .addra(addr),
            .clka(clk),
            .dina(wdata_local),
            .ena(en),
            .injectdbiterra(1'b0),
            .injectsbiterra(1'b0),
            .sbiterra(sbiterra),
            .dbiterra(dbiterra), 
            .regcea(1'b0),
            .rsta(1'b0),
            .sleep(1'b0),
            .wea(we_local)
        );
    end
    else begin
`endif
        logic `ARRAY(BYTES, WIDTH / BYTES) data `N(DEPTH);

        logic `N(ADDR_WIDTH) resetAddr;
        logic [BYTES-1: 0][WIDTH/BYTES-1: 0] resetData;
        logic `N(ADDR_WIDTH+1) counter;
        logic resetState;
        if(RESET)begin
            assign resetAddr = resetState ? counter : addr;
            assign resetData = resetState ? 0 : wdata;
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
            assign resetAddr = addr;
            assign resetData = wdata;
            assign resetState = 0;
            assign ready = 1'b1;
        end
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

        for(genvar j=0; j<BYTES; j++)begin
            always_ff @(posedge clk)begin
                if(we[j] | resetState)begin
                    data[resetAddr][j] <= resetData[j];
                end
            end
        end
`ifdef SYNTH_VIVADO
    end
endgenerate
`endif

`ifdef REPORT_RAM
    initial begin
        $display("0r0w1rw_%0dx%0d_%0d %m", WIDTH, DEPTH, WIDTH / BYTES);
    end
`endif
endmodule

module SDPRAM#(
    parameter WIDTH = 32,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    parameter INIT_VALUE = 0,
    parameter READ_LATENCY = 0,
    parameter BYTE_WRITE = 0,
    parameter RESET = 0,
    parameter BYTES = BYTE_WRITE == 1 ? WIDTH / 8 : 1
)(
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(ADDR_WIDTH) addr0,
    input logic `N(ADDR_WIDTH) addr1,
    input logic [BYTES-1: 0] we,
    input logic `ARRAY(BYTES, WIDTH / BYTES) wdata,
    output logic `N(WIDTH) rdata1,
    output logic ready
);

generate
`ifdef SYNTH_VIVADO
    if(1)begin
        localparam BYTE_WRITE_WIDTH = BYTES == 1 ? WIDTH : 8;
        localparam WIDTH_LOCAL = WIDTH + BYTES * ((WIDTH/BYTES) % BYTE_WRITE_WIDTH);
        localparam BYTES_LOCAL = WIDTH_LOCAL / BYTE_WRITE_WIDTH;
        localparam DELTA = BYTES_LOCAL / BYTES;
        logic [BYTES_LOCAL-1: 0] we_local;
        logic [BYTES_LOCAL-1: 0][BYTE_WRITE_WIDTH-1: 0] wdata_local;
        for(genvar i=0; i<BYTES; i++)begin
            assign we_local[i*DELTA +: DELTA] = {DELTA{we[i]}};
            assign wdata_local[i*DELTA +: DELTA] = wdata[i];
        end
        assign ready = 1'b1;
        
        wire dbiterrb, sbiterrb;
        xpm_memory_sdpram #(
            .ADDR_WIDTH_A(ADDR_WIDTH),
            .ADDR_WIDTH_B(ADDR_WIDTH),
            .AUTO_SLEEP_TIME(0),
            .BYTE_WRITE_WIDTH_A(BYTE_WRITE_WIDTH),
            .CASCADE_HEIGHT(0),
            .ECC_MODE("no_ecc"),
            .MEMORY_INIT_FILE("none"),
            .MEMORY_INIT_PARAM("0"),
            .MEMORY_OPTIMIZATION("true"),
            .MEMORY_PRIMITIVE("auto"),
            .MEMORY_SIZE(WIDTH_LOCAL * DEPTH),
            .MESSAGE_CONTROL(0),
            .READ_DATA_WIDTH_B(WIDTH_LOCAL),
            .READ_LATENCY_B(READ_LATENCY),
            .READ_RESET_VALUE_B("0"),
            .RST_MODE_A("SYNC"),
            .RST_MODE_B("SYNC"),
            .SIM_ASSERT_CHK(0),
            .USE_MEM_INIT(1),
            .WAKEUP_TIME("disable_sleep"),
            .WRITE_DATA_WIDTH_A(WIDTH_LOCAL),
            .WRITE_MODE_B("read_first")
        )
        xpm_memory_sdpram_inst (
            .doutb(rdata1),
            .addra(addr0),
            .addrb(addr1),
            .clka(clk),
            .clkb(clk),
            .dina(wdata_local),
            .ena(|we_local),
            .enb(en),
            .injectdbiterra(1'b0),
            .injectsbiterra(1'b0),
            .sbiterrb(sbiterrb),
            .dbiterrb(dbiterrb), 
            .regceb(1'b0),
            .rstb(1'b0),
            .sleep(1'b0),
            .wea(we_local)
        );
    end
    else begin
`endif
        logic `ARRAY(BYTES, WIDTH / BYTES) data `N(DEPTH);

        logic `N(ADDR_WIDTH) resetAddr;
        logic [BYTES-1: 0][WIDTH/BYTES-1: 0] resetData;
        logic `N(ADDR_WIDTH+1) counter;
        logic resetState;
        if(RESET)begin
            assign resetAddr = resetState ? counter : addr0;
            assign resetData = resetState ? 0 : wdata;
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
            assign resetAddr = addr0;
            assign resetData = wdata;
            assign resetState = 0;
            assign ready = 1'b1;
        end

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

        always_ff @(posedge clk or posedge rst)begin
            for(int i=0; i<BYTES; i++)begin
                if(we[i] | resetState)begin
                    data[resetAddr][i] <= resetData[i];
                end
            end
        end
`ifdef SYNTH_VIVADO
    end
`endif
endgenerate
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
generate
    if(RW_PORT == 1 && READ_PORT == 0 && WRITE_PORT == 0)begin
        SPRAM #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH),
            .READ_LATENCY(READ_LATENCY),
            .BYTE_WRITE(BYTE_WRITE),
            .BYTES(BYTES),
            .RESET(RESET)
        ) spram (
            .*,
            .addr(waddr)
        );
    end
    else if(RW_PORT == 0 && READ_PORT == 1 && WRITE_PORT == 1)begin
        SDPRAM #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH),
            .READ_LATENCY(READ_LATENCY),
            .BYTE_WRITE(BYTE_WRITE),
            .BYTES(BYTES),
            .RESET(RESET)
        ) sdpram (
            .*,
            .addr0(waddr),
            .addr1(raddr),
            .rdata1(rdata)
        );
    end
`ifdef SYNTH_VIVADO
    else if(RW_PORT == 1 && READ_PORT == 1 && WRITE_PORT == 0 && BYTE_WRITE == 0)begin
        xpm_memory_dpdistram #(
            .ADDR_WIDTH_A(ADDR_WIDTH),               // DECIMAL
            .ADDR_WIDTH_B(ADDR_WIDTH),               // DECIMAL
            .BYTE_WRITE_WIDTH_A(WIDTH),        // DECIMAL
            .CLOCKING_MODE("common_clock"), // String
            .MEMORY_INIT_FILE(""),      // String
            .MEMORY_INIT_PARAM("0"),        // String
            .MEMORY_OPTIMIZATION("true"),   // String
            .MEMORY_SIZE(WIDTH * DEPTH),             // DECIMAL
            .MESSAGE_CONTROL(0),            // DECIMAL
            .READ_DATA_WIDTH_A(WIDTH),         // DECIMAL
            .READ_DATA_WIDTH_B(WIDTH),         // DECIMAL
            .READ_LATENCY_A(READ_LATENCY),             // DECIMAL
            .READ_LATENCY_B(READ_LATENCY),             // DECIMAL
            .READ_RESET_VALUE_A("0"),       // String
            .READ_RESET_VALUE_B("0"),       // String
            .RST_MODE_A("SYNC"),            // String
            .RST_MODE_B("SYNC"),            // String
            .SIM_ASSERT_CHK(0),
            .USE_EMBEDDED_CONSTRAINT(0),    // DECIMAL
            .USE_MEM_INIT(1),               // DECIMAL
            .WRITE_DATA_WIDTH_A(WIDTH)         // DECIMAL
        )
        xpm_memory_dpdistram_inst (
            .douta(rdata[1]),
            .doutb(rdata[0]),
            .addra(waddr),
            .addrb(raddr),
            .clka(clk),
            .clkb(clk),
            .dina(wdata),
            .ena(en[1] | (|we)),
            .enb(en[0]),
            .regcea(0),
            .regceb(0),
            .rsta(1'b0),
            .rstb(1'b0),
            .wea(we)
        );
    end
`endif
    else begin
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
    end
endgenerate


`ifdef REPORT_RAM
    initial begin
        $display("%0dr%0dw%0drw_%0dx%0d_%0d %m", READ_PORT, WRITE_PORT, RW_PORT, WIDTH, DEPTH, WIDTH / BYTES);
    end
`endif
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