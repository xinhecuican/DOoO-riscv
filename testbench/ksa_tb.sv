
// iverilog -g2012 testbench/ksa_tb.sv src/utils/ksa.sv -s ksa_tb -o build/sim.out 
// vvp -n build/sim.out
module ksa_tb();
    localparam WIDTH = 39;
    logic [WIDTH-1: 0] a, b, sum, result;
    logic Co;

    initial begin
        $dumpfile("build/wave.vcd");
        $dumpvars(0, ksa_tb);
    end

    assign result = a + b;

    initial begin
        for(int i=0; i<10000; i++)begin
            a = $random;
            b = $random;
            #10;
            if(result != sum)begin
                $display("error");
                $finish;
            end
        end
        $finish;
    end

    KSA #(WIDTH) ksa (a, b, sum);
endmodule