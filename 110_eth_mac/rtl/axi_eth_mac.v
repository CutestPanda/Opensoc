`timescale 1ns / 1ps
/********************************************************************
本模块: AXI-以太网MAC

描述:
带发送/接收fifo的以太网MAC
基于描述符的DMA传输
带寄存器配置接口

注意：
MDIO控制器、中断请求信号位于APB时钟域

协议:
APB SLAVE
AXI MASTER
MDIO

作者: 陈家耀
日期: 2025/04/26
********************************************************************/


module axi_eth_mac #(
	parameter EN_MDIO = "true", // 是否使能MDIO控制器
	parameter EN_ITR = "true", // 是否启用中断
	parameter integer M_AXI_DATA_WIDTH = 32, // AXI主机的数据位宽(16 | 32 | 64 | 128 | 256)
	parameter integer M_AXI_MAX_BURST_LEN = 32, // AXI主机的最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter EN_DMA_MM2S_UNALIGNED_TRANS = "false", // 是否在DMA的MM2S通道允许非对齐传输
	parameter EN_DMA_S2MM_UNALIGNED_TRANS = "false", // 是否在DMA的S2MM通道允许非对齐传输
	parameter integer ETH_RX_TIMEOUT_N = 8, // 以太网接收超时周期数(必须在范围[4, 256]内)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// APB从机时钟和复位
	input wire pclk,
	input wire presetn,
	// AXI主机时钟和复位
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
	// 以太网发送时钟和复位
	input wire eth_tx_aclk,
	input wire eth_tx_aresetn,
	// 以太网接收时钟和复位
	input wire eth_rx_aclk,
	input wire eth_rx_aresetn,
	
	// APB从机接口
	input wire[31:0] paddr,
    input wire psel,
    input wire penable,
    input wire pwrite,
    input wire[31:0] pwdata,
    output wire pready_out, // const -> 1'b1
    output wire[31:0] prdata_out,
    output wire pslverr_out, // const -> 1'b0
	
	// AXI主机
	// AR通道
	output wire[31:0] m_axi_araddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_arburst,
	output wire[3:0] m_axi_arcache, // const -> 4'b0011
	output wire[7:0] m_axi_arlen,
	output wire[2:0] m_axi_arprot, // const -> 3'b000
	output wire[2:0] m_axi_arsize, // const -> clogb2(M_AXI_DATA_WIDTH/8)
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// R通道
	input wire[M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_rresp,
	input wire m_axi_rlast,
	input wire m_axi_rvalid,
	output wire m_axi_rready,
	// AW通道
	output wire[31:0] m_axi_awaddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_awburst,
	output wire[3:0] m_axi_awcache, // const -> 4'b0011
	output wire[7:0] m_axi_awlen,
	output wire[2:0] m_axi_awprot, // const -> 3'b000
	output wire[2:0] m_axi_awsize, // const -> clogb2(M_AXI_DATA_WIDTH/8)
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// B通道
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_bresp,
	input wire m_axi_bvalid,
	output wire m_axi_bready, // const -> 1'b1
	// W通道
	output wire[M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
	output wire[M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready,
	
	// 发送的以太网帧字节流
	output wire[7:0] eth_tx_data,
	output wire eth_tx_valid,
	
	// 接收的以太网帧字节流
	input wire[7:0] eth_rx_data,
	input wire eth_rx_valid,
	
	// MDIO接口
	output wire mdc,
	input wire mdio_i,
	output wire mdio_o,
	output wire mdio_t, // 1为输入, 0为输出
	
	// 中断请求
	output wire dma_mm2s_cmd_done_itr,
	output wire dma_s2mm_cmd_done_itr
);
	
	/** 常量 **/
	// 以太网发送帧传输状态常量
	localparam ETH_TX_FRAME_TRANS_STS_IDLE = 2'b00;
	localparam ETH_TX_FRAME_TRANS_STS_GET_DSC_0 = 2'b01;
	localparam ETH_TX_FRAME_TRANS_STS_GET_DSC_1 = 2'b10;
	localparam ETH_TX_FRAME_TRANS_STS_START_DMA = 2'b11;
	// 以太网接收帧传输状态常量
	localparam ETH_RX_FRAME_TRANS_STS_IDLE = 2'b00;
	localparam ETH_RX_FRAME_TRANS_STS_GET_DSC_0 = 2'b01;
	localparam ETH_RX_FRAME_TRANS_STS_GET_DSC_1 = 2'b10;
	localparam ETH_RX_FRAME_TRANS_STS_START_DMA = 2'b11;
	
	/**
	AXI通用DMA引擎
	
	输出数据流位宽变换: M_AXI_DATA_WIDTH -> 16
	输入数据流位宽变换: 16 -> M_AXI_DATA_WIDTH
	**/
	// DMA的MM2S通道命令AXIS从机
	wire[55:0] s_mm2s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_mm2s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_mm2s_cmd_axis_last; // 帧尾标志
	wire s_mm2s_cmd_axis_valid;
	wire s_mm2s_cmd_axis_ready;
	// S2MM命令AXIS从机
	wire[55:0] s_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_s2mm_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_s2mm_cmd_axis_valid;
	wire s_s2mm_cmd_axis_ready;
	// 输出数据流位宽变换AXIS从机
	wire[M_AXI_DATA_WIDTH-1:0] s_mm2s_dw_cvt_axis_data;
	wire[M_AXI_DATA_WIDTH/8-1:0] s_mm2s_dw_cvt_axis_keep;
	wire s_mm2s_dw_cvt_axis_last;
	wire s_mm2s_dw_cvt_axis_valid;
	wire s_mm2s_dw_cvt_axis_ready;
	// 输出数据流位宽变换AXIS主机
	wire[15:0] m_mm2s_dw_cvt_axis_data;
	wire[1:0] m_mm2s_dw_cvt_axis_keep;
	wire m_mm2s_dw_cvt_axis_last;
	wire m_mm2s_dw_cvt_axis_valid;
	wire m_mm2s_dw_cvt_axis_ready;
	// 输入数据流位宽变换AXIS从机
	wire[15:0] s_s2mm_dw_cvt_axis_data;
	wire[1:0] s_s2mm_dw_cvt_axis_keep;
	wire s_s2mm_dw_cvt_axis_last;
	wire s_s2mm_dw_cvt_axis_valid;
	wire s_s2mm_dw_cvt_axis_ready;
	// 输入数据流位宽变换AXIS主机
	wire[M_AXI_DATA_WIDTH-1:0] m_s2mm_dw_cvt_axis_data;
	wire[M_AXI_DATA_WIDTH/8-1:0] m_s2mm_dw_cvt_axis_keep;
	wire m_s2mm_dw_cvt_axis_last;
	wire m_s2mm_dw_cvt_axis_valid;
	wire m_s2mm_dw_cvt_axis_ready;
	// 命令完成指示
	wire mm2s_cmd_done;
	wire s2mm_cmd_done;
	// 常量状态信息
	wire[8:0] dma_const_sts_m_axi_data_width; // AXI主机的数据位宽
	wire dma_const_sts_en_mm2s_unaligned_trans; // 是否在DMA的MM2S通道允许非对齐传输
	wire dma_const_sts_en_s2mm_unaligned_trans; // 是否在DMA的S2MM通道允许非对齐传输
	
	assign dma_const_sts_m_axi_data_width = M_AXI_DATA_WIDTH;
	assign dma_const_sts_en_mm2s_unaligned_trans = EN_DMA_MM2S_UNALIGNED_TRANS == "true";
	assign dma_const_sts_en_s2mm_unaligned_trans = EN_DMA_S2MM_UNALIGNED_TRANS == "true";
	
	axi_dma_engine #(
		.EN_RD_CHN("true"),
		.EN_WT_CHN("true"),
		.DATA_WIDTH(M_AXI_DATA_WIDTH),
		.MAX_BURST_LEN(M_AXI_MAX_BURST_LEN),
		.S_CMD_AXIS_COMMON_CLOCK("true"),
		.M_MM2S_AXIS_COMMON_CLOCK("true"),
		.S_S2MM_AXIS_COMMON_CLOCK("true"),
		.EN_WT_BYTES_N_STAT("false"),
		.EN_MM2S_UNALIGNED_TRANS(EN_DMA_MM2S_UNALIGNED_TRANS),
		.EN_S2MM_UNALIGNED_TRANS(EN_DMA_S2MM_UNALIGNED_TRANS),
		.SIM_DELAY(SIM_DELAY)
	)axi_dma_engine_u(
		.s_cmd_axis_aclk(m_axi_aclk),
		.s_cmd_axis_aresetn(m_axi_aresetn),
		.s_s2mm_axis_aclk(m_axi_aclk),
		.s_s2mm_axis_aresetn(m_axi_aresetn),
		.m_mm2s_axis_aclk(m_axi_aclk),
		.m_mm2s_axis_aresetn(m_axi_aresetn),
		.m_axi_aclk(m_axi_aclk),
		.m_axi_aresetn(m_axi_aresetn),
		
		.mm2s_cmd_done(mm2s_cmd_done),
		.s2mm_cmd_done(s2mm_cmd_done),
		
		.s_mm2s_cmd_axis_data(s_mm2s_cmd_axis_data),
		.s_mm2s_cmd_axis_user(s_mm2s_cmd_axis_user),
		.s_mm2s_cmd_axis_last(s_mm2s_cmd_axis_last),
		.s_mm2s_cmd_axis_valid(s_mm2s_cmd_axis_valid),
		.s_mm2s_cmd_axis_ready(s_mm2s_cmd_axis_ready),
		
		.s_s2mm_cmd_axis_data(s_s2mm_cmd_axis_data),
		.s_s2mm_cmd_axis_user(s_s2mm_cmd_axis_user),
		.s_s2mm_cmd_axis_valid(s_s2mm_cmd_axis_valid),
		.s_s2mm_cmd_axis_ready(s_s2mm_cmd_axis_ready),
		
		.s_s2mm_axis_data(m_s2mm_dw_cvt_axis_data),
		.s_s2mm_axis_keep(m_s2mm_dw_cvt_axis_keep),
		.s_s2mm_axis_last(m_s2mm_dw_cvt_axis_last),
		.s_s2mm_axis_valid(m_s2mm_dw_cvt_axis_valid),
		.s_s2mm_axis_ready(m_s2mm_dw_cvt_axis_ready),
		
		.m_mm2s_axis_data(s_mm2s_dw_cvt_axis_data),
		.m_mm2s_axis_keep(s_mm2s_dw_cvt_axis_keep),
		.m_mm2s_axis_user(),
		.m_mm2s_axis_last(s_mm2s_dw_cvt_axis_last),
		.m_mm2s_axis_valid(s_mm2s_dw_cvt_axis_valid),
		.m_mm2s_axis_ready(s_mm2s_dw_cvt_axis_ready),
		
		.m_axi_araddr(m_axi_araddr),
		.m_axi_arburst(m_axi_arburst),
		.m_axi_arcache(m_axi_arcache),
		.m_axi_arlen(m_axi_arlen),
		.m_axi_arprot(m_axi_arprot),
		.m_axi_arsize(m_axi_arsize),
		.m_axi_arvalid(m_axi_arvalid),
		.m_axi_arready(m_axi_arready),
		.m_axi_rdata(m_axi_rdata),
		.m_axi_rresp(m_axi_rresp),
		.m_axi_rlast(m_axi_rlast),
		.m_axi_rvalid(m_axi_rvalid),
		.m_axi_rready(m_axi_rready),
		.m_axi_awaddr(m_axi_awaddr),
		.m_axi_awburst(m_axi_awburst),
		.m_axi_awcache(m_axi_awcache),
		.m_axi_awlen(m_axi_awlen),
		.m_axi_awprot(m_axi_awprot),
		.m_axi_awsize(m_axi_awsize),
		.m_axi_awvalid(m_axi_awvalid),
		.m_axi_awready(m_axi_awready),
		.m_axi_bresp(m_axi_bresp),
		.m_axi_bvalid(m_axi_bvalid),
		.m_axi_bready(m_axi_bready),
		.m_axi_wdata(m_axi_wdata),
		.m_axi_wstrb(m_axi_wstrb),
		.m_axi_wlast(m_axi_wlast),
		.m_axi_wvalid(m_axi_wvalid),
		.m_axi_wready(m_axi_wready),
		
		.s2mm_err_flag()
	);
	
	axis_dw_cvt #(
		.slave_data_width(M_AXI_DATA_WIDTH),
		.master_data_width(16),
		.slave_user_width_foreach_byte(1),
		.en_keep("true"),
		.en_last("true"),
		.en_out_isolation("false"),
		.simulation_delay(SIM_DELAY)
	)mm2s_dw_cvt_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.s_axis_data(s_mm2s_dw_cvt_axis_data),
		.s_axis_keep(s_mm2s_dw_cvt_axis_keep),
		.s_axis_user({(M_AXI_DATA_WIDTH/8){1'bx}}),
		.s_axis_last(s_mm2s_dw_cvt_axis_last),
		.s_axis_valid(s_mm2s_dw_cvt_axis_valid),
		.s_axis_ready(s_mm2s_dw_cvt_axis_ready),
		
		.m_axis_data(m_mm2s_dw_cvt_axis_data),
		.m_axis_keep(m_mm2s_dw_cvt_axis_keep),
		.m_axis_user(),
		.m_axis_last(m_mm2s_dw_cvt_axis_last),
		.m_axis_valid(m_mm2s_dw_cvt_axis_valid),
		.m_axis_ready(m_mm2s_dw_cvt_axis_ready)
	);
	
	axis_dw_cvt #(
		.slave_data_width(16),
		.master_data_width(M_AXI_DATA_WIDTH),
		.slave_user_width_foreach_byte(1),
		.en_keep("true"),
		.en_last("true"),
		.en_out_isolation("false"),
		.simulation_delay(SIM_DELAY)
	)s2mm_dw_cvt_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.s_axis_data(s_s2mm_dw_cvt_axis_data),
		.s_axis_keep(s_s2mm_dw_cvt_axis_keep),
		.s_axis_user(2'bxx),
		.s_axis_last(s_s2mm_dw_cvt_axis_last),
		.s_axis_valid(s_s2mm_dw_cvt_axis_valid),
		.s_axis_ready(s_s2mm_dw_cvt_axis_ready),
		
		.m_axis_data(m_s2mm_dw_cvt_axis_data),
		.m_axis_keep(m_s2mm_dw_cvt_axis_keep),
		.m_axis_user(),
		.m_axis_last(m_s2mm_dw_cvt_axis_last),
		.m_axis_valid(m_s2mm_dw_cvt_axis_valid),
		.m_axis_ready(m_s2mm_dw_cvt_axis_ready)
	);
	
	/** 以太网发送fifo **/
	// 以太网发送fifo写端口(AXIS从机)
	wire[15:0] s_tx_fifo_axis_data;
	wire[1:0] s_tx_fifo_axis_keep;
	wire s_tx_fifo_axis_last;
	wire s_tx_fifo_axis_valid;
	wire s_tx_fifo_axis_ready;
	// 以太网发送fifo读端口(AXIS主机)
	wire[15:0] m_tx_fifo_axis_data;
	wire[1:0] m_tx_fifo_axis_keep;
	wire m_tx_fifo_axis_last;
	wire m_tx_fifo_axis_valid;
	wire m_tx_fifo_axis_ready;
	
	assign s_tx_fifo_axis_data = m_mm2s_dw_cvt_axis_data;
	assign s_tx_fifo_axis_keep = m_mm2s_dw_cvt_axis_keep;
	assign s_tx_fifo_axis_last = m_mm2s_dw_cvt_axis_last;
	assign s_tx_fifo_axis_valid = m_mm2s_dw_cvt_axis_valid;
	assign m_mm2s_dw_cvt_axis_ready = s_tx_fifo_axis_ready;
	
	assign m_tx_fifo_axis_keep[0] = 1'b1;
	
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(2048),
		.fifo_data_width(18),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(1024),
		.almost_empty_th(1024),
		.simulation_delay(SIM_DELAY)
	)eth_tx_fifo_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.fifo_wen(s_tx_fifo_axis_valid),
		.fifo_din({s_tx_fifo_axis_data, s_tx_fifo_axis_keep[1], s_tx_fifo_axis_last}),
		.fifo_full_n(s_tx_fifo_axis_ready),
		
		.fifo_ren(m_tx_fifo_axis_ready),
		.fifo_dout({m_tx_fifo_axis_data, m_tx_fifo_axis_keep[1], m_tx_fifo_axis_last}),
		.fifo_empty_n(m_tx_fifo_axis_valid)
	);
	
	/** 以太网接收fifo **/
	// 以太网接收fifo写端口(AXIS从机)
	wire[15:0] s_rx_fifo_axis_data;
	wire[1:0] s_rx_fifo_axis_keep;
	wire s_rx_fifo_axis_last;
	wire s_rx_fifo_axis_valid;
	wire s_rx_fifo_axis_ready;
	// 以太网接收fifo读端口(AXIS主机)
	wire[15:0] m_rx_fifo_axis_data;
	wire[1:0] m_rx_fifo_axis_keep;
	wire m_rx_fifo_axis_last;
	wire m_rx_fifo_axis_valid;
	wire m_rx_fifo_axis_ready;
	// 以太网接收fifo剩余可用存储项数
	reg[12:0] rx_fifo_rmn_data_n;
	
	assign s_s2mm_dw_cvt_axis_data = m_rx_fifo_axis_data;
	assign s_s2mm_dw_cvt_axis_keep = m_rx_fifo_axis_keep;
	assign s_s2mm_dw_cvt_axis_last = m_rx_fifo_axis_last;
	assign s_s2mm_dw_cvt_axis_valid = m_rx_fifo_axis_valid;
	assign m_rx_fifo_axis_ready = s_s2mm_dw_cvt_axis_ready;
	
	assign m_rx_fifo_axis_keep[0] = 1'b1;
	
	// 以太网接收fifo剩余可用存储项数
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			rx_fifo_rmn_data_n <= 13'd2048;
		else if(
			(s_rx_fifo_axis_valid & s_rx_fifo_axis_ready) ^ 
			(m_rx_fifo_axis_valid & m_rx_fifo_axis_ready)
		)
			rx_fifo_rmn_data_n <= # SIM_DELAY 
				(m_rx_fifo_axis_valid & m_rx_fifo_axis_ready) ? (rx_fifo_rmn_data_n + 13'd1):(rx_fifo_rmn_data_n - 13'd1);
	end
	
	ram_fifo_wrapper #(
		.fwft_mode("true"),
		.ram_type("bram"),
		.en_bram_reg("false"),
		.fifo_depth(2048),
		.fifo_data_width(18),
		.full_assert_polarity("low"),
		.empty_assert_polarity("low"),
		.almost_full_assert_polarity("no"),
		.almost_empty_assert_polarity("no"),
		.en_data_cnt("false"),
		.almost_full_th(1024),
		.almost_empty_th(1024),
		.simulation_delay(SIM_DELAY)
	)eth_rx_fifo_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.fifo_wen(s_rx_fifo_axis_valid),
		.fifo_din({s_rx_fifo_axis_data, s_rx_fifo_axis_keep[1], s_rx_fifo_axis_last}),
		.fifo_full_n(s_rx_fifo_axis_ready),
		
		.fifo_ren(m_rx_fifo_axis_ready),
		.fifo_dout({m_rx_fifo_axis_data, m_rx_fifo_axis_keep[1], m_rx_fifo_axis_last}),
		.fifo_empty_n(m_rx_fifo_axis_valid)
	);
	
	/**
	以太网发送描述符
	
	32位描述符: {保留(3位), 帧字节数(12位), 有效标志(1位), 偏移地址[16:1](16位)}
	**/
	// 运行时参数
	wire[31:0] eth_tx_buf_baseaddr; // 以太网帧发送缓存区基址
	wire[7:0] eth_tx_dsc_buf_len; // 以太网发送描述符缓存区长度 - 1
	// 以太网发送描述符缓存区控制
	wire new_eth_tx_dsc_created_sync; // 新建以太网发送描述符(请求)
	reg new_eth_tx_dsc_created_d1; // 延迟1clk的新建以太网发送描述符(请求)
	wire on_new_eth_tx_dsc_created; // 新建以太网发送描述符(指示)
	reg[8:0] eth_tx_dsc_buf_wptr; // 以太网发送描述符缓存区(写指针)
	reg[8:0] eth_tx_dsc_buf_rptr; // 以太网发送描述符缓存区(读指针)
	wire eth_tx_dsc_buf_empty_n; // 以太网发送描述符缓存区空标志
	reg[1:0] eth_tx_frame_trans_sts; // 以太网发送帧传输状态
	reg[31:0] eth_tx_frame_baseaddr; // 以太网发送帧基址
	reg[11:0] eth_tx_frame_len; // 以太网发送帧长度
	// 以太网发送描述符缓存存储器端口#A
	wire eth_tx_dsc_mem_ena;
	wire eth_tx_dsc_mem_wea;
	wire[8:0] eth_tx_dsc_mem_addra;
	wire[15:0] eth_tx_dsc_mem_dina;
	wire[15:0] eth_tx_dsc_mem_douta;
	// 以太网发送描述符缓存存储器端口#B
	wire eth_tx_dsc_mem_enb;
	wire eth_tx_dsc_mem_web;
	wire[8:0] eth_tx_dsc_mem_addrb;
	wire[15:0] eth_tx_dsc_mem_dinb;
	wire[15:0] eth_tx_dsc_mem_doutb;
	// DMA的MM2S通道命令AXIS主机
	wire[55:0] m_mm2s_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_mm2s_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_mm2s_cmd_axis_last; // 帧尾标志
	wire m_mm2s_cmd_axis_valid;
	wire m_mm2s_cmd_axis_ready;
	
	assign s_mm2s_cmd_axis_data = m_mm2s_cmd_axis_data;
	assign s_mm2s_cmd_axis_user = m_mm2s_cmd_axis_user;
	assign s_mm2s_cmd_axis_last = m_mm2s_cmd_axis_last;
	assign s_mm2s_cmd_axis_valid = m_mm2s_cmd_axis_valid;
	assign m_mm2s_cmd_axis_ready = s_mm2s_cmd_axis_ready;
	
	assign on_new_eth_tx_dsc_created = new_eth_tx_dsc_created_sync & (~new_eth_tx_dsc_created_d1);
	assign eth_tx_dsc_buf_empty_n = ~(eth_tx_dsc_buf_wptr == eth_tx_dsc_buf_rptr);
	
	assign eth_tx_dsc_mem_enb = 
		((eth_tx_frame_trans_sts == ETH_TX_FRAME_TRANS_STS_IDLE) & eth_tx_dsc_buf_empty_n) | 
		(eth_tx_frame_trans_sts == ETH_TX_FRAME_TRANS_STS_GET_DSC_0) | 
		(m_mm2s_cmd_axis_valid & m_mm2s_cmd_axis_ready);
	assign eth_tx_dsc_mem_web = eth_tx_frame_trans_sts == ETH_TX_FRAME_TRANS_STS_START_DMA;
	assign eth_tx_dsc_mem_addrb = {eth_tx_dsc_buf_rptr[7:0], eth_tx_frame_trans_sts != ETH_TX_FRAME_TRANS_STS_IDLE};
	assign eth_tx_dsc_mem_dinb = {
		3'b000, // 保留(3位)
		eth_tx_frame_len, // 帧字节数(12位)
		1'b0 // 有效标志(1位)
	};
	
	assign m_mm2s_cmd_axis_data = {
		12'd0, eth_tx_frame_len, // 待传输字节数(24bit)
		eth_tx_frame_baseaddr // 传输首地址(32bit)
	};
	assign m_mm2s_cmd_axis_user = 1'b0; // 递增传输
	assign m_mm2s_cmd_axis_last = 1'b1;
	assign m_mm2s_cmd_axis_valid = eth_tx_frame_trans_sts == ETH_TX_FRAME_TRANS_STS_START_DMA;
	
	// 延迟1clk的新建以太网发送描述符(请求)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			new_eth_tx_dsc_created_d1 <= 1'b0;
		else
			new_eth_tx_dsc_created_d1 <= # SIM_DELAY new_eth_tx_dsc_created_sync;
	end
	
	// 以太网发送描述符缓存区(写指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_tx_dsc_buf_wptr <= {1'b0, 8'd0};
		else if(on_new_eth_tx_dsc_created)
		begin
			eth_tx_dsc_buf_wptr[7:0] <= # SIM_DELAY 
				(eth_tx_dsc_buf_wptr[7:0] == eth_tx_dsc_buf_len) ? 
					8'd0:
					(eth_tx_dsc_buf_wptr[7:0] + 8'd1);
			eth_tx_dsc_buf_wptr[8] <= # SIM_DELAY 
				(eth_tx_dsc_buf_wptr[7:0] == eth_tx_dsc_buf_len) ? 
					(~eth_tx_dsc_buf_wptr[8]):
					eth_tx_dsc_buf_wptr[8];
		end
	end
	
	// 以太网发送描述符缓存区(读指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_tx_dsc_buf_rptr <= {1'b0, 8'd0};
		else if(m_mm2s_cmd_axis_valid & m_mm2s_cmd_axis_ready)
		begin
			eth_tx_dsc_buf_rptr[7:0] <= # SIM_DELAY 
				(eth_tx_dsc_buf_rptr[7:0] == eth_tx_dsc_buf_len) ? 
					8'd0:
					(eth_tx_dsc_buf_rptr[7:0] + 8'd1);
			eth_tx_dsc_buf_rptr[8] <= # SIM_DELAY 
				(eth_tx_dsc_buf_rptr[7:0] == eth_tx_dsc_buf_len) ? 
					(~eth_tx_dsc_buf_rptr[8]):
					eth_tx_dsc_buf_rptr[8];
		end
	end
	
	// 以太网发送帧传输状态
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_tx_frame_trans_sts <= ETH_TX_FRAME_TRANS_STS_IDLE;
		else
		begin
			case(eth_tx_frame_trans_sts)
				ETH_TX_FRAME_TRANS_STS_IDLE:
					if(eth_tx_dsc_buf_empty_n)
						eth_tx_frame_trans_sts <= # SIM_DELAY ETH_TX_FRAME_TRANS_STS_GET_DSC_0;
				ETH_TX_FRAME_TRANS_STS_GET_DSC_0:
					eth_tx_frame_trans_sts <= # SIM_DELAY ETH_TX_FRAME_TRANS_STS_GET_DSC_1;
				ETH_TX_FRAME_TRANS_STS_GET_DSC_1:
					eth_tx_frame_trans_sts <= # SIM_DELAY ETH_TX_FRAME_TRANS_STS_START_DMA;
				ETH_TX_FRAME_TRANS_STS_START_DMA:
					if(m_mm2s_cmd_axis_ready)
						eth_tx_frame_trans_sts <= # SIM_DELAY ETH_TX_FRAME_TRANS_STS_IDLE;
				default:
					eth_tx_frame_trans_sts <= # SIM_DELAY ETH_TX_FRAME_TRANS_STS_IDLE;
			endcase
		end
	end
	
	// 以太网发送帧基址
	always @(posedge m_axi_aclk)
	begin
		if(eth_tx_frame_trans_sts == ETH_TX_FRAME_TRANS_STS_GET_DSC_0)
			eth_tx_frame_baseaddr <= # SIM_DELAY 
				eth_tx_buf_baseaddr + {eth_tx_dsc_mem_doutb, 1'b0};
	end
	// 以太网发送帧长度
	always @(posedge m_axi_aclk)
	begin
		if(eth_tx_frame_trans_sts == ETH_TX_FRAME_TRANS_STS_GET_DSC_1)
			eth_tx_frame_len <= # SIM_DELAY eth_tx_dsc_mem_doutb[12:1];
	end
	
	bram_true_dual_port_async #(
		.mem_width(16),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.read_write_mode("no_change"),
		.use_output_register("false"),
		.simulation_delay(SIM_DELAY)
	)eth_tx_dsc_mem_u(
		.clk_a(pclk),
		.clk_b(m_axi_aclk),
		
		.ena(eth_tx_dsc_mem_ena),
		.wea(eth_tx_dsc_mem_wea),
		.addra(eth_tx_dsc_mem_addra),
		.dina(eth_tx_dsc_mem_dina),
		.douta(eth_tx_dsc_mem_douta),
		
		.enb(eth_tx_dsc_mem_enb),
		.web(eth_tx_dsc_mem_web),
		.addrb(eth_tx_dsc_mem_addrb),
		.dinb(eth_tx_dsc_mem_dinb),
		.doutb(eth_tx_dsc_mem_doutb)
	);
	
	/**
	以太网接收描述符
	
	32位描述符: {保留(3位), 帧字节数(12位), 处理完成标志(1位), 偏移地址[16:1](16位)}
	**/
	// 运行时参数
	wire[31:0] eth_rx_buf_baseaddr; // 以太网帧接收缓存区基址
	wire[7:0] eth_rx_dsc_buf_len; // 以太网接收描述符缓存区长度 - 1
	// 以太网接收描述符缓存区控制
	reg[8:0] eth_rx_dsc_avilable_wptr; // 以太网接收描述符可传输(写指针)
	wire[8:0] eth_rx_dsc_avilable_wptr_nxt; // 下一以太网接收描述符可传输(写指针)
	reg[8:0] eth_rx_dsc_avilable_rptr; // 以太网接收描述符可传输(读指针)
	reg[8:0] eth_rx_dsc_processed_wptr; // 以太网接收描述符处理完成(写指针)
	wire[8:0] eth_rx_dsc_processed_wptr_nxt; // 下一以太网接收描述符处理完成(写指针)
	wire eth_rx_dsc_free_sync; // 释放以太网接收描述符(请求)
	reg eth_rx_dsc_free_d1; // 延迟1clk的释放以太网接收描述符(请求)
	wire on_eth_rx_dsc_free; // 释放以太网接收描述符(指示)
	reg[8:0] eth_rx_dsc_processed_rptr; // 以太网接收描述符处理完成(读指针)
	wire[8:0] eth_rx_dsc_processed_rptr_nxt; // 下一以太网接收描述符处理完成(读指针)
	wire has_avilable_eth_rx_dsc; // 有可传输的以太网接收描述符(标志)
	reg[1:0] eth_rx_frame_trans_sts; // 以太网接收帧传输状态
	reg[31:0] eth_rx_frame_baseaddr; // 以太网接收帧传输基址
	reg[11:0] eth_rx_frame_len; // 以太网接收帧传输长度
	// 待响应的接收到新的帧和帧处理完成请求
	wire on_eth_frame_recv; // 接收并存入新的以太网帧(指示)
	wire[11:0] eth_frame_recv_byte_n; // 新接收并存入的以太网帧的字节数
	wire on_eth_rx_dsc_processed; // 以太网接收描述符处理完成(指示)
	reg eth_frame_recv_req_pending; // 等待的接收并存入新的以太网帧请求
	reg[11:0] eth_frame_recv_byte_n_latched; // 锁存的新接收并存入的以太网帧的字节数
	reg eth_rx_dsc_processed_req_pending; // 等待的以太网接收描述符处理完成请求
	wire on_resp_to_eth_frame_recv_req; // 响应接收并存入新的以太网帧请求(指示)
	reg[1:0] on_resp_to_eth_rx_dsc_processed_req; // 响应以太网接收描述符处理完成请求(两阶段指示)
	// 以太网接收描述符缓存存储器端口#A
	wire eth_rx_dsc_mem_ena;
	wire eth_rx_dsc_mem_wea;
	wire[8:0] eth_rx_dsc_mem_addra;
	wire[15:0] eth_rx_dsc_mem_dina;
	wire[15:0] eth_rx_dsc_mem_douta;
	// 以太网接收描述符缓存存储器端口#B
	wire eth_rx_dsc_mem_enb;
	wire eth_rx_dsc_mem_web;
	wire[8:0] eth_rx_dsc_mem_addrb;
	wire[15:0] eth_rx_dsc_mem_dinb;
	wire[15:0] eth_rx_dsc_mem_doutb;
	// S2MM命令AXIS主机
	wire[55:0] m_s2mm_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_s2mm_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_s2mm_cmd_axis_valid;
	wire m_s2mm_cmd_axis_ready;
	
	assign s_s2mm_cmd_axis_data = m_s2mm_cmd_axis_data;
	assign s_s2mm_cmd_axis_user = m_s2mm_cmd_axis_user;
	assign s_s2mm_cmd_axis_valid = m_s2mm_cmd_axis_valid;
	assign m_s2mm_cmd_axis_ready = s_s2mm_cmd_axis_ready;
	
	assign on_eth_rx_dsc_free = eth_rx_dsc_free_sync & (~eth_rx_dsc_free_d1);
	assign on_eth_rx_dsc_processed = s2mm_cmd_done;
	assign on_resp_to_eth_frame_recv_req = 
		(~on_resp_to_eth_rx_dsc_processed_req[1]) & (
			(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_IDLE) | 
			(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_START_DMA)
		);
	
	assign eth_rx_dsc_avilable_wptr_nxt[7:0] = 
		(eth_frame_recv_req_pending & on_resp_to_eth_frame_recv_req) ? (
			(eth_rx_dsc_avilable_wptr[7:0] == eth_rx_dsc_buf_len) ? 
				8'd0:
				(eth_rx_dsc_avilable_wptr[7:0] + 8'd1)
		):eth_rx_dsc_avilable_wptr[7:0];
	assign eth_rx_dsc_avilable_wptr_nxt[8] = 
		(eth_frame_recv_req_pending & on_resp_to_eth_frame_recv_req) ? (
			(eth_rx_dsc_avilable_wptr[7:0] == eth_rx_dsc_buf_len) ? 
				(~eth_rx_dsc_avilable_wptr[8]):
				eth_rx_dsc_avilable_wptr[8]
		):eth_rx_dsc_avilable_wptr[8];
	assign eth_rx_dsc_processed_wptr_nxt[7:0] = 
		on_resp_to_eth_rx_dsc_processed_req[1] ? (
			(eth_rx_dsc_processed_wptr[7:0] == eth_rx_dsc_buf_len) ? 
				8'd0:
				(eth_rx_dsc_processed_wptr[7:0] + 8'd1)
		):eth_rx_dsc_processed_wptr[7:0];
	assign eth_rx_dsc_processed_wptr_nxt[8] = 
		on_resp_to_eth_rx_dsc_processed_req[1] ? (
			(eth_rx_dsc_processed_wptr[7:0] == eth_rx_dsc_buf_len) ? 
				(~eth_rx_dsc_processed_wptr[8]):
				eth_rx_dsc_processed_wptr[8]
		):eth_rx_dsc_processed_wptr[8];
	assign eth_rx_dsc_processed_rptr_nxt[7:0] = 
		on_eth_rx_dsc_free ? (
			(eth_rx_dsc_processed_rptr[7:0] == eth_rx_dsc_buf_len) ? 
				8'd0:
				(eth_rx_dsc_processed_rptr[7:0] + 8'd1)
		):eth_rx_dsc_processed_rptr[7:0];
	assign eth_rx_dsc_processed_rptr_nxt[8] = 
		on_eth_rx_dsc_free ? (
			(eth_rx_dsc_processed_rptr[7:0] == eth_rx_dsc_buf_len) ? 
				(~eth_rx_dsc_processed_rptr[8]):
				eth_rx_dsc_processed_rptr[8]
		):eth_rx_dsc_processed_rptr[8];
	
	assign has_avilable_eth_rx_dsc = ~(eth_rx_dsc_avilable_wptr == eth_rx_dsc_avilable_rptr);
	
	assign eth_rx_dsc_mem_enb = 
		(
			(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_IDLE) & 
			(eth_frame_recv_req_pending | eth_rx_dsc_processed_req_pending | has_avilable_eth_rx_dsc)
		) | 
		(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_GET_DSC_0) | 
		(
			(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_START_DMA) & 
			(eth_frame_recv_req_pending | eth_rx_dsc_processed_req_pending)
		);
	assign eth_rx_dsc_mem_web = 
		on_resp_to_eth_rx_dsc_processed_req[1] | (
			eth_frame_recv_req_pending & (
				(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_IDLE) | 
				(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_START_DMA)
			)
		);
	assign eth_rx_dsc_mem_addrb = 
		(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_IDLE) ? (
			(eth_frame_recv_req_pending | eth_rx_dsc_processed_req_pending) ? (
				((~on_resp_to_eth_rx_dsc_processed_req[1]) & eth_frame_recv_req_pending) ? 
					{eth_rx_dsc_avilable_wptr[7:0], 1'b1}:
					{eth_rx_dsc_processed_wptr[7:0], 1'b1}
			):
			{eth_rx_dsc_avilable_rptr[7:0], 1'b0}
		):
		(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_START_DMA) ? (
			eth_frame_recv_req_pending ? 
				{eth_rx_dsc_avilable_wptr[7:0], 1'b1}:
				{eth_rx_dsc_processed_wptr[7:0], 1'b1}
		):
		{eth_rx_dsc_avilable_rptr[7:0], 1'b1};
	assign eth_rx_dsc_mem_dinb = 
		on_resp_to_eth_rx_dsc_processed_req[1] ? {
			3'b000, // 保留(3位)
			eth_rx_dsc_mem_doutb[12:1], // 帧字节数(12位)
			1'b1 // 处理完成标志(1位)
		}:{
			3'b000, // 保留(3位)
			eth_frame_recv_byte_n_latched, // 帧字节数(12位)
			1'b0 // 处理完成标志(1位)
		};
	
	assign m_s2mm_cmd_axis_data = {
		12'd0, eth_rx_frame_len, // 待传输字节数(24bit)
		eth_rx_frame_baseaddr // 传输首地址(32bit)
	};
	assign m_s2mm_cmd_axis_user = 1'b0; // 递增传输
	assign m_s2mm_cmd_axis_valid = eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_START_DMA;
	
	// 以太网接收描述符可传输(写指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_dsc_avilable_wptr <= {1'b0, 8'd0};
		else if(eth_frame_recv_req_pending & on_resp_to_eth_frame_recv_req)
			eth_rx_dsc_avilable_wptr <= # SIM_DELAY eth_rx_dsc_avilable_wptr_nxt;
	end
	// 以太网接收描述符可传输(读指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_dsc_avilable_rptr <= {1'b0, 8'd0};
		else if(m_s2mm_cmd_axis_valid & m_s2mm_cmd_axis_ready)
		begin
			eth_rx_dsc_avilable_rptr[7:0] <= # SIM_DELAY 
				(eth_rx_dsc_avilable_rptr[7:0] == eth_rx_dsc_buf_len) ? 
					8'd0:
					(eth_rx_dsc_avilable_rptr[7:0] + 8'd1);
			eth_rx_dsc_avilable_rptr[8] <= # SIM_DELAY 
				(eth_rx_dsc_avilable_rptr[7:0] == eth_rx_dsc_buf_len) ? 
					(~eth_rx_dsc_avilable_rptr[8]):
					eth_rx_dsc_avilable_rptr[8];
		end
	end
	// 以太网接收描述符处理完成(写指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_dsc_processed_wptr <= {1'b0, 8'd0};
		else if(on_resp_to_eth_rx_dsc_processed_req[1])
			eth_rx_dsc_processed_wptr <= # SIM_DELAY eth_rx_dsc_processed_wptr_nxt;
	end
	// 以太网接收描述符处理完成(读指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_dsc_processed_rptr <= {1'b0, 8'd0};
		else if(on_eth_rx_dsc_free)
			eth_rx_dsc_processed_rptr <= # SIM_DELAY eth_rx_dsc_processed_rptr_nxt;
	end
	
	// 延迟1clk的释放以太网接收描述符(请求)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_dsc_free_d1 <= 1'b0;
		else
			eth_rx_dsc_free_d1 <= # SIM_DELAY eth_rx_dsc_free_sync;
	end
	
	// 以太网接收帧传输状态
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_frame_trans_sts <= ETH_RX_FRAME_TRANS_STS_IDLE;
		else
		begin
			case(eth_rx_frame_trans_sts)
				ETH_RX_FRAME_TRANS_STS_IDLE:
					if(has_avilable_eth_rx_dsc & (~eth_frame_recv_req_pending) & (~eth_rx_dsc_processed_req_pending))
						eth_rx_frame_trans_sts <= # SIM_DELAY ETH_RX_FRAME_TRANS_STS_GET_DSC_0;
				ETH_RX_FRAME_TRANS_STS_GET_DSC_0:
					eth_rx_frame_trans_sts <= # SIM_DELAY ETH_RX_FRAME_TRANS_STS_GET_DSC_1;
				ETH_RX_FRAME_TRANS_STS_GET_DSC_1:
					eth_rx_frame_trans_sts <= # SIM_DELAY ETH_RX_FRAME_TRANS_STS_START_DMA;
				ETH_RX_FRAME_TRANS_STS_START_DMA:
					if(m_s2mm_cmd_axis_ready)
						eth_rx_frame_trans_sts <= # SIM_DELAY ETH_RX_FRAME_TRANS_STS_IDLE;
				default:
					eth_rx_frame_trans_sts <= # SIM_DELAY ETH_RX_FRAME_TRANS_STS_IDLE;
			endcase
		end
	end
	
	// 以太网接收帧传输基址
	always @(posedge m_axi_aclk)
	begin
		if(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_GET_DSC_0)
			eth_rx_frame_baseaddr <= # SIM_DELAY 
				eth_rx_buf_baseaddr + {eth_rx_dsc_mem_doutb, 1'b0};
	end
	// 以太网接收帧传输长度
	always @(posedge m_axi_aclk)
	begin
		if(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_GET_DSC_1)
			eth_rx_frame_len <= # SIM_DELAY eth_rx_dsc_mem_doutb[12:1];
	end
	
	// 等待的接收并存入新的以太网帧请求
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_frame_recv_req_pending <= 1'b0;
		else if(
			eth_frame_recv_req_pending ? 
				on_resp_to_eth_frame_recv_req:
				on_eth_frame_recv
		)
			eth_frame_recv_req_pending <= # SIM_DELAY ~eth_frame_recv_req_pending;
	end
	// 锁存的新接收并存入的以太网帧的字节数
	always @(posedge m_axi_aclk)
	begin
		if((~eth_frame_recv_req_pending) & on_eth_frame_recv)
			eth_frame_recv_byte_n_latched <= # SIM_DELAY eth_frame_recv_byte_n;
	end
	// 等待的以太网接收描述符处理完成请求
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_dsc_processed_req_pending <= 1'b0;
		else if(
			eth_rx_dsc_processed_req_pending ? 
				on_resp_to_eth_rx_dsc_processed_req[1]:
				on_eth_rx_dsc_processed
		)
			eth_rx_dsc_processed_req_pending <= # SIM_DELAY ~eth_rx_dsc_processed_req_pending;
	end
	
	// 响应以太网接收描述符处理完成请求(两阶段指示)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			on_resp_to_eth_rx_dsc_processed_req <= 2'b01;
		else if(
			on_resp_to_eth_rx_dsc_processed_req[1] | (
				eth_rx_dsc_processed_req_pending & (~eth_frame_recv_req_pending) & (
					(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_IDLE) | 
					(eth_rx_frame_trans_sts == ETH_RX_FRAME_TRANS_STS_START_DMA)
				)
			)
		)
			on_resp_to_eth_rx_dsc_processed_req <= # SIM_DELAY 
				{on_resp_to_eth_rx_dsc_processed_req[0], on_resp_to_eth_rx_dsc_processed_req[1]};
	end
	
	bram_true_dual_port_async #(
		.mem_width(16),
		.mem_depth(512),
		.INIT_FILE("no_init"),
		.read_write_mode("no_change"),
		.use_output_register("false"),
		.simulation_delay(SIM_DELAY)
	)eth_rx_dsc_mem_u(
		.clk_a(pclk),
		.clk_b(m_axi_aclk),
		
		.ena(eth_rx_dsc_mem_ena),
		.wea(eth_rx_dsc_mem_wea),
		.addra(eth_rx_dsc_mem_addra),
		.dina(eth_rx_dsc_mem_dina),
		.douta(eth_rx_dsc_mem_douta),
		
		.enb(eth_rx_dsc_mem_enb),
		.web(eth_rx_dsc_mem_web),
		.addrb(eth_rx_dsc_mem_addrb),
		.dinb(eth_rx_dsc_mem_dinb),
		.doutb(eth_rx_dsc_mem_doutb)
	);
	
	/** AXIS-以太网MAC **/
	// 接收MAC地址过滤
	wire broadcast_accept; // 是否接受广播帧
	wire[47:0] unicast_filter_mac; // 单播过滤MAC
	wire[47:0] multicast_filter_mac_0; // 组播过滤MAC#0
	wire[47:0] multicast_filter_mac_1; // 组播过滤MAC#1
	wire[47:0] multicast_filter_mac_2; // 组播过滤MAC#2
	wire[47:0] multicast_filter_mac_3; // 组播过滤MAC#3
	// 发送的以太网帧数据(AXIS从机)
	wire[15:0] s_eth_tx_axis_data;
	wire[1:0] s_eth_tx_axis_keep;
	wire s_eth_tx_axis_last;
	wire s_eth_tx_axis_valid;
	wire s_eth_tx_axis_ready;
	// 接收的以太网帧数据(AXIS主机)
	wire[23:0] m_eth_rx_axis_data; // {帧号(8位), 半字数据(16位)}
	wire[1:0] m_eth_rx_axis_keep;
	wire m_eth_rx_axis_last;
	wire m_eth_rx_axis_valid;
	// 以太网帧接收流控制
	reg eth_rx_frame_transmitting; // 以太网帧接收传输中(标志)
	wire eth_rx_frame_valid; // 以太网帧接收有效(标志)
	wire eth_rx_dsc_full_n_nxt; // 下一以太网接收描述符满(标志)
	wire eth_rx_buf_enough; // 以太网接收缓存有足够的空间(标志)
	reg to_discard_eth_rx_frame; // 以太网帧接收舍弃(标志)
	reg[11:0] now_eth_rx_frame_len; // 读取接收以太网帧的长度(计数器)
	
	assign on_eth_frame_recv = s_rx_fifo_axis_valid & m_eth_rx_axis_last;
	assign eth_frame_recv_byte_n = now_eth_rx_frame_len;
	
	assign s_eth_tx_axis_data = m_tx_fifo_axis_data;
	assign s_eth_tx_axis_keep = m_tx_fifo_axis_keep;
	assign s_eth_tx_axis_last = m_tx_fifo_axis_last;
	assign s_eth_tx_axis_valid = m_tx_fifo_axis_valid;
	assign m_tx_fifo_axis_ready = s_eth_tx_axis_ready;
	
	assign s_rx_fifo_axis_data = m_eth_rx_axis_data[15:0];
	assign s_rx_fifo_axis_keep = m_eth_rx_axis_keep;
	assign s_rx_fifo_axis_last = m_eth_rx_axis_last;
	// 断言: 以太网接收fifo必定非满!
	assign s_rx_fifo_axis_valid = m_eth_rx_axis_valid & (~to_discard_eth_rx_frame);
	
	assign eth_rx_frame_valid = m_eth_rx_axis_valid | eth_rx_frame_transmitting;
	assign eth_rx_dsc_full_n_nxt = 
		~(
			(eth_rx_dsc_avilable_wptr_nxt[8] ^ eth_rx_dsc_processed_rptr_nxt[8]) & 
			(eth_rx_dsc_avilable_wptr_nxt[7:0] == eth_rx_dsc_processed_rptr_nxt[7:0])
		);
	assign eth_rx_buf_enough = (rx_fifo_rmn_data_n > ((14 + 1500) / 2)) & eth_rx_dsc_full_n_nxt;
	
	// 以太网帧接收传输中(标志)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			eth_rx_frame_transmitting <= 1'b0;
		else if(
			// eth_rx_frame_transmitting ? (m_eth_rx_axis_valid & m_eth_rx_axis_last):m_eth_rx_axis_valid
			m_eth_rx_axis_valid & ((~eth_rx_frame_transmitting) | m_eth_rx_axis_last)
		)
			eth_rx_frame_transmitting <= # SIM_DELAY ~eth_rx_frame_transmitting;
	end
	
	// 以太网帧接收舍弃(标志)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			to_discard_eth_rx_frame <= 1'b0;
		else if(
			(m_eth_rx_axis_valid & m_eth_rx_axis_last) | 
			// (~m_eth_rx_axis_valid) & (~eth_rx_frame_transmitting) & eth_rx_buf_enough
			((~eth_rx_frame_valid) & eth_rx_buf_enough)
		)
			to_discard_eth_rx_frame <= # SIM_DELAY 
				// m_eth_rx_axis_valid ? (~eth_rx_buf_enough):1'b0
				m_eth_rx_axis_valid & (~eth_rx_buf_enough);
	end
	
	// 读取接收以太网帧的长度(计数器)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			now_eth_rx_frame_len <= 12'd1;
		else if(s_rx_fifo_axis_valid)
			now_eth_rx_frame_len <= # SIM_DELAY m_eth_rx_axis_last ? 12'd1:(now_eth_rx_frame_len + 12'd1);
	end
	
	axis_eth_mac #(
		.ETH_RX_TIMEOUT_N(ETH_RX_TIMEOUT_N),
		.SIM_DELAY(SIM_DELAY)
	)axis_eth_mac_u(
		.s_axis_aclk(m_axi_aclk),
		.s_axis_aresetn(m_axi_aresetn),
		.eth_tx_aclk(eth_tx_aclk),
		.eth_tx_aresetn(eth_tx_aresetn),
		.m_axis_aclk(m_axi_aclk),
		.m_axis_aresetn(m_axi_aresetn),
		.eth_rx_aclk(eth_rx_aclk),
		.eth_rx_aresetn(eth_rx_aresetn),
		
		.broadcast_accept(broadcast_accept),
		.unicast_filter_mac(unicast_filter_mac),
		.multicast_filter_mac_0(multicast_filter_mac_0),
		.multicast_filter_mac_1(multicast_filter_mac_1),
		.multicast_filter_mac_2(multicast_filter_mac_2),
		.multicast_filter_mac_3(multicast_filter_mac_3),
		
		.s_axis_data(s_eth_tx_axis_data),
		.s_axis_keep(s_eth_tx_axis_keep),
		.s_axis_last(s_eth_tx_axis_last),
		.s_axis_valid(s_eth_tx_axis_valid),
		.s_axis_ready(s_eth_tx_axis_ready),
		
		.m_axis_data(m_eth_rx_axis_data),
		.m_axis_keep(m_eth_rx_axis_keep),
		.m_axis_last(m_eth_rx_axis_last),
		.m_axis_valid(m_eth_rx_axis_valid),
		
		.eth_tx_data(eth_tx_data),
		.eth_tx_valid(eth_tx_valid),
		
		.eth_rx_data(eth_rx_data),
		.eth_rx_valid(eth_rx_valid)
	);
	
	/** 以太网MDIO控制器 **/
	// 运行时参数
	wire[9:0] mdc_div_rate; // MDIO时钟分频系数(分频数 = (分频系数 + 1) * 2)
	// 常量状态信息
	wire mdio_ctrler_present; // MDIO控制器存在(标志)
	// 块级控制
	wire mdio_access_start;
	wire mdio_access_is_rd; // 是否读寄存器
	wire[9:0] mdio_access_addr; // 访问地址({寄存器地址(5位), PHY地址(5位)})
	wire[15:0] mdio_access_wdata; // 写数据
	wire mdio_access_idle;
	wire[15:0] mdio_access_rdata; // 读数据
	wire mdio_access_done;
	
	assign mdio_ctrler_present = EN_MDIO == "true";
	
	generate
		if(EN_MDIO == "true")
		begin
			eth_mac_mdio #(
				.SIM_DELAY(SIM_DELAY)
			)eth_mac_mdio_u(
				.aclk(pclk),
				.aresetn(presetn),
				
				.mdc_div_rate(mdc_div_rate),
				
				.mdio_access_start(mdio_access_start),
				.mdio_access_is_rd(mdio_access_is_rd),
				.mdio_access_addr(mdio_access_addr),
				.mdio_access_wdata(mdio_access_wdata),
				.mdio_access_idle(mdio_access_idle),
				.mdio_access_rdata(mdio_access_rdata),
				.mdio_access_done(mdio_access_done),
				
				.mdc(mdc),
				.mdio_i(mdio_i),
				.mdio_o(mdio_o),
				.mdio_t(mdio_t)
			);
		end
		else
		begin
			assign mdio_access_idle = 1'b1;
			assign mdio_access_rdata = 16'h0000;
			assign mdio_access_done = 1'b0;
			
			assign mdc = 1'b1;
			assign mdio_o = 1'b1;
			assign mdio_t = 1'b1;
		end
	endgenerate
	
	/** 寄存器配置接口 **/
	// 以太网描述符变更请求
	wire new_eth_tx_dsc_created; // 新建以太网发送描述符(请求)
	wire eth_rx_dsc_free; // 释放以太网接收描述符(请求)
	// DMA命令完成指示
	reg mm2s_cmd_done_extended; // 延长的DMA MM2S通道命令完成(请求)
	reg[4:0] mm2s_cmd_done_extension_cnt; // DMA MM2S通道命令完成请求延长(计数器)
	reg s2mm_cmd_done_extended; // 延长的DMA S2MM通道命令完成(请求)
	reg[4:0] s2mm_cmd_done_extension_cnt; // DMA S2MM通道命令完成请求延长(计数器)
	wire mm2s_cmd_done_sync; // 同步的DMA MM2S通道命令完成(请求)
	wire s2mm_cmd_done_sync; // 同步的DMA S2MM通道命令完成(请求)
	
	// 延长的DMA MM2S通道命令完成(请求)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			mm2s_cmd_done_extended <= 1'b0;
		else if(
			mm2s_cmd_done_extended ? 
				(&mm2s_cmd_done_extension_cnt):
				mm2s_cmd_done
		)
			mm2s_cmd_done_extended <= # SIM_DELAY ~mm2s_cmd_done_extended;
	end
	// 延长的DMA S2MM通道命令完成(请求)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			s2mm_cmd_done_extended <= 1'b0;
		else if(
			s2mm_cmd_done_extended ? 
				(&s2mm_cmd_done_extension_cnt):
				s2mm_cmd_done
		)
			s2mm_cmd_done_extended <= # SIM_DELAY ~s2mm_cmd_done_extended;
	end
	
	// DMA MM2S通道命令完成请求延长(计数器)
	always @(posedge m_axi_aclk)
	begin
		if(mm2s_cmd_done_extended)
			mm2s_cmd_done_extension_cnt <= # SIM_DELAY 5'd0;
		else
			mm2s_cmd_done_extension_cnt <= # SIM_DELAY mm2s_cmd_done_extension_cnt + 5'd1;
	end
	// DMA S2MM通道命令完成请求延长(计数器)
	always @(posedge m_axi_aclk)
	begin
		if(s2mm_cmd_done_extended)
			s2mm_cmd_done_extension_cnt <= # SIM_DELAY 5'd0;
		else
			s2mm_cmd_done_extension_cnt <= # SIM_DELAY s2mm_cmd_done_extension_cnt + 5'd1;
	end
	
	/*
	跨时钟域:
		eth_mac_regs_if_u/eth_tx_buf_baseaddr_r[*] -> ...
		eth_mac_regs_if_u/eth_tx_dsc_buf_len_r[*] -> ...
		eth_mac_regs_if_u/eth_rx_buf_baseaddr_r[*] -> ...
		eth_mac_regs_if_u/eth_rx_dsc_buf_len_r[*] -> ...
		eth_mac_regs_if_u/broadcast_accept_r -> ...
		eth_mac_regs_if_u/unicast_filter_mac_r[*] -> ...
		eth_mac_regs_if_u/multicast_filter_mac_0_r[*] -> ...
		eth_mac_regs_if_u/multicast_filter_mac_1_r[*] -> ...
		eth_mac_regs_if_u/multicast_filter_mac_2_r[*] -> ...
		eth_mac_regs_if_u/multicast_filter_mac_3_r[*] -> ...
	*/
	eth_mac_regs_if #(
		.EN_ITR(EN_ITR),
		.SIM_DELAY(SIM_DELAY)
	)eth_mac_regs_if_u(
		.pclk(pclk),
		.presetn(presetn),
		
		.paddr(paddr),
		.psel(psel),
		.penable(penable),
		.pwrite(pwrite),
		.pwdata(pwdata),
		.pready_out(pready_out),
		.prdata_out(prdata_out),
		.pslverr_out(pslverr_out),
		
		.mm2s_cmd_done(mm2s_cmd_done_sync),
		.s2mm_cmd_done(s2mm_cmd_done_sync),
		
		.new_eth_tx_dsc_created(new_eth_tx_dsc_created),
		.eth_rx_dsc_free(eth_rx_dsc_free),
		
		.dma_const_sts_m_axi_data_width(dma_const_sts_m_axi_data_width),
		.dma_const_sts_en_mm2s_unaligned_trans(dma_const_sts_en_mm2s_unaligned_trans),
		.dma_const_sts_en_s2mm_unaligned_trans(dma_const_sts_en_s2mm_unaligned_trans),
		.mdio_ctrler_present(mdio_ctrler_present),
		
		.eth_tx_buf_baseaddr(eth_tx_buf_baseaddr),
		.eth_tx_dsc_buf_len(eth_tx_dsc_buf_len),
		.eth_rx_buf_baseaddr(eth_rx_buf_baseaddr),
		.eth_rx_dsc_buf_len(eth_rx_dsc_buf_len),
		.broadcast_accept(broadcast_accept),
		.unicast_filter_mac(unicast_filter_mac),
		.multicast_filter_mac_0(multicast_filter_mac_0),
		.multicast_filter_mac_1(multicast_filter_mac_1),
		.multicast_filter_mac_2(multicast_filter_mac_2),
		.multicast_filter_mac_3(multicast_filter_mac_3),
		.mdc_div_rate(mdc_div_rate),
		
		.mdio_access_start(mdio_access_start),
		.mdio_access_is_rd(mdio_access_is_rd),
		.mdio_access_addr(mdio_access_addr),
		.mdio_access_wdata(mdio_access_wdata),
		.mdio_access_idle(mdio_access_idle),
		.mdio_access_rdata(mdio_access_rdata),
		.mdio_access_done(mdio_access_done),
		
		.eth_tx_dsc_mem_ena(eth_tx_dsc_mem_ena),
		.eth_tx_dsc_mem_wea(eth_tx_dsc_mem_wea),
		.eth_tx_dsc_mem_addra(eth_tx_dsc_mem_addra),
		.eth_tx_dsc_mem_dina(eth_tx_dsc_mem_dina),
		.eth_tx_dsc_mem_douta(eth_tx_dsc_mem_douta),
		
		.eth_rx_dsc_mem_ena(eth_rx_dsc_mem_ena),
		.eth_rx_dsc_mem_wea(eth_rx_dsc_mem_wea),
		.eth_rx_dsc_mem_addra(eth_rx_dsc_mem_addra),
		.eth_rx_dsc_mem_dina(eth_rx_dsc_mem_dina),
		.eth_rx_dsc_mem_douta(eth_rx_dsc_mem_douta),
		
		.dma_mm2s_cmd_done_itr(dma_mm2s_cmd_done_itr),
		.dma_s2mm_cmd_done_itr(dma_s2mm_cmd_done_itr)
	);
	
	/*
	跨时钟域:
		eth_mac_regs_if_u/new_eth_tx_dsc_created_r -> sync_for_new_eth_tx_dsc_created_u/dff_chain[0].dffs[0]
		eth_mac_regs_if_u/eth_rx_dsc_free_r -> sync_for_eth_rx_dsc_free_u/dff_chain[0].dffs[0]
		mm2s_cmd_done_extended -> sync_for_mm2s_cmd_done_u/dff_chain[0].dffs[0]
		s2mm_cmd_done_extended -> sync_for_s2mm_cmd_done_u/dff_chain[0].dffs[0]
	*/
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_new_eth_tx_dsc_created_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.single_bit_in(new_eth_tx_dsc_created),
		
		.single_bit_out(new_eth_tx_dsc_created_sync)
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_rx_dsc_free_u(
		.clk(m_axi_aclk),
		.rst_n(m_axi_aresetn),
		
		.single_bit_in(eth_rx_dsc_free),
		
		.single_bit_out(eth_rx_dsc_free_sync)
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_mm2s_cmd_done_u(
		.clk(pclk),
		.rst_n(presetn),
		
		.single_bit_in(mm2s_cmd_done_extended),
		
		.single_bit_out(mm2s_cmd_done_sync)
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_s2mm_cmd_done_u(
		.clk(pclk),
		.rst_n(presetn),
		
		.single_bit_in(s2mm_cmd_done_extended),
		
		.single_bit_out(s2mm_cmd_done_sync)
	);
	
endmodule
