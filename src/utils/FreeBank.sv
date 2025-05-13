
interface FreeBankIO #(
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 4,
    parameter READ_PORT = 1,
    parameter WRITE_PORT = 1
);
    logic en;
    logic [$clog2(READ_PORT): 0] rdNum;
    logic [READ_PORT-1: 0][DATA_WIDTH-1: 0] r_idxs;
    logic we;
    logic [$clog2(WRITE_PORT): 0] wrNum;
    logic [WRITE_PORT-1: 0][DATA_WIDTH-1: 0] w_idxs;
    logic [$clog2(DEPTH): 0] remain_count;

    modport io (input  en, rdNum, we, wrNum, w_idxs, output r_idxs, remain_count);

endinterface //FreelistIO

module FreeBank #(
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 4,
    parameter READ_PORT = 1,
    parameter WRITE_PORT = 1
)(
    input logic clk,
    input logic rst,
    FreeBankIO.io io
);
localparam SLICE_BASE_NUM = DEPTH / READ_PORT;
localparam SLICE_REMAIN_NUM = DEPTH % READ_PORT;
localparam OFFSET = $clog2(READ_PORT)**2 - READ_PORT;

    logic [$clog2(READ_PORT)-1: 0] slice_head, slice_tail;
    logic [$clog2(READ_PORT): 0] slice_head_n, slice_tail_n;
    logic [READ_PORT-1: 0] slice_en, slice_we;
    logic [READ_PORT: 0] rd_mask;
    logic [WRITE_PORT: 0] wr_mask;
    logic [READ_PORT-1: 0][DATA_WIDTH-1: 0] r_idxs;

    MaskGen #(READ_PORT+1) gen_rd_mask (io.rdNum, rd_mask);
    MaskGen #(WRITE_PORT+1) gen_wr_mask (io.wrNum, wr_mask);
    assign slice_en = {READ_PORT{io.en}} & rd_mask[READ_PORT-1: 0];
    assign slice_we = {READ_PORT{io.we}} & {{READ_PORT-WRITE_PORT{1'b0}}, wr_mask[WRITE_PORT-1: 0]};
generate
    for(genvar i=0; i<READ_PORT; i++)begin
        localparam SLICE_DEPTH = SLICE_BASE_NUM + (i < SLICE_REMAIN_NUM);
        logic [$clog2(READ_PORT)-1: 0] roffset, roffset_en, woffset;
        if((SLICE_BASE_NUM & (SLICE_BASE_NUM -1)) == 0)begin
            assign roffset_en = i - slice_head;
            assign roffset = slice_head + i;
            assign woffset = i - slice_tail;
        end
        else begin
            assign roffset_en = i < slice_head ? i - OFFSET - slice_head : i - slice_head;
            assign roffset = slice_head >= READ_PORT - i ? slice_head + i - READ_PORT : slice_head + i;
            assign woffset = i < slice_tail ? i - OFFSET - slice_tail : i - slice_tail;
        end
        FreelistSlice #(
            .DEPTH(SLICE_DEPTH),
            .DATA_WIDTH(DATA_WIDTH),
            .START(i),
            .INTERVAL(READ_PORT)
        ) slice (
            .clk(clk),
            .rst(rst),
            .en(slice_en[roffset_en]),
            .r_idx(r_idxs[i]),
            .we(slice_we[woffset]),
            .w_idx(io.w_idxs[woffset])
        );
        assign io.r_idxs[i] = r_idxs[roffset];
    end
    if((SLICE_BASE_NUM & (SLICE_BASE_NUM -1)) == 0)begin
        always_ff @(posedge clk, negedge rst)begin
            if(~rst)begin
                slice_head <= 0;
                slice_tail <= 0;
            end
            else begin
                if(io.en)begin
                    slice_head <= slice_head_n;
                end
                if(io.we)begin
                    slice_tail <= slice_tail_n;
                end
            end
        end
    end
    else begin
        always_ff @(posedge clk, negedge rst)begin
            if(~rst)begin
                slice_head <= 0;
                slice_tail <= 0;
            end
            else begin
                if(io.en)begin
                    slice_head <= slice_head_n < READ_PORT ? slice_head_n : slice_head_n - READ_PORT;
                end
                if(io.we)begin
                    slice_tail <= slice_tail_n < READ_PORT ? slice_tail_n : slice_tail_n - READ_PORT;
                end
            end
        end
    end
endgenerate

    assign slice_head_n = slice_head + io.rdNum;
    assign slice_tail_n = slice_tail + io.wrNum;

    always_ff @(posedge clk, negedge rst)begin
        if(~rst)begin
            io.remain_count <= DEPTH;
        end
        else begin
            io.remain_count <= io.remain_count - ({$clog2(READ_PORT)+1{io.en}} & io.rdNum) 
                                        + ({$clog2(WRITE_PORT)+1{io.we}} & io.wrNum);
        end
    end

endmodule

module FreelistSlice #(
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 4,
    parameter START = 0,
    parameter INTERVAL = 1
)(
    input logic clk,
    input logic rst,
    input logic en,
    output logic [DATA_WIDTH-1: 0] r_idx,
    input logic we,
    input logic [DATA_WIDTH-1: 0] w_idx
);
    logic [DATA_WIDTH-1: 0] freelist[DEPTH-1: 0];
generate
    for(genvar i=0; i<DEPTH; i++)begin
        if(i == 0)begin
            always_ff @(posedge clk, negedge rst)begin
                if(~rst)begin
                    freelist[i] <= START;
                end
                else begin
                    if(we)begin
                        freelist[0] <= w_idx;
                    end
                    else if(en)begin
                        freelist[0] <= freelist[1];
                    end
                end
            end
        end
        else if(i == DEPTH - 1)begin
            always_ff @(posedge clk, negedge rst)begin
                if(~rst)begin
                    freelist[i] <= START + i * INTERVAL;
                end
                else begin
                    if(we)begin
                        freelist[DEPTH-1] <= freelist[DEPTH-2];
                    end
                end
            end
        end
        else begin
            always_ff @(posedge clk, negedge rst)begin
                if(~rst)begin
                    freelist[i] <= START + i * INTERVAL;
                end
                else begin
                    if(en & ~we)begin
                        freelist[i] <= freelist[i+1];
                    end
                    else if(we & ~en)begin
                        freelist[i] <= freelist[i-1];
                    end
                end
            end
        end
    end
endgenerate
    assign r_idx = freelist[0];
endmodule