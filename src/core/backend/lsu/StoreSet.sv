`include "../../../defines/defines.svh"

module StoreSet(
    input logic clk,
    input logic rst,
    StoreSetIO.ss io,
    input BackendCtrl backendCtrl
);

    SSITEntry `N(`FETCH_WIDTH) ssit_entrys;
    logic ssit_we;
    logic `N(2) ssit_wmask;
    logic `ARRAY(2, `SSIT_WIDTH) ssit_waddr;
    SSITEntry  ssit_wdata;
    logic lfst_inc;
    logic `N(`LFST_WIDTH) lfst_counter, ssit_wcounter;
    logic `N(`SSIT_RESET_WIDTH) rst_counter;
    logic ssit_rst;

    always_ff @(posedge clk)begin
        ssit_we <= io.ssit_we;
        ssit_waddr <= io.ssit_widx;
    end
    always_comb begin
        // store load
        case({ssit_entrys[1].en, ssit_entrys[0].en})
        2'b00: begin
            ssit_wmask = 2'b11;
            ssit_wcounter = lfst_counter;
            lfst_inc = 1'b1;
        end
        2'b01: begin
            ssit_wmask = 2'b01;
            ssit_wcounter = ssit_entrys[0].idx;
            lfst_inc = 1'b0;
        end
        2'b10: begin
            ssit_wmask = 2'b10;
            ssit_wcounter = ssit_entrys[1].idx;
            lfst_inc = 1'b0;
        end
        2'b11: begin
            ssit_wmask = 2'b11;
            ssit_wcounter = ssit_entrys[0].idx < ssit_entrys[1].idx ? ssit_entrys[0].idx : ssit_entrys[1].idx;
            lfst_inc = 1'b0;
        end
        endcase
    end
    assign ssit_wdata.en = 1'b1;
    assign ssit_wdata.idx = ssit_wcounter;
    assign io.ssit_entrys = ssit_entrys;
    MPRAM #(
        .WIDTH($bits(SSITEntry)),
        .DEPTH(`SSIT_SIZE),
        .READ_PORT(`FETCH_WIDTH),
        .WRITE_PORT(2),
        .READ_LATENCY(1),
        .BANK_SIZE(`SSIT_SIZE / 4)
    ) ssit (
        .clk,
        .rst,
        .rst_sync(ssit_rst),
        .en(io.en | io.ssit_we),
        .raddr((|io.ssit_we ? io.ssit_widx : io.raddr)),
        .rdata(ssit_entrys),
        .we({2{ssit_we}} & ssit_wmask),
        .waddr(ssit_waddr),
        .wdata({2{ssit_wdata}}),
        .ready()
    );

    logic `N(`LFST_SIZE) lfst_en;
    RobIdx `N(`LFST_SIZE) lfst_idx;
    RobIdx `N(`STORE_PIPELINE) lfst_finish_idx;
    logic `ARRAY(`FETCH_WIDTH, `LFST_SIZE) lfst_we_mask;
    logic `ARRAY(`STORE_PIPELINE, `LFST_SIZE) lfst_finish_mask;
    logic `N(`LFST_SIZE) lfst_we_valid, lfst_finish_valid;
    logic `N(`STORE_PIPELINE) lfst_finish_eq;

generate
    for(genvar i=0; i<`LOAD_PIPELINE; i++)begin
        logic `N(`STORE_PIPELINE) lfst_rw_conflict;
        assign io.lfst_en[i] = lfst_en[io.lfst_raddr[i]] & ~(|lfst_rw_conflict);
        assign io.lfst_idx[i] = lfst_idx[io.lfst_raddr[i]];
        for(genvar j=0; j<`STORE_PIPELINE; j++)begin
            assign lfst_rw_conflict[j] = io.lfst_finish[j] & lfst_finish_eq[j] & (io.lfst_raddr[i] == io.lfst_finish_waddr[j]);
        end
    end
    for(genvar i=0; i<`STORE_PIPELINE; i++)begin
        assign lfst_finish_idx[i] = lfst_idx[io.lfst_finish_waddr[i]];

        logic `N(`LFST_SIZE) lfst_finish_dec;
        assign lfst_finish_eq[i] = io.lfst_finish_idx[i] == lfst_finish_idx[i];
        Decoder #(`LFST_SIZE) decoder_finish(io.lfst_finish_waddr[i], lfst_finish_dec);
        assign lfst_finish_mask[i] = lfst_finish_dec & {`LFST_SIZE{io.lfst_finish[i] & lfst_finish_eq[i]}};
    end
    for(genvar i=0; i<`FETCH_WIDTH; i++)begin
        logic `N(`LFST_SIZE) lfst_waddr_dec;
        Decoder #(`LFST_SIZE) decoder_waddr(io.lfst_waddr[i], lfst_waddr_dec);
        assign lfst_we_mask[i] = lfst_waddr_dec & {`LFST_SIZE{io.lfst_we[i]}};
    end
    ParallelOR #(`LFST_SIZE, `FETCH_WIDTH) or_lfst_we (lfst_we_mask, lfst_we_valid);
    ParallelOR #(`LFST_SIZE, `STORE_PIPELINE) or_lfst_finish (lfst_finish_mask, lfst_finish_valid);
endgenerate

    always_ff @(posedge clk)begin
        for(int i=0; i<`FETCH_WIDTH; i++)begin
            if(io.lfst_we[i])begin
                lfst_idx[io.lfst_waddr[i]] <= io.lfst_widx[i];
            end
        end
    end

    always_ff @(posedge clk, negedge rst)begin
        if(rst == `RST)begin
            lfst_en <= 0;
            lfst_counter <= 0;
            rst_counter <= 0;
            ssit_rst <= 1'b0;
        end
        else begin
            lfst_en <= (lfst_en | lfst_we_valid) & ~lfst_finish_valid & {`LFST_SIZE{~backendCtrl.redirect}};
            if(lfst_inc & ssit_we) begin
                lfst_counter <= lfst_counter + 1;
            end
            if(ssit_we & (|{ssit_entrys[1].en, ssit_entrys[0].en}))begin
                rst_counter <= rst_counter + 1;
            end
            ssit_rst <= ssit_we & (|{ssit_entrys[1].en, ssit_entrys[0].en}) & (|rst_counter);
        end
    end
endmodule