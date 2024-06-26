`include "../../../defines/defines.svh"
`include "../../../defines/csr_defines.svh"

module CSR(
    input logic clk,
    input logic rst,
    input logic `N(`VADDR_SIZE) exc_pc,
    input CSRRedirectInfo redirect,
    IssueCSRIO.csr issue_csr_io,
    WriteBackIO.fu csr_wb_io,
    BackendCtrl backendCtrl,
    output logic `N(`VADDR_SIZE) target_pc
);
    logic `N(2) mode;
    logic exc_ecall;

    // machine mode regs
    ISA misa;
    VENDORID mvendorid;
    logic `N(`MXL) marchid;
    logic `N(`MXL) mimpid;
    logic `N(`MXL) mhartid;
    STATUS mstatus;
    TVEC mtvec;
    logic `N(`MXL) medeleg;
    logic `N(`MXL) mideleg;
    logic `N(`MXL) mip;
    logic `N(`MXL) mie;
    logic `N(`MXL) mscratch;
    logic `N(`MXL) mepc;
    CAUSE mcause;
    logic `N(`MXL) mtval;
`ifdef RV32I
    STATUSH mstatush;
    logic `N(`MXL) medelegh;
`endif

    // superviser
    STATUS sstatus;
    TVEC stvec;
    logic `N(`MXL) sip;
    logic `N(`MXL) sie;
    logic `N(`MXL) sepc;
    CAUSE scause;
    logic `N(`MXL) stval;
    SATP satp;

// csr write
    logic `N(`CSR_NUM) wen;
    logic `N(`XLEN) wdata, origin_data, rdata;
    logic `N(`CSROP_WIDTH) csrop;
    logic csrrw, csrrs, csrrc, ecall, ebreak;
    logic `N(`EXC_WIDTH) exccode;

    assign csrop = issue_csr_io.bundle.csrop;
    assign origin_data = csrop[2] ? issue_csr_io.bundle.imm : issue_csr_io.rdata;
    assign csrrw = ~csrop[1] & csrop[0] & ~issue_csr_io.bundle.exc_valid;
    assign csrrs = csrop[1] & ~csrop[0] & ~issue_csr_io.bundle.exc_valid;
    assign csrrc = csrop[1] & csrop[0] & ~issue_csr_io.bundle.exc_valid;
    assign ecall = csrop[2] & ~csrop[1] & ~csrop[0];
    assign ebreak = ~csrop[2] & ~csrop[1] & ~csrop[0];
    assign wdata = csrrw ? origin_data :
                   csrrs ? rdata | origin_data : rdata & ~origin_data;
// csr read
    logic `ARRAY(`CSR_NUM, 12) cmp_csrid;
    logic `ARRAY(`CSR_NUM, `MXL) cmp_csr_data;
    logic `N(`CSR_NUM) cmp_eq;
    logic redirect_older;
    LoopCompare #(`ROB_WIDTH) cmp_redirect_older (backendCtrl.redirectIdx, issue_csr_io.bundle.robIdx, redirect_older);
    assign wen = cmp_eq  & 
       {`CSR_NUM{~((csrrs | csrrc) & (issue_csr_io.bundle.imm == 0)) & 
                 ~(backendCtrl.redirect & redirect_older) & 
                 issue_csr_io.en}};

`define CSR_CMP_DEF(name, i, WARL, mask)        \
    localparam [7: 0] ``name``_id = i;                 \
    assign cmp_csrid[i] = `CSRID_``name;        \
generate                                        \
    if(WARL)begin                               \
        assign cmp_csr_data[i] = name & mask;   \
    end                                         \
    else begin                                  \
        assign cmp_csr_data[i] = name;          \
    end                                         \
endgenerate                                     \

    `CSR_CMP_DEF(misa,      0, 1, `ISA_MASK)
    `CSR_CMP_DEF(mvendorid, 1, 0, 0)
    `CSR_CMP_DEF(marchid,   2, 0, 0)
    `CSR_CMP_DEF(mimpid,    3, 0, 0)
    `CSR_CMP_DEF(mhartid,   4, 0, 0)
    `CSR_CMP_DEF(mstatus,   5, 0, 0)
    `CSR_CMP_DEF(mtvec,     6, 1, `TVEC_MASK)
    `CSR_CMP_DEF(medeleg,   7, 0, 0)
    `CSR_CMP_DEF(mideleg,   8, 0, 0)
    `CSR_CMP_DEF(mip,       9, 1, `IP_MASK)
    `CSR_CMP_DEF(mie,       10,1, `IP_MASK)
    `CSR_CMP_DEF(mscratch,  11,0, 0)
    `CSR_CMP_DEF(mepc,      12,0, 0)
    `CSR_CMP_DEF(mcause,    13,1, `CAUSE_MASK)
    `CSR_CMP_DEF(mtval,     14,0, 0)

    `CSR_CMP_DEF(sstatus,   15,0, 0)
    `CSR_CMP_DEF(stvec,     16,1, `TVEC_MASK)
    `CSR_CMP_DEF(sip,       17,1, `IP_MASK)
    `CSR_CMP_DEF(sie,       18,1, `IP_MASK)
    `CSR_CMP_DEF(sepc,      19,0, 0)
    `CSR_CMP_DEF(scause,    20,1, `CAUSE_MASK)
    `CSR_CMP_DEF(stval,     21,0, 0)
    `CSR_CMP_DEF(satp,      22,0, 0)
`ifdef RV32I
    `CSR_CMP_DEF(mstatush,  23,0, 0)
    `CSR_CMP_DEF(medelegh,  24,0, 0)
`endif
    ParallelEQ #(
        .RADIX(`CSR_NUM),
        .WIDTH(12),
        .DATA_WIDTH(`MXL)
    ) parallel_eq_rdata (
        .origin(issue_csr_io.bundle.csrid),
        .cmp_en({`CSR_NUM{1'b1}}),
        .cmp(cmp_csrid),
        .data_i(cmp_csr_data),
        .eq(cmp_eq),
        .data_o(rdata)
    );

`define CSR_WRITE_DEF(name, init_value, WRITE_ENABLE, MASK_VALID, mask) \
generate                                                                \
    if(WRITE_ENABLE)begin                                               \
        if(MASK_VALID)begin                                             \
            always_ff @(posedge clk or posedge rst)begin                \
                if(rst == `RST)begin                                    \
                    name <= init_value;                                 \
                end                                                     \
                else begin                                              \
                    if(wen[``name``_id])begin                           \
                        name <= wdata & mask;                           \
                    end                                                 \
                end                                                     \
            end                                                         \
        end                                                             \
        else begin                                                      \
            always_ff @(posedge clk or posedge rst)begin                \
                if(rst == `RST)begin                                    \
                    name <= init_value;                                 \
                end                                                     \
                else begin                                              \
                    if(wen[``name``_id])begin                           \
                        name <= wdata;                                  \
                    end                                                 \
                end                                                     \
            end                                                         \
        end                                                             \
    end                                                                 \
    else begin                                                          \
        always_ff @(posedge clk or posedge rst)begin                    \
            if(rst == `RST)begin                                        \
                name <= init_value;                                     \
            end                                                         \
        end                                                             \
    end                                                                 \
endgenerate                                                             \

    `CSR_WRITE_DEF(misa,        `MISA_INIT, 1, 0, 0)
    `CSR_WRITE_DEF(mvendorid,   0,          0, 0, 0)
    `CSR_WRITE_DEF(marchid,     0,          0, 0, 0)
    `CSR_WRITE_DEF(mimpid,      0,          0, 0, 0)
    `CSR_WRITE_DEF(mhartid,     0,          0, 0, 0)
    `CSR_WRITE_DEF(mtvec,       0,          1, 0, 0)
    `CSR_WRITE_DEF(medeleg,     0,          1, 0, 0)
    `CSR_WRITE_DEF(mideleg,     0,          1, 0, 0)
    `CSR_WRITE_DEF(mscratch,    0,          1, 0, 0)
    `CSR_WRITE_DEF(sstatus,     0,          1, 1, `STATUS_MASK)
    `CSR_WRITE_DEF(stvec,       0,          1, 0, 0)
    `CSR_WRITE_DEF(sip,         0,          1, 0, 0)
    `CSR_WRITE_DEF(sie,         0,          1, 0, 0)
    `CSR_WRITE_DEF(sepc,        0,          1, 0, 0)
    `CSR_WRITE_DEF(scause,      0,          1, 1, `CAUSE_MASK)
    `CSR_WRITE_DEF(stval,       0,          1, 0, 0)
    `CSR_WRITE_DEF(satp,        0,          1, 0, 0)
`ifdef RV32I
    `CSR_WRITE_DEF(mstatush,    0,          1, 0, 0)
    `CSR_WRITE_DEF(medelegh,    0,          1, 0, 0)
`endif

    logic `N(`VADDR_SIZE-2) vec_pc;
    logic `N(`EXC_WIDTH) ecall_exccode;
    /* verilator lint_off UNOPTFLAT */
    logic ret, ret_priv_error, ret_valid;
    assign vec_pc = mtvec[`MXL-1: 2] + mcause[`EXC_WIDTH-1: 0];
    assign target_pc = ret_valid ? mepc : 
                                   {{`VADDR_SIZE-`MXL{1'b0}}, mtvec[`MXL-1: 2], 2'b00};

    assign ecall_exccode = {{`EXC_WIDTH-4{1'b0}}, 2'b10, mode};
    assign ret = redirect.exccode == `EXC_MRET | redirect.exccode == `EXC_SRET;
    assign ret_priv_error = mode < redirect.exccode[1: 0];
    assign ret_valid = ret & ~ret_priv_error;
    assign exccode = redirect.exccode == `EXC_EC ? ecall_exccode : 
                     ret & ret_priv_error ? `EXC_II : redirect.exccode;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            mstatus <= 0;
            mepc <= 0;
            mcause <= 0;
            mtval <= 0;
        end
        else begin
            if(wen[mstatus_id])begin
                mstatus <= wdata & `STATUS_MASK;
            end
            if(wen[mcause_id])begin
                mcause <= wdata & `CAUSE_MASK;
            end
            if(wen[mepc_id])begin
                mepc <= wdata;
            end
            if(redirect.en & ~ret_valid)begin
                mstatus.mpp <= mode;
                mstatus.mpie <= mstatus.mie;
                mstatus.mie <= 0;
            end
            if(redirect.en && exccode == `EXC_MRET && ret_valid)begin
                mstatus.mie <= mstatus.mpie;
                mstatus.mpie <= 1;
            end
            if(redirect.en & ~ret_valid)begin
                mcause[`EXC_WIDTH-1: 0] <= exccode;
            end
            if(redirect.en & ~ret_valid)begin
                mepc <= exc_pc;
            end
        end
    end

// wb
    assign csr_wb_io.datas[0].en = issue_csr_io.en;
    assign csr_wb_io.datas[0].robIdx = issue_csr_io.bundle.robIdx;
    assign csr_wb_io.datas[0].rd = issue_csr_io.bundle.rd;
    assign csr_wb_io.datas[0].res = rdata;
    assign csr_wb_io.datas[0].exccode = issue_csr_io.bundle.exc_valid ? issue_csr_io.bundle.exccode : `EXC_NONE;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            mode <= 2'b11;
        end
        else begin
            if(redirect.en & ~ret_valid)begin
                mode <= 2'b11;
            end
            if(redirect.en && redirect.exccode == `EXC_MRET && !ret_priv_error)begin
                mode <= mstatus.mpp;
            end
        end
    end

`ifdef DIFFTEST
    DifftestCSRState difftest_csr_state (
        .clock(clk),
        .coreid(mhartid),
        .priviledgeMode(mode),
        .mstatus(mstatus),
        .sstatus(sstatus),
        .mepc(mepc),
        .sepc(sepc),
        .mtval(mtval),
        .stval(stval),
        .mtvec(mtvec),
        .stvec(stvec),
        .mcause(mcause),
        .scause(scause),
        .satp(satp),
        .mip(mip),
        .mie(mie),
        .mscratch(mscratch),
        .sscratch(),
        .mideleg(mideleg),
        .medeleg(medeleg)
    );
`endif
endmodule