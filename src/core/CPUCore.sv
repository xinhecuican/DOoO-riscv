
`include "../defines/defines.svh"

module CPUCore (
    input logic clk,
    input logic rst,

    AxiIO.master axi
);

    ICacheAxi.cache icache_io;
    IfuBackendIO.ifu ifu_backend_io;
    FsqBackendIO.backend fsq_back_io;
    CommitBus commitBus;

    IFU ifu(.*, .axi_io(icache_io));
    Backend backend(.*);
    AxiInterface axi_interface(.*);
endmodule
