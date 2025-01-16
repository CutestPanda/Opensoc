`timescale 1ns / 1ps
/********************************************************************
本模块: ICB到AXI-Lite桥

描述:
将ICB主机转换为AXI-Lite主机

注意：
无

协议:
ICB SLAVE
AXI-Lite MASTER

作者: 陈家耀
日期: 2025/01/16
********************************************************************/


module icb_axi_bridge #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_addr,
	input wire s_icb_cmd_read,
	input wire[31:0] s_icb_cmd_wdata,
	input wire[3:0] s_icb_cmd_wmask,
	input wire s_icb_cmd_valid,
	output wire s_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_rdata,
	output wire s_icb_rsp_err,
	output wire s_icb_rsp_valid,
	input wire s_icb_rsp_ready,
	
	// AXI-Lite主机
	// 读地址通道
    output wire[31:0] m_axi_araddr,
    output wire[2:0] m_axi_arprot, // const -> 3'b000
    output wire m_axi_arvalid,
    input wire m_axi_arready,
    // 写地址通道
    output wire[31:0] m_axi_awaddr,
    output wire[2:0] m_axi_awprot, // const -> 3'b000
    output wire m_axi_awvalid,
    input wire m_axi_awready,
    // 写响应通道
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_bresp,
    input wire m_axi_bvalid,
    output wire m_axi_bready,
    // 读数据通道
    input wire[31:0] m_axi_rdata,
    // 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
    input wire[1:0] m_axi_rresp,
    input wire m_axi_rvalid,
    output wire m_axi_rready,
    // 写数据通道
    output wire[31:0] m_axi_wdata,
    output wire[3:0] m_axi_wstrb,
    output wire m_axi_wvalid,
    input wire m_axi_wready
);
	
	/** 写数据低时延fifo **/
	// fifo写端口
	wire wchn_fifo_wen;
	wire[31:0] wchn_fifo_din_wdata;
	wire[3:0] wchn_fifo_din_wstrb;
	wire wchn_fifo_full_n;
	// fifo读端口
	wire wchn_fifo_ren;
	wire[31:0] wchn_fifo_dout_wdata;
	wire[3:0] wchn_fifo_dout_wstrb;
	wire wchn_fifo_empty_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("true"),
		.fifo_depth(2),
		.fifo_data_width(36),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(simulation_delay)
	)wchn_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(wchn_fifo_wen),
		.fifo_din({wchn_fifo_din_wdata, wchn_fifo_din_wstrb}),
		.fifo_full_n(wchn_fifo_full_n),
		
		.fifo_ren(wchn_fifo_ren),
		.fifo_dout({wchn_fifo_dout_wdata, wchn_fifo_dout_wstrb}),
		.fifo_empty_n(wchn_fifo_empty_n)
	);
	
	/** ICB事务信息fifo **/
	// fifo写端口
	wire icb_trans_msg_fifo_wen;
	wire icb_trans_msg_fifo_din_is_read;
	wire icb_trans_msg_fifo_full_n;
	// fifo读端口
	wire icb_trans_msg_fifo_ren;
	wire icb_trans_msg_fifo_dout_is_read;
	wire icb_trans_msg_fifo_empty_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(2),
		.fifo_data_width(1),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(simulation_delay)
	)icb_trans_msg_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(icb_trans_msg_fifo_wen),
		.fifo_din(icb_trans_msg_fifo_din_is_read),
		.fifo_full_n(icb_trans_msg_fifo_full_n),
		
		.fifo_ren(icb_trans_msg_fifo_ren),
		.fifo_dout(icb_trans_msg_fifo_dout_is_read),
		.fifo_empty_n(icb_trans_msg_fifo_empty_n)
	);
	
	/**
	协议转换
	
	将ICB从机的命令通道路由到AXI主机的AR/AW通道
	保存ICB从机命令通道上的写数据, 接入AXI主机的W通道
	保存ICB事务信息, 将AXI主机的R/B通道路由到ICB从机的响应通道
	**/
	assign s_icb_cmd_ready = 
		icb_trans_msg_fifo_full_n & (s_icb_cmd_read ? m_axi_arready:(m_axi_awready & wchn_fifo_full_n));
	
	assign s_icb_rsp_rdata = m_axi_rdata;
	assign s_icb_rsp_err = icb_trans_msg_fifo_dout_is_read ? m_axi_rresp[1]:m_axi_bresp[1];
	assign s_icb_rsp_valid = icb_trans_msg_fifo_empty_n & (icb_trans_msg_fifo_dout_is_read ? m_axi_rvalid:m_axi_bvalid);
	
	assign m_axi_araddr = s_icb_cmd_addr;
	assign m_axi_arprot = 3'b000;
	assign m_axi_arvalid = icb_trans_msg_fifo_full_n & s_icb_cmd_valid & s_icb_cmd_read;
	
	assign m_axi_awaddr = s_icb_cmd_addr;
	assign m_axi_awprot = 3'b000;
	assign m_axi_awvalid = icb_trans_msg_fifo_full_n & s_icb_cmd_valid & (~s_icb_cmd_read) & wchn_fifo_full_n;
	
	assign m_axi_bready = icb_trans_msg_fifo_empty_n & (~icb_trans_msg_fifo_dout_is_read) & s_icb_rsp_ready;
	
	assign m_axi_rready = icb_trans_msg_fifo_empty_n & icb_trans_msg_fifo_dout_is_read & s_icb_rsp_ready;
	
	assign m_axi_wdata = wchn_fifo_dout_wdata;
	assign m_axi_wstrb = wchn_fifo_dout_wstrb;
	assign m_axi_wvalid = wchn_fifo_empty_n;
	
	assign wchn_fifo_wen = icb_trans_msg_fifo_full_n & s_icb_cmd_valid & (~s_icb_cmd_read) & m_axi_awready;
	assign wchn_fifo_din_wdata = s_icb_cmd_wdata;
	assign wchn_fifo_din_wstrb = s_icb_cmd_wmask;
	assign wchn_fifo_ren = m_axi_wready;
	
	assign icb_trans_msg_fifo_wen = s_icb_cmd_valid & (s_icb_cmd_read ? m_axi_arready:(m_axi_awready & wchn_fifo_full_n));
	assign icb_trans_msg_fifo_din_is_read = s_icb_cmd_read;
	assign icb_trans_msg_fifo_ren = s_icb_rsp_ready & (icb_trans_msg_fifo_dout_is_read ? m_axi_rvalid:m_axi_bvalid);
	
endmodule
