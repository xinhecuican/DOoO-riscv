`include "../../../defines/defines.svh"
`include "../../../defines/csr_defines.svh"

module CSR(
    input logic clk,
    input logic rst,
    input logic ext_irq,
    input logic `N(`VADDR_SIZE) exc_pc,
    input logic `N(32) trapInst,
    input logic `N(`VADDR_SIZE) exc_vaddr,
    input CSRRedirectInfo redirect,
    IssueCSRIO.csr issue_csr_io,
    WriteBackIO.fu csr_wb_io,
    BackendCtrl backendCtrl,
    CsrTlbIO.csr csr_itlb_io,
    CsrTlbIO.csr csr_ltlb_io,
    CsrTlbIO.csr csr_stlb_io,
    CsrL2IO.csr  csr_l2_io,
    ClintIO.cpu clint_io,
    output CSRIrqInfo irqInfo,
    output logic `N(`VADDR_SIZE) target_pc
);
    logic `N(2) mode;
    logic mode_m, mode_s, mode_u;
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
    IP mip;
    logic `N(`MXL) mie;
    logic `N(`MXL) mscratch;
    logic `N(`MXL) mepc;
    CAUSE mcause;
    logic `N(`MXL) mtval;
    logic `N(`MXL) mcycle;
    logic `N(`MXL) minstret;
