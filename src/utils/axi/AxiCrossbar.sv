`include "../../defines/defines.svh"

module AxiCrossbar #(
    parameter SLAVE=1,
    parameter MASTER=1,
    parameter ADDR_WIDTH=`PADDR_SIZE,
    parameter ID_WIDTH = `AXI_ID_W,
    parameter DATA_WIDTH = `XLEN,
    parameter `N(SLAVE*`PADDR_SIZE) SLV_START=0,
    parameter `N(SLAVE*`PADDR_SIZE) SLV_END=0
)(
    input logic clk,
    input logic rst,
    input logic `N(SLAVE) sclk,
    input logic `N(SLAVE) srst,
    input logic `N(MASTER) mclk,
    input logic `N(MASTER) mrst,
    input AxiMAR `N(MASTER) m_mar,
    input AxiMAW `N(MASTER) m_maw,
    input AxiMR  `N(MASTER) m_mr,
    input AxiMW  `N(MASTER) m_mw,
    input AxiMB  `N(MASTER) m_mb,
    output AxiSAR `N(MASTER) m_sar,
    output AxiSAW `N(MASTER) m_saw,
    output AxiSR  `N(MASTER) m_sr,
    output AxiSW  `N(MASTER) m_sw,
    output AxiSB  `N(MASTER) m_sb,
    output AxiMAR `N(SLAVE)  s_mar,
    output AxiMAW `N(SLAVE)  s_maw,
    output AxiMR  `N(SLAVE)  s_mr,
    output AxiMW  `N(SLAVE)  s_mw,
    output AxiMB  `N(SLAVE)  s_mb,
    input AxiSAR `N(SLAVE)  s_sar,
    input AxiSAW `N(SLAVE)  s_saw,
    input AxiSR  `N(SLAVE)  s_sr,
    input AxiSW  `N(SLAVE)  s_sw,
    input AxiSB  `N(SLAVE)  s_sb
);
    localparam AWCH_W =  ADDR_WIDTH + ID_WIDTH + 29;
    localparam WCH_W = DATA_WIDTH + DATA_WIDTH/8;
    localparam BCH_W = ID_WIDTH + 2;
    localparam ARCH_W = AWCH_W;
    localparam RCH_W = DATA_WIDTH + ID_WIDTH + 2;

    logic `N(MASTER) s_awvalid, s_awready;
    logic `ARRAY(MASTER, AWCH_W) s_awch;
    logic `N(MASTER) s_wvalid, s_wready, s_wlast;
    logic `ARRAY(MASTER, WCH_W) s_wch;
    logic `N(MASTER) s_bvalid, s_bready;
    logic `ARRAY(MASTER, BCH_W) s_bch;
    logic `N(MASTER) s_arvalid, s_arready;
    logic `ARRAY(MASTER, ARCH_W) s_arch;
    logic `N(MASTER) s_rvalid, s_rready, s_rlast;
    logic `ARRAY(MASTER, RCH_W) s_rch;

    logic `N(SLAVE) m_awvalid, m_awready;
    logic `ARRAY(SLAVE, AWCH_W) m_awch;
    logic `N(SLAVE) m_wvalid, m_wready, m_wlast;
    logic `ARRAY(SLAVE, WCH_W) m_wch;
    logic `N(SLAVE) m_bvalid, m_bready;
    logic `ARRAY(SLAVE, BCH_W) m_bch;
    logic `N(SLAVE) m_arvalid, m_arready;
    logic `ARRAY(SLAVE, ARCH_W) m_arch;
    logic `N(SLAVE) m_rvalid, m_rready, m_rlast;
    logic `ARRAY(SLAVE, RCH_W) m_rch;
