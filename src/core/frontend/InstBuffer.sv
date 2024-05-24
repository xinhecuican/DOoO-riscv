`include "../../defines/defines.svh"

module InstBuffer (
    input logic clk,
    input logic rst,
    input logic stall,
    PreDecodeIBufferIO.instbuffer pd_ibuffer_io,
    FrontendCtrl fontendCtrl,
    output FetchBundle fetchBundle,
    output logic full
);
    typedef struct packed {
        FsqIdxInfo fsqInfo;
        logic [31: 0] inst;
    } IBufData;

    typedef struct {
        logic we;
        logic `N(`INST_BUFFER_BANK_WIDTH) rindex;
        logic `N(`INST_BUFFER_BANK_WIDTH) windex;
        IBufData wdata;
        IBufData rdata;
    } IBufCtrl;

    IBufCtrl ibuf `N(`INST_BUFFER_BANK_NUM);
    logic `N(`INST_BUFFER_BANK_WIDTH) current_bank;
    logic [$clog2(`INST_BUFFER_SIZE): 0] inst_num;
    logic [`INST_BUFFER_BANK_NUM*2-1: 0] data_valid_shift;
    logic `N(`INST_BUFFER_BANK_NUM) inst_buffer_we;
    logic `N($clog2(`INST_BUFFER_SIZE)) head, tail;
    logic `N($clog2(`FETCH_WIDTH)) outNum;
    logic `N(`INST_BUFFER_BANK_NUM*2) out_en_shift;
    logic `N(`INST_BUFFER_BANK_NUM) inst_buffer_re;
    logic `N(`FETCH_WIDTH) out_en_compose;

    assign data_valid_shift = pd_ibuffer_io.en << tail[`INST_BUFFER_BANK_WIDTH-1: 0];
    assign inst_buffer_we = data_valid_shift[`INST_BUFFER_BANK_NUM-1: 0] | 
                            data_valid_shift[`INST_BUFFER_BANK_NUM*2-1: `INST_BUFFER_BANK_NUM];
    assign outNum = stall ? 0 : inst_num >= `FETCH_WIDTH ? `FETCH_WIDTH : inst_num;
    always_comb begin
        out_en_compose[0] = |inst_num;
        out_en_compose[1] = |inst_num[$clog2(`INST_BUFFER_SIZE): 1];
        out_en_compose[2] = |inst_num[$clog2(`INST_BUFFER_SIZE): 2] & (inst_num[0] & inst_num[1]);
        out_en_compose[3] = |inst_num[$clog2(`INST_BUFFER_SIZE): 2];
    end
    assign out_en_shift = out_en_compose << head[`INST_BUFFER_BANK_WIDTH-1: 0];
    assign inst_buffer_re = out_en_shift[`INST_BUFFER_BANK_NUM-1: 0] |
                            out_en_shift[`INST_BUFFER_BANK_NUM * 2 - 1: `INST_BUFFER_BANK_NUM];
    generate;
        for(genvar i=0; i<`INST_BUFFER_BANK_NUM; i++)begin
            InstBufferBank #($bits(IBufData)) u_InstBufferBank(
                .clk   (clk   ),
                .rst   (rst   ),
                .we    (ibuf[i].we    ),
                .din   (ibuf[i].wdata   ),
                .waddr (ibuf[i].windex ),
                .raddr (ibuf[i].rindex ),
                .dout  (ibuf[i].rdata  )
            );
        end
        for(genvar j=0; j<`INST_BUFFER_BANK_NUM; j++)begin
            logic `N(`INST_BUFFER_BANK_WIDTH) writeIdx;
            assign writeIdx = tail[`INST_BUFFER_BANK_WIDTH-1: 0] + j;
            assign ibuf[j].we = inst_buffer_we[j];
            assign ibuf[j].wdata = '{fsqInfo: '{idx: pd_ibuffer_io.fsqIdx, offset: j}, inst: pd_ibuffer_io.inst[writeIdx]};
        end
        for(genvar i=0; i<`FETCH_WIDTH; i++)begin
            logic `N(`INST_BUFFER_BANK_WIDTH) readIdx;
            assign readIdx = head[`INST_BUFFER_BANK_WIDTH-1: 0] + i;
            assign fetchBundle.fsqInfo[i] = ibuf[readIdx].rdata.fsqInfo;
            assign fetchBundle.inst[i] = ibuf[readIdx].rdata.inst;
        end
    endgenerate
    assign fetchBundle.en = out_en_compose;
    assign full = inst_num == `INST_BUFFER_SIZE;

    always_ff @(posedge clk) begin
        if(rst == `RST || frontendCtrl.redirect)begin
            for(int i=0; i<`INST_BUFFER_BANK_SIZE; i++)begin
                ibuf[i].we <= 0;
                ibuf[i].rindex <= 0;

            end
            inst_num <= 0;
        end 
        else begin
            // enqueue
            inst_num <= inst_num + pd_ibuffer_io.num - outNum;
            if(inst_num != 0 && !stall)begin
                head <= head + outNum;
                for(int i=0; i<`INST_BUFFER_BANK_NUM; i++)begin
                    ibuf[i].rindex <= ibuf[i].rindex + inst_buffer_re[i];
                end
            end
            if(pd_ibuffer_io.en[0])begin
                tail <= tail + pd_ibuffer_io.num;
                for(int i=0; i<`INST_BUFFER_BANK_NUM; i++)begin
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
    input logic `N(`INST_BUFFER_BANK_WIDTH) waddr,
    input logic `N(`INST_BUFFER_BANK_WIDTH) raddr,
    output logic `N(WIDTH) dout
);
    logic `N(WIDTH) ram `N(`INST_BUFFER_BANK_SIZE);
    
    assign dout = ram[raddr];
    always_ff @(posedge clk)begin
        if(rst == `RST)begin
            for(int i=0; i<`INST_BUFFER_BANK_SIZE; i++)begin
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
