
module CalValidNum_tb();

localparam NUM = 4;
logic [NUM-1: 0] in;
logic [NUM-1: 0][$clog2(NUM)-1: 0] out, ref_out;

generate
    assign ref_out[0] = 0;
    for(genvar i=1; i<NUM; i++)begin
        assign ref_out[i] = $countbits(in[i-1: 0], '1);
    end
endgenerate

CalValidNum #(
    .NUM(NUM)
) cal_valid_num (
    .en(in),
    .out(out)
);

initial begin
    for(int i=0; i<NUM**2; i++)begin
        in = i;
        #10;
        if(out != ref_out)begin
            $display("error, in=%d", in);
            for(int j=0; j<NUM; j++)begin
                $display("out[%d]: %d, %d", j, out[j], ref_out[j]);
            end
            $finish;
        end
    end
    #10;
    $finish;
end
endmodule