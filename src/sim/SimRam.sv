`include "../defines/defines.svh"
module SimRam(
    input logic clk,
    input logic rst,
    AxiIO.slave axi
);
    logic [63: 0] rIdx, wIdx, rIdx_n;
    logic [63: 0] rdata;
    logic [63: 0] wmask;
    logic [7: 0] arlen;
    logic [7: 0] arsize, arsize_n;
    logic [3: 0] rsize;
    logic [7: 0] rshift, rshift_n;

    logic [7: 0] awlen;
    logic [7: 0] awsize;
    logic [3: 0] wsize;
    logic [7: 0] wshift;

    assign wmask =  {
`ifdef SV64
                    {8{axi.mw.strb[7]}},
                    {8{axi.mw.strb[6]}},
                    {8{axi.mw.strb[5]}},
                    {8{axi.mw.strb[4]}},
`endif
                    {8{axi.mw.strb[3]}},
                    {8{axi.mw.strb[2]}},
                    {8{axi.mw.strb[1]}},
                    {8{axi.mw.strb[0]}}};
    assign rIdx_n = axi.ar_valid && axi.ar_ready ? (axi.mar.addr & 32'h7fffffff) >> 3 :
                    axi.r_valid & axi.r_ready & (rsize <= arsize) ? rIdx + 1 : rIdx;
    always_comb begin
        if(axi.r_valid & axi.r_ready)begin
            if(rsize <= arsize)begin
                rshift_n = 0;
            end
            else begin
                rshift_n = rshift + (8 * arsize);
            end
        end
        else begin
            rshift_n = rshift;
        end
        case(axi.mar.size)
        3'b000: arsize_n = 1;
        3'b001: arsize_n = 2;
        3'b010: arsize_n = 4;
        3'b011: arsize_n = 8;
        3'b100: arsize_n = 16;
        3'b101: arsize_n = 32;
        3'b110: arsize_n = 64;
        3'b111: arsize_n = 128;
        endcase
    end
    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            axi.ar_ready <= 1'b1;
            axi.r_valid <= 1'b0;
            axi.sr.id <= 0;
            axi.sr.data <= 0;
            axi.sr.last <= 0;
            axi.sr.resp <= 0;
            axi.aw_ready <= 1'b1;
            axi.w_ready <= 1'b1;
            axi.sb.id <= 0;
            axi.sb.resp <= 0;
            axi.b_valid <= 1'b0;
            rIdx <= 0;
            wIdx <= 0;
            rsize <= 0;
            rshift <= 0;
            wsize <= 0;
            wshift <= 0;
        end
        else begin
            if(axi.ar_valid && axi.ar_ready)begin
                axi.ar_ready <= 1'b0;
                rIdx <= (axi.mar.addr & 32'h7fffffff) >> 3;
                if(axi.mar.burst == 0)begin
                    arlen <= 1;
                end
                else begin
                    arlen <= axi.mar.len + 1;
                end
                arsize <= arsize_n;
                axi.sr.id <= axi.mar.id;
                axi.sr.user <= axi.mar.user;
                axi.r_valid <= 1'b1;
                axi.sr.last <= axi.mar.len == 0;
                if(axi.mar.addr)
                rsize <= 8 - (arsize_n+axi.mar.addr[2: 0]);
                rshift <= 8 * ((axi.mar.addr[2: 0] + arsize_n) & 3'b111);
                axi.sr.data <= rdata >> (8 * (axi.mar.addr[2: 0]));
            end
            if(axi.r_valid & axi.r_ready)begin
                if(arlen == 2)begin
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
                axi.sr.data <= rdata >> rshift_n;
            end

            if(axi.sr.last && axi.r_valid && axi.r_ready)begin
                axi.sr.last <= 1'b0;
                axi.r_valid <= 1'b0;
                axi.ar_ready <= 1'b1;
            end

            if(axi.aw_valid && axi.aw_ready)begin
                wIdx <= (axi.maw.addr & 32'h7fffffff) >> 3;
                axi.aw_ready <= 1'b0;
                axi.w_ready <= 1'b1;
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

            if(axi.w_ready)begin
                if(axi.w_valid)begin
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
                if(axi.w_valid && axi.mw.last)begin
                    axi.w_ready <= 1'b0;
                    axi.b_valid <= 1'b1;
                end
            end

            if(axi.b_valid)begin
                axi.b_valid <= 1'b0;
                axi.aw_ready <= 1'b1;
            end
        end
    end

    RAMHelper ram(
        .clk(clk),
        .en(1'b1),
        .rIdx(rIdx_n),
        .rdata(rdata),
        .wIdx(wIdx),
        .wdata((axi.mw.data << wshift)),
        .wmask((wmask << wshift)),
        .wen(axi.w_valid)
    );
endmodule