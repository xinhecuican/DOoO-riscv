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
generate
    if(WAY_NUM == 1)begin
        assign replace_io.miss_way = 0;
    end
    else begin 
        logic `N(DEPTH * (WAY_NUM - 1)) plru;
        logic `N(WAY_NUM-1) rdata `N(READ_PORT);
        logic `N(WAY_NUM-1) updateData `N(READ_PORT);


        for(genvar i=0; i<READ_PORT; i++)begin
            assign rdata[i] = plru[replace_io.hit_index[i]*(WAY_NUM-1)+: (WAY_NUM-1)];
            PLRUUpdate #(WAY_NUM) update (rdata[i], replace_io.hit_way[i], updateData[i]);
        end


        logic `N(WAY_WIDTH) replaceOut;
        PLRUReplace #(WAY_NUM) replace (plru[replace_io.miss_index*(WAY_NUM-1)+: (WAY_NUM-1)], replaceOut);
        always_ff @(posedge clk)begin
            replace_io.miss_way <= replaceOut;
        end

        always_ff @(posedge clk or posedge rst)begin
            if(rst == `RST)begin
                plru <= 0;
            end
            else begin
                for(int i=0; i<READ_PORT; i++)begin
                    if(replace_io.hit_en[i])begin
                        plru[replace_io.hit_index[i]*(WAY_NUM-1)+: WAY_NUM-1] <= updateData[i];
                    end
                end
            end
        end
    end
endgenerate


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
                2'b00: out = {2'b11, rdata[0]};
                2'b01: out = {2'b01, rdata[0]};
                2'b10: out = {rdata[2], 2'b01};
                2'b11: out = {rdata[2], 2'b00};
            endcase
        end
    end
    else if (WAY_NUM == 8) begin
        always_comb begin
            case (hit_way)
                3'b000: out = {2'b11, rdata[5], 1'b1, rdata[2:0]};
                3'b001: out = {2'b01, rdata[5], 1'b1, rdata[2:0]};
                3'b010: out = {rdata[6], 3'b011, rdata[2:0]};
                3'b011: out = {rdata[6], 3'b001, rdata[2:0]};
                3'b100: out = {rdata[6: 4], 3'b011, rdata[0]};
                3'b101: out = {rdata[6: 4], 3'b010, rdata[0]};
                3'b110: out = {rdata[6: 4], 2'b00, rdata[1], 1'b1};
                3'b111: out = {rdata[6: 4], 2'b00, rdata[1], 1'b0};
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
            casez (rdata)
            3'b00?: out = 2'b00;
            3'b10?: out = 2'b01;
            3'b?10: out = 2'b10;
            3'b?11: out = 2'b11;
            default: out = 0;
            endcase
        end
    end
    else if (WAY_NUM == 8) begin
        always_comb begin
            casez (rdata)
                7'b00?0???: out = 0;
                7'b10?0???: out = 1;
                7'b?100???: out = 2;
                7'b?110???: out = 3;
                7'b???100?: out = 4;
                7'b???110?: out = 5;
                7'b???1?10: out = 6;
                7'b???1?11: out = 7;
                default: out    = 0;
            endcase
        end

    end
    else begin
        assign out = 0;
    end
endgenerate
endmodule