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
    logic `ARRAY(WRITE_PORT, 32) waddr_dec;
    logic `ARRAY(32, WRITE_PORT) waddr_dec_rev; 

generate;
    for(genvar i=0; i<READ_PORT; i++)begin
        assign rat_io.preg[i] = rat[rat_io.vreg[i]];
    end
    for(genvar i=0; i<WRITE_PORT; i++)begin
        Decoder #(32) decoder_we(rat_io.waddr[i], waddr_dec[i]);
    end
    for(genvar i=0; i<32; i++)begin
        for(genvar j=0; j<WRITE_PORT; j++)begin
            assign waddr_dec_rev[i][j] = waddr_dec[j][i];
        end
        logic `N(`PREG_WIDTH) wdata, eq_wdata;
        logic we, eq_we;
        FairSelect #(WRITE_PORT, `PREG_WIDTH) select_wdata (waddr_dec_rev[i] & rat_io.we, rat_io.wdata, eq_we, eq_wdata);
        assign we = eq_we;
        assign wdata = eq_wdata;

        always_ff @(posedge clk or negedge rst)begin
            if(rst == `RST)begin
                rat[i] <= i;
            end
            else if(we)begin
                rat[i] <= wdata;
            end
        end
    end
endgenerate

endmodule