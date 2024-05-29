`include "../../../defines/defines.svh"

// rename alias table

interface RATIO #(
    parameter READ_PORT = 4,
    parameter WRITE_PORT = 4
);
    logic `ARRAY(READ_PORT, 5) vreg;
    logic `ARRAY(READ_PORT, `PREG_WIDTH) preg;
    logic `N(WRITE_PORT) we;
    logic `ARRAY(WRITE_PORT, 5) waddr;
    logic `ARRAY(WRITE_PORT, `PREG_WIDTH) wdata;

    modport rat(input vreg, we, waddr, wdata, output preg);
    modport rename(output vreg, we, waddr, wdata, input preg);
endinterface

module RAT #(
    parameter READ_PORT = 4,
    parameter WRITE_PORT = 4
)(
    input logic clk,
    input logic rst,
    RATIO.rat rat_io
);

    logic `N(`PREG_WIDTH) rat `N(32);

generate;
    for(genvar i=0; i<READ_PORT; i++)begin
        assign rat_io.preg[i] = rat[rat_io.vreg[i]];
    end
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<32; i++)begin
                rat[i] <= i;
            end
        end
        else begin
            for(int i=0; i<WRITE_PORT; i++)begin
                if(rat_io.we[i])begin
                    rat[rat_io.waddr[i]] <= rat_io.wdata[i];
                end
            end
        end
    end

endmodule