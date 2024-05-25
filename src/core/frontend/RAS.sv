`include "../../defines/defines.svh"

module RAS(
    input logic clk,
    input logic rst,
    BpuRASIO.ras ras_io
);
    logic `N(`RAS_WIDTH) top, top_p1, top_n1;
    logic `N(`RAS_WIDTH) waddr;
    RasEntry entry, updateEntry;
    RasType squashType;
    logic we;

    assign top_p1 = top - 1;
    assign top_n1 = top + 1;
    assign waddr = ras_io.squash && squashType == POP_PUSH ? ras_io.squashInfo.redirectInfo.rasIdx - 1 :
                   ras_io.squash ? ras_io.squashInfo.redirectInfo.rasIdx :
                   ras_io.ras_type == POP_PUSH ? top_p1 : top;
    assign updateEntry.pc = ras_io.squash ? ras_io.squashInfo.target_pc : ras_io.target;
    assign squashType = ras_io.squashInfo.ras_type;
    assign we = ~ras_io.squash & ras_io.ras_type[1] | ras_io.squash & squashType[1];
    assign ras_io.rasIdx = top;
    assign ras_io.entry = entry;
    SDPRAM #(
        .WIDTH($bits(RasEntry)),
        .DEPTH(`RAS_SIZE)
    ) ras (
        .clk(clk),
        .rst(rst),
        .en(1'b1),
        .we(we),
        .addr0(waddr),
        .addr1(top_p1),
        .wdata(updateEntry),
        .rdata1(entry)
    );

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            top <= 0;
        end
        else begin
            if(ras_io.squash)begin
                if(squashType == POP)begin
                    top <= ras_io.squashInfo.redirectInfo.rasIdx - 1;
                end
                else if(ras_io.ras_type == PUSH)begin
                    top <= ras_io.squashInfo.redirectInfo.rasIdx + 1;
                end
                else begin
                    top <= ras_io.squashInfo.redirectInfo.rasIdx;
                end
            end
            if(ras_io.en)begin
                if(ras_io.ras_type == POP)begin
                    top <= top_p1;
                end
                else if(ras_io.ras_type == PUSH)begin
                    top <= top_n1;
                end
            end
        end
    end

endmodule