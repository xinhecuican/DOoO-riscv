`include "../../defines/defines.svh"

module ROB(
    input logic clk,
    input logic rst,
    RenameDisIO.dis dis_io
);

    typedef struct packed {
        logic wb;
    } RobStatus;

    typedef struct packed {
        logic `N(5) vrd;
        logic `N(`PREG_WIDTH) prd;
    } RobData;

    localparam ROB_BANK_SIZE = `ROB_SIZE / `FETCH_WIDTH;
    RobStatus status `N(`ROB_SIZE);
    logic `N(ROB_BANK_SIZE) valid `N(`FETCH_WIDTH);
    logic `N($clog2(ROB_BANK_SIZE)) dataWIdx `N(`FETCH_WIDTH);
    logic `N($clog2(ROB_BANK_SIZE)) dataRIdx `N(`FETCH_WIDTH);
    logic `N(`FETCH_WIDTH) data_en;
    logic `N(`ROB_WIDTH) head, tail;

    logic `N(`FETCH_WIDTH) dis_en;
    logic `N(`FETCH_WIDTH * 2) dis_en_shift;
    logic `N($clog2(`FETCH_WIDTH)) dis_validNum;

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N($clog2(`FETCH_WIDTH)) bank_widx;
        assign bank_widx = dis_io.robIdx[$clog2(`FETCH_WIDTH)-1: 0];
        SDPRAM #(
            .WIDTH($bits(RobData)),
            .DEPTH(ROB_BANK_SIZE)
        ) robData (
            .clk(clk),
            .rst(rst),
            .en(1'b1),
            .addr0(dataWIdx[i]),
            .addr1(dataRIdx[i]),
            .we(data_en[i]),
            .wdata({dis_io.op[bank_widx].di.rd, dis_io.prd[bank_widx]})
        );
    end
endgenerate

generate
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        assign dis_en[i] = dis_io.op[i].en;
    end
    assign dis_en_shift = dis_en << tail[$clog2(`FETCH_WIDTH)-1: 0];
    assign data_en = dis_en_shift[`FETCH_WIDTH-1: 0] | dis_en_shift[`FETCH_WIDTH * 2 - 1 : `FETCH_WIDTH];
    ParallelAdder #(1, `FETCH_WIDTH) adder_dis_valid (dis_en, dis_validNum);
endgenerate

    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            head <= 0;
            tail <= 0;
            status <= '{default: 0};
            dataWIdx <= '{default: 0};
            dataRIdx <= '{default: 0};
        end
        else begin
            if(dis_io.op[0].en)begin
                for(int i=0; i<`FETCH_WIDTH; i++)begin
                    dataWIdx[i] <= dataWIdx[i] + data_en[i];
                end
            end
        end
    end

endmodule