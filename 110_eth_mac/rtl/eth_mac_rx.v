`timescale 1ns / 1ps
/********************************************************************
本模块: 以太网接收

描述:
输入字节流, 生成接收的以太网帧数据
从以太网帧自动去除前导码、帧起始界定符、帧检验序列
自动舍弃CRC校验失败的帧
自动舍弃不符合最小长度的帧
支持接收MAC地址过滤

注意：
组播过滤MAC的第40位复用为有效位

协议:
AXIS MASTER

作者: 陈家耀
日期: 2025/04/25
********************************************************************/


module eth_mac_rx #(
	parameter integer ETH_RX_TIMEOUT_N = 8, // 以太网接收超时周期数(必须在范围[4, 256]内)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
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
	
	// 以太网帧字节流
	input wire[7:0] eth_rx_data,
	input wire eth_rx_valid,
	
	// 接收的以太网帧数据(AXIS主机)
	output wire[23:0] m_axis_data, // {帧号(8位), 半字数据(16位)}
	output wire[1:0] m_axis_keep,
	output wire m_axis_last,
	output wire m_axis_valid
);
	
	/** 内部配置 **/
	localparam PRE_CODE = 8'h55; // 前导码
	localparam SFD_CODE = 8'hd5; // 帧起始界定符
	localparam integer MIN_ETH_RX_FLEN = 14 + 46; // 可接受的最小以太网帧长度(帧头 + 帧数据)
	
	/** 常量 **/
	// 以太网接收状态独热码索引
	localparam integer ETH_RX_STS_ID_IDLE = 0;
	localparam integer ETH_RX_STS_ID_PRE = 1;
	localparam integer ETH_RX_STS_ID_SFD = 2;
	localparam integer ETH_RX_STS_ID_DATA = 3;
	
	/** 以太网帧数据乒乓缓存 **/
	// 写端口
	wire eth_frame_wen; // 以太网帧缓存写使能
	wire eth_frame_full_n; // 以太网帧缓存满标志
	reg[1:0] eth_frame_wptr_at_w; // 位于写端口的以太网帧缓存写指针
	wire[1:0] eth_frame_rptr_at_w; // 位于写端口的以太网帧缓存读指针
	wire[1:0] ping_pong_ram_wen_a;
	wire[9:0] ping_pong_ram_addr_a[0:1];
	wire[17:0] ping_pong_ram_din_a[0:1]; // {last(1位), 是否两个字节都有效(1位), data(16位)}
	// 读端口
	wire eth_frame_ren; // 以太网帧缓存读使能
	wire eth_frame_empty_n; // 以太网帧缓存空标志
	wire[1:0] eth_frame_wptr_at_r; // 位于读端口的以太网帧缓存写指针
	reg[1:0] eth_frame_rptr_at_r; // 位于读端口的以太网帧缓存读指针
	wire[1:0] ping_pong_ram_ren_b;
	wire[9:0] ping_pong_ram_addr_b[0:1];
	wire[17:0] ping_pong_ram_dout_b[0:1]; // {last(1位), 是否两个字节都有效(1位), data(16位)}
	
	assign eth_frame_full_n = 
		(eth_frame_wptr_at_w[0] == eth_frame_rptr_at_w[0]) | 
		(eth_frame_wptr_at_w[1] == eth_frame_rptr_at_w[1]);
	assign eth_frame_empty_n = 
		eth_frame_wptr_at_r != eth_frame_rptr_at_r;
	
	// 位于写端口的以太网帧缓存写指针
	always @(posedge eth_rx_aclk or negedge eth_rx_aresetn)
	begin
		if(~eth_rx_aresetn)
			eth_frame_wptr_at_w <= 2'b00;
		else if(eth_frame_wen & eth_frame_full_n)
		begin
			case(eth_frame_wptr_at_w)
				2'b00: eth_frame_wptr_at_w <= # SIM_DELAY 2'b01;
				2'b01: eth_frame_wptr_at_w <= # SIM_DELAY 2'b11;
				2'b11: eth_frame_wptr_at_w <= # SIM_DELAY 2'b10;
				2'b10: eth_frame_wptr_at_w <= # SIM_DELAY 2'b00;
				default: eth_frame_wptr_at_w <= # SIM_DELAY 2'b00;
			endcase
		end
	end
	
	// 位于读端口的以太网帧缓存读指针
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			eth_frame_rptr_at_r <= 2'b00;
		else if(eth_frame_ren & eth_frame_empty_n)
		begin
			case(eth_frame_rptr_at_r)
				2'b00: eth_frame_rptr_at_r <= # SIM_DELAY 2'b01;
				2'b01: eth_frame_rptr_at_r <= # SIM_DELAY 2'b11;
				2'b11: eth_frame_rptr_at_r <= # SIM_DELAY 2'b10;
				2'b10: eth_frame_rptr_at_r <= # SIM_DELAY 2'b00;
				default: eth_frame_rptr_at_r <= # SIM_DELAY 2'b00;
			endcase
		end
	end
	
	bram_simple_dual_port_async #(
		.style("LOW_LATENCY"),
		.mem_width(18),
		.mem_depth(1024),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)ping_pong_ram_u0(
		.clk_a(eth_rx_aclk),
		.clk_b(m_axis_aclk),
		
		.wen_a(ping_pong_ram_wen_a[0]),
		.addr_a(ping_pong_ram_addr_a[0]),
		.din_a(ping_pong_ram_din_a[0]),
		
		.ren_b(ping_pong_ram_ren_b[0]),
		.addr_b(ping_pong_ram_addr_b[0]),
		.dout_b(ping_pong_ram_dout_b[0])
	);
	
	bram_simple_dual_port_async #(
		.style("LOW_LATENCY"),
		.mem_width(18),
		.mem_depth(1024),
		.INIT_FILE("no_init"),
		.simulation_delay(SIM_DELAY)
	)ping_pong_ram_u1(
		.clk_a(eth_rx_aclk),
		.clk_b(m_axis_aclk),
		
		.wen_a(ping_pong_ram_wen_a[1]),
		.addr_a(ping_pong_ram_addr_a[1]),
		.din_a(ping_pong_ram_din_a[1]),
		
		.ren_b(ping_pong_ram_ren_b[1]),
		.addr_b(ping_pong_ram_addr_b[1]),
		.dout_b(ping_pong_ram_dout_b[1])
	);
	
	/*
	跨时钟域: 
		eth_frame_wptr_at_w[0] -> sync_for_eth_frame_wptr_u0/dffs[0]
		eth_frame_wptr_at_w[1] -> sync_for_eth_frame_wptr_u1/dffs[0]
		eth_frame_rptr_at_r[0] -> sync_for_eth_frame_rptr_u0/dffs[0]
		eth_frame_rptr_at_r[1] -> sync_for_eth_frame_rptr_u1/dffs[0]
	*/
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_wptr_u0(
		.clk(m_axis_aclk),
		.rst_n(m_axis_aresetn),
		
		.single_bit_in(eth_frame_wptr_at_w[0]),
		
		.single_bit_out(eth_frame_wptr_at_r[0])
	);
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_wptr_u1(
		.clk(m_axis_aclk),
		.rst_n(m_axis_aresetn),
		
		.single_bit_in(eth_frame_wptr_at_w[1]),
		
		.single_bit_out(eth_frame_wptr_at_r[1])
	);
	
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_rptr_u0(
		.clk(eth_rx_aclk),
		.rst_n(eth_rx_aresetn),
		
		.single_bit_in(eth_frame_rptr_at_r[0]),
		
		.single_bit_out(eth_frame_rptr_at_w[0])
	);
	
	single_bit_syn #(
		.SYN_STAGE(3),
		.PRESET_V(1'b0),
		.SIM_DELAY(SIM_DELAY)
	)sync_for_eth_frame_rptr_u1(
		.clk(eth_rx_aclk),
		.rst_n(eth_rx_aresetn),
		
		.single_bit_in(eth_frame_rptr_at_r[1]),
		
		.single_bit_out(eth_frame_rptr_at_w[1])
	);
	
	/** 输出以太网帧数据 **/
	wire frame_buf_rsel; // 以太网帧缓存RAM读选择
	reg[9:0] frame_buf_raddr; // 以太网帧缓存读地址
	reg frame_buf_ren_d1; // 延迟1clk的以太网帧缓存读使能
	reg frame_buf_dout_to_mask; // 舍弃的以太网帧缓存半字(标志)
	wire[15:0] frame_buf_dout_hw; // 以太网帧缓存读数据
	wire frame_buf_dout_both_vld; // 以太网帧缓存半字中两个字节均有效(标志)
	wire frame_buf_dout_last; // 以太网帧缓存最后1个半字(标志)
	wire frame_buf_dout_vld; // 以太网帧缓存半字有效(标志)
	reg[7:0] eth_frame_id_out_r; // 输出的以太网帧号
	reg[15:0] eth_frame_data_out_r; // 输出的以太网帧半字数据
	reg[1:0] eth_frame_keep_out_r; // 输出的以太网帧半字掩码
	reg eth_frame_last_out_r; // 输出的以太网帧最后1个半字(标志)
	reg eth_frame_valid_out_r; // 输出的以太网帧半字有效(标志)
	
	assign m_axis_data = {eth_frame_id_out_r, eth_frame_data_out_r};
	assign m_axis_keep = eth_frame_keep_out_r;
	assign m_axis_last = eth_frame_last_out_r;
	assign m_axis_valid = eth_frame_valid_out_r;
	
	assign eth_frame_ren = frame_buf_ren_d1 & frame_buf_dout_last;
	
	assign ping_pong_ram_ren_b[0] = (~frame_buf_rsel) & ((frame_buf_raddr != 10'd0) | eth_frame_empty_n);
	assign ping_pong_ram_ren_b[1] = frame_buf_rsel & ((frame_buf_raddr != 10'd0) | eth_frame_empty_n);
	assign ping_pong_ram_addr_b[0] = frame_buf_raddr;
	assign ping_pong_ram_addr_b[1] = frame_buf_raddr;
	
	assign frame_buf_rsel = eth_frame_rptr_at_r[0] ^ eth_frame_rptr_at_r[1];
	
	assign {frame_buf_dout_last, frame_buf_dout_both_vld, frame_buf_dout_hw} = ping_pong_ram_dout_b[frame_buf_rsel];
	assign frame_buf_dout_vld = frame_buf_ren_d1 & (~frame_buf_dout_to_mask);
	
	// 以太网帧缓存读地址
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			frame_buf_raddr <= 10'd0;
		else if((frame_buf_raddr != 10'd0) | eth_frame_empty_n)
			frame_buf_raddr <= # SIM_DELAY 
				(frame_buf_ren_d1 & frame_buf_dout_last) ? 
					10'd0:
					(frame_buf_raddr + 10'd1);
	end
	
	// 延迟1clk的以太网帧缓存读使能
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			frame_buf_ren_d1 <= 1'b0;
		else
			frame_buf_ren_d1 <= # SIM_DELAY (frame_buf_raddr != 10'd0) | eth_frame_empty_n;
	end
	
	// 舍弃的以太网帧缓存半字(标志)
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			frame_buf_dout_to_mask <= 1'b0;
		else
			frame_buf_dout_to_mask <= # SIM_DELAY frame_buf_ren_d1 & frame_buf_dout_last;
	end
	
	// 输出的以太网帧号
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			eth_frame_id_out_r <= 8'd0;
		else if(eth_frame_valid_out_r & eth_frame_last_out_r)
			eth_frame_id_out_r <= # SIM_DELAY eth_frame_id_out_r + 8'd1;
	end
	// 输出的以太网帧半字数据, 输出的以太网帧半字掩码, 输出的以太网帧最后1个半字(标志)
	always @(posedge m_axis_aclk)
	begin
		if(frame_buf_dout_vld)
			{eth_frame_data_out_r, eth_frame_keep_out_r, eth_frame_last_out_r} <= # SIM_DELAY 
				{frame_buf_dout_hw, frame_buf_dout_both_vld, 1'b1, frame_buf_dout_last};
	end
	// 输出的以太网帧半字有效(标志)
	always @(posedge m_axis_aclk or negedge m_axis_aresetn)
	begin
		if(~m_axis_aresetn)
			eth_frame_valid_out_r <= 1'b0;
		else
			eth_frame_valid_out_r <= # SIM_DELAY frame_buf_dout_vld;
	end
	
	/** 以太网帧数据接收 **/
	wire frame_buf_extra_wen; // 以太网帧缓存RAM补充写入(指示)
	reg[3:0] eth_rx_sts; // 以太网接收状态
	reg[11:0] eth_rx_field_byte_cnt; // 以太网接收字段内字节计数器
	reg[7:0] eth_rx_timeout_cnt; // 以太网接收超时计数器
	wire frame_buf_wsel; // 以太网帧缓存RAM写选择
	wire eth_rx_timeout_flag; // 以太网接收超时(标志)
	reg[10:0] frame_buf_waddr; // 以太网帧缓存写地址
	wire[10:0] frame_buf_waddr_sub5; // 以太网帧缓存写地址 - 5
	reg[47:0] eth_rx_latest_6byte; // 以太网接收的最近6个字节
	reg[47:0] eth_rx_dst_mac; // 目标MAC地址
	wire[31:0] eth_rx_crc32; // 以太网接收CRC32校验值
	wire[31:0] eth_crc32_cal; // 计算的以太网帧CRC32校验值
	wire[31:0] eth_crc32_for_validate; // 待校验的以太网帧CRC32
	reg[127:0] eth_crc32_for_validate_latest4; // 最近4个待校验的以太网帧CRC32
	reg eth_rx_dst_mac_accept; // 目标MAC地址被接受(标志)
	wire eth_rx_frame_len_agree; // 以太网接收的帧长度符合要求(标志)
	wire eth_rx_crc32_validated; // 以太网接收帧CRC32校验成功(标志)
	
	// 注意: 保证以太网帧缓存满标志(eth_frame_full_n)无效!
	assign eth_frame_wen = frame_buf_extra_wen & eth_rx_dst_mac_accept & eth_rx_frame_len_agree & eth_rx_crc32_validated;
	
	assign ping_pong_ram_wen_a[0] = 
		(~frame_buf_wsel) & 
		((eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_valid & eth_rx_field_byte_cnt[0]) | frame_buf_extra_wen);
	assign ping_pong_ram_wen_a[1] = 
		frame_buf_wsel & 
		((eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_valid & eth_rx_field_byte_cnt[0]) | frame_buf_extra_wen);
	assign ping_pong_ram_addr_a[0] = 
		frame_buf_extra_wen ? 
			frame_buf_waddr_sub5[10:1]:
			frame_buf_waddr[10:1];
	assign ping_pong_ram_addr_a[1] = 
		frame_buf_extra_wen ? 
			frame_buf_waddr_sub5[10:1]:
			frame_buf_waddr[10:1];
	assign ping_pong_ram_din_a[0] = 
		frame_buf_extra_wen ? 
			{1'b1, ~frame_buf_waddr[0], eth_rx_latest_6byte[39:32], 
				frame_buf_waddr[0] ? eth_rx_latest_6byte[39:32]:eth_rx_latest_6byte[47:40]}:
			{1'b0, 1'b1, eth_rx_data, eth_rx_latest_6byte[7:0]};
	assign ping_pong_ram_din_a[1] = 
		frame_buf_extra_wen ? 
			{1'b1, ~frame_buf_waddr[0], eth_rx_latest_6byte[39:32], 
				frame_buf_waddr[0] ? eth_rx_latest_6byte[39:32]:eth_rx_latest_6byte[47:40]}:
			{1'b0, 1'b1, eth_rx_data, eth_rx_latest_6byte[7:0]};
	
	assign frame_buf_extra_wen = eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_timeout_flag;
	
	assign frame_buf_wsel = eth_frame_wptr_at_w[0] ^ eth_frame_wptr_at_w[1];
	
	assign eth_rx_timeout_flag = eth_rx_timeout_cnt == (ETH_RX_TIMEOUT_N - 1);
	
	assign frame_buf_waddr_sub5 = frame_buf_waddr - 11'd5;
	
	assign eth_rx_crc32 = {eth_rx_latest_6byte[7:0], eth_rx_latest_6byte[15:8], eth_rx_latest_6byte[23:16], eth_rx_latest_6byte[31:24]};
	assign eth_crc32_for_validate = 
		~{
			eth_crc32_cal[0], eth_crc32_cal[1], eth_crc32_cal[2], eth_crc32_cal[3], 
			eth_crc32_cal[4], eth_crc32_cal[5], eth_crc32_cal[6], eth_crc32_cal[7], 
			eth_crc32_cal[8], eth_crc32_cal[9], eth_crc32_cal[10], eth_crc32_cal[11], 
			eth_crc32_cal[12], eth_crc32_cal[13], eth_crc32_cal[14], eth_crc32_cal[15], 
			eth_crc32_cal[16], eth_crc32_cal[17], eth_crc32_cal[18], eth_crc32_cal[19], 
			eth_crc32_cal[20], eth_crc32_cal[21], eth_crc32_cal[22], eth_crc32_cal[23], 
			eth_crc32_cal[24], eth_crc32_cal[25], eth_crc32_cal[26], eth_crc32_cal[27], 
			eth_crc32_cal[28], eth_crc32_cal[29], eth_crc32_cal[30], eth_crc32_cal[31]
		};
	assign eth_rx_frame_len_agree = frame_buf_waddr >= (MIN_ETH_RX_FLEN + 4);
	assign eth_rx_crc32_validated = eth_rx_crc32 == eth_crc32_for_validate_latest4[127:96];
	
	// 以太网接收状态
	always @(posedge eth_rx_aclk or negedge eth_rx_aresetn)
	begin
		if(~eth_rx_aresetn)
			eth_rx_sts <= 4'b0001 << ETH_RX_STS_ID_IDLE;
		else if(
			(eth_rx_sts[ETH_RX_STS_ID_IDLE] & eth_rx_valid & (eth_rx_data == PRE_CODE)) | 
			(eth_rx_sts[ETH_RX_STS_ID_PRE] & (
				eth_rx_timeout_flag | (eth_rx_valid & (eth_rx_data != PRE_CODE)) | 
				(eth_rx_valid & (eth_rx_data == PRE_CODE) & (eth_rx_field_byte_cnt == 12'd6))
			)) | 
			(eth_rx_sts[ETH_RX_STS_ID_SFD] & (eth_rx_timeout_flag | eth_rx_valid)) | 
			(eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_timeout_flag)
		)
			eth_rx_sts <= # SIM_DELAY 
				({4{eth_rx_sts[ETH_RX_STS_ID_IDLE]}} & (4'b0001 << ETH_RX_STS_ID_PRE)) | 
				({4{eth_rx_sts[ETH_RX_STS_ID_PRE]}} & (
					(eth_rx_valid & (eth_rx_data == PRE_CODE) & (eth_rx_field_byte_cnt == 12'd6)) ? 
						(4'b0001 << ETH_RX_STS_ID_SFD):
						(4'b0001 << ETH_RX_STS_ID_IDLE)
				)) | 
				({4{eth_rx_sts[ETH_RX_STS_ID_SFD]}} & (
					(eth_rx_valid & (eth_rx_data == SFD_CODE)) ? 
						(4'b0001 << ETH_RX_STS_ID_DATA):
						(4'b0001 << ETH_RX_STS_ID_IDLE)
				)) | 
				({4{eth_rx_sts[ETH_RX_STS_ID_DATA]}} & (4'b0001 << ETH_RX_STS_ID_IDLE));
	end
	
	// 以太网接收字段内字节计数器
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_sts[ETH_RX_STS_ID_IDLE])
			eth_rx_field_byte_cnt <= # SIM_DELAY eth_rx_valid ? 12'd1:12'd0;
		else if(eth_rx_valid)
			eth_rx_field_byte_cnt <= # SIM_DELAY eth_rx_field_byte_cnt + 12'd1;
	end
	
	// 以太网接收超时计数器
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_sts[ETH_RX_STS_ID_IDLE] | eth_rx_valid)
			eth_rx_timeout_cnt <= # SIM_DELAY 8'd0;
		else if(~eth_rx_timeout_flag)
			eth_rx_timeout_cnt <= # SIM_DELAY eth_rx_timeout_cnt + 8'd1;
	end
	
	// 以太网帧缓存写地址
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_sts[ETH_RX_STS_ID_IDLE])
			frame_buf_waddr <= # SIM_DELAY 11'd0;
		else if(eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_valid)
			frame_buf_waddr <= # SIM_DELAY frame_buf_waddr + 11'd1;
	end
	
	// 目标MAC地址
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_valid & (eth_rx_field_byte_cnt >= 12'd8) & (eth_rx_field_byte_cnt <= 12'd13))
			eth_rx_dst_mac <= # SIM_DELAY {eth_rx_dst_mac[39:0], eth_rx_data};
	end
	
	// 最近4个待校验的以太网帧CRC32
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_valid)
			eth_crc32_for_validate_latest4 <= # SIM_DELAY 
				{eth_crc32_for_validate_latest4[95:0], eth_crc32_for_validate};
	end
	
	// 目标MAC地址被接受(标志)
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_valid & (eth_rx_field_byte_cnt == 12'd14))
		begin
			if(eth_rx_dst_mac == 48'hff_ff_ff_ff_ff_ff) // 广播过滤
				eth_rx_dst_mac_accept <= # SIM_DELAY broadcast_accept;
			else if(~eth_rx_dst_mac[40]) // 单播过滤
				eth_rx_dst_mac_accept <= # SIM_DELAY eth_rx_dst_mac == unicast_filter_mac;
			else // 组播过滤
				eth_rx_dst_mac_accept <= # SIM_DELAY 
					(multicast_filter_mac_0[40] & (eth_rx_dst_mac == multicast_filter_mac_0)) | 
					(multicast_filter_mac_1[40] & (eth_rx_dst_mac == multicast_filter_mac_1)) | 
					(multicast_filter_mac_2[40] & (eth_rx_dst_mac == multicast_filter_mac_2)) | 
					(multicast_filter_mac_3[40] & (eth_rx_dst_mac == multicast_filter_mac_3));
		end
	end
	
	// 以太网接收的最近6个字节
	always @(posedge eth_rx_aclk)
	begin
		if(eth_rx_valid)
			eth_rx_latest_6byte <= # SIM_DELAY {eth_rx_latest_6byte[39:0], eth_rx_data};
	end
	
	crc32_d8 #(
		.SIM_DELAY(SIM_DELAY)
	)crc32_d8_u(
		.clk(eth_rx_aclk),
		.rst_n(eth_rx_aresetn),
		
		.data(eth_rx_data),
		.crc_en(eth_rx_sts[ETH_RX_STS_ID_DATA] & eth_rx_valid),
		.crc_clr(eth_rx_sts[ETH_RX_STS_ID_IDLE]),
		.crc_data(eth_crc32_cal),
		.crc_next()
	);
	
endmodule
