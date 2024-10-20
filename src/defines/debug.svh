`ifndef __CORE_DEBUG_SVH
`define __CORE_DEBUG_SVH

`define ENABLE_LOG
`define T_LOG_ALL
// `define T_FSQ
// `define T_TAGE
// `define T_BR_HIST
`define T_DCACHE
`define T_SCB
// `define T_ICACHE

// `define REPORT_RAM
// `define REPORT_UNPARAM
// `define REPORT_CONSTRAINT

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

`ifdef DIFFTEST
package DLog;
    typedef enum logic [1: 0] { Debug, Info, Warning, Error} LogLevel;
    logic logValid = 1'b0;
    logic [63: 0] cycleCnt;
    parameter [7: 0] logLevel = Debug;

endpackage

`endif

`define Log(level, tag=T_LOG_ALL, cond, msg) \
`ifdef ENABLE_LOG \
`ifdef tag \
    always_ff @(posedge clk)begin \
        if(DLog::logValid && level >= DLog::logLevel && (cond))begin \
            $display("[%16d] %s", DLog::cycleCnt, msg); \
        end \
    end \
`endif \
`endif \

`define LOG_ARRAY(tag=T_LOG_ALL, name, arr_name, num) \
`ifdef ENABLE_LOG \
`ifdef tag \
    string name; \
    always_comb begin \
        if(DLog::logValid)begin \
            name = ""; \
            for (int i = 0; i < num; i++) begin \
                name = $sformatf("%s %h", name, arr_name[i]); \
            end \
        end \
        else begin \
            name = ""; \
        end \
    end \
`endif \
`endif \


`define UNPARAM(name, default_value, reason) \
`ifdef REPORT_UNPARAM \
    initial begin \
        if(`name != default_value)begin \
            $display("Error0-0. [%s] unsupport %d, because %s", `"name`", `name, `"reason`"); \
        end \
    end \
`endif

`define CONSTRAINT(name, default_value, reason) \
`ifdef REPORT_CONSTRAINT \
    initial begin \
        if(`name != default_value)begin \
            $display("Error0-1. [%s] unsupport %d, because %s", `"name`", `name, `"reason`"); \
        end \
    end \
`endif

`define CRITICAL(from, to) /* critical path ``from`` to ``to`` */

`endif