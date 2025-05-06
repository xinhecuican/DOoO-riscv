`include "../src/defines/global.svh"



    class RandomSelector #(
        parameter DEPTH = 16,
        parameter DATA_WIDTH = 4,
        parameter READ_PORT = 1,
        parameter WRITE_PORT = 1
    );
        typedef virtual FreeBankIO #(DEPTH, DATA_WIDTH, READ_PORT, WRITE_PORT) vif_t;
        vif_t vif_dut;
        vif_t vif_ref;
        rand logic en, we;
        rand logic [$clog2(READ_PORT): 0] rdNum;
        rand logic [$clog2(WRITE_PORT): 0] wrNum;
        int free_idxs[$];
        logic [WRITE_PORT-1: 0][DATA_WIDTH-1: 0] w_idxs;
        int insert_loc;

        constraint rd_range {
            rdNum <= vif_ref.remain_count;
            rdNum <= READ_PORT;
        }

        constraint wr_range {
            wrNum <= DEPTH - vif_ref.remain_count;
            wrNum <= WRITE_PORT;
        }

        function new(vif_t vif_dut, vif_t vif_ref);
            this.vif_dut = vif_dut;
            this.vif_ref = vif_ref;
            vif_dut.en = 1'b0;
            vif_dut.we = 1'b0;
            vif_ref.en = 1'b0;
            vif_ref.we = 1'b0;
        endfunction

        function sample();
            for(int i=0; i<WRITE_PORT; i++)begin
                if(we && (i < wrNum))begin
                    w_idxs[i] = free_idxs.pop_back();
                end
            end

            for(int i=0; i<READ_PORT; i++)begin
                if(en && (i < rdNum))begin
                    insert_loc = {$random} % free_idxs.size();
                    free_idxs.insert(insert_loc, vif_dut.r_idxs[i]);
                end
            end
            vif_dut.en = en;
            vif_dut.we = we;
            vif_dut.rdNum = rdNum;
            vif_dut.wrNum = wrNum;
            vif_dut.w_idxs = w_idxs;
            vif_ref.en = en;
            vif_ref.we = we;
            vif_ref.rdNum = rdNum;
            vif_ref.wrNum = wrNum;
            vif_ref.w_idxs = w_idxs;
        endfunction
    endclass

module FreeBank_tb();
    parameter DEPTH = 16;
    parameter DATA_WIDTH = 4;
    parameter READ_PORT = 4;
    parameter WRITE_PORT = 2;

    logic clk, rst;
    FreeBankIO #(        
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .READ_PORT(READ_PORT),
        .WRITE_PORT(WRITE_PORT)
    ) dut_io();
    FreeBankIO #(        
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .READ_PORT(READ_PORT),
        .WRITE_PORT(WRITE_PORT)
    ) ref_io();

    FreeBank #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .READ_PORT(READ_PORT),
        .WRITE_PORT(WRITE_PORT)
    ) dut (.*, .io(dut_io));

    FreeBank_ref #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .READ_PORT(READ_PORT),
        .WRITE_PORT(WRITE_PORT)
    ) freeBank_ref (.*, .io(ref_io));

    initial begin
`ifdef DUMP_VPD
        $vcdpluson();
`endif
    end

    test #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH),
        .READ_PORT(READ_PORT),
        .WRITE_PORT(WRITE_PORT)
    ) test_inst(.*);

endmodule

program automatic test #(
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 4,
    parameter READ_PORT = 1,
    parameter WRITE_PORT = 1
)(
    output logic clk,
    output logic rst
);
    typedef virtual FreeBankIO #(DEPTH, DATA_WIDTH, READ_PORT, WRITE_PORT) vif_t;
    vif_t dut_io = FreeBank_tb.dut_io;
    vif_t ref_io = FreeBank_tb.ref_io;
    RandomSelector #(DEPTH, DATA_WIDTH, READ_PORT, WRITE_PORT) s = new(dut_io, ref_io);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 0;
        #10;
        rst = 1;
        #15;
        repeat(100)begin
            s.randomize();
            #1;
            s.sample();
            #9;
        end
        $finish;
    end
endprogram

module FreeBank_ref #(
    parameter DEPTH = 16,
    parameter DATA_WIDTH = 4,
    parameter READ_PORT = 1,
    parameter WRITE_PORT = 1
)(
    input logic clk,
    input logic rst,
    FreeBankIO.io io
);
    logic `ARRAY(DEPTH, DATA_WIDTH) freelist;
    logic `N($clog2(DEPTH)) head, tail;

generate
    for(genvar i=0; i<READ_PORT; i++)begin
        assign io.r_idxs[i] = freelist[head + i];
    end
endgenerate

    always_ff @(posedge clk, negedge rst)begin
        if(~rst)begin
            for(int i=0; i<DEPTH; i++)begin
                freelist[i] <= i;
            end
            head <= 0;
            tail <= 0;
            io.remain_count <= DEPTH;
        end
        else begin
            if(io.en)begin
                head <= head + io.rdNum;
            end
            if(io.we)begin
                for(int i=0; i<WRITE_PORT; i++)begin
                    freelist[tail+i] <= io.w_idxs[i];
                end
                tail <= tail + io.wrNum;
            end
            io.remain_count <= io.remain_count - (io.en ? io.rdNum : 0) + (io.we ? io.wrNum : 0);
        end
    end
endmodule