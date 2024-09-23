`include "../../../../defines/defines.svh"

typedef struct packed {
    logic we;
    logic `N(`PADDR_SIZE) addr;
    logic `N(`DCACHE_WAY) way;
} DCacheDirectoryWReq;

module DCacheDirectory(
    input logic clk,
    input logic rst,
    input logic en,
    input logic `N(`PADDR_SIZE) addr,
    output logic hit,
    output logic `N(`DCACHE_TAG) hit_tag,
    input DCacheDirectoryWReq wreq
);
    logic `ARRAY(`DCACHE_WAY, `DCACHE_TAG) tags `N(`DCACHE_SET);
    
endmodule