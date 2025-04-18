`include "../../../defines/defines.svh"
`include "../../../defines/fp_defines.svh"

typedef struct packed {
    ExStatusBundle status;
} FDivPipeInfo;

module FDivUnit(
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    IssueFDivIO.fdiv issue_fdiv_io,
    IssueWakeupIO.issue fdiv_wakeup_io,
    WriteBackIO.fu fdiv_wb_io,
    input BackendCtrl backendCtrl
);
    ExStatusBundle ex_status;
    FDivSlice #(FP32) slice (
        .clk,
        .rst,
        .round_mode(issue_fdiv_io.bundle[0].rm == 3'b111 ? round_mode : issue_fdiv_io.bundle[0].rm),
        .en(issue_fdiv_io.en),
        .div(issue_fdiv_io.bundle[0].div),
        .rs1_data(issue_fdiv_io.rs1_data),
        .rs2_data(issue_fdiv_io.rs2_data),
        .wakeup_ready(fdiv_wakeup_io.ready),
        .wb_ready(fdiv_wb_io.valid),
        .ex_status_i(issue_fdiv_io.status),
        .backendCtrl,
        .wakeup_en(fdiv_wakeup_io.en),
        .wakeup_rd(fdiv_wakeup_io.rd),
        .en_o(fdiv_wb_io.datas[0].en),
        .done(issue_fdiv_io.done),
        .res(fdiv_wb_io.datas[0].res),
        .ex_status_o(ex_status),
        .status(fdiv_wb_io.datas[0].exccode)
    );
    assign fdiv_wakeup_io.we = '1;
    assign fdiv_wb_io.datas[0].we = '1;
    assign fdiv_wb_io.datas[0].rd = ex_status.rd;
    assign fdiv_wb_io.datas[0].robIdx = ex_status.robIdx;
    assign fdiv_wb_io.datas[0].irq_enable = 1;
endmodule

module FDivSlice #(
    parameter logic [`FP_FORMAT_BITS-1:0] fp_fmt = 0
) (
    input logic clk,
    input logic rst,
    input roundmode_e round_mode,
    input logic en,
    input logic div,
    input logic `N(`XLEN) rs1_data,
    input logic `N(`XLEN) rs2_data,
    input logic wakeup_ready,
    input logic wb_ready,
    ExStatusBundle ex_status_i,
    input BackendCtrl backendCtrl,
    output logic wakeup_en,
    output logic `N(`PREG_WIDTH) wakeup_rd,
    output logic en_o,
    output logic done,
    output logic `N(`XLEN) res,
    output ExStatusBundle ex_status_o,
    output FFlags status
);
    typedef enum  { IDLE, WAIT, WB } State;
    localparam FP_WIDTH = fp_width(fp_fmt);
    State state;
    ExStatusBundle ex_status;
    logic input_older, output_older;
    logic div_start, sqrt_start;
    logic `N(64) div_res;
    FFlags div_fflags, fflags;
    logic div_ready, div_done;
    logic wakeup_valid, wb_valid;

    LoopCompare #(`ROB_WIDTH) cmp_input (ex_status_i.robIdx, backendCtrl.redirectIdx, input_older);
    LoopCompare #(`ROB_WIDTH) cmp_output (ex_status_o.robIdx, backendCtrl.redirectIdx, output_older);
    assign div_start = en & div & (~backendCtrl.redirect | input_older);
    assign sqrt_start = en & ~div & (~backendCtrl.redirect | input_older);
    div_sqrt_top_mvp div_sqrt (
        .Clk_CI(clk),
        .Rst_RBI(rst),
        .Div_start_SI(div_start),
        .Sqrt_start_SI(sqrt_start),
        .Operand_a_DI({32'b0, rs1_data}),
        .Operand_b_DI({32'b0, rs2_data}),
        .RM_SI({1'b0, round_mode[1: 0]}),
        .Precision_ctl_SI(6'b0),
        .Format_sel_SI(fp_fmt == FP32 ? 2'b00 : 2'b01),
        .Kill_SI(state == WAIT && (backendCtrl.redirect & ~output_older)),
        .Result_DO(div_res),
        .Fflags_SO(div_fflags),
        .Ready_SO(div_ready),
        .Done_SO(div_done)
    );
    
    assign done = wakeup_valid && wakeup_ready;
    assign ex_status_o = ex_status;
    assign wakeup_rd = ex_status.rd;
    always_ff @(posedge clk)begin
        if(div_done)begin
            res <= div_res[FP_WIDTH-1: 0];
            status <= div_fflags;
        end
    end
    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            state <= IDLE;
            ex_status <= 0;
            wakeup_en <= 0;
            en_o <= 0;
        end
        else begin
            case(state)
            IDLE: begin
                if(en & (~backendCtrl.redirect | input_older))begin
                    state <= WAIT;
                    ex_status <= ex_status_i;
                end
            end
            WAIT: begin
                if(backendCtrl.redirect & ~output_older)begin
                    state <= IDLE;
                end
                else if(div_done)begin
                    state <= WB;
                    wakeup_en <= 1'b1;
                    en_o <= 1'b1;
                end
            end
            WB: begin
                if(backendCtrl.redirect & ~output_older | wakeup_valid & wb_valid)begin
                    state <= IDLE;
                    wakeup_en <= 1'b0;
                    en_o <= 1'b0;
                    wakeup_valid <= 0;
                    wb_valid <= 0;
                end else begin
                    if(wakeup_en & wakeup_ready)begin
                        wakeup_valid <= 1'b1;
                        wakeup_en <= 1'b0;
                    end
                    if(en_o & wb_ready)begin
                        en_o <= 1'b0;
                        wb_valid <= 1'b1;
                    end
                end
            end
            endcase
        end
    end
endmodule