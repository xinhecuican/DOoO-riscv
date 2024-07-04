`include "../../defines/defines.svh"

module InstBuffer (
    input logic clk,
    input logic rst,
    input logic stall,
    PreDecodeIBufferIO.instbuffer pd_ibuffer_io,
    FrontendCtrl frontendCtrl,
    output FetchBundle fetchBundle,
    output logic full
);
    typedef struct packed {
        logic iam;
        FsqIdxInfo fsqInfo;
        logic [31: 0] inst;
    } IBufData;

    typedef struct packed{
        logic we;
        logic `N(`IBUF_BANK_WIDTH) rindex;
        logic `N(`IBUF_BANK_WIDTH) windex;
        IBufData wdata;
        IBufData rdata;
    } IBufCtrl;

    /* verilator lint_off UNOPTFLAT */
    IBufCtrl ibuf `N(`IBUF_BANK_NUM);
    logic [$clog2(`IBUF_SIZE): 0] inst_num;
    logic [`IBUF_BANK_NUM*2-1: 0] data_valid_shift;
    logic `N(`IBUF_BANK_NUM) inst_buffer_we;
    logic `N($clog2(`IBUF_SIZE)) head, tail;
    logic `N($clog2(`FETCH_WIDTH)+1) outNum;
    logic `N(`IBUF_BANK_NUM*2) out_en_shift;
    logic `N(`IBUF_BANK_NUM) inst_buffer_re;
    logic `N(`FETCH_WIDTH) out_en_compose;
    IBufData `N(`BLOCK_INST_SIZE) in_data;

    assign data_valid_shift = pd_ibuffer_io.en << tail[$clog2(`IBUF_BANK_NUM)-1: 0];
    assign inst_buffer_we = (data_valid_shift[`IBUF_BANK_NUM-1: 0] | 
                            data_valid_shift[`IBUF_BANK_NUM*2-1: `IBUF_BANK_NUM]) &
                            {`IBUF_BANK_NUM{~full}};
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
        for(genvar i=0; i<`IBUF_BANK_NUM; i++)begin
            InstBufferBank #($bits(IBufData)) u_InstBufferBank(
                .clk   (clk   ),
                .rst   (rst   ),
                .we    (inst_buffer_we[i]    ),
                .din   (ibuf[i].wdata   ),
                .waddr (ibuf[i].windex ),
                .raddr (ibuf[i].rindex ),
                .dout  (ibuf[i].rdata  )
            );
        end
        for(genvar j=0; j<`IBUF_BANK_NUM; j++)begin
            logic `N($clog2(`IBUF_BANK_NUM)) writeIdx, offset;
            assign writeIdx = j - tail[$clog2(`IBUF_BANK_NUM)-1: 0];
            assign offset = j + pd_ibuffer_io.shiftIdx;
            assign ibuf[j].we = inst_buffer_we[j];
            assign in_data[j] = '{iam: pd_ibuffer_io.iam, 
                                  fsqInfo: '{idx: pd_ibuffer_io.fsqIdx, offset: offset}, 
                                  inst: pd_ibuffer_io.inst[j]};
            assign ibuf[j].wdata = in_data[writeIdx];
        end
        for(genvar i=0; i<`FETCH_WIDTH; i++)begin
            logic `N($clog2(`IBUF_BANK_NUM)) readIdx;
            assign readIdx = head[$clog2(`IBUF_BANK_NUM)-1: 0] + i;
            assign fetchBundle.fsqInfo[i] = ibuf[readIdx].rdata.fsqInfo;
            assign fetchBundle.inst[i] = ibuf[readIdx].rdata.inst;
            assign fetchBundle.iam[i] = ibuf[readIdx].rdata.iam;
        end
    endgenerate
    assign fetchBundle.en = out_en_compose;
    assign full = inst_num + pd_ibuffer_io.num > `IBUF_SIZE;

    always_ff @(posedge clk or posedge rst) begin
        if(rst == `RST || frontendCtrl.redirect)begin
            for(int i=0; i<`IBUF_BANK_NUM; i++)begin
                ibuf[i].rindex <= 0;
                ibuf[i].windex <= 0;
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
                    ibuf[i].windex <= ibuf[i].windex + inst_buffer_we[i];
                end
            end
        end
    end

endmodule

module InstBufferBank #(
    parameter WIDTH = 32
)(
    input logic clk,
    input logic rst,
    input logic we,
    input logic `N(WIDTH) din,
    input logic `N(`IBUF_BANK_WIDTH) waddr,
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
            if(we)begin
                ram[waddr] <= din;
            end
        end
    end
endmodule
