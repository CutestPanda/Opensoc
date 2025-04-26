`timescale 1ns / 1ps
/********************************************************************
本模块: ARP发送测试

描述:
无

注意：
无

协议:
RGMII

作者: 陈家耀
日期: 2025/04/26
********************************************************************/


module eth_arp_tx_test(
    // 时钟和复位
	input wire osc_clk,
	input wire ext_resetn,
	
	// 按键
	input wire key_start,
	
	// RGMII接口
	output wire eth_txc, // RGMII发送数据时钟    
    output wire eth_tx_ctl, // RGMII输出数据有效信号
    output wire[3:0] eth_txd, // RGMII输出数据          
    output wire eth_rst_n, // 以太网芯片复位信号，低电平有效
	input wire eth_rxc, // RGMII接收数据时钟
    input wire eth_rx_ctl, // RGMII输入数据有效信号
    input wire[3:0] eth_rxd // RGMII输入数据
);
	
	/** 内部配置 **/
	localparam SRC_MAC = 48'h00_11_22_33_44_55; // 源MAC地址
	localparam SRC_IP = 32'hc0_a8_01_6D; // 源IP地址(192.168.1.109)
	localparam DST_IP = 32'hc0_a8_01_66; // 目标IP地址(192.168.1.102)
	
	/** PLL **/
	wire pll_clk_in;
	wire pll_resetn_in;
	wire pll_clk_eth_tx_out; // 125MHz
	wire pll_clk_idelay_out; // 200MHz
	wire pll_clk_axis_out; // 100MHz
	wire pll_resetn_out;
	
	assign pll_clk_in = osc_clk;
	assign pll_resetn_in = ext_resetn;
	
	// 请例化PLL!!!
	/*
	clk_wiz_0 pll_u0(
	   .clk_in1(pll_clk_in),
	   .resetn(pll_resetn_in),
	   
	   .clk_out1(pll_clk_eth_tx_out),
	   .clk_out2(pll_clk_idelay_out),
	   .clk_out3(pll_clk_axis_out),
	   .locked(pll_resetn_out)
	);
	*/
	
	/** 开始测试按键 **/
	wire key_start_pressed;
	
	key_detect #(
		.elmt_buff_p(2 * 1000 * 1000),
		.detect_edge("neg"),
		.simulation_delay(0)
	)key_detect_u0(
		.clk(pll_clk_axis_out),
		.rst_n(pll_resetn_out),
		
		.key(key_start),
		
		.pressed(key_start_pressed)
	);
	
	/** 以太网发送测试帧 **/
	wire[15:0] tx_data_lut[1:21];
	reg[4:0] tx_cnt;
	// 发送的以太网帧数据(AXIS主机)
	wire[15:0] m_tx_axis_data;
	wire[1:0] m_tx_axis_keep;
	wire m_tx_axis_last;
	wire m_tx_axis_valid;
	wire m_tx_axis_ready;
	
	assign tx_data_lut[1] = 16'hff_ff;
	assign tx_data_lut[2] = 16'hff_ff;
	assign tx_data_lut[3] = 16'hff_ff;
	assign tx_data_lut[4] = {SRC_MAC[39:32], SRC_MAC[47:40]};
	assign tx_data_lut[5] = {SRC_MAC[23:16], SRC_MAC[31:24]};
	assign tx_data_lut[6] = {SRC_MAC[7:0], SRC_MAC[15:8]};
	assign tx_data_lut[7] = 16'h06_08;
	assign tx_data_lut[8] = 16'h01_00;
	assign tx_data_lut[9] = 16'h00_08;
	assign tx_data_lut[10] = 16'h04_06;
	assign tx_data_lut[11] = 16'h01_00;
	assign tx_data_lut[12] = {SRC_MAC[39:32], SRC_MAC[47:40]};
	assign tx_data_lut[13] = {SRC_MAC[23:16], SRC_MAC[31:24]};
	assign tx_data_lut[14] = {SRC_MAC[7:0], SRC_MAC[15:8]};
	assign tx_data_lut[15] = {SRC_IP[23:16], SRC_IP[31:24]};
	assign tx_data_lut[16] = {SRC_IP[7:0], SRC_IP[15:8]};
	assign tx_data_lut[17] = 16'hff_ff;
	assign tx_data_lut[18] = 16'hff_ff;
	assign tx_data_lut[19] = 16'hff_ff;
	assign tx_data_lut[20] = {DST_IP[23:16], DST_IP[31:24]};
	assign tx_data_lut[21] = {DST_IP[7:0], DST_IP[15:8]};
	
	assign m_tx_axis_data = tx_data_lut[tx_cnt];
	assign m_tx_axis_keep = 2'b11;
	assign m_tx_axis_last = tx_cnt == 5'd21;
	assign m_tx_axis_valid = tx_cnt != 5'd0;
	
	always @(posedge pll_clk_axis_out or negedge pll_resetn_out)
	begin
		if(~pll_resetn_out)
			tx_cnt <= 5'd0;
		else if((tx_cnt == 5'd0) ? key_start_pressed:m_tx_axis_ready)
			tx_cnt <= (tx_cnt == 5'd21) ? 5'd0:(tx_cnt + 5'd1);
	end
	
	/** AXIS-以太网MAC **/
	// 以太网接收时钟和复位
	wire eth_rx_aclk;
	wire eth_rx_aresetn;
	// 发送的以太网帧数据(AXIS从机)
	wire[15:0] s_tx_axis_data;
	wire[1:0] s_tx_axis_keep;
	wire s_tx_axis_last;
	wire s_tx_axis_valid;
	wire s_tx_axis_ready;
	// 接收的以太网帧数据(AXIS主机)
	wire[23:0] m_rx_axis_data; // {帧号(8位), 半字数据(16位)}
	wire[1:0] m_rx_axis_keep;
	wire m_rx_axis_last;
	wire m_rx_axis_valid;
	// 发送的以太网帧字节流
	wire[7:0] eth_tx_data;
	wire eth_tx_valid;
	// 接收的以太网帧字节流
	wire[7:0] eth_rx_data;
	wire eth_rx_valid;
	
	assign s_tx_axis_data = m_tx_axis_data;
	assign s_tx_axis_keep = m_tx_axis_keep;
	assign s_tx_axis_last = m_tx_axis_last;
	assign s_tx_axis_valid = m_tx_axis_valid;
	assign m_tx_axis_ready = s_tx_axis_ready;
	
	axis_eth_mac #(
		.ETH_RX_TIMEOUT_N(8),
		.SIM_DELAY(0)
	)axis_eth_mac_u(
		.s_axis_aclk(pll_clk_axis_out),
		.s_axis_aresetn(pll_resetn_out),
		.eth_tx_aclk(pll_clk_eth_tx_out),
		.eth_tx_aresetn(pll_resetn_out),
		.m_axis_aclk(pll_clk_axis_out),
		.m_axis_aresetn(pll_resetn_out),
		.eth_rx_aclk(eth_rx_aclk),
		.eth_rx_aresetn(eth_rx_aresetn),
		
		.broadcast_accept(1'b0),
		.unicast_filter_mac(SRC_MAC),
		.multicast_filter_mac_0(48'h00_00_00_00_00_00),
		.multicast_filter_mac_1(48'h00_00_00_00_00_00),
		.multicast_filter_mac_2(48'h00_00_00_00_00_00),
		.multicast_filter_mac_3(48'h00_00_00_00_00_00),
		
		.s_axis_data(s_tx_axis_data),
		.s_axis_keep(s_tx_axis_keep),
		.s_axis_last(s_tx_axis_last),
		.s_axis_valid(s_tx_axis_valid),
		.s_axis_ready(s_tx_axis_ready),
		
		.m_axis_data(m_rx_axis_data),
		.m_axis_keep(m_rx_axis_keep),
		.m_axis_last(m_rx_axis_last),
		.m_axis_valid(m_rx_axis_valid),
		
		.eth_tx_data(eth_tx_data),
		.eth_tx_valid(eth_tx_valid),
		
		.eth_rx_data(eth_rx_data),
		.eth_rx_valid(eth_rx_valid)
	);
	
	/** GMII转RGMII **/
	assign eth_rst_n = pll_resetn_out;
	assign eth_rx_aresetn = pll_resetn_out;
	
	rgmii_tx rgmii_tx_u(
		.gmii_tx_clk(pll_clk_eth_tx_out),
		.gmii_tx_en(eth_tx_valid),
		.gmii_txd(eth_tx_data),
		
		.rgmii_txc(eth_txc),
		.rgmii_tx_ctl(eth_tx_ctl),
		.rgmii_txd(eth_txd)
	);
	
	rgmii_rx #(
		.IDELAY_VALUE(0)
	)rgmii_rx_u(
		.idelay_clk(pll_clk_idelay_out),
		
		.rgmii_rxc(eth_rxc),
		.rgmii_rx_ctl(eth_rx_ctl),
		.rgmii_rxd(eth_rxd),
		
		.gmii_rx_clk(eth_rx_aclk),
		.gmii_rx_dv(eth_rx_valid),
		.gmii_rxd(eth_rx_data)
	);
	
endmodule
