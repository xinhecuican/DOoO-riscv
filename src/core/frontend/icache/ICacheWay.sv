`include "../../../defines/defines.svh"

interface ICacheWayIO;
    logic `N(`ICACHE_BANK) en;
    logic tagv_en;
    logic tagv_we;
    logic span; //request span one line
    logic `N(`ICACHE_SET_WIDTH) tagv_index;
    logic `N(`ICACHE_SET_WIDTH) tagv_windex;
    logic `ARRAY(2,(`ICACHE_TAG+1)) tagv;
    logic `N(`ICACHE_TAG+1) tagv_wdata;
    logic `N(`ICACHE_BANK * `ICACHE_SET_WIDTH) index;
    logic `N(`ICACHE_BANK) we;
    logic `ARRAY(`ICACHE_BANK, `ICACHE_SET_WIDTH) windex;
    logic `ARRAY(`ICACHE_BANK, 32) data;
    logic `ARRAY(`ICACHE_BANK, 32) wdata;
    modport way(input en, tagv_en, tagv_we, span, tagv_index, tagv_windex, tagv_wdata, index, we, windex, wdata, output tagv, data);
endinterface

module ICacheWay(
    input logic clk,
    input logic rst,
    ICacheWayIO.way io
);
    logic `N(`ICACHE_SET_WIDTH) tagv_index_p1;
    logic `N(`ICACHE_TAG+1) tagv `N(`ICACHE_SET);

    assign tagv_index_p1 = io.tagv_index + 1;
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            tagv <= '{default: 0};
        end
        else begin
            if(io.tagv_en)begin
                io.tagv[0] <= tagv[io.tagv_index];
                // if(io.span)begin
                    io.tagv[1] <= tagv[tagv_index_p1];
                // end
            end

            if(io.tagv_we)begin
                tagv[io.tagv_windex] <= io.tagv_wdata;
            end
        end
    end

    generate;
        for(genvar i=0; i<`ICACHE_BANK; i++)begin
            MPRAM #(
                .WIDTH(32),
                .DEPTH(`ICACHE_SET),
                .READ_PORT(1),
                .WRITE_PORT(1)
            ) bank(
                .clk(clk),
                .rst(rst),
                .en(io.en[i]),
                .waddr(io.windex[i]),
                .raddr(io.index[i*`ICACHE_SET_WIDTH+: `ICACHE_SET_WIDTH]),
                .we(io.we[i]),
                .wdata(io.wdata[i]),
                .rdata(io.data[i]),
                .ready()
            );
        end
    endgenerate
endmodule