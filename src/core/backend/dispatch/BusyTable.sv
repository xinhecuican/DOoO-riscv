`include "../../../defines/defines.svh"

interface BusyTableIO #(
    parameter PORT_NUM = 4
);
    logic `N(`FETCH_WIDTH) dis_en;
    logic `ARRAY(`FETCH_WIDTH, `PREG_WIDTH) dis_rd;
    logic `ARRAY(PORT_NUM, `PREG_WIDTH) preg;
    logic `N(PORT_NUM) reg_en;

    modport busytable(input dis_en, dis_rd, preg, output reg_en);
endinterface

module BusyTable #(
    parameter WAKEUP_NUM = 4,
    parameter PORT_NUM = 4,
    parameter PREG_SIZE = 128,
    parameter FPV = 0
)(
    input logic clk,
    input logic rst,
    BusyTableIO.busytable io,
    WakeupBus.in wakeupBus,
    input CommitWalk commitWalk,
    input BackendCtrl backendCtrl
);
    logic `N(PREG_SIZE) valid;

    logic `ARRAY(WAKEUP_NUM, PREG_SIZE) wb_valids;
    logic `N(PREG_SIZE) wb_valid, wb_valid_combine;
generate
    for(genvar i=0; i<WAKEUP_NUM; i++)begin
        logic `N(PREG_SIZE) rd_decode;
        Decoder #(PREG_SIZE) decoder_rd (wakeupBus.rd[i], rd_decode);
        assign wb_valids[i] = (rd_decode & {PREG_SIZE{wakeupBus.en[i] & (wakeupBus.we[i])}});
    end
    ParallelOR #(PREG_SIZE, WAKEUP_NUM) or_wb_valid (wb_valids, wb_valid);
    assign wb_valid_combine = valid | wb_valid;
endgenerate

    logic `ARRAY(`FETCH_WIDTH, PREG_SIZE) dis_valids;
    logic `N(PREG_SIZE) dis_valid;
generate
    for(genvar i=0; i<PORT_NUM; i++)begin
        assign io.reg_en[i] = wb_valid_combine[io.preg[i]];
    end

    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N(PREG_SIZE) rd_decode;
        Decoder #(PREG_SIZE) decoder_rd (io.dis_rd[i], rd_decode);
        assign dis_valids[i] = (rd_decode & {PREG_SIZE{io.dis_en[i] & ~backendCtrl.redirect}});
    end
    ParallelOR #(PREG_SIZE, `FETCH_WIDTH) or_dis_valid (dis_valids, dis_valid);
endgenerate

    logic `ARRAY(`WALK_WIDTH, PREG_SIZE) walk_valids;
    logic `N(PREG_SIZE) walk_valid;
generate
    for(genvar i=0; i<`WALK_WIDTH; i++)begin
        logic `N(PREG_SIZE) rd_decode;
        Decoder #(PREG_SIZE) decoder_rd (commitWalk.prd[i], rd_decode);
        if(FPV)begin
            assign walk_valids[i] = rd_decode & {PREG_SIZE{commitWalk.walk & commitWalk.en[i] & commitWalk.fp_we[i]}};
        end
        else begin
            assign walk_valids[i] = (rd_decode & {PREG_SIZE{commitWalk.walk & commitWalk.en[i]
                                    & commitWalk.we[i] & ~commitWalk.fp_we[i]}});
        end
    end
    ParallelOR #(PREG_SIZE, `WALK_WIDTH) or_walk_valid (walk_valids, walk_valid);
endgenerate

    always_ff @(posedge clk or negedge rst)begin
        if(rst == `RST)begin
            valid <= {PREG_SIZE{1'b1}};
        end
        else begin
            valid <= (wb_valid_combine | walk_valid) & ~dis_valid;
        end
    end
endmodule