
`include "../defines/defines.svh"

module CPUCore (
    input logic clk,
    input logic rst,

    AxiIO.master axi
);

    ICacheAxi icache_io();
    DCacheAxi dcache_io();
    IfuBackendIO ifu_backend_io();
    FsqBackendIO fsq_back_io();
    CommitBus commitBus();

    IFU ifu(.*, .axi_io(icache_io));
    Backend backend(.*,
                    .commitBus_out(commitBus),
                    .axi_io(dcache_io));
    AxiInterface axi_interface(.*);
endmodule
