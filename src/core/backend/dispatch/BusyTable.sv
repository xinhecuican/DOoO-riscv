`include "../../../defines/defines.svh"

module BusyTable(
    input logic clk,
    input logic rst,
    BusyTable.busytable io
);
    logic `N(`PREG_SIZE) valid;
    logic `ARRAY(`FETCH_WIDTH, `PREG_SIZE) dis_valids;
    logic `N(`PREG_SIZE) dis_valid;

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign dis_valids[i] = (((`PREG_SIZE'b1 << io.dis_rd[i])) & {`PREG_SIZE{io.dis_en[i]}});
        assign io.rs1_en[i] = valid[io.rs1[i]];
        assign io.rs2_en[i] = valid[io.rs2[i]];
    end
    assign dis_valid = |dis_valids;
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            valid <= (1 << `PREG_SIZE) - 1;
        end
        else begin
            valid <= valid & ~dis_valid;
        end
    end
endmodule