`ifdef RV32I
    STATUSH mstatush;
    logic `N(`MXL) medelegh;
    logic `N(`MXL) mcycleh;
    logic `N(`MXL) minstreth;
`endif
    logic `N(`MXL) mconfigptr;

    logic `ARRAY(`PMPCFG_SIZE, `MXL) pmpcfg;
    logic `ARRAY(`PMP_SIZE, `MXL) pmpaddr;

    // superviser
    TVEC stvec;
    logic `N(`MXL) stval;
    logic `N(`MXL) sepc;
    logic `N(`MXL) sscratch;
    CAUSE scause;
    SATP satp;

    assign mode_m = mode == `M_MODE;
    assign mode_s = mode == `S_MODE;
    assign mode_u = mode == `U_MODE;

// csr write
    logic we, we_s1, we_s2, we_o;
    logic `N(`CSR_NUM) wen, wen_s1, wen_s2, wen_o; // exe wb retire
    logic `N(`XLEN) wdata, origin_data, rdata, cmp_rdata;
    logic `N(`XLEN) wdata_s1, wdata_s2;
    logic `N(`CSROP_WIDTH) csrop;
    logic csrrw, csrrs, csrrc;
    logic `N(`EXC_WIDTH) exccode;
    logic pmp_cmp;
    logic `N(`XLEN) pmp_rdata;

    assign csrop = issue_csr_io.bundle.csrop;
    assign origin_data = csrop[2] ? issue_csr_io.bundle.imm : issue_csr_io.rdata;
    assign csrrw = ~csrop[3] & ~csrop[1] & csrop[0] & ~issue_csr_io.bundle.exc_valid;
    assign csrrs = ~csrop[3] & csrop[1] & ~csrop[0] & ~issue_csr_io.bundle.exc_valid;
    assign csrrc = ~csrop[3] & csrop[1] & csrop[0] & ~issue_csr_io.bundle.exc_valid;
    assign rdata = pmp_cmp ? pmp_rdata : cmp_rdata;
    assign wdata = csrrw ? origin_data :
                   csrrs ? rdata | origin_data : rdata & ~origin_data;
// csr read
    logic `ARRAY(`CSR_NUM, 12) cmp_csrid;
    logic `ARRAY(`CSR_NUM, `MXL) cmp_csr_data;
    logic `N(`CSR_NUM) cmp_eq;
    logic mode_valid;
    logic s_map, s_map_s1, s_map_s2;
    RobIdx robIdx_s1, robIdx_s2;
    logic redirect_older, redirect_s1_older, redirect_s2_older;
    LoopCompare #(`ROB_WIDTH) cmp_redirect_older (issue_csr_io.status.robIdx, backendCtrl.redirectIdx, redirect_older);
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s1_older (robIdx_s1, backendCtrl.redirectIdx, redirect_s1_older);
    LoopCompare #(`ROB_WIDTH) cmp_redirect_s2_older (robIdx_s2, backendCtrl.redirectIdx, redirect_s2_older);
    assign mode_valid = mode >= issue_csr_io.bundle.csrid[11: 10];
    assign we = ~((csrrs | csrrc) & (issue_csr_io.bundle.imm == 0)) & 
                 (~backendCtrl.redirect | redirect_older) & 
                 issue_csr_io.en & mode_valid &
                 (csrrw | csrrs | csrrc);
    assign wen = cmp_eq  & {`CSR_NUM{we}};
    assign s_map = issue_csr_io.bundle.csrid[11: 10] == 2'b01;
    assign we_o = we_s2 & (~backendCtrl.redirect | redirect_s2_older);
    assign wen_o = wen_s2 & {`CSR_NUM{(~backendCtrl.redirect) | redirect_s2_older}};
    always_ff @(posedge clk)begin
        robIdx_s1 <= issue_csr_io.status.robIdx;
        robIdx_s2 <= robIdx_s1;
        wdata_s1 <= wdata;
        wdata_s2 <= wdata_s1;
        s_map_s1 <= s_map;
        s_map_s2 <= s_map_s1;
        we_s1 <= we;
        we_s2 <= we_s1 & (~backendCtrl.redirect | redirect_s1_older);
        wen_s1 <= wen;
        wen_s2 <= wen_s1 & {`CSR_NUM{(~backendCtrl.redirect | redirect_s1_older)}};

    end

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
        .data_o(cmp_rdata)
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
                    if(wen_o[``name``_id])begin                         \
                        name <= wdata_s2 & mask;                        \
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
                    if(wen_o[``name``_id])begin                         \
                        name <= wdata_s2;                               \
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
    `CSR_WRITE_DEF(stvec,       0,              1, 0, 0)
    `CSR_WRITE_DEF(mconfigptr,  0,              0, 0, 0)
    `CSR_WRITE_DEF(sscratch,    0,              1, 0, 0)
`ifdef RV32I
    `CSR_WRITE_DEF(mstatush,    0,              1, 0, 0)
    `CSR_WRITE_DEF(medelegh,    0,              1, 0, 0)
`endif

    logic `N(`VADDR_SIZE-2) mvec_pc, svec_pc;
    logic `N(`VADDR_SIZE) mtarget_pc, starget_pc;
    logic `N(`EXC_WIDTH) ecall_exccode;
    logic `N(`MXL) exccode_decode;
    logic `N(`MXL) edelege;
    logic edelege_valid;
    /* verilator lint_off UNOPTFLAT */
    logic ret, ret_priv_error, ret_valid;
    assign mvec_pc = mtvec[`MXL-1: 2] + mcause[`EXC_WIDTH-1: 0];
    assign svec_pc = stvec[`MXL-1: 2] + mcause[`EXC_WIDTH-1: 0];
    assign mtarget_pc = redirect.irq & (mtvec[1: 0] == 2'b01) ? {mvec_pc, 2'b00} : 
                        {{`VADDR_SIZE-`MXL{1'b0}}, mtvec[`MXL-1: 2], 2'b00};
    assign starget_pc = redirect.irq & (stvec[1: 0] == 2'b01) ? {mvec_pc, 2'b00} : 
                        {{`VADDR_SIZE-`MXL{1'b0}}, stvec[`MXL-1: 2], 2'b00};
    assign target_pc = (redirect.exccode == `EXC_MRET) & ~ret_priv_error ? mepc :
                       (redirect.exccode == `EXC_SRET) & ~ret_priv_error ? sepc :
                       edelege_valid ? starget_pc : mtarget_pc;

    assign ecall_exccode = {{`EXC_WIDTH-4{1'b0}}, 2'b10, mode};
    assign ret = redirect.exccode == `EXC_MRET | redirect.exccode == `EXC_SRET;
    assign ret_priv_error = mode < redirect.exccode[1: 0] ||
                            (mode == 2'b01 && mstatus.tsr);
    assign ret_valid = ret & ~ret_priv_error;
    assign exccode = redirect.exccode == `EXC_EC ? ecall_exccode : 
                     (ret & ret_priv_error) ? `EXC_II : redirect.exccode;
    Decoder #(`MXL) deocder_exccode (exccode, exccode_decode);
    assign edelege = medeleg & exccode_decode;
    assign edelege_valid = (|edelege) & (mode != 2'b11) | (redirect.irq & redirect.irq_deleg);

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
            if(wen_o[mstatus_id])begin
                if(s_map)begin
                    mstatus <= wdata_s2 & `SSTATUS_MASK;
                end
                else begin
                    mstatus <= wdata_s2 & `STATUS_MASK;
                end
            end
            if(wen_o[mepc_id])begin
                mepc <= wdata_s2;
            end
            if(wen_o[sepc_id])begin
                sepc <= wdata_s2;
            end
            if(wen_o[mie_id] | wen_o[sie_id])begin
                mie <= wdata_s2;
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
                if(mstatus.mpp != `M_MODE)begin
                    mstatus.mprv <= 0;
                end
            end
            if(redirect.en && exccode == `EXC_SRET && ret_valid)begin
                mstatus.sie <= mstatus.spie;
                mstatus.spp <= 0;
                mstatus.spie <= 1;
                mstatus.mprv <= 0;
            end
            if(redirect.en & ~ret_valid)begin
                if(edelege_valid)begin
                    scause[`EXC_WIDTH-1: 0] <= {redirect.irq, {`MXL-1-`EXC_WIDTH{1'b1}}, exccode};
                end
                if(~edelege_valid)begin
                    mcause[`EXC_WIDTH-1: 0] <= {redirect.irq, {`MXL-1-`EXC_WIDTH{1'b1}}, exccode};
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
            if(redirect.en & ~ret_valid & ~redirect.irq)begin
                if(edelege_valid)begin
                    case(exccode)
                    `EXC_II: stval <= trapInst;
                    `EXC_IAM, `EXC_IAF, `EXC_IPF, `EXC_BP: stval <= exc_pc;
                    `EXC_LAM, `EXC_LAF, `EXC_SAM, `EXC_SAF,
                    `EXC_LPF, `EXC_SPF: stval <= exc_vaddr;
                    default: stval <= 0;
                    endcase
                end
                else begin
                    case(exccode)
                    `EXC_II: mtval <= trapInst;
                    `EXC_IAM, `EXC_IAF, `EXC_IPF, `EXC_BP: mtval <= exc_pc;
                    `EXC_LAM, `EXC_LAF, `EXC_SAM, `EXC_SAF,
                    `EXC_LPF, `EXC_SPF: mtval <= exc_vaddr;
                    default: mtval <= 0;
                    endcase
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
    assign csr_wb_io.datas[0].exccode = ((csrrw | csrrs | csrrc) & (~mode_valid | (~((|cmp_eq) | pmp_cmp)))) |
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
            if(redirect.en && !ret_priv_error)begin
                if(redirect.exccode == `EXC_MRET)begin
                    mode <= mstatus.mpp;
                end
                if(redirect.exccode == `EXC_SRET)begin
                    mode <= mstatus.spp;
                end
            end
        end
    end

// interrupt
    logic msip, ssip, mtip, stip, meip, seip;
    logic msip_s1, mtip_s1, meip_s1;
    logic `N(7) deleg_s, irq_enable, irq_valid;
    logic `N(3) irqIdx;

    assign mip = '{
        meip: meip,
        seip: seip,
        msip: msip,
        ssip: ssip,
        mtip: mtip,
        stip: stip,
        default: 0
    };
generate
    for(genvar i=0; i<7; i++)begin
        localparam idx = (i << 1) + 1;
        assign deleg_s[i] =  mideleg[idx] & mip[idx];
        assign irq_enable[i] = deleg_s[i] ? (mode == `S_MODE) & mstatus.sie | (mode == `U_MODE) :
                               (mode == `M_MODE) & mstatus.mie | (mode < `M_MODE);
        assign irq_valid[i] = mie[idx] & mip[idx] & irq_enable[i];
    end
endgenerate
    PEncoder #(7) encoder_irq (irq_valid, irqIdx);
    assign irqInfo.irq = |irq_valid;
    assign irqInfo.deleg = deleg_s[irqIdx];
    assign irqInfo.exccode = irq_valid[6] ? `EXCI_COUNTEROV :
                             irq_valid[5] ? `EXCI_MEXT :
                             irq_valid[4] ? `EXCI_SEXT :
                             irq_valid[3] ? `EXCI_MTIMER :
                             irq_valid[2] ? `EXCI_STIMER :
                             irq_valid[1] ? `EXCI_MSI :
                             irq_valid[0] ? `EXCI_SSI : `EXC_NONE;
    always_ff @(posedge clk)begin
        msip <= msip_s1;
        mtip <= mtip_s1;
        meip <= meip_s1;
    end
    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            msip_s1 <= 0;
            mtip_s1 <= 0;
            meip_s1 <= 0;
            ssip <= 0;
            stip <= 0;
        end
        else begin
            msip_s1 <= clint_io.soft_irq;
            mtip_s1 <= clint_io.timer_irq;
            meip_s1 <= ext_irq;
            if(wen_o[mip_id] | wen_o[sip_id])begin
                ssip <= wdata_s2[1];
                stip <= wdata_s2[5];
                seip <= wdata_s2[9];
            end
        end
    end

// pmp
    localparam [11: 0] pmpcfg_base = 12'h3a0;
    localparam [11: 0] pmpaddr_base = 12'h3b0;
    logic `N($clog2(`PMPCFG_SIZE)) pmp_id;
    logic `N($clog2(`PMP_SIZE)) pmpaddr_id;
    logic pmpcfg_cmp_en, pmpaddr_cmp_en;
    logic pmpcfg_s1, pmpcfg_s2, pmpaddr_s1, pmpaddr_s2;
    assign pmp_id = issue_csr_io.bundle.csrid[$clog2(`PMPCFG_SIZE)-1: 0];
    assign pmpaddr_id = issue_csr_io.bundle.csrid[$clog2(`PMP_SIZE)-1: 0];
    assign pmpcfg_cmp_en = issue_csr_io.bundle.csrid[11: $clog2(`PMPCFG_SIZE)] == pmpcfg_base[11: $clog2(`PMPCFG_SIZE)];
    assign pmpaddr_cmp_en = issue_csr_io.bundle.csrid[11: $clog2(`PMP_SIZE)] == pmpaddr_base[11: $clog2(`PMP_SIZE)];
    assign pmp_cmp = pmpcfg_cmp_en | pmpaddr_cmp_en;
    assign pmp_rdata = issue_csr_io.bundle.csrid[11: 4] == 8'h3a ? pmpcfg[pmp_id] : pmpaddr[pmpaddr_id];

    always_ff @(posedge clk)begin
        pmpcfg_s1 <= pmpcfg_cmp_en;
        pmpcfg_s2 <= pmpcfg_s1;
        pmpaddr_s1 <= pmpaddr_cmp_en;
        pmpaddr_s2 <= pmpaddr_s1;
    end

    always_ff @(posedge clk, posedge rst)begin
        if(rst == `RST)begin
            pmpcfg <= 0;
            pmpaddr <= 0;
        end
        else begin
            if(we_o & pmpcfg_s2)begin
                pmpcfg[pmp_id] <= wdata_s2;
            end
            if(we_o & pmpcfg_s2)begin
                pmpaddr[pmpaddr_id] <= wdata_s2;
            end
        end
    end


// tlb
`define TLB_ASSIGN(name, IFETCH) \
    logic ``name``_we, ``name``_pmpcfg_en, ``name``_pmpaddr_en, ``name``_we_o; \
    logic `N(`XLEN) ``name``_wdata; \
    assign ``name``_we_o = ``name``_we & (~backendCtrl.redirect | redirect_s2_older); \
    always_ff @(posedge clk)begin \
        if(~IFETCH & mstatus.mprv)begin \
            name.mode <= mstatus.mpp; \
        end \
        else begin \
            name.mode <= mode; \
        end \
        ``name``_we <= we_s1 & (~backendCtrl.redirect | redirect_s1_older); \
        ``name``_pmpcfg_en <= pmpcfg_s1; \
        ``name``_pmpaddr_en <= pmpaddr_s1; \
        ``name``_wdata <= wdata_s1; \
        name.sum <= mstatus.sum; \
        name.mxr <= mstatus.mxr; \
        name.asid <= satp.asid; \
        name.satp_mode <= satp.mode; \
    end \
    always_ff @(posedge clk, posedge rst)begin \
        if(rst == `RST)begin \
            name.pmpcfg <= 0; \
            name.pmpaddr <= 0; \
        end \
        else begin \
            if(``name``_we_o & ``name``_pmpcfg_en)begin \
                name.pmpcfg[pmp_id] <= ``name``_wdata; \
            end \
            if(``name``_we_o & ``name``_pmpaddr_en)begin \
                name.pmpaddr[pmpaddr_id] <= ``name``_wdata; \
            end \
        end \
    end \

    `TLB_ASSIGN(csr_itlb_io, 1)
    `TLB_ASSIGN(csr_ltlb_io, 0)
    `TLB_ASSIGN(csr_stlb_io, 0)
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
        .sscratch(sscratch),
        .mideleg(mideleg),
        .medeleg(medeleg)
    );
`endif
endmodule