generate
    for(genvar i=0; i<MASTER; i++)begin
        AxiIO axi();
        assign axi.mar = m_mar[i];
        assign axi.maw = m_maw[i];
        assign axi.mr  = m_mr[i];
        assign axi.mw  = m_mw[i];
        assign axi.mb  = m_mb[i];
        assign m_sar[i] = axi.sar;
        assign m_saw[i] = axi.saw;
        assign m_sr[i]  = axi.sr;
        assign m_sw[i]  = axi.sw;
        assign m_sb[i]  = axi.sb;
        AxiSlaveWrapper #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .ID_WIDTH(ID_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .AWCH(AWCH_W),
            .WCH(WCH_W),
            .BCH(BCH_W),
            .ARCH(ARCH_W),
            .RCH(RCH_W)
        ) slave_wrapper(
            .clk(mclk[i]),
            .rst(mrst[i]),
            .slave(axi.slave),
            .aclk(clk),
            .aresetn(~rst),
            .srst(rst),
            .awvalid(s_awvalid[i]),
            .awready(s_awready[i]),
            .awch(s_awch[i]),
            .wvalid(s_wvalid[i]),
            .wready(s_wready[i]),
            .wlast(s_wlast[i]),
            .wch(s_wch[i]),
            .bvalid(s_bvalid[i]),
            .bready(s_bready[i]),
            .bch(s_bch[i]),
            .arvalid(s_arvalid[i]),
            .arready(s_arready[i]),
            .arch(s_arch[i]),
            .rvalid(s_rvalid[i]),
            .rready(s_rready[i]),
            .rlast(s_rlast[i]),
            .rch(s_rch[i])
        );
    end
endgenerate


    axicb_switch_top #(
        .AXI_ADDR_W(`PADDR_SIZE),
        .AXI_ID_W(`AXI_ID_W),
        .AXI_DATA_W(`XLEN),
        .AXI_SIGNALING(1),
        .MST_NB(MASTER),
        .SLV_NB(SLAVE),
        .MST_PIPELINE(0),
        .SLV_PIPELINE(0),
        .AWCH_W(AWCH_W),
        .WCH_W(WCH_W),
        .BCH_W(BCH_W),
        .ARCH_W(ARCH_W),
        .RCH_W(RCH_W),
        .SLV_START(SLV_START),
        .SLV_END(SLV_END)
    )switch(
        .aclk(clk),
        .aresetn(~rst),
        .srst(rst),
        .i_awvalid(s_awvalid),
        .i_awready(s_awready),
        .i_awch(s_awch),
        .i_wvalid(s_wvalid),
        .i_wready(s_wready),
        .i_wlast(s_wlast),
        .i_wch(s_wch),
        .i_bvalid(s_bvalid),
        .i_bready(s_bready),
        .i_bch(s_bch),
        .i_arvalid(s_arvalid),
        .i_arready(s_arready),
        .i_arch(s_arch),
        .i_rvalid(s_rvalid),
        .i_rready(s_rready),
        .i_rlast(s_rlast),
        .i_rch(s_rch),
        .o_awvalid(m_awvalid),
        .o_awready(m_awready),
        .o_awch(m_awch),
        .o_wvalid(m_wvalid),
        .o_wready(m_wready),
        .o_wlast(m_wlast),
        .o_wch(m_wch),
        .o_bvalid(m_bvalid),
        .o_bready(m_bready),
        .o_bch(m_bch),
        .o_arvalid(m_arvalid),
        .o_arready(m_arready),
        .o_arch(m_arch),
        .o_rvalid(m_rvalid),
        .o_rready(m_rready),
        .o_rlast(m_rlast),
        .o_rch(m_rch)
    );

generate
    for(genvar i=0; i<SLAVE; i++)begin
            AxiIO axi();
            assign s_mar[i] = axi.mar; 
            assign s_maw[i] = axi.maw; 
            assign s_mr[i] = axi.mr  ;
            assign s_mw[i] = axi.mw  ;
            assign s_mb[i] = axi.mb  ;
            assign axi.sar = s_sar[i];
            assign axi.saw = s_saw[i];
            assign axi.sr =  s_sr[i] ;
            assign axi.sw =  s_sw[i] ;
            assign axi.sb =  s_sb[i] ;
        AxiMasterWrapper #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .ID_WIDTH(ID_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .AWCH(AWCH_W),
            .WCH(WCH_W),
            .BCH(BCH_W),
            .ARCH(ARCH_W),
            .RCH(RCH_W)
        ) master_wrapper(
            .clk(clk),
            .rst(rst),
            .master(axi.master),
            .aclk(sclk[i]),
            .aresetn(~srst[i]),
            .srst(srst[i]),
            .awvalid(m_awvalid[i]),
            .awready(m_awready[i]),
            .awch(m_awch[i]),
            .wvalid(m_wvalid[i]),
            .wready(m_wready[i]),
            .wlast(m_wlast[i]),
            .wch(m_wch[i]),
            .bvalid(m_bvalid[i]),
            .bready(m_bready[i]),
            .bch(m_bch[i]),
            .arvalid(m_arvalid[i]),
            .arready(m_arready[i]),
            .arch(m_arch[i]),
            .rvalid(m_rvalid[i]),
            .rready(m_rready[i]),
            .rlast(m_rlast[i]),
            .rch(m_rch[i])
        );
    end
endgenerate

endmodule

module AxiSlaveWrapper #(
    parameter ADDR_WIDTH=32,
    parameter ID_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter AWCH = 8,
    parameter WCH = 8,
    parameter BCH = 8,
    parameter ARCH = 8,
    parameter RCH = 8
)(
    input logic clk,
    input logic rst,
    AxiIO.slave slave,
    input logic aclk,
    input logic aresetn,
    input logic srst,
    output logic awvalid,
    input logic awready,
    output logic [AWCH-1: 0] awch,
    output logic wvalid,
    input logic wready,
    output logic wlast,
    output logic [WCH-1: 0] wch,
    input logic bvalid,
    output logic bready,
    input logic [BCH-1: 0] bch,
    output logic arvalid,
    input logic arready,
    output logic [ARCH-1: 0] arch,
    input logic rvalid,
    output logic rready,
    input logic rlast,
    input logic [RCH-1: 0] rch
);
    axicb_slv_if #(
        .AXI_ADDR_W(ADDR_WIDTH),
        .AXI_ID_W(ID_WIDTH),
        .AXI_DATA_W(DATA_WIDTH),
        .AXI_SIGNALING(1),
        .AWCH_W(AWCH),
        .WCH_W(WCH),
        .BCH_W(BCH),
        .ARCH_W(ARCH),
        .RCH_W(RCH)
    ) slv_if (
        .i_aclk(clk),
        .i_aresetn(~rst),
        .i_srst(rst),
        .i_awvalid(slave.maw.valid),
        .i_awready(slave.saw.ready),
        .i_awaddr(slave.maw.addr),
        .i_awlen(slave.maw.len),
        .i_awsize(slave.maw.size),
        .i_awburst(slave.maw.burst),
        .i_awlock(slave.maw.lock),
        .i_awcache(slave.maw.cache),
        .i_awprot(slave.maw.prot),
        .i_awqos(slave.maw.qos),
        .i_awregion(slave.maw.region),
        .i_awid(slave.maw.id),
        .i_awuser(slave.maw.user),
        .i_wvalid(slave.mw.valid),
        .i_wready(slave.sw.ready),
        .i_wlast(slave.mw.last),
        .i_wdata(slave.mw.data),
        .i_wstrb(slave.mw.wstrb),
        .i_wuser(slave.mw.user),
        .i_bvalid(slave.sb.valid),
        .i_bready(slave.mb.ready),
        .i_bid(slave.sb.id),
        .i_bresp(slave.sb.resp),
        .i_buser(slave.sb.user),
        .i_arvalid(slave.mar.valid),
        .i_arready(slave.sar.ready),
        .i_araddr(slave.mar.addr),
        .i_arlen(slave.mar.len),
        .i_arsize(slave.mar.size),
        .i_arburst(slave.mar.burst),
        .i_arlock(slave.mar.lock),
        .i_arcache(slave.mar.cache),
        .i_arprot(slave.mar.prot),
        .i_arqos(slave.mar.qos),
        .i_arregion(slave.mar.region),
        .i_arid(slave.mar.id),
        .i_aruser(slave.mar.user),
        .i_rvalid(slave.sr.valid),
        .i_rready(slave.mr.ready),
        .i_rid(slave.sr.id),
        .i_rresp(slave.sr.resp),
        .i_rdata(slave.sr.data),
        .i_rlast(slave.sr.last),
        .i_ruser(slave.sr.user),
        .o_aclk(aclk),
        .o_aresetn(aresetn),
        .o_srst(srst),
        .o_awvalid(awvalid),
        .o_awready(awready),
        .o_awch(awch),
        .o_wvalid(wvalid),
        .o_wready(wready),
        .o_wlast(wlast),
        .o_wch(wch),
        .o_bvalid(bvalid),
        .o_bready(bready),
        .o_bch(bch),
        .o_arvalid(arvalid),
        .o_arready(arready),
        .o_arch(arch),
        .o_rvalid(rvalid),
        .o_rready(rready),
        .o_rlast(rlast),
        .o_rch(rch)
    );
endmodule

module AxiMasterWrapper #(
    parameter ADDR_WIDTH=32,
    parameter ID_WIDTH = 8,
    parameter DATA_WIDTH = 32,
    parameter AWCH = 8,
    parameter WCH = 8,
    parameter BCH = 8,
    parameter ARCH = 8,
    parameter RCH = 8
)(
    input logic clk,
    input logic rst,
    AxiIO.master master,
    input logic aclk,
    input logic aresetn,
    input logic srst,
    input logic awvalid,
    output logic awready,
    input logic [AWCH-1: 0] awch,
    input logic wvalid,
    output logic wready,
    input logic wlast,
    input logic [WCH-1: 0] wch,
    output logic bvalid,
    input logic bready,
    output logic [BCH-1: 0] bch,
    input logic arvalid,
    output logic arready,
    input logic [ARCH-1: 0] arch,
    output logic rvalid,
    input logic rready,
    output logic rlast,
    output logic [RCH-1: 0] rch
);
    axicb_mst_if #(
        .AXI_ADDR_W(ADDR_WIDTH),
        .AXI_ID_W(ID_WIDTH),
        .AXI_DATA_W(DATA_WIDTH),
        .AXI_SIGNALING(1),
        .AWCH_W(AWCH),
        .WCH_W(WCH),
        .BCH_W(BCH),
        .ARCH_W(ARCH),
        .RCH_W(RCH)
    ) slv_if (
        .o_aclk(aclk),
        .o_aresetn(aresetn),
        .o_srst(srst),
        .o_awvalid(master.maw.valid),
        .o_awready(master.saw.ready),
        .o_awaddr(master.maw.addr),
        .o_awlen(master.maw.len),
        .o_awsize(master.maw.size),
        .o_awburst(master.maw.burst),
        .o_awlock(master.maw.lock),
        .o_awcache(master.maw.cache),
        .o_awprot(master.maw.prot),
        .o_awqos(master.maw.qos),
        .o_awregion(master.maw.region),
        .o_awid(master.maw.id),
        .o_awuser(master.maw.user),
        .o_wvalid(master.mw.valid),
        .o_wready(master.sw.ready),
        .o_wlast(master.mw.last),
        .o_wdata(master.mw.data),
        .o_wstrb(master.mw.wstrb),
        .o_wuser(master.mw.user),
        .o_bvalid(master.sb.valid),
        .o_bready(master.mb.ready),
        .o_bid(master.sb.id),
        .o_bresp(master.sb.resp),
        .o_buser(master.sb.user),
        .o_arvalid(master.mar.valid),
        .o_arready(master.sar.ready),
        .o_araddr(master.mar.addr),
        .o_arlen(master.mar.len),
        .o_arsize(master.mar.size),
        .o_arburst(master.mar.burst),
        .o_arlock(master.mar.lock),
        .o_arcache(master.mar.cache),
        .o_arprot(master.mar.prot),
        .o_arqos(master.mar.qos),
        .o_arregion(master.mar.region),
        .o_arid(master.mar.id),
        .o_aruser(master.mar.user),
        .o_rvalid(master.sr.valid),
        .o_rready(master.mr.ready),
        .o_rid(master.sr.id),
        .o_rresp(master.sr.resp),
        .o_rdata(master.sr.data),
        .o_rlast(master.sr.last),
        .o_ruser(master.sr.user),
        .i_aclk(clk),
        .i_aresetn(~rst),
        .i_srst(rst),
        .i_awvalid(awvalid),
        .i_awready(awready),
        .i_awch(awch),
        .i_wvalid(wvalid),
        .i_wready(wready),
        .i_wlast(wlast),
        .i_wch(wch),
        .i_bvalid(bvalid),
        .i_bready(bready),
        .i_bch(bch),
        .i_arvalid(arvalid),
        .i_arready(arready),
        .i_arch(arch),
        .i_rvalid(rvalid),
        .i_rready(rready),
        .i_rlast(rlast),
        .i_rch(rch)
    );
endmodule