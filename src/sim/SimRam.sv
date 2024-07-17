`include "../defines/defines.svh"
module SimRam(
    input logic clk,
    input logic rst,
    AxiIO.slave axi
);
    logic [63: 0] rIdx, wIdx;
    logic [63: 0] rdata;
    logic [63: 0] wmask;
    logic [7: 0] arlen;
    logic [7: 0] arsize;
    logic [3: 0] rsize;
    logic [7: 0] rshift;

    logic [7: 0] awlen;
    logic [7: 0] awsize;
    logic [3: 0] wsize;
    logic [7: 0] wshift;

    assign wmask = {{8{axi.mw.wstrb[7]}},
                    {8{axi.mw.wstrb[6]}},
                    {8{axi.mw.wstrb[5]}},
                    {8{axi.mw.wstrb[4]}},
                    {8{axi.mw.wstrb[3]}},
                    {8{axi.mw.wstrb[2]}},
                    {8{axi.mw.wstrb[1]}},
                    {8{axi.mw.wstrb[0]}}};
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            axi.sar.ready <= 1'b1;
            axi.sr.valid <= 1'b0;
            axi.sr.id <= 0;
            axi.sr.data <= 0;
            axi.sr.resp <= 0;
            axi.sr.last <= 0;
            axi.saw.ready <= 1'b1;
            axi.sw.ready <= 1'b1;
            axi.sb.id <= 0;
            axi.sb.resp <= 0;
            axi.sb.valid <= 1'b0;
            rIdx <= 0;
            wIdx <= 0;
            rsize <= 0;
            rshift <= 0;
            wsize <= 0;
            wshift <= 0;
        end
        else begin
            if(axi.mar.valid && axi.sar.ready)begin
                axi.sar.ready <= 1'b0;
                rIdx <= (axi.mar.addr & 32'h7fffffff) >> 3;
                if(axi.mar.burst == 0)begin
                    arlen <= 1;
                end
                else begin
                    arlen <= axi.mar.len + 1;
                end
                case(axi.mar.size)
                3'b000: arsize <= 1;
                3'b001: arsize <= 2;
                3'b010: arsize <= 4;
                3'b011: arsize <= 8;
                3'b100: arsize <= 16;
                3'b101: arsize <= 32;
                3'b110: arsize <= 64;
                3'b111: arsize <= 128;
                endcase
                axi.sr.id <= axi.mar.id;
                axi.sr.user <= axi.mar.user;
                rsize <= 8;
            end
            if(!axi.sar.ready)begin
                if(arlen == 1)begin
                    axi.sar.ready <= 1'b1;
                    axi.sr.last <= 1'b1;
                end
                if(rsize <= arsize)begin
                    rIdx <= rIdx + 1;
                    rshift <= 0;
                    rsize <= 8;
                end
                else begin
                    rsize <= rsize - arsize;
                    rshift <= rshift + (8 * arsize);
                end
                arlen <= arlen - 1;
                axi.sr.data <= (rdata >> rshift);
                axi.sr.valid <= 1'b1;
            end

            if(axi.sr.last && axi.sr.valid)begin
                axi.sr.last <= 1'b0;
                axi.sr.valid <= 1'b0;
            end

            if(axi.maw.valid && axi.saw.ready)begin
                wIdx <= (axi.maw.addr & 32'h7fffffff) >> 3;
                axi.saw.ready <= 1'b0;
                axi.sw.ready <= 1'b1;
                axi.sb.id <= axi.maw.id;
                case(axi.maw.size)
                3'b000: awsize <= 1;
                3'b001: awsize <= 2;
                3'b010: awsize <= 4;
                3'b011: awsize <= 8;
                3'b100: awsize <= 16;
                3'b101: awsize <= 32;
                3'b110: awsize <= 64;
                3'b111: awsize <= 128;
                endcase
                wsize <= 8;
            end

            if(axi.sw.ready)begin
                if(axi.mw.valid)begin
                    if(wsize <= awsize)begin
                        wIdx <= wIdx + 1;
                        wshift <= 0;
                        wsize <= 8;
                    end
                    else begin
                        wsize <= wsize - awsize;
                        wshift <= wshift + (8 * awsize);
                    end
                end
                if(axi.mw.valid && axi.mw.last)begin
                    axi.sw.ready <= 1'b0;
                    axi.sb.valid <= 1'b1;
                end
            end

            if(axi.sb.valid)begin
                axi.sb.valid <= 1'b0;
                axi.saw.ready <= 1'b1;
            end
        end
    end

    RAMHelper ram(
        .clk(clk),
        .en(1'b1),
        .rIdx(rIdx),
        .rdata(rdata),
        .wIdx(wIdx),
        .wdata((axi.mw.data << wshift)),
        .wmask((wmask << wshift)),
        .wen(axi.mw.valid)
    );
endmodule