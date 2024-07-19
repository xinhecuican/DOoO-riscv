`ifndef __CORE_DEBUG_SVH
`define __CORE_DEBUG_SVH

`define ENABLE_LOG
`define T_LOG_ALL
`define T_FSQ
`define T_RAS

`define PERF(name, cond) \
`ifdef DIFFTEST \
    logic [31: 0] perf_counter_``name; \
    always_ff @(posedge clk or posedge rst) begin \
        if(rst == `RST)begin \
            perf_counter_``name <= 0; \
        end \
        else if(cond)begin \
            perf_counter_``name <= perf_counter_``name + 1; \
        end \
    end \
    DifftestLogEvent #(`"name`") log_event_``name (clk, 0, perf_counter_``name); \
`endif \

package DLog;
    typedef enum logic [1: 0] { Debug, Info, Warning, Error} LogLevel;
    logic logValid = 1'b0;
    logic [63: 0] cycleCnt;
    parameter [7: 0] logLevel = Debug;

endpackage

`define Log(level, tag=T_LOG_ALL, cond, msg) \
`ifdef ENABLE_LOG \
`ifdef tag \
generate; \
    if(level >= DLog::logLevel)begin \
        always_ff @(posedge clk)begin \
            if(DLog::logValid && (cond))begin \
                $display("[%16d] %m: %s", DLog::cycleCnt, msg); \
            end \
        end \
    end \
endgenerate \
`endif \
`endif \

`define UNPARAM /* UNPARAM */

`endif