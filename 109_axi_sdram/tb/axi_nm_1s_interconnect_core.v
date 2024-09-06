`timescale 1ns / 1ps
/********************************************************************
本模块: AXI多主一从总线互联(核心)

描述: 
支持多达8个AXI主机
采用Round-Robin仲裁算法

注意：
以下非寄存器输出 ->
    从机R通道: sx_axi_rvalid
    从机W通道: sx_axi_wready
    从机B通道: sx_axi_bvalid
    主机R通道: m_axi_rready
    主机W通道: m_axi_wdata, m_axi_wstrb, m_axi_wlast, m_axi_wvalid
    主机B通道: m_axi_bready

协议:
AXI MASTER/SLAVE

作者: 陈家耀
日期: 2024/04/28
********************************************************************/


module axi_nm_1s_interconnect_core #(
    parameter integer master_n = 3, // 主机个数(必须在范围[2, 8]内)
    parameter integer arb_itv = 2, // 仲裁间隔周期数(必须在范围[2, 16]内)
    parameter real simulation_delay = 1 // 仿真延时
)(
    // 时钟和复位
    input wire clk,
    input wire rst_n,
    
    // 0号AXI从机
    // AR
    input wire[31:0] s0_axi_araddr,
    input wire[1:0] s0_axi_arburst,
    input wire[3:0] s0_axi_arcache,
    input wire[7:0] s0_axi_arlen,
    input wire s0_axi_arlock,
    input wire[2:0] s0_axi_arprot,
    input wire[2:0] s0_axi_arsize,
    input wire s0_axi_arvalid,
    output wire s0_axi_arready,
    // R
    output wire[31:0] s0_axi_rdata,
    output wire s0_axi_rlast,
    output wire[1:0] s0_axi_rresp,
    output wire s0_axi_rvalid,
    input wire s0_axi_rready,
    // AW
    input wire[31:0] s0_axi_awaddr,
    input wire[1:0] s0_axi_awburst,
    input wire[3:0] s0_axi_awcache,
    input wire[7:0] s0_axi_awlen,
    input wire s0_axi_awlock,
    input wire[2:0] s0_axi_awprot,
    input wire[2:0] s0_axi_awsize,
    input wire s0_axi_awvalid,
    output wire s0_axi_awready,
    // W
    input wire[31:0] s0_axi_wdata,
    input wire[3:0] s0_axi_wstrb,
    input wire s0_axi_wlast,
    input wire s0_axi_wvalid,
    output wire s0_axi_wready,
    // B
    output wire[1:0] s0_axi_bresp,
    output wire s0_axi_bvalid,
    input wire s0_axi_bready,
    
    // 1号AXI从机
    // AR
    input wire[31:0] s1_axi_araddr,
    input wire[1:0] s1_axi_arburst,
    input wire[3:0] s1_axi_arcache,
    input wire[7:0] s1_axi_arlen,
    input wire s1_axi_arlock,
    input wire[2:0] s1_axi_arprot,
    input wire[2:0] s1_axi_arsize,
    input wire s1_axi_arvalid,
    output wire s1_axi_arready,
    // R
    output wire[31:0] s1_axi_rdata,
    output wire s1_axi_rlast,
    output wire[1:0] s1_axi_rresp,
    output wire s1_axi_rvalid,
    input wire s1_axi_rready,
    // AW
    input wire[31:0] s1_axi_awaddr,
    input wire[1:0] s1_axi_awburst,
    input wire[3:0] s1_axi_awcache,
    input wire[7:0] s1_axi_awlen,
    input wire s1_axi_awlock,
    input wire[2:0] s1_axi_awprot,
    input wire[2:0] s1_axi_awsize,
    input wire s1_axi_awvalid,
    output wire s1_axi_awready,
    // W
    input wire[31:0] s1_axi_wdata,
    input wire[3:0] s1_axi_wstrb,
    input wire s1_axi_wlast,
    input wire s1_axi_wvalid,
    output wire s1_axi_wready,
    // B
    output wire[1:0] s1_axi_bresp,
    output wire s1_axi_bvalid,
    input wire s1_axi_bready,
    
    // 2号AXI从机
    // AR
    input wire[31:0] s2_axi_araddr,
    input wire[1:0] s2_axi_arburst,
    input wire[3:0] s2_axi_arcache,
    input wire[7:0] s2_axi_arlen,
    input wire s2_axi_arlock,
    input wire[2:0] s2_axi_arprot,
    input wire[2:0] s2_axi_arsize,
    input wire s2_axi_arvalid,
    output wire s2_axi_arready,
    // R
    output wire[31:0] s2_axi_rdata,
    output wire s2_axi_rlast,
    output wire[1:0] s2_axi_rresp,
    output wire s2_axi_rvalid,
    input wire s2_axi_rready,
    // AW
    input wire[31:0] s2_axi_awaddr,
    input wire[1:0] s2_axi_awburst,
    input wire[3:0] s2_axi_awcache,
    input wire[7:0] s2_axi_awlen,
    input wire s2_axi_awlock,
    input wire[2:0] s2_axi_awprot,
    input wire[2:0] s2_axi_awsize,
    input wire s2_axi_awvalid,
    output wire s2_axi_awready,
    // W
    input wire[31:0] s2_axi_wdata,
    input wire[3:0] s2_axi_wstrb,
    input wire s2_axi_wlast,
    input wire s2_axi_wvalid,
    output wire s2_axi_wready,
    // B
    output wire[1:0] s2_axi_bresp,
    output wire s2_axi_bvalid,
    input wire s2_axi_bready,
    
    // 3号AXI从机
    // AR
    input wire[31:0] s3_axi_araddr,
    input wire[1:0] s3_axi_arburst,
    input wire[3:0] s3_axi_arcache,
    input wire[7:0] s3_axi_arlen,
    input wire s3_axi_arlock,
    input wire[2:0] s3_axi_arprot,
    input wire[2:0] s3_axi_arsize,
    input wire s3_axi_arvalid,
    output wire s3_axi_arready,
    // R
    output wire[31:0] s3_axi_rdata,
    output wire s3_axi_rlast,
    output wire[1:0] s3_axi_rresp,
    output wire s3_axi_rvalid,
    input wire s3_axi_rready,
    // AW
    input wire[31:0] s3_axi_awaddr,
    input wire[1:0] s3_axi_awburst,
    input wire[3:0] s3_axi_awcache,
    input wire[7:0] s3_axi_awlen,
    input wire s3_axi_awlock,
    input wire[2:0] s3_axi_awprot,
    input wire[2:0] s3_axi_awsize,
    input wire s3_axi_awvalid,
    output wire s3_axi_awready,
    // W
    input wire[31:0] s3_axi_wdata,
    input wire[3:0] s3_axi_wstrb,
    input wire s3_axi_wlast,
    input wire s3_axi_wvalid,
    output wire s3_axi_wready,
    // B
    output wire[1:0] s3_axi_bresp,
    output wire s3_axi_bvalid,
    input wire s3_axi_bready,
    
    // 4号AXI从机
    // AR
    input wire[31:0] s4_axi_araddr,
    input wire[1:0] s4_axi_arburst,
    input wire[3:0] s4_axi_arcache,
    input wire[7:0] s4_axi_arlen,
    input wire s4_axi_arlock,
    input wire[2:0] s4_axi_arprot,
    input wire[2:0] s4_axi_arsize,
    input wire s4_axi_arvalid,
    output wire s4_axi_arready,
    // R
    output wire[31:0] s4_axi_rdata,
    output wire s4_axi_rlast,
    output wire[1:0] s4_axi_rresp,
    output wire s4_axi_rvalid,
    input wire s4_axi_rready,
    // AW
    input wire[31:0] s4_axi_awaddr,
    input wire[1:0] s4_axi_awburst,
    input wire[3:0] s4_axi_awcache,
    input wire[7:0] s4_axi_awlen,
    input wire s4_axi_awlock,
    input wire[2:0] s4_axi_awprot,
    input wire[2:0] s4_axi_awsize,
    input wire s4_axi_awvalid,
    output wire s4_axi_awready,
    // W
    input wire[31:0] s4_axi_wdata,
    input wire[3:0] s4_axi_wstrb,
    input wire s4_axi_wlast,
    input wire s4_axi_wvalid,
    output wire s4_axi_wready,
    // B
    output wire[1:0] s4_axi_bresp,
    output wire s4_axi_bvalid,
    input wire s4_axi_bready,
    
    // 5号AXI从机
    // AR
    input wire[31:0] s5_axi_araddr,
    input wire[1:0] s5_axi_arburst,
    input wire[3:0] s5_axi_arcache,
    input wire[7:0] s5_axi_arlen,
    input wire s5_axi_arlock,
    input wire[2:0] s5_axi_arprot,
    input wire[2:0] s5_axi_arsize,
    input wire s5_axi_arvalid,
    output wire s5_axi_arready,
    // R
    output wire[31:0] s5_axi_rdata,
    output wire s5_axi_rlast,
    output wire[1:0] s5_axi_rresp,
    output wire s5_axi_rvalid,
    input wire s5_axi_rready,
    // AW
    input wire[31:0] s5_axi_awaddr,
    input wire[1:0] s5_axi_awburst,
    input wire[3:0] s5_axi_awcache,
    input wire[7:0] s5_axi_awlen,
    input wire s5_axi_awlock,
    input wire[2:0] s5_axi_awprot,
    input wire[2:0] s5_axi_awsize,
    input wire s5_axi_awvalid,
    output wire s5_axi_awready,
    // W
    input wire[31:0] s5_axi_wdata,
    input wire[3:0] s5_axi_wstrb,
    input wire s5_axi_wlast,
    input wire s5_axi_wvalid,
    output wire s5_axi_wready,
    // B
    output wire[1:0] s5_axi_bresp,
    output wire s5_axi_bvalid,
    input wire s5_axi_bready,
    
    // 6号AXI从机
    // AR
    input wire[31:0] s6_axi_araddr,
    input wire[1:0] s6_axi_arburst,
    input wire[3:0] s6_axi_arcache,
    input wire[7:0] s6_axi_arlen,
    input wire s6_axi_arlock,
    input wire[2:0] s6_axi_arprot,
    input wire[2:0] s6_axi_arsize,
    input wire s6_axi_arvalid,
    output wire s6_axi_arready,
    // R
    output wire[31:0] s6_axi_rdata,
    output wire s6_axi_rlast,
    output wire[1:0] s6_axi_rresp,
    output wire s6_axi_rvalid,
    input wire s6_axi_rready,
    // AW
    input wire[31:0] s6_axi_awaddr,
    input wire[1:0] s6_axi_awburst,
    input wire[3:0] s6_axi_awcache,
    input wire[7:0] s6_axi_awlen,
    input wire s6_axi_awlock,
    input wire[2:0] s6_axi_awprot,
    input wire[2:0] s6_axi_awsize,
    input wire s6_axi_awvalid,
    output wire s6_axi_awready,
    // W
    input wire[31:0] s6_axi_wdata,
    input wire[3:0] s6_axi_wstrb,
    input wire s6_axi_wlast,
    input wire s6_axi_wvalid,
    output wire s6_axi_wready,
    // B
    output wire[1:0] s6_axi_bresp,
    output wire s6_axi_bvalid,
    input wire s6_axi_bready,
    
    // 7号AXI从机
    // AR
    input wire[31:0] s7_axi_araddr,
    input wire[1:0] s7_axi_arburst,
    input wire[3:0] s7_axi_arcache,
    input wire[7:0] s7_axi_arlen,
    input wire s7_axi_arlock,
    input wire[2:0] s7_axi_arprot,
    input wire[2:0] s7_axi_arsize,
    input wire s7_axi_arvalid,
    output wire s7_axi_arready,
    // R
    output wire[31:0] s7_axi_rdata,
    output wire s7_axi_rlast,
    output wire[1:0] s7_axi_rresp,
    output wire s7_axi_rvalid,
    input wire s7_axi_rready,
    // AW
    input wire[31:0] s7_axi_awaddr,
    input wire[1:0] s7_axi_awburst,
    input wire[3:0] s7_axi_awcache,
    input wire[7:0] s7_axi_awlen,
    input wire s7_axi_awlock,
    input wire[2:0] s7_axi_awprot,
    input wire[2:0] s7_axi_awsize,
    input wire s7_axi_awvalid,
    output wire s7_axi_awready,
    // W
    input wire[31:0] s7_axi_wdata,
    input wire[3:0] s7_axi_wstrb,
    input wire s7_axi_wlast,
    input wire s7_axi_wvalid,
    output wire s7_axi_wready,
    // B
    output wire[1:0] s7_axi_bresp,
    output wire s7_axi_bvalid,
    input wire s7_axi_bready,
    
    // AXI主机
    // AR
    output wire[31:0] m_axi_araddr,
    output wire[1:0] m_axi_arburst,
    output wire[3:0] m_axi_arcache,
    output wire[7:0] m_axi_arlen,
    output wire m_axi_arlock,
    output wire[2:0] m_axi_arprot,
    output wire[2:0] m_axi_arsize,
    output wire[clogb2(master_n-1):0] m_axi_arid,
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // R
    input wire[31:0] m_axi_rdata,
    input wire m_axi_rlast,
    input wire[1:0] m_axi_rresp,
    input wire[clogb2(master_n-1):0] m_axi_rid,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // AW
    output wire[31:0] m_axi_awaddr,
    output wire[1:0] m_axi_awburst,
    output wire[3:0] m_axi_awcache,
    output wire[7:0] m_axi_awlen,
    output wire m_axi_awlock,
    output wire[2:0] m_axi_awprot,
    output wire[2:0] m_axi_awsize,
    output wire[clogb2(master_n-1):0] m_axi_awid,
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // W
    output wire[31:0] m_axi_wdata,
    output wire[3:0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input wire m_axi_wready,
    // B
    input wire[1:0] m_axi_bresp,
    input wire[clogb2(master_n-1):0] m_axi_bid,
    input wire m_axi_bvalid,
    output wire m_axi_bready
);
    
    // 计算log2(bit_depth)               
    function integer clogb2 (input integer bit_depth);
        integer temp;
    begin
        temp = bit_depth;
        for(clogb2 = -1;temp > 0;clogb2 = clogb2 + 1)
            temp = temp >> 1;
    end
    endfunction
    
    /** 常量 **/
    // 响应类型
    localparam RESP_OKAY = 2'b00;
    localparam RESP_EXOKAY = 2'b01;
    localparam RESP_SLVERR = 2'b10;
    localparam RESP_DECERR = 2'b11;
    
    /** AXI读地址/读数据通道 **/
    // AXI读通道
    wire[52:0] s_ar_payload[7:0]; // 从机AR通道的负载
    wire[7:0] s_ar_valid; // 从机AR通道的valid信号
    wire[7:0] s_ar_ready; // 从机AR通道的ready信号
    wire[7:0] s_r_valid; // 从机R通道的valid信号
    wire[7:0] s_r_ready; // 从机R通道的ready信号
    wire[52:0] m_ar_payload; // 主机AR通道的负载
    // AR通道授权主机编号fifo写端口
    wire ar_grant_mid_fifo_wen;
    wire ar_grant_mid_fifo_full_n;
    wire[master_n-1:0] ar_grant_mid_fifo_din_onehot; // 独热码编号
    // AR通道授权主机编号fifo读端口
    wire ar_grant_mid_fifo_ren;
    wire ar_grant_mid_fifo_empty_n;
    wire[master_n-1:0] ar_grant_mid_fifo_dout_onehot;
    
    // 从机AR通道的负载
    assign s_ar_payload[0] = {s0_axi_araddr, s0_axi_arburst, s0_axi_arcache, s0_axi_arlen, s0_axi_arlock, s0_axi_arprot, s0_axi_arsize};
    assign s_ar_payload[1] = {s1_axi_araddr, s1_axi_arburst, s1_axi_arcache, s1_axi_arlen, s1_axi_arlock, s1_axi_arprot, s1_axi_arsize};
    assign s_ar_payload[2] = {s2_axi_araddr, s2_axi_arburst, s2_axi_arcache, s2_axi_arlen, s2_axi_arlock, s2_axi_arprot, s2_axi_arsize};
    assign s_ar_payload[3] = {s3_axi_araddr, s3_axi_arburst, s3_axi_arcache, s3_axi_arlen, s3_axi_arlock, s3_axi_arprot, s3_axi_arsize};
    assign s_ar_payload[4] = {s4_axi_araddr, s4_axi_arburst, s4_axi_arcache, s4_axi_arlen, s4_axi_arlock, s4_axi_arprot, s4_axi_arsize};
    assign s_ar_payload[5] = {s5_axi_araddr, s5_axi_arburst, s5_axi_arcache, s5_axi_arlen, s5_axi_arlock, s5_axi_arprot, s5_axi_arsize};
    assign s_ar_payload[6] = {s6_axi_araddr, s6_axi_arburst, s6_axi_arcache, s6_axi_arlen, s6_axi_arlock, s6_axi_arprot, s6_axi_arsize};
    assign s_ar_payload[7] = {s7_axi_araddr, s7_axi_arburst, s7_axi_arcache, s7_axi_arlen, s7_axi_arlock, s7_axi_arprot, s7_axi_arsize};
    // 从机AR通道的valid信号
    assign s_ar_valid = {s7_axi_arvalid, s6_axi_arvalid, s5_axi_arvalid, s4_axi_arvalid, 
        s3_axi_arvalid, s2_axi_arvalid, s1_axi_arvalid, s0_axi_arvalid};
    // 从机AR通道的ready信号
    assign {s7_axi_arready, s6_axi_arready, s5_axi_arready, s4_axi_arready, 
        s3_axi_arready, s2_axi_arready, s1_axi_arready, s0_axi_arready} = s_ar_ready;
    // 从机R通道的负载
    assign {s0_axi_rdata, s0_axi_rresp, s0_axi_rlast} = {m_axi_rdata, m_axi_rresp, m_axi_rlast};
    assign {s1_axi_rdata, s1_axi_rresp, s1_axi_rlast} = {m_axi_rdata, (master_n >= 2) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    assign {s2_axi_rdata, s2_axi_rresp, s2_axi_rlast} = {m_axi_rdata, (master_n >= 3) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    assign {s3_axi_rdata, s3_axi_rresp, s3_axi_rlast} = {m_axi_rdata, (master_n >= 4) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    assign {s4_axi_rdata, s4_axi_rresp, s4_axi_rlast} = {m_axi_rdata, (master_n >= 5) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    assign {s5_axi_rdata, s5_axi_rresp, s5_axi_rlast} = {m_axi_rdata, (master_n >= 6) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    assign {s6_axi_rdata, s6_axi_rresp, s6_axi_rlast} = {m_axi_rdata, (master_n >= 7) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    assign {s7_axi_rdata, s7_axi_rresp, s7_axi_rlast} = {m_axi_rdata, (master_n >= 8) ? m_axi_rresp:RESP_DECERR, m_axi_rlast};
    // 从机R通道的valid信号
    assign {s7_axi_rvalid, s6_axi_rvalid, s5_axi_rvalid, s4_axi_rvalid, 
        s3_axi_rvalid, s2_axi_rvalid, s1_axi_rvalid, s0_axi_rvalid} = s_r_valid;
    // 从机R通道的ready信号
    assign s_r_ready = {s7_axi_rready, s6_axi_rready, s5_axi_rready, s4_axi_rready, 
        s3_axi_rready, s2_axi_rready, s1_axi_rready, s0_axi_rready};
    // 主机AR通道的负载
    assign {m_axi_araddr, m_axi_arburst, m_axi_arcache, m_axi_arlen, m_axi_arlock, m_axi_arprot, m_axi_arsize} = m_ar_payload;
    
    /** AXI读通道仲裁与路由 **/
    // AXI读地址通道仲裁
    axi_arbitrator #(
        .master_n(master_n),
        .arb_itv(arb_itv),
        .simulation_delay(simulation_delay)
    )axi_ar_arbitrator(
        .clk(clk),
        .rst_n(rst_n),
        
        .s0_ar_aw_payload(s_ar_payload[0]),
        .s1_ar_aw_payload(s_ar_payload[1]),
        .s2_ar_aw_payload(s_ar_payload[2]),
        .s3_ar_aw_payload(s_ar_payload[3]),
        .s4_ar_aw_payload(s_ar_payload[4]),
        .s5_ar_aw_payload(s_ar_payload[5]),
        .s6_ar_aw_payload(s_ar_payload[6]),
        .s7_ar_aw_payload(s_ar_payload[7]),
        .s_ar_aw_valid(s_ar_valid),
        .s_ar_aw_ready(s_ar_ready),
        
        .m_ar_aw_payload(m_ar_payload),
        .m_ar_aw_id(m_axi_arid),
        .m_ar_aw_valid(m_axi_arvalid),
        .m_ar_aw_ready(m_axi_arready),
        
        .grant_mid_fifo_wen(ar_grant_mid_fifo_wen),
        .grant_mid_fifo_full_n(ar_grant_mid_fifo_full_n),
        .grant_mid_fifo_din_onehot(ar_grant_mid_fifo_din_onehot),
        .grant_mid_fifo_din_bin()
    );
    
    // AXI读数据通道路由
    axi_rchn_router #(
        .master_n(master_n),
        .simulation_delay(simulation_delay)
    )axi_r_router(
        .clk(clk),
        .rst_n(rst_n),
        
        .s_rvalid(s_r_valid),
        .s_rready(s_r_ready),
        
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        
        .grant_mid_fifo_ren(ar_grant_mid_fifo_ren),
        .grant_mid_fifo_empty_n(ar_grant_mid_fifo_empty_n),
        .grant_mid_fifo_dout_onehot(ar_grant_mid_fifo_dout_onehot)
    );
    
    // AR通道授权主机编号fifo
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(4),
        .fifo_data_width(master_n),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )ar_grant_mid_fifo(
        .clk(clk),
        .rst_n(rst_n),
        
        .fifo_wen(ar_grant_mid_fifo_wen),
        .fifo_din(ar_grant_mid_fifo_din_onehot),
        .fifo_full_n(ar_grant_mid_fifo_full_n),
        
        .fifo_ren(ar_grant_mid_fifo_ren),
        .fifo_dout(ar_grant_mid_fifo_dout_onehot),
        .fifo_empty_n(ar_grant_mid_fifo_empty_n)
    );
    
    /** AXI写地址/写数据/写响应通道 **/
    // AXI写通道
    wire[52:0] s_aw_payload[7:0]; // 从机AW通道的负载
    wire[7:0] s_aw_valid; // 从机AW通道的valid信号
    wire[7:0] s_aw_ready; // 从机AW通道的ready信号
    wire[35:0] s_w_payload[7:0]; // 从机W通道的负载
    wire[7:0] s_w_last; // 从机W通道的last信号
    wire[7:0] s_w_valid; // 从机W通道的valid信号
    wire[7:0] s_w_ready; // 从机W通道的ready信号
    wire[7:0] s_b_valid; // 从机B通道的valid信号
    wire[7:0] s_b_ready; // 从机B通道的ready信号
    wire[52:0] m_aw_payload; // 主机AW通道的负载
    wire[35:0] m_w_payload; // 主机W通道的负载
    // AW通道授权主机编号fifo写端口
    wire aw_grant_mid_fifo_wen;
    wire aw_grant_mid_fifo_full_n;
    wire[master_n-1:0] aw_grant_mid_fifo_din_onehot; // 独热码编号
    wire[clogb2(master_n-1):0] aw_grant_mid_fifo_din_bin; // 二进制码编号
    // AW通道授权主机编号fifo读端口
    wire aw_grant_mid_fifo_ren;
    wire aw_grant_mid_fifo_empty_n;
    wire[master_n-1:0] aw_grant_mid_fifo_dout_onehot; // 独热码编号
    wire[clogb2(master_n-1):0] aw_grant_mid_fifo_dout_bin; // 二进制码编号
    
    // 从机AW通道的负载
    assign s_aw_payload[0] = {s0_axi_awaddr, s0_axi_awburst, s0_axi_awcache, s0_axi_awlen, s0_axi_awlock, s0_axi_awprot, s0_axi_awsize};
    assign s_aw_payload[1] = {s1_axi_awaddr, s1_axi_awburst, s1_axi_awcache, s1_axi_awlen, s1_axi_awlock, s1_axi_awprot, s1_axi_awsize};
    assign s_aw_payload[2] = {s2_axi_awaddr, s2_axi_awburst, s2_axi_awcache, s2_axi_awlen, s2_axi_awlock, s2_axi_awprot, s2_axi_awsize};
    assign s_aw_payload[3] = {s3_axi_awaddr, s3_axi_awburst, s3_axi_awcache, s3_axi_awlen, s3_axi_awlock, s3_axi_awprot, s3_axi_awsize};
    assign s_aw_payload[4] = {s4_axi_awaddr, s4_axi_awburst, s4_axi_awcache, s4_axi_awlen, s4_axi_awlock, s4_axi_awprot, s4_axi_awsize};
    assign s_aw_payload[5] = {s5_axi_awaddr, s5_axi_awburst, s5_axi_awcache, s5_axi_awlen, s5_axi_awlock, s5_axi_awprot, s5_axi_awsize};
    assign s_aw_payload[6] = {s6_axi_awaddr, s6_axi_awburst, s6_axi_awcache, s6_axi_awlen, s6_axi_awlock, s6_axi_awprot, s6_axi_awsize};
    assign s_aw_payload[7] = {s7_axi_awaddr, s7_axi_awburst, s7_axi_awcache, s7_axi_awlen, s7_axi_awlock, s7_axi_awprot, s7_axi_awsize};
    // 从机AW通道的valid信号
    assign s_aw_valid = {s7_axi_awvalid, s6_axi_awvalid, s5_axi_awvalid, s4_axi_awvalid, 
        s3_axi_awvalid, s2_axi_awvalid, s1_axi_awvalid, s0_axi_awvalid};
    // 从机AW通道的ready信号
    assign {s7_axi_awready, s6_axi_awready, s5_axi_awready, s4_axi_awready, 
        s3_axi_awready, s2_axi_awready, s1_axi_awready, s0_axi_awready} = s_aw_ready;
    // 从机W通道的负载
    assign s_w_payload[0] = {s0_axi_wdata, s0_axi_wstrb};
    assign s_w_payload[1] = {s1_axi_wdata, s1_axi_wstrb};
    assign s_w_payload[2] = {s2_axi_wdata, s2_axi_wstrb};
    assign s_w_payload[3] = {s3_axi_wdata, s3_axi_wstrb};
    assign s_w_payload[4] = {s4_axi_wdata, s4_axi_wstrb};
    assign s_w_payload[5] = {s5_axi_wdata, s5_axi_wstrb};
    assign s_w_payload[6] = {s6_axi_wdata, s6_axi_wstrb};
    assign s_w_payload[7] = {s7_axi_wdata, s7_axi_wstrb};
    // 从机W通道的last信号
    assign s_w_last = {s7_axi_wlast, s6_axi_wlast, s5_axi_wlast, s4_axi_wlast,
        s3_axi_wlast, s2_axi_wlast, s1_axi_wlast, s0_axi_wlast};
    // 从机W通道的valid信号
    assign s_w_valid = {s7_axi_wvalid, s6_axi_wvalid, s5_axi_wvalid, s4_axi_wvalid,
        s3_axi_wvalid, s2_axi_wvalid, s1_axi_wvalid, s0_axi_wvalid};
    // 从机W通道的ready信号
    assign {s7_axi_wready, s6_axi_wready, s5_axi_wready, s4_axi_wready,
        s3_axi_wready, s2_axi_wready, s1_axi_wready, s0_axi_wready} = s_w_ready;
    // 从机B通道的负载
    assign s0_axi_bresp = m_axi_bresp;
    assign s1_axi_bresp = (master_n >= 2) ? m_axi_bresp:RESP_DECERR;
    assign s2_axi_bresp = (master_n >= 3) ? m_axi_bresp:RESP_DECERR;
    assign s3_axi_bresp = (master_n >= 4) ? m_axi_bresp:RESP_DECERR;
    assign s4_axi_bresp = (master_n >= 5) ? m_axi_bresp:RESP_DECERR;
    assign s5_axi_bresp = (master_n >= 6) ? m_axi_bresp:RESP_DECERR;
    assign s6_axi_bresp = (master_n >= 7) ? m_axi_bresp:RESP_DECERR;
    assign s7_axi_bresp = (master_n >= 8) ? m_axi_bresp:RESP_DECERR;
    // 从机B通道的valid信号
    assign {s7_axi_bvalid, s6_axi_bvalid, s5_axi_bvalid, s4_axi_bvalid, 
        s3_axi_bvalid, s2_axi_bvalid, s1_axi_bvalid, s0_axi_bvalid} = s_b_valid;
    // 从机B通道的ready信号
    assign s_b_ready = {s7_axi_bready, s6_axi_bready, s5_axi_bready, s4_axi_bready, 
        s3_axi_bready, s2_axi_bready, s1_axi_bready, s0_axi_bready};
    // 主机AW通道的负载
    assign {m_axi_awaddr, m_axi_awburst, m_axi_awcache, m_axi_awlen, m_axi_awlock, m_axi_awprot, m_axi_awsize} = m_aw_payload;
    // 主机W通道的负载
    assign {m_axi_wdata, m_axi_wstrb} = m_w_payload;
    
    /** AXI写通道仲裁与路由 **/
    // AXI写地址通道仲裁
    axi_arbitrator #(
        .master_n(master_n),
        .arb_itv(arb_itv),
        .simulation_delay(simulation_delay)
    )axi_aw_arbitrator(
        .clk(clk),
        .rst_n(rst_n),
        
        .s0_ar_aw_payload(s_aw_payload[0]),
        .s1_ar_aw_payload(s_aw_payload[1]),
        .s2_ar_aw_payload(s_aw_payload[2]),
        .s3_ar_aw_payload(s_aw_payload[3]),
        .s4_ar_aw_payload(s_aw_payload[4]),
        .s5_ar_aw_payload(s_aw_payload[5]),
        .s6_ar_aw_payload(s_aw_payload[6]),
        .s7_ar_aw_payload(s_aw_payload[7]),
        .s_ar_aw_valid(s_aw_valid),
        .s_ar_aw_ready(s_aw_ready),
        
        .m_ar_aw_payload(m_aw_payload),
        .m_ar_aw_id(m_axi_awid),
        .m_ar_aw_valid(m_axi_awvalid),
        .m_ar_aw_ready(m_axi_awready),
        
        .grant_mid_fifo_wen(aw_grant_mid_fifo_wen),
        .grant_mid_fifo_full_n(aw_grant_mid_fifo_full_n),
        .grant_mid_fifo_din_onehot(aw_grant_mid_fifo_din_onehot),
        .grant_mid_fifo_din_bin(aw_grant_mid_fifo_din_bin)
    );
    
    // AXI写数据/写响应通道路由
    axi_wchn_router #(
        .master_n(master_n),
        .simulation_delay(simulation_delay)
    )axi_w_b_router(
        .clk(clk),
        .rst_n(rst_n),
        
        .s0_w_payload(s_w_payload[0]),
        .s1_w_payload(s_w_payload[1]),
        .s2_w_payload(s_w_payload[2]),
        .s3_w_payload(s_w_payload[3]),
        .s4_w_payload(s_w_payload[4]),
        .s5_w_payload(s_w_payload[5]),
        .s6_w_payload(s_w_payload[6]),
        .s7_w_payload(s_w_payload[7]),
        .s_w_last(s_w_last),
        .s_w_valid(s_w_valid),
        .s_w_ready(s_w_ready),
        .s_b_valid(s_b_valid),
        .s_b_ready(s_b_ready),
        
        .m_w_payload(m_w_payload),
        .m_w_last(m_axi_wlast),
        .m_w_valid(m_axi_wvalid),
        .m_w_ready(m_axi_wready),
        .m_b_valid(m_axi_bvalid),
        .m_b_ready(m_axi_bready),
        
        .grant_mid_fifo_ren(aw_grant_mid_fifo_ren),
        .grant_mid_fifo_empty_n(aw_grant_mid_fifo_empty_n),
        .grant_mid_fifo_dout_onehot(aw_grant_mid_fifo_dout_onehot),
        .grant_mid_fifo_dout_bin(aw_grant_mid_fifo_dout_bin)
    );
    
    // AW通道授权主机编号fifo
    fifo_based_on_regs #(
        .fwft_mode("true"),
        .fifo_depth(4),
        .fifo_data_width(master_n + clogb2(master_n-1) + 1),
        .almost_full_th(),
        .almost_empty_th(),
        .simulation_delay(simulation_delay)
    )aw_grant_mid_fifo(
        .clk(clk),
        .rst_n(rst_n),
        
        .fifo_wen(aw_grant_mid_fifo_wen),
        .fifo_din({aw_grant_mid_fifo_din_onehot, aw_grant_mid_fifo_din_bin}),
        .fifo_full_n(aw_grant_mid_fifo_full_n),
        
        .fifo_ren(aw_grant_mid_fifo_ren),
        .fifo_dout({aw_grant_mid_fifo_dout_onehot, aw_grant_mid_fifo_dout_bin}),
        .fifo_empty_n(aw_grant_mid_fifo_empty_n)
    );
    
endmodule
