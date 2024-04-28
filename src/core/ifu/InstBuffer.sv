`include "../../defines/defines.svh"

module InstBuffer (
    input logic clk,
    input logic rst,
    PreDecodeIBufferIO.instbuffer pd_ibuffer_io,
    IBufferDecodeIO.instbuffer ibuffer_decode_io,
    output logic full
);
    typedef struct {
        logic we;
        logic `N(`INST_BUFFER_BANK_WIDTH) rindex;
        logic `N(`INST_BUFFER_BANK_WIDTH) windex;
        logic `DATA_BUS wdata;
        logic `DATA_BUS rdata;
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

    assign data_valid_shift = pd_ibuffer_io.en << current_bank;
    assign inst_buffer_we = data_valid_shift[`INST_BUFFER_BANK_NUM-1: 0] | 
                            data_valid_shift[`INST_BUFFER_BANK_NUM*2-1: `INST_BUFFER_BANK_NUM];
    assign outNum = inst_num >= `FETCH_WIDTH ? `FETCH_WIDTH : inst_num;
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
            InstBufferBank u_InstBufferBank(
                .clk   (clk   ),
                .rst   (rst   ),
                .we    (ibuf[i].we    ),
                .din   (ibuf[i].din   ),
                .waddr (ibuf[i].windex ),
                .raddr (ibuf[i].rindex ),
                .dout  (ibuf[i].rdata  )
            );
        end
        for(genvar j=0; j<`INST_BUFFER_BANK_NUM; j++)begin
            assign ibuf[j].we = inst_buffer_we[j];
        end
        for(genvar i=0; i<`FETCH_WIDTH; i++)begin
            assign ibuffer_decode_io.inst[i] = ibuf[head+i].rdata;
        end
    endgenerate
    assign ibuffer_decode_io.en = out_en_compose;


    always_ff @(posedge clk) begin
        if(rst == `RST)begin
            for(int i=0; i<`INST_BUFFER_BANK_SIZE; i++)begin
                ibuf[i].we <= 0;
                ibuf[i].rindex <= 0;
                ibuf[i].wdata <= 0;
            end
            current_bank <= 0;
            inst_num <= 0;
        end 
        else begin
            // enqueue
            inst_num <= inst_num + pd_ibuffer_io.num - outNum;
            if(inst_num != 0)begin
                head <= head + outNum;
                for(int i=0; i<`INST_BUFFER_BANK_NUM; i++)begin
                    ibuf[i].rindex <= ibuf[i].rindex + inst_buffer_re[i];
                end
            end
            if(pd_ibuffer_io.en[0])begin
                tail <= pd_ibuffer_io.num;
                for(int i=0; i<`INST_BUFFER_BANK_NUM; i++)begin
                    ibuf[i].windex <= ibuf[i].windex + inst_buffer_we[i];
                end
            end
        end
    end

endmodule

module InstBufferBank(
    input logic clk,
    input logic rst,
    input logic we,
    input logic `DATA_BUS din,
    input logic `N(`INST_BUFFER_BANK_WIDTH) waddr,
    input logic `N(`INST_BUFFER_BANK_WIDTH) raddr,
    output logic `DATA_BUS dout
);
    logic `DATA_BUS ram `N(`INST_BUFFER_BANK_SIZE);
    
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
