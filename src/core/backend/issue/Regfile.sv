`include "../../../defines/defines.svh"

module Regfile(
    input logic clk,
    input logic rst,
    RegfileIO.regfile io,
    WriteBackBus wbBus
`ifdef DIFFTEST
    ,DiffRAT.regfile diff_rat
`endif
);
    logic `ARRAY(`REGFILE_READ_PORT, `XLEN) rdata;
    MPRAM #(
        .WIDTH(`XLEN),
        .DEPTH(`PREG_SIZE),
        .READ_PORT(`REGFILE_READ_PORT),
        .WRITE_PORT(`REGFILE_WRITE_PORT),
        .RESET(1)
    ) ram (
        .clk(clk),
        .rst(rst),
        .en(io.en),
        .raddr(io.raddr),
        .rdata(rdata),
        .we(io.we),
        .waddr(io.waddr),
        .wdata(io.wdata),
        .ready()
    );
// bypass
generate
    for(genvar i=0; i<`REGFILE_READ_PORT; i++)begin
        logic `N(`WB_SIZE) eq;
        logic wb_valid;
        logic `N(`XLEN) data, wb_data;
        ParallelEQ #(
            .WIDTH(`PREG_WIDTH),
            .RADIX(`WB_SIZE),
            .DATA_WIDTH(`XLEN)
        ) parallel_eq_bypass(
            .origin(io.raddr[i]),
            .cmp_en(wbBus.en),
            .cmp(wbBus.rd),
            .data_i(wbBus.res),
            .eq(eq),
            .data_o(data)
        );
        always_ff @(posedge clk)begin
            wb_valid <= |eq;
            wb_data <= data;
        end
        assign io.rdata[i] = wb_valid ? wb_data : rdata[i];
    end
endgenerate
    
`ifdef DIFFTEST
    logic `N(`XLEN) data `N(`PREG_SIZE);
    logic `ARRAY(32, `XLEN) diff_data;
    always_ff @(posedge clk)begin
        for(int i=0; i<`REGFILE_WRITE_PORT; i++)begin
            if(io.we[i])begin
                data[io.waddr[i]] <= io.wdata[i];
            end
        end
    end

generate
    for(genvar i=0; i<32; i++)begin
        assign diff_data[i] = data[diff_rat.map_reg[i]];
    end
endgenerate

    DifftestArchIntRegState diff_int_reg(
        .clock(clk),
        .coreid(0),
        .gpr_0(diff_data[0]),
        .gpr_1(diff_data[1]),
        .gpr_2(diff_data[2]),
        .gpr_3(diff_data[3]),
        .gpr_4(diff_data[4]),
        .gpr_5(diff_data[5]),
        .gpr_6(diff_data[6]),
        .gpr_7(diff_data[7]),
        .gpr_8(diff_data[8]),
        .gpr_9(diff_data[9]),
        .gpr_10(diff_data[10]),
        .gpr_11(diff_data[11]),
        .gpr_12(diff_data[12]),
        .gpr_13(diff_data[13]),
        .gpr_14(diff_data[14]),
        .gpr_15(diff_data[15]),
        .gpr_16(diff_data[16]),
        .gpr_17(diff_data[17]),
        .gpr_18(diff_data[18]),
        .gpr_19(diff_data[19]),
        .gpr_20(diff_data[20]),
        .gpr_21(diff_data[21]),
        .gpr_22(diff_data[22]),
        .gpr_23(diff_data[23]),
        .gpr_24(diff_data[24]),
        .gpr_25(diff_data[25]),
        .gpr_26(diff_data[26]),
        .gpr_27(diff_data[27]),
        .gpr_28(diff_data[28]),
        .gpr_29(diff_data[29]),
        .gpr_30(diff_data[30]),
        .gpr_31(diff_data[31])
    );
`endif
endmodule