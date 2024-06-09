`include "../../defines/defines.svh"

// only support 4-way
module PLRU#(
    parameter DEPTH = 256,
    parameter WAY_NUM = 4,
    parameter READ_PORT = 1,
    parameter WAY_WIDTH = $clog2(WAY_NUM),
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst,
    ReplaceIO.replace replace_io
);
    logic `N(WAY_NUM-1) plru `N(DEPTH);
    logic `N(WAY_NUM-1) rdata `N(READ_PORT);
    logic `N(WAY_NUM-1) updateData `N(READ_PORT);

generate
    for(genvar i=0; i<READ_PORT; i++)begin
        assign rdata[i] = plru[replace_io.hit_index[i]];
        PLRUUpdate #(WAY_NUM) update (rdata[i], replace_io.hit_way[i], updateData[i]);
    end
endgenerate

    logic `N(WAY_NUM-1) replaceData;
    logic `N(WAY_WIDTH) replaceOut;
    assign replaceData = plru[replace_io.miss_index];
    PLRUReplace #(WAY_NUM) replace (replaceData, replaceOut);
    always_ff @(posedge clk)begin
        replace_io.miss_way <= replaceOut;
    end


    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            plru <= '{default: 0};
        end
        else begin
            for(int i=0; i<READ_PORT; i++)begin
                if(replace_io.hit_en[i])begin
                    plru[replace_io.hit_index[i]] <= updateData[i];
                end
            end
        end
    end


endmodule

module PLRUUpdate #(
    parameter WAY_NUM = 1,
    parameter WAY_WIDTH = $clog2(WAY_NUM)
)(
    input logic `N(WAY_NUM-1) rdata,
    input logic `N(WAY_WIDTH) hit_way,
    output logic `N(WAY_NUM-1) out
);
generate
    if(WAY_NUM == 4)begin
        always_comb begin
            case (hit_way)
                2'b00: out = {rdata[2:1], 1'b1};
                2'b01: out = {rdata[2], 1'b1, rdata[0]};
                2'b10: out = {1'b1, rdata[1:0]};
                2'b11: out = {1'b0, rdata[1:0]};
            endcase
        end
    end
    else if (WAY_NUM == 8) begin
        always_comb begin
            case (hit_way)
                3'b000: out = {rdata[6:3], 1'b1, rdata[2:1], 1'b1};
                3'b001: out = {rdata[6:3], 1'b1, rdata[2:1], 1'b0};
                3'b010: out = {rdata[6:3], 1'b0, rdata[2:1], 1'b1};
                3'b011: out = {rdata[6:3], 1'b0, rdata[2:1], 1'b0};
                3'b100: out = {rdata[6:5], 1'b1, rdata[4:3], 1'b1, rdata[2:0]};
                3'b101: out = {rdata[6:5], 1'b1, rdata[4:3], 1'b0, rdata[2:0]};
                3'b110: out = {rdata[6:5], 1'b0, rdata[4:3], 1'b1, rdata[2:0]};
                3'b111: out = {rdata[6:5], 1'b0, rdata[4:3], 1'b0, rdata[2:0]};
            endcase
        end
    end
    else begin
        $warning("plru way unfit");
        assign out = rdata;
    end
endgenerate
endmodule

module PLRUReplace #(
    parameter WAY_NUM = 1,
    parameter WAY_WIDTH = $clog2(WAY_NUM)
)(
    input logic `N(WAY_NUM-1) rdata,
    output logic `N(WAY_WIDTH) out
);
generate
    if(WAY_NUM == 4)begin
        always_comb begin
        case (rdata)
            3'b000: out = 2'b00;
            3'b001: out = 2'b01;
            3'b010: out = 2'b10;
            3'b011: out = 2'b11;
            3'b100: out = 2'b00;
            3'b101: out = 2'b01;
            3'b110: out = 2'b10;
            3'b111: out = 2'b11;
        endcase
        end
    end
    else if (WAY_NUM == 8) begin
        always_comb begin
            case (rdata)
                7'b0000000, 7'b0000001, 7'b0000010, 7'b0000011, 7'b0000100, 7'b0000101, 7'b0000110, 7'b0000111: out = 3'b000;
                7'b0001000, 7'b0001001, 7'b0001010, 7'b0001011, 7'b0001100, 7'b0001101, 7'b0001110, 7'b0001111: out = 3'b001;
                7'b0010000, 7'b0010001, 7'b0010010, 7'b0010011, 7'b0010100, 7'b0010101, 7'b0010110, 7'b0010111: out = 3'b010;
                7'b0011000, 7'b0011001, 7'b0011010, 7'b0011011, 7'b0011100, 7'b0011101, 7'b0011110, 7'b0011111: out = 3'b011;
                7'b0100000, 7'b0100001, 7'b0100010, 7'b0100011, 7'b0100100, 7'b0100101, 7'b0100110, 7'b0100111: out = 3'b100;
                7'b0101000, 7'b0101001, 7'b0101010, 7'b0101011, 7'b0101100, 7'b0101101, 7'b0101110, 7'b0101111: out = 3'b101;
                7'b0110000, 7'b0110001, 7'b0110010, 7'b0110011, 7'b0110100, 7'b0110101, 7'b0110110, 7'b0110111: out = 3'b110;
                7'b0111000, 7'b0111001, 7'b0111010, 7'b0111011, 7'b0111100, 7'b0111101, 7'b0111110, 7'b0111111: out = 3'b111;
                default: out = 3'b000;
            endcase
        end
    end
    else begin
        assign out = 0;
    end
endgenerate
endmodule