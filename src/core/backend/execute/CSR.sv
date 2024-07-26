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
    CsrTlbIO.csr csr_itlb_io,
    CsrTlbIO.csr csr_ltlb_io,
    CsrTlbIO.csr csr_stlb_io,
    CsrL2IO.csr  csr_l2_io,
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
    logic `N(`MXL) sscratch;
    logic `N(`MXL) mcycle;
    logic `N(`MXL) minstret;
`ifdef RV32I
    STATUSH mstatush;
    logic `N(`MXL) medelegh;
    logic `N(`MXL) mcycleh;
    logic `N(`MXL) minstreth;
`endif
    logic `N(`MXL) mconfigptr;

    // superviser
    TVEC stvec;
    logic `N(`MXL) stval;
    logic `N(`MXL) sepc;
    CAUSE scause;
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
    logic mode_valid;
    logic s_map;
    logic redirect_older;
    LoopCompare #(`ROB_WIDTH) cmp_redirect_older (backendCtrl.redirectIdx, issue_csr_io.status.robIdx, redirect_older);
    assign mode_valid = mode >= issue_csr_io.bundle.csrid[11: 10];
    assign wen = cmp_eq  & 
       {`CSR_NUM{~((csrrs | csrrc) & (issue_csr_io.bundle.imm == 0)) & 
                 ~(backendCtrl.redirect & redirect_older) & 
                 issue_csr_io.en & mode_valid &
                 (csrrw | csrrs | csrrc)}};
    assign s_map = issue_csr_io.bundle.csrid[11: 10] == 2'b01;

`define CSR_CMP_DEF(name, map, i, WARL, mask)                 \
    localparam [7: 0] ``name``_id = i;                        \
    assign cmp_csrid[i] = `CSRID_``name;                      \
generate                                                      \
    if(WARL)begin                                             \
            assign cmp_csr_data[i] = map & mask;              \
    end                                                       \
    else begin                                                \
        assign cmp_csr_data[i] = map;                         \
    end                                                       \
endgenerate                                                   \

    `CSR_CMP_DEF(misa, misa,            0, 1, `ISA_MASK     )
    `CSR_CMP_DEF(mvendorid, mvendorid,  1, 0, 0             )
    `CSR_CMP_DEF(marchid, marchid,      2, 0, 0             )
    `CSR_CMP_DEF(mimpid, mimpid,        3, 0, 0             )
    `CSR_CMP_DEF(mhartid, mhartid,      4, 0, 0             )
    `CSR_CMP_DEF(mstatus, mstatus,      5, 0, 0             )
    `CSR_CMP_DEF(mtvec, mtvec,          6, 1, `TVEC_MASK    )
    `CSR_CMP_DEF(medeleg, medeleg,      7, 0, 0             )
    `CSR_CMP_DEF(mideleg, mideleg,      8, 0, 0             )
    `CSR_CMP_DEF(mip, mip,              9, 1, `IP_MASK      )
    `CSR_CMP_DEF(mie, mie,              10,1, `IP_MASK      )
    `CSR_CMP_DEF(mscratch, mscratch,    11,0, 0             )
    `CSR_CMP_DEF(mepc, mepc,            12,1, `EPC_MASK     )
    `CSR_CMP_DEF(mcause, mcause,        13,1, `CAUSE_MASK   )
    `CSR_CMP_DEF(mtval, mtval,          14,0, 0             )
    `CSR_CMP_DEF(mconfigptr, mconfigptr,15,0, 0             )
    `CSR_CMP_DEF(stval, stval,          16,0, 0             )
    `CSR_CMP_DEF(stvec, stvec,          17,1, `TVEC_MASK    )
    `CSR_CMP_DEF(sepc, sepc,            18,0, 0             )
    `CSR_CMP_DEF(satp, satp,            19,0, 0             )
    `CSR_CMP_DEF(sstatus, mstatus,      20,1, `SSTATUS_MASK )
    `CSR_CMP_DEF(sip, mip,              21,1, `SIP_MASK     )
    `CSR_CMP_DEF(sie, mie,              22,1, `SIP_MASK     )
    `CSR_CMP_DEF(scause, scause,        23,1, `CAUSE_MASK   )
    `CSR_CMP_DEF(sscratch, sscratch,    24,0, 0             )
    `CSR_CMP_DEF(mcycle, mcycle,        25,0, 0             )
    `CSR_CMP_DEF(minstret, minstret,    26,0, 0             )
`ifdef RV32I
    `CSR_CMP_DEF(mstatush, mstatush,    27,0, 0             )
    `CSR_CMP_DEF(medelegh, medelegh,    28,0, 0             )
    `CSR_CMP_DEF(mcycleh, mcycleh,      29,0, 0             )
    `CSR_CMP_DEF(minstreth, minstreth,  30,0, 0             )
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

    `CSR_WRITE_DEF(misa,        `MISA_INIT,     1, 0, 0)
    `CSR_WRITE_DEF(mvendorid,   0,              0, 0, 0)
    `CSR_WRITE_DEF(marchid,     0,              0, 0, 0)
    `CSR_WRITE_DEF(mimpid,      0,              0, 0, 0)
    `CSR_WRITE_DEF(mhartid,     0,              0, 0, 0)
    `CSR_WRITE_DEF(mtvec,       0,              1, 0, 0)
    `CSR_WRITE_DEF(medeleg,     `MEDELEG_INIT,  1, 0, 0)
    `CSR_WRITE_DEF(mideleg,     0,              1, 0, 0)
    `CSR_WRITE_DEF(mscratch,    0,              1, 0, 0)
    `CSR_WRITE_DEF(satp,        0,              1, 0, 0)
    `CSR_WRITE_DEF(mconfigptr,  0,              0, 0, 0)
    `CSR_WRITE_DEF(sscratch,    0,              1, 0, 0)
`ifdef RV32I
    `CSR_WRITE_DEF(mstatush,    0,              1, 0, 0)
    `CSR_WRITE_DEF(medelegh,    0,              1, 0, 0)
`endif

    logic `N(`VADDR_SIZE-2) vec_pc;
    logic `N(`EXC_WIDTH) ecall_exccode;
    logic `N(`MXL) exccode_decode;
    logic `N(`MXL) edelege;
    logic edelege_valid;
    /* verilator lint_off UNOPTFLAT */
    logic ret, ret_priv_error, ret_valid;
    assign vec_pc = mtvec[`MXL-1: 2] + mcause[`EXC_WIDTH-1: 0];
    assign target_pc = ret_valid ? mepc : 
                                   {{`VADDR_SIZE-`MXL{1'b0}}, mtvec[`MXL-1: 2], 2'b00};

    assign ecall_exccode = {{`EXC_WIDTH-4{1'b0}}, 2'b10, mode};
    assign ret = redirect.exccode == `EXC_MRET | redirect.exccode == `EXC_SRET;
    assign ret_priv_error = mode < redirect.exccode[1: 0] ||
                            (mode == 2'b01 && mstatus.tsr);
    assign ret_valid = ret & ~ret_priv_error;
    assign exccode = redirect.exccode == `EXC_EC ? ecall_exccode : 
                     (ret & ret_priv_error) ? `EXC_II : redirect.exccode;
    Decoder #(`MXL) deocder_exccode (exccode, exccode_decode);
    assign edelege = medeleg & exccode_decode;
    assign edelege_valid = (|edelege) & (mode != 2'b11);

    logic `N(64) mcycle_n;
    assign mcycle_n = {mcycleh, mcycle} + 1;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            mstatus <= 0;
            mepc <= 0;
            mcause <= 0;
            scause <= 0;
            mtval <= 0;
            sepc <= 0;
            stval <= 0;
            mip <= 0;
            mie <= 0;
            mcycle <= 0;
            mcycleh <= 0;
            minstret <= 0;
            minstreth <= 0;
        end
        else begin
`ifndef DIFFTEST
            {mcycleh, mcycle} <= mcycle_n;
`endif
            if(wen[mstatus_id])begin
                if(s_map)begin
                    mstatus <= wdata & `SSTATUS_MASK;
                end
                else begin
                    mstatus <= wdata & `STATUS_MASK;
                end
            end
            if(wen[mepc_id])begin
                mepc <= wdata;
            end
            if(wen[sepc_id])begin
                sepc <= wdata;
            end
            if(wen[mie_id] | wen[sie_id])begin
                mie <= wdata;
            end
            if(wen[mip_id] | wen[sip_id])begin
                mip <= wdata;
            end
            if(redirect.en & ~ret_valid)begin
                if(edelege_valid)begin
                    mstatus.spp <= mode;
                    mstatus.spie <= mstatus.sie;
                    mstatus.sie <= 0;
                end
                if(~edelege_valid)begin
                    mstatus.mpp <= mode;
                    mstatus.mpie <= mstatus.mie;
                    mstatus.mie <= 0;
                end
            end
            if(redirect.en && exccode == `EXC_MRET && ret_valid)begin
                mstatus.mie <= mstatus.mpie;
                mstatus.mpp <= 0;
                mstatus.mpie <= 1;
            end
            if(redirect.en && exccode == `EXC_SRET && ret_valid)begin
                mstatus.sie <= mstatus.spie;
                mstatus.spp <= 0;
                mstatus.spie <= 1;
            end
            if(redirect.en & ~ret_valid)begin
                if(edelege_valid)begin
                    scause[`EXC_WIDTH-1: 0] <= exccode;
                end
                if(~edelege_valid)begin
                    mcause[`EXC_WIDTH-1: 0] <= exccode;
                end
            end
            if(redirect.en & ~ret_valid)begin
                if(edelege_valid)begin
                    sepc <= exc_pc;
                end
                if(~edelege_valid) begin
                    mepc <= exc_pc;
                end
            end
        end
    end

// wb
    assign csr_wb_io.datas[0].en = issue_csr_io.en;
    assign csr_wb_io.datas[0].we = issue_csr_io.status.we;
    assign csr_wb_io.datas[0].robIdx = issue_csr_io.status.robIdx;
    assign csr_wb_io.datas[0].rd = issue_csr_io.status.rd;
    assign csr_wb_io.datas[0].res = rdata;
    assign csr_wb_io.datas[0].exccode = ((csrrw | csrrs | csrrc) & (~mode_valid | (~(|cmp_eq)))) |
                                        (wen[satp_id] & mstatus.tvm) ? `EXC_II :
                                        issue_csr_io.bundle.exc_valid ? issue_csr_io.bundle.exccode : `EXC_NONE;

    always_ff @(posedge clk or posedge rst)begin
        if(rst == `RST)begin
            mode <= 2'b11;
        end
        else begin
            if(redirect.en & ~ret_valid)begin
                if(edelege_valid)begin
                    mode <= 2'b01;
                end
                else begin
                    mode <= 2'b11;
                end
            end
            if(redirect.en && redirect.exccode == `EXC_MRET && !ret_priv_error)begin
                mode <= mstatus.mpp;
            end
        end
    end

// tlb
`define TLB_ASSIGN(name) \
    always_ff @(posedge clk)begin \
        if((mode == 2'b11) & mstatus.mprv)begin \
            name.mode <= mstatus.mpp; \
        end \
        name.sum <= mstatus.sum; \
        name.asid <= satp.asid; \
        name.satp_mode <= satp.mode; \
    end \

    `TLB_ASSIGN(csr_itlb_io)
    `TLB_ASSIGN(csr_ltlb_io)
    `TLB_ASSIGN(csr_stlb_io)
    always_ff @(posedge clk)begin
        if((mode == 2'b11) & mstatus.mprv)begin
            csr_l2_io.mode <= mstatus.mpp;
        end
        csr_l2_io.sum <= mstatus.sum;
        csr_l2_io.mxr <= mstatus.mxr;
        csr_l2_io.ppn <= satp.ppn;
    end

`ifdef DIFFTEST
    DifftestCSRState difftest_csr_state (
        .clock(clk),
        .coreid(mhartid),
        .priviledgeMode(mode),
        .mstatus(mstatus),
        .sstatus((mstatus & `SSTATUS_MASK)),
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