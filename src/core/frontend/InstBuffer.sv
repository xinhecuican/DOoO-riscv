`include "../../defines/defines.svh"

module InstBuffer (
    input logic clk,
    input logic rst,
    input logic stall,
    PreDecodeIBufferIO.instbuffer pd_ibuffer_io,
    input FrontendCtrl frontendCtrl,
    output FetchBundle fetchBundle,
    output logic full
);
    localparam WPORT = `BLOCK_INST_SIZE / `IBUF_BANK_NUM;
    typedef struct packed {
        logic iam;
        logic ipf;
        FsqIdxInfo fsqInfo;
        logic [31: 0] inst;
    } IBufData;

    typedef struct packed{
        logic `N(WPORT) we;
        logic `N(`IBUF_BANK_WIDTH) rindex;
        logic `ARRAY(WPORT, `IBUF_BANK_WIDTH) windex;
        IBufData `N(WPORT) wdata;
        IBufData rdata;
    } IBufCtrl;

    /* verilator lint_off UNOPTFLAT */
    IBufCtrl ibuf `N(`IBUF_BANK_NUM);
    logic [$clog2(`IBUF_SIZE): 0] inst_num;
    logic [`BLOCK_INST_SIZE+`IBUF_BANK_SIZE-1: 0] data_valid_shift;
    logic `ARRAY(WPORT, `IBUF_BANK_NUM) inst_buffer_we;
    logic `ARRAY(`IBUF_BANK_NUM, WPORT) inst_buffer_we_reverse;
    logic `ARRAY(`IBUF_BANK_NUM, $clog2(WPORT)+1) ibuf_we_num;
    logic `N($clog2(`IBUF_SIZE)) head, tail;
    logic `N($clog2(`FETCH_WIDTH)+1) outNum;
    logic `N(`IBUF_BANK_NUM*2) out_en_shift;
    logic `N(`IBUF_BANK_NUM) inst_buffer_re;
    logic `N(`FETCH_WIDTH) out_en_compose;
    IBufData `N(`BLOCK_INST_SIZE) in_data;
    IBufData `ARRAY(WPORT, `IBUF_BANK_NUM) in_data_w;

generate
    for(genvar i=0; i<WPORT; i++)begin
        logic `ARRAY(2, `IBUF_BANK_NUM) data_valid_shift;
        assign data_valid_shift = pd_ibuffer_io.en[i * `IBUF_BANK_NUM +: `IBUF_BANK_NUM] << tail[$clog2(`IBUF_BANK_NUM)-1: 0];
        assign inst_buffer_we[i] = (data_valid_shift[0] | data_valid_shift[1]) & {`IBUF_BANK_NUM{~full}};
    end
endgenerate
    assign outNum = stall ? 0 : inst_num >= `FETCH_WIDTH ? `FETCH_WIDTH : inst_num;
    always_comb begin
        out_en_compose[0] = |inst_num;
        out_en_compose[1] = |inst_num[$clog2(`IBUF_SIZE): 1];
        out_en_compose[2] = (|inst_num[$clog2(`IBUF_SIZE): 2]) | (inst_num[0] & inst_num[1]);
        out_en_compose[3] = |inst_num[$clog2(`IBUF_SIZE): 2];
    end
    assign out_en_shift = out_en_compose << head[$clog2(`IBUF_BANK_NUM)-1: 0];
    assign inst_buffer_re = out_en_shift[`IBUF_BANK_NUM-1: 0] |
                            out_en_shift[`IBUF_BANK_NUM * 2 - 1: `IBUF_BANK_NUM];
generate;
    for(genvar i=0; i<`BLOCK_INST_SIZE; i++)begin
        assign in_data[i] = '{iam: pd_ibuffer_io.iam, 
                                ipf: pd_ibuffer_io.ipf[i],
                                fsqInfo: '{idx: pd_ibuffer_io.fsqIdx, offset: pd_ibuffer_io.offset[i]
