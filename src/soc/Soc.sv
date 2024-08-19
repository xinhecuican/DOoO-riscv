`include "../defines/defines.svh"

module Soc(
    input logic clk,
    input logic rst
);
    AxiIO core_axi();
    CPUCore core(.*, .axi(core_axi.master));
endmodule