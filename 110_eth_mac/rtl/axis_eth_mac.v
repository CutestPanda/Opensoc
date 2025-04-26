`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS-以太网MAC

描述:
1.以太网发送
接收以太网帧数据包, 添加前导码、帧起始界定符、帧检验序列并在必要时填充帧数据, 输出字节流
对于每个以太网帧, 字节流是连续输出的

2.以太网接收
输入字节流, 生成接收的以太网帧数据
从以太网帧自动去除前导码、帧起始界定符、帧检验序列
自动舍弃CRC校验失败的帧
自动舍弃不符合最小长度的帧
支持接收MAC地址过滤

注意：
组播过滤MAC的第40位复用为有效位

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/04/26
********************************************************************/


module axis_eth_mac #(
	parameter integer ETH_RX_TIMEOUT_N = 8, // 以太网接收超时周期数(必须在范围[4, 256]内)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // AXIS从机时钟和复位
	input wire s_axis_aclk,
	input wire s_axis_aresetn,
	// 以太网发送时钟和复位
	input wire eth_tx_aclk,
	input wire eth_tx_aresetn,
	// AXIS主机时钟和复位
	input wire m_axis_aclk,
	input wire m_axis_aresetn,
	// 以太网接收时钟和复位
	input wire eth_rx_aclk,
	input wire eth_rx_aresetn,
	
	// 接收MAC地址过滤
	input wire broadcast_accept, // 是否接受广播帧
	input wire[47:0] unicast_filter_mac, // 单播过滤MAC
	input wire[47:0] multicast_filter_mac_0, // 组播过滤MAC#0
	input wire[47:0] multicast_filter_mac_1, // 组播过滤MAC#1
	input wire[47:0] multicast_filter_mac_2, // 组播过滤MAC#2
	input wire[47:0] multicast_filter_mac_3, // 组播过滤MAC#3
	
	// 发送的以太网帧数据(AXIS从机)
	input wire[15:0] s_axis_data,
	input wire[1:0] s_axis_keep,
	input wire s_axis_last,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// 接收的以太网帧数据(AXIS主机)
	output wire[23:0] m_axis_data, // {帧号(8位), 半字数据(16位)}
	output wire[1:0] m_axis_keep,
	output wire m_axis_last,
	output wire m_axis_valid,
	
	// 发送的以太网帧字节流
	output wire[7:0] eth_tx_data,
	output wire eth_tx_valid,
	
	// 接收的以太网帧字节流
	input wire[7:0] eth_rx_data,
	input wire eth_rx_valid
);
	
	eth_mac_tx #(
		.SIM_DELAY(SIM_DELAY)
	)eth_mac_tx_u(
		.s_axis_aclk(s_axis_aclk),
		.s_axis_aresetn(s_axis_aresetn),
		.eth_tx_aclk(eth_tx_aclk),
		.eth_tx_aresetn(eth_tx_aresetn),
		
		.s_axis_data(s_axis_data),
		.s_axis_keep(s_axis_keep),
		.s_axis_last(s_axis_last),
		.s_axis_valid(s_axis_valid),
		.s_axis_ready(s_axis_ready),
		
		.eth_tx_data(eth_tx_data),
		.eth_tx_valid(eth_tx_valid)
	);
	
	eth_mac_rx #(
		.ETH_RX_TIMEOUT_N(ETH_RX_TIMEOUT_N),
		.SIM_DELAY(SIM_DELAY)
	)eth_mac_rx_u(
		.m_axis_aclk(m_axis_aclk),
		.m_axis_aresetn(m_axis_aresetn),
		.eth_rx_aclk(eth_rx_aclk),
		.eth_rx_aresetn(eth_rx_aresetn),
		
		.broadcast_accept(broadcast_accept),
		.unicast_filter_mac(unicast_filter_mac),
		.multicast_filter_mac_0(multicast_filter_mac_0),
		.multicast_filter_mac_1(multicast_filter_mac_1),
		.multicast_filter_mac_2(multicast_filter_mac_2),
		.multicast_filter_mac_3(multicast_filter_mac_3),
		
		.eth_rx_data(eth_rx_data),
		.eth_rx_valid(eth_rx_valid),
		
		.m_axis_data(m_axis_data),
		.m_axis_keep(m_axis_keep),
		.m_axis_last(m_axis_last),
		.m_axis_valid(m_axis_valid)
	);
	
endmodule