`ifdef RVC
                                , size: i+pd_ibuffer_io.shiftIdx
`endif
                                }, 
                                inst: pd_ibuffer_io.inst[i]};
    end
    assign in_data_w = in_data;

    for(genvar i=0; i<`IBUF_BANK_NUM; i++)begin
        InstBufferBank #($bits(IBufData)) u_InstBufferBank(
            .clk   (clk   ),
            .rst   (rst   ),
            .we    (ibuf[i].we     ),
            .din   (ibuf[i].wdata  ),
            .waddr (ibuf[i].windex ),
            .raddr (ibuf[i].rindex ),
            .dout  (ibuf[i].rdata  )
        );
        logic `N($clog2(`IBUF_BANK_NUM)) writeIdx;
        assign writeIdx = i - tail[$clog2(`IBUF_BANK_NUM)-1: 0];
        for(genvar j=0; j<WPORT; j++)begin
            assign ibuf[i].wdata[j] = in_data_w[j][writeIdx];
            assign ibuf[i].we[j] = inst_buffer_we[j][i];
            assign inst_buffer_we_reverse[i][j] = inst_buffer_we[j][i];
        end
        ParallelAdder #(1, WPORT) adder_we_num (inst_buffer_we_reverse[i], ibuf_we_num[i]);
    end

    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N($clog2(`IBUF_BANK_NUM)) readIdx;
        assign readIdx = head[$clog2(`IBUF_BANK_NUM)-1: 0] + i;
        assign fetchBundle.fsqInfo[i] = ibuf[readIdx].rdata.fsqInfo;
        assign fetchBundle.inst[i] = ibuf[readIdx].rdata.inst;
        assign fetchBundle.iam[i] = ibuf[readIdx].rdata.iam;
        assign fetchBundle.ipf[i] = ibuf[readIdx].rdata.ipf;
    end
endgenerate
    assign fetchBundle.en = out_en_compose;
    assign full = inst_num + pd_ibuffer_io.num > `IBUF_SIZE;

    always_ff @(posedge clk or posedge rst) begin
        if(rst == `RST)begin
            for(int i=0; i<`IBUF_BANK_NUM; i++)begin
                ibuf[i].rindex <= 0;
                for(int j=0; j<WPORT; j++)begin
                    ibuf[i].windex[j] <= j;
                end
            end
            inst_num <= 0;
            head <= 0;
            tail <= 0;
        end
        else if(frontendCtrl.redirect)begin
            for(int i=0; i<`IBUF_BANK_NUM; i++)begin
                ibuf[i].rindex <= 0;
                for(int j=0; j<WPORT; j++)begin
                    ibuf[i].windex[j] <= j;
                end
            end
            inst_num <= 0;
            head <= 0;
            tail <= 0;
        end
        else begin
            // enqueue
            inst_num <= inst_num + ({$clog2(`BLOCK_INST_SIZE)+1{~full & pd_ibuffer_io.en[0]}} & pd_ibuffer_io.num) - ({$clog2(`FETCH_WIDTH)+1{~stall}} & outNum);
            if(inst_num != 0 && !stall)begin
                head <= head + outNum;
                for(int i=0; i<`IBUF_BANK_NUM; i++)begin
                    ibuf[i].rindex <= ibuf[i].rindex + inst_buffer_re[i];
                end
            end
            if(pd_ibuffer_io.en[0] & ~full)begin
                tail <= tail + pd_ibuffer_io.num;
                for(int i=0; i<`IBUF_BANK_NUM; i++)begin
                    for(int j=0; j<WPORT; j++)begin
                        ibuf[i].windex[j] <= ibuf[i].windex[j] + ibuf_we_num[i];
                    end
                end
            end
        end
    end

endmodule

module InstBufferBank #(
    parameter WIDTH = 32,
    parameter WPORT = `BLOCK_INST_SIZE / `IBUF_BANK_NUM
)(
    input logic clk,
    input logic rst,
    input logic `N(WPORT) we,
    input logic `ARRAY(WPORT, WIDTH) din,
    input logic `ARRAY(WPORT, `IBUF_BANK_WIDTH) waddr,
    input logic `N(`IBUF_BANK_WIDTH) raddr,
    output logic `N(WIDTH) dout
);
    logic `N(WIDTH) ram `N(`IBUF_BANK_SIZE);
    
    assign dout = ram[raddr];
    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            for(int i=0; i<`IBUF_BANK_SIZE; i++)begin
                ram[i] <= 0;
            end
        end
        else begin
            for(int i=0; i<WPORT; i++)begin
                if(we[i])begin
                    ram[waddr[i]] <= din[i];
                end
            end
        end
    end
endmodule
