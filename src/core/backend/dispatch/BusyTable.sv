`include "../../../defines/defines.svh"

interface BusyTableIO;
    logic `N(`FETCH_WIDTH) dis_en;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) dis_rd;

    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rs1;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) rs2;
    logic `N(`FETCH_WIDTH) rs1_en;
    logic `N(`FETCH_WIDTH) rs2_en;

    modport busytable(input dis_en, dis_rd, rs1, rs2, output rs1_en, rs2_en);
endinterface

module BusyTable(
    input logic clk,
    input logic rst,
    BusyTableIO.busytable io,
    WriteBackBus wbBus,
    CommitBus commitBus,
    CommitWalk commitWalk,
    BackendCtrl backendCtrl
);
    logic `N(`PREG_SIZE) valid;


    logic `ARRAY(`FETCH_WIDTH, `PREG_SIZE) dis_valids;
    logic `N(`PREG_SIZE) dis_valid;
generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N(`PREG_SIZE) rd_decode;
        Decoder #(`PREG_SIZE) decoder_rd (io.dis_rd[i], rd_decode);
        assign dis_valids[i] = (rd_decode & {`PREG_SIZE{io.dis_en[i] & ~backendCtrl.redirect}});
        assign io.rs1_en[i] = valid[io.rs1[i]];
        assign io.rs2_en[i] = valid[io.rs2[i]];
    end
    assign dis_valid = |dis_valids;
endgenerate

    logic `ARRAY(`WB_SIZE, `PREG_SIZE) wb_valids;
    logic `N(`PREG_SIZE) wb_valid;
generate
    for(genvar i=0; i<`WB_SIZE; i++)begin
        logic `N(`PREG_SIZE) rd_decode;
        Decoder #(`PREG_SIZE) decoder_rd (wbBus.rd[i], rd_decode);
        assign wb_valids[i] = (rd_decode & {`PREG_SIZE{wbBus.en[i] & (wbBus.rd[i] != 0)}});
    end
    assign wb_valid = |wb_valids;
endgenerate

    logic `ARRAY(`WB_SIZE, `PREG_SIZE) walk_valids;
    logic `N(`PREG_SIZE) walk_valid;
generate
    for(genvar i=0; i<`COMMIT_WIDTH; i++)begin
        logic `N(`PREG_SIZE) rd_decode;
        Decoder #(`PREG_SIZE) decoder_rd (commitWalk.prd[i], rd_decode);
        assign walk_valids[i] = (rd_decode & {`PREG_SIZE{commitWalk.walk & commitWalk.we[i]}});
    end
    assign walk_valid = |walk_valids;
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            valid <= {`PREG_SIZE{1'b1}};
        end
        else begin
            valid <= (valid | wb_valid | walk_valid) & ~dis_valid;
        end
    end
endmodule