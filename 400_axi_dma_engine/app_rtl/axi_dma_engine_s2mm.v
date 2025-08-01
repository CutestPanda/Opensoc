/*
MIT License

Copyright (c) 2024 Panda, 2257691535@qq.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

`timescale 1ns / 1ps
/********************************************************************
本模块: AXI通用DMA引擎S2MM通道

描述:
接收写请求命令, 接收输入数据流, 驱动AXI写通道
提供4KB边界保护
提供写数据fifo
支持非对齐传输, 支持输入数据流重对齐

注意：
不支持回环(WRAP)突发类型
AXI主机的地址位宽固定为32位
突发类型为固定时, 传输基地址必须是对齐的

仅比对了写请求给出的传输次数和写数据实际的传输次数

协议:
AXIS SLAVE
AXI MASTER(WRITE ONLY)

作者: 陈家耀
日期: 2025/01/29
********************************************************************/


module axi_dma_engine_s2mm #(
	parameter integer DATA_WIDTH = 32, // 传输数据位宽(32 | 64 | 128 | 256)
	parameter integer MAX_BURST_LEN = 32, // 最大的突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	parameter S_CMD_AXIS_COMMON_CLOCK = "true", // 命令AXIS从机与AXI主机是否使用相同的时钟和复位
	parameter S_S2MM_AXIS_COMMON_CLOCK = "true", // 输入数据流AXIS从机与AXI主机是否使用相同的时钟和复位
	parameter EN_WT_BYTES_N_STAT = "false", // 是否启用写字节数实时统计
	parameter EN_UNALIGNED_TRANS = "false", // 是否允许非对齐传输
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 命令AXIS从机的时钟和复位
	input wire s_cmd_axis_aclk,
	input wire s_cmd_axis_aresetn,
	// 输入数据流AXIS从机的时钟和复位
	input wire s_s2mm_axis_aclk,
	input wire s_s2mm_axis_aresetn,
	// AXI主机的时钟和复位
	input wire m_axi_aclk,
	input wire m_axi_aresetn,
	
	// 命令完成指示
	// 注意: S2MM通道命令完成指示是脉冲信号!
	output wire cmd_done,
	
	// 命令AXIS从机
	input wire[55:0] s_cmd_axis_data, // {待传输字节数(24bit), 传输首地址(32bit)}
	input wire s_cmd_axis_user, // {固定(1'b1)/递增(1'b0)传输(1bit)}
	input wire s_cmd_axis_valid,
	output wire s_cmd_axis_ready,
	
	// 输入数据流AXIS从机
	input wire[DATA_WIDTH-1:0] s_s2mm_axis_data,
	input wire[DATA_WIDTH/8-1:0] s_s2mm_axis_keep,
	input wire s_s2mm_axis_last,
	input wire s_s2mm_axis_valid,
	output wire s_s2mm_axis_ready,
	
	// AXI主机(写通道)
	// AW通道
	output wire[31:0] m_axi_awaddr,
	// 2'b00 -> FIXED; 2'b01 -> INCR; 2'b10 -> WRAP; 2'b11 -> RESERVED
	output wire[1:0] m_axi_awburst,
	output wire[3:0] m_axi_awcache, // const -> 4'b0011
	output wire[7:0] m_axi_awlen,
	output wire[2:0] m_axi_awprot, // const -> 3'b000
	output wire[2:0] m_axi_awsize, // const -> clogb2(DATA_WIDTH/8)
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// W通道
	output wire[DATA_WIDTH-1:0] m_axi_wdata,
	output wire[DATA_WIDTH/8-1:0] m_axi_wstrb,
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready,
	// B通道
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_bresp,
	input wire m_axi_bvalid,
	output wire m_axi_bready, // const -> 1'b1
	
	// 错误标志
	output wire[1:0] err_flag // {写响应错误标志(1bit), 写传输次数不匹配错误标志(1bit)}
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 常量 **/
	// 写突发预启动流程控制状态常量
	localparam WBURST_PRE_LC_CTRL_STS_IDLE = 2'b00; // 状态: 空闲
	localparam WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0 = 2'b01; // 状态: 生成突发信息阶段#0
	localparam WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1 = 2'b10; // 状态: 生成突发信息阶段#1
	localparam WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST = 2'b11; // 状态: 启动突发
	// AXI突发类型
	localparam AXI_BURST_FIXED = 2'b00;
	localparam AXI_BURST_INCR = 2'b01;
	localparam AXI_BURST_WRAP = 2'b10;
	// 写突发生命周期标志各个阶段对应的独热码索引
	localparam integer WT_BURST_LIFE_CYCLE_INVALID = 0;
	localparam integer WT_BURST_LIFE_CYCLE_PRE_LAUNCHED = 1;
	localparam integer WT_BURST_LIFE_CYCLE_DATA_READY = 2;
	localparam integer WT_BURST_LIFE_CYCLE_TRANS = 3;
	
	/** 写数据实时统计 **/
	// 命令AXIS从机
	wire[31:0] s_cmd_stat_axis_data; // {传输首地址(32bit)}
	wire s_cmd_stat_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_cmd_stat_axis_valid;
	wire s_cmd_stat_axis_ready;
	// 命令AXIS主机
	wire[55:0] m_cmd_stat_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_cmd_stat_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_cmd_stat_axis_last; // 标志自动分割后命令包的最后1条
	wire m_cmd_stat_axis_valid;
	wire m_cmd_stat_axis_ready;
	// 输入数据流AXIS从机
	wire[DATA_WIDTH-1:0] s_s2mm_stat_axis_data;
	wire[DATA_WIDTH/8-1:0] s_s2mm_stat_axis_keep;
	wire s_s2mm_stat_axis_last;
	wire s_s2mm_stat_axis_valid;
	wire s_s2mm_stat_axis_ready;
	// 输入数据流AXIS主机
	wire[DATA_WIDTH-1:0] m_s2mm_stat_axis_data;
	wire[DATA_WIDTH/8-1:0] m_s2mm_stat_axis_keep;
	wire m_s2mm_stat_axis_last;
	wire m_s2mm_stat_axis_valid;
	wire m_s2mm_stat_axis_ready;
	
	generate
		if(EN_WT_BYTES_N_STAT == "true")
		begin
			assign s_cmd_stat_axis_data = s_cmd_axis_data[31:0];
			assign s_cmd_stat_axis_user = s_cmd_axis_user;
			assign s_cmd_stat_axis_valid = s_cmd_axis_valid;
			assign s_cmd_axis_ready = s_cmd_stat_axis_ready;
			
			assign s_s2mm_stat_axis_data = s_s2mm_axis_data;
			assign s_s2mm_stat_axis_keep = s_s2mm_axis_keep;
			assign s_s2mm_stat_axis_last = s_s2mm_axis_last;
			assign s_s2mm_stat_axis_valid = s_s2mm_axis_valid;
			assign s_s2mm_axis_ready = s_s2mm_stat_axis_ready;
			
			axi_dma_engine_wdata_stat #(
				.DATA_WIDTH(DATA_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)axi_dma_engine_wdata_stat_u(
				.cmd_axis_aclk(s_cmd_axis_aclk),
				.cmd_axis_aresetn(s_cmd_axis_aresetn),
				.s2mm_axis_aclk(s_s2mm_axis_aclk),
				.s2mm_axis_aresetn(s_s2mm_axis_aresetn),
				
				.s_cmd_axis_data(s_cmd_stat_axis_data),
				.s_cmd_axis_user(s_cmd_stat_axis_user),
				.s_cmd_axis_valid(s_cmd_stat_axis_valid),
				.s_cmd_axis_ready(s_cmd_stat_axis_ready),
				
				.m_cmd_axis_data(m_cmd_stat_axis_data),
				.m_cmd_axis_user(m_cmd_stat_axis_user),
				.m_cmd_axis_last(m_cmd_stat_axis_last),
				.m_cmd_axis_valid(m_cmd_stat_axis_valid),
				.m_cmd_axis_ready(m_cmd_stat_axis_ready),
				
				.s_s2mm_axis_data(s_s2mm_stat_axis_data),
				.s_s2mm_axis_keep(s_s2mm_stat_axis_keep),
				.s_s2mm_axis_last(s_s2mm_stat_axis_last),
				.s_s2mm_axis_valid(s_s2mm_stat_axis_valid),
				.s_s2mm_axis_ready(s_s2mm_stat_axis_ready),
				
				.m_s2mm_axis_data(m_s2mm_stat_axis_data),
				.m_s2mm_axis_keep(m_s2mm_stat_axis_keep),
				.m_s2mm_axis_last(m_s2mm_stat_axis_last),
				.m_s2mm_axis_valid(m_s2mm_stat_axis_valid),
				.m_s2mm_axis_ready(m_s2mm_stat_axis_ready)
			);
		end
		else
		begin
			assign s_cmd_stat_axis_ready = 1'b1;
			
			assign s_s2mm_stat_axis_ready = 1'b1;
			
			assign m_cmd_stat_axis_data = s_cmd_axis_data;
			assign m_cmd_stat_axis_user = s_cmd_axis_user;
			assign m_cmd_stat_axis_last = 1'b1;
			assign m_cmd_stat_axis_valid = s_cmd_axis_valid;
			assign s_cmd_axis_ready = m_cmd_stat_axis_ready;
			
			assign m_s2mm_stat_axis_data = s_s2mm_axis_data;
			assign m_s2mm_stat_axis_keep = s_s2mm_axis_keep;
			assign m_s2mm_stat_axis_last = s_s2mm_axis_last;
			assign m_s2mm_stat_axis_valid = s_s2mm_axis_valid;
			assign s_s2mm_axis_ready = m_s2mm_stat_axis_ready;
		end
	endgenerate
	
	/** 命令fifo **/
	// fifo写端口
	wire[55:0] s_cmd_fifo_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire s_cmd_fifo_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire s_cmd_fifo_axis_last; // 标志自动分割后命令包的最后1条
	wire s_cmd_fifo_axis_valid;
	wire s_cmd_fifo_axis_ready;
	// fifo读端口
	wire[55:0] m_cmd_fifo_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m_cmd_fifo_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m_cmd_fifo_axis_last; // 标志自动分割后命令包的最后1条
	wire m_cmd_fifo_axis_valid;
	wire m_cmd_fifo_axis_ready;
	
	assign s_cmd_fifo_axis_data = m_cmd_stat_axis_data;
	assign s_cmd_fifo_axis_user = m_cmd_stat_axis_user;
	assign s_cmd_fifo_axis_last = m_cmd_stat_axis_last;
	assign s_cmd_fifo_axis_valid = m_cmd_stat_axis_valid;
	assign m_cmd_stat_axis_ready = s_cmd_fifo_axis_ready;
	
	axis_data_fifo #(
		.is_async((S_CMD_AXIS_COMMON_CLOCK == "true") ? "false":"true"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth(512),
		.data_width(56),
		.user_width(1),
		.simulation_delay(SIM_DELAY)
	)cmd_fifo(
		.s_axis_aclk(s_cmd_axis_aclk),
		.s_axis_aresetn(s_cmd_axis_aresetn),
		.m_axis_aclk(m_axi_aclk),
		.m_axis_aresetn(m_axi_aresetn),
		
		.s_axis_data(s_cmd_fifo_axis_data),
		.s_axis_keep(7'bxxx_xxxx),
		.s_axis_strb(7'bxxx_xxxx),
		.s_axis_user(s_cmd_fifo_axis_user),
		.s_axis_last(s_cmd_fifo_axis_last),
		.s_axis_valid(s_cmd_fifo_axis_valid),
		.s_axis_ready(s_cmd_fifo_axis_ready),
		
		.m_axis_data(m_cmd_fifo_axis_data),
		.m_axis_keep(),
		.m_axis_strb(),
		.m_axis_user(m_cmd_fifo_axis_user),
		.m_axis_last(m_cmd_fifo_axis_last),
		.m_axis_valid(m_cmd_fifo_axis_valid),
		.m_axis_ready(m_cmd_fifo_axis_ready)
	);
	
	/** 命令流输入 **/
	wire[23:0] in_cmd_btt; // 待传输字节数
	wire[31:0] in_cmd_baseaddr; // 传输首地址
	// 注意: 传输末地址用于计算传输次数, 因此仅考虑传输首地址的非对齐部分!
	wire[24:0] in_cmd_trm_addr; // 传输末地址
	wire[23:0] in_cmd_trans_n; // 传输次数
	wire in_cmd_fixed; // 是否固定传输
	wire in_cmd_last; // 标志自动分割后命令包的最后1条
	wire in_cmd_valid;
	wire in_cmd_ready;
	
	assign {in_cmd_btt, in_cmd_baseaddr} = m_cmd_fifo_axis_data;
	assign in_cmd_trm_addr = in_cmd_btt + in_cmd_baseaddr[clogb2(DATA_WIDTH/8-1):0];
	assign in_cmd_trans_n = in_cmd_trm_addr[24:clogb2(DATA_WIDTH/8-1)+1] + (|in_cmd_trm_addr[clogb2(DATA_WIDTH/8-1):0]);
	assign in_cmd_fixed = m_cmd_fifo_axis_user;
	assign in_cmd_last = m_cmd_fifo_axis_last;
	assign in_cmd_valid = m_cmd_fifo_axis_valid;
	assign m_cmd_fifo_axis_ready = in_cmd_ready;
	
	/**
	写突发信息
	
	写突发的生命周期:
		无效 -> 写突发已预启动 -> 写突发的数据已准备好 -> 传输中
	**/
	// 写突发信息表
	reg[3:0] wt_burst_life_cycle_flag[0:3]; // 写突发生命周期标志
	reg[31:0] wt_burst_baseaddr[0:3]; // 写突发首地址
	reg[7:0] wt_burst_len_sub1[0:3]; // 写突发长度 - 1
	reg wt_burst_is_fixed[0:3]; // 是否固定传输
	reg wt_burst_is_last_of_req[0:3]; // 是否写请求最后1次突发
	reg wt_burst_is_last_split_cmd[0:3]; // 是否自动分割后命令包的最后1条命令
	// 预启动写突发
	wire to_pre_launch_wt_burst; // 执行预启动写突发(标志)
	wire wt_burst_item_pre_launch_permitted; // 当前写突发信息表项允许预启动(标志)
	reg[3:0] wt_burst_pre_launch_ptr; // 待预启动写突发信息表项(指针)
	wire[31:0] wt_burst_pre_launch_baseaddr; // 预启动写突发时给出的首地址
	wire[7:0] wt_burst_pre_launch_len_sub1; // 预启动写突发时给出的(写突发长度 - 1)
	wire wt_burst_pre_launch_is_fixed; // 预启动写突发时给出的"是否固定传输"标志
	wire wt_burst_pre_launch_is_last_of_req; // 预启动写突发时给出的"是否写请求最后1次突发"标志
	wire wt_burst_pre_launch_is_last_split_cmd; // 预启动写突发时给出的"自动分割后命令包的最后1条"标志
	// 准备好写突发的数据
	wire wt_data_prepared; // 准备好当前写突发信息表项的数据(标志)
	wire wt_burst_item_at_data_preparation_stage; // 当前写突发信息表项处于准备数据阶段(标志)
	reg[3:0] wt_burst_data_preparation_ptr; // 待准备数据的写突发信息表项(指针)
	// 写突发开始传输
	wire to_start_wt_burst; // 执行写突发开始传输(标志)
	wire wt_burst_item_trans_permitted; // 当前写突发信息表项允许开始传输(标志)
	reg[3:0] wt_burst_start_trans_ptr; // 待开始传输的写突发信息表项(指针)
	// 完成写突发
	wire to_fns_wt_burst; // 完成当前表项对应的写突发(标志)
	wire wt_burst_item_at_trans_stage; // 当前写突发信息表项处于传输阶段(标志)
	reg[3:0] wt_burst_cmplt_ptr; // 待完成的写突发信息表项(指针)
	
	assign wt_burst_item_pre_launch_permitted = 
		|(wt_burst_pre_launch_ptr & {
			wt_burst_life_cycle_flag[3][WT_BURST_LIFE_CYCLE_INVALID], 
			wt_burst_life_cycle_flag[2][WT_BURST_LIFE_CYCLE_INVALID], 
			wt_burst_life_cycle_flag[1][WT_BURST_LIFE_CYCLE_INVALID], 
			wt_burst_life_cycle_flag[0][WT_BURST_LIFE_CYCLE_INVALID]
		});
	assign wt_burst_item_at_data_preparation_stage = 
		|(wt_burst_data_preparation_ptr & {
			wt_burst_life_cycle_flag[3][WT_BURST_LIFE_CYCLE_PRE_LAUNCHED], 
			wt_burst_life_cycle_flag[2][WT_BURST_LIFE_CYCLE_PRE_LAUNCHED], 
			wt_burst_life_cycle_flag[1][WT_BURST_LIFE_CYCLE_PRE_LAUNCHED], 
			wt_burst_life_cycle_flag[0][WT_BURST_LIFE_CYCLE_PRE_LAUNCHED]
		});
	assign wt_burst_item_trans_permitted = 
		|(wt_burst_start_trans_ptr & {
			wt_burst_life_cycle_flag[3][WT_BURST_LIFE_CYCLE_DATA_READY], 
			wt_burst_life_cycle_flag[2][WT_BURST_LIFE_CYCLE_DATA_READY], 
			wt_burst_life_cycle_flag[1][WT_BURST_LIFE_CYCLE_DATA_READY], 
			wt_burst_life_cycle_flag[0][WT_BURST_LIFE_CYCLE_DATA_READY]
		});
	assign wt_burst_item_at_trans_stage = 
		|(wt_burst_cmplt_ptr & {
			wt_burst_life_cycle_flag[3][WT_BURST_LIFE_CYCLE_TRANS], 
			wt_burst_life_cycle_flag[2][WT_BURST_LIFE_CYCLE_TRANS], 
			wt_burst_life_cycle_flag[1][WT_BURST_LIFE_CYCLE_TRANS], 
			wt_burst_life_cycle_flag[0][WT_BURST_LIFE_CYCLE_TRANS]
		});
	
	// 写突发信息表
	genvar wt_burst_msg_i;
	generate
		for(wt_burst_msg_i = 0;wt_burst_msg_i < 4;wt_burst_msg_i = wt_burst_msg_i + 1)
		begin
			// 写突发生命周期标志
			always @(posedge m_axi_aclk or negedge m_axi_aresetn)
			begin
				if(~m_axi_aresetn)
					wt_burst_life_cycle_flag[wt_burst_msg_i] <= (4'b0001 << WT_BURST_LIFE_CYCLE_INVALID);
				else if(
					(wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID] & 
						wt_burst_pre_launch_ptr[wt_burst_msg_i] & to_pre_launch_wt_burst) | 
					(wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_PRE_LAUNCHED] & 
						wt_burst_data_preparation_ptr[wt_burst_msg_i] & wt_data_prepared) | 
					(wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_DATA_READY] & 
						wt_burst_start_trans_ptr[wt_burst_msg_i] & to_start_wt_burst) | 
					(wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_TRANS] & 
						wt_burst_cmplt_ptr[wt_burst_msg_i] & to_fns_wt_burst)
				)
					wt_burst_life_cycle_flag[wt_burst_msg_i] <= # SIM_DELAY 
						({4{wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID]}} & 
							(4'b0001 << WT_BURST_LIFE_CYCLE_PRE_LAUNCHED)) | 
						({4{wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_PRE_LAUNCHED]}} & 
							(4'b0001 << WT_BURST_LIFE_CYCLE_DATA_READY)) | 
						({4{wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_DATA_READY]}} & 
							(4'b0001 << WT_BURST_LIFE_CYCLE_TRANS)) | 
						({4{wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_TRANS]}} & 
							(4'b0001 << WT_BURST_LIFE_CYCLE_INVALID));
			end
			// 写突发首地址
			always @(posedge m_axi_aclk)
			begin
				if(to_pre_launch_wt_burst & 
					wt_burst_pre_launch_ptr[wt_burst_msg_i] & 
					wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID])
					wt_burst_baseaddr[wt_burst_msg_i] <= # SIM_DELAY wt_burst_pre_launch_baseaddr;
			end
			// 写突发长度 - 1
			always @(posedge m_axi_aclk)
			begin
				if(to_pre_launch_wt_burst & 
					wt_burst_pre_launch_ptr[wt_burst_msg_i] & 
					wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID])
					wt_burst_len_sub1[wt_burst_msg_i] <= # SIM_DELAY wt_burst_pre_launch_len_sub1;
			end
			// 是否固定传输
			always @(posedge m_axi_aclk)
			begin
				if(to_pre_launch_wt_burst & 
					wt_burst_pre_launch_ptr[wt_burst_msg_i] & 
					wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID])
					wt_burst_is_fixed[wt_burst_msg_i] <= # SIM_DELAY wt_burst_pre_launch_is_fixed;
			end
			// 是否写请求最后1次突发
			always @(posedge m_axi_aclk)
			begin
				if(to_pre_launch_wt_burst & 
					wt_burst_pre_launch_ptr[wt_burst_msg_i] & 
					wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID])
					wt_burst_is_last_of_req[wt_burst_msg_i] <= # SIM_DELAY wt_burst_pre_launch_is_last_of_req;
			end
			
			// 是否自动分割后命令包的最后1条命令
			always @(posedge m_axi_aclk)
			begin
				if(to_pre_launch_wt_burst & 
					wt_burst_pre_launch_ptr[wt_burst_msg_i] & 
					wt_burst_life_cycle_flag[wt_burst_msg_i][WT_BURST_LIFE_CYCLE_INVALID])
					wt_burst_is_last_split_cmd[wt_burst_msg_i] <= # SIM_DELAY wt_burst_pre_launch_is_last_split_cmd;
			end
		end
	endgenerate
	
	// 待预启动写突发信息表项(指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wt_burst_pre_launch_ptr <= 4'b0001;
		else if(to_pre_launch_wt_burst & wt_burst_item_pre_launch_permitted)
			wt_burst_pre_launch_ptr <= # SIM_DELAY {wt_burst_pre_launch_ptr[2:0], wt_burst_pre_launch_ptr[3]};
	end
	// 待准备数据的写突发信息表项(指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wt_burst_data_preparation_ptr <= 4'b0001;
		else if(wt_data_prepared & wt_burst_item_at_data_preparation_stage)
			wt_burst_data_preparation_ptr <= # SIM_DELAY {wt_burst_data_preparation_ptr[2:0], wt_burst_data_preparation_ptr[3]};
	end
	// 待开始传输的写突发信息表项(指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wt_burst_start_trans_ptr <= 4'b0001;
		else if(to_start_wt_burst & wt_burst_item_trans_permitted)
			wt_burst_start_trans_ptr <= # SIM_DELAY {wt_burst_start_trans_ptr[2:0], wt_burst_start_trans_ptr[3]};
	end
	// 待完成的写突发信息表项(指针)
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wt_burst_cmplt_ptr <= 4'b0001;
		else if(to_fns_wt_burst & wt_burst_item_at_trans_stage)
			wt_burst_cmplt_ptr <= # SIM_DELAY {wt_burst_cmplt_ptr[2:0], wt_burst_cmplt_ptr[3]};
	end
	
	/** 重对齐信息fifo **/
	// fifo写端口
	wire dre_msg_fifo_wen;
	wire[clogb2(DATA_WIDTH/8-1):0] dre_msg_fifo_din; // 重对齐基准字节位置
	wire dre_msg_fifo_full_n;
	// fifo读端口
	wire dre_msg_fifo_ren;
	wire[clogb2(DATA_WIDTH/8-1):0] dre_msg_fifo_dout; // 重对齐基准字节位置
	wire dre_msg_fifo_empty_n;
	
	generate
		if(EN_UNALIGNED_TRANS == "true")
		begin
			if(S_S2MM_AXIS_COMMON_CLOCK == "false")
			begin
				// 注意: 异步时钟下使用深度较小的寄存器fifo也可!
				axis_data_fifo #(
					.is_async("true"),
					.en_packet_mode("false"),
					// 注意: lutram可能不具备通用性!
					.ram_type("lutram"),
					.fifo_depth(32),
					.data_width(8),
					.user_width(1),
					.simulation_delay(SIM_DELAY)
				)dre_msg_fifo(
					.s_axis_aclk(m_axi_aclk),
					.s_axis_aresetn(m_axi_aresetn),
					.m_axis_aclk(s_s2mm_axis_aclk),
					.m_axis_aresetn(s_s2mm_axis_aresetn),
					
					.s_axis_data(8'h00 | dre_msg_fifo_din),
					.s_axis_keep(1'bx),
					.s_axis_strb(1'bx),
					.s_axis_user(1'bx),
					.s_axis_last(1'bx),
					.s_axis_valid(dre_msg_fifo_wen),
					.s_axis_ready(dre_msg_fifo_full_n),
					
					.m_axis_data(dre_msg_fifo_dout), // 位宽8bit与(clogb2(DATA_WIDTH/8-1)+1)bit不符, 截取低位
					.m_axis_keep(),
					.m_axis_strb(),
					.m_axis_user(),
					.m_axis_last(),
					.m_axis_valid(dre_msg_fifo_empty_n),
					.m_axis_ready(dre_msg_fifo_ren)
				);
			end
			else
			begin
				fifo_based_on_regs #(
					.fwft_mode("true"),
					.low_latency_mode("false"),
					.fifo_depth(4),
					.fifo_data_width(clogb2(DATA_WIDTH/8-1)+1),
					.almost_full_th(2),
					.almost_empty_th(2),
					.simulation_delay(SIM_DELAY)
				)dre_msg_fifo(
					.clk(m_axi_aclk),
					.rst_n(m_axi_aresetn),
					
					.fifo_wen(dre_msg_fifo_wen),
					.fifo_din(dre_msg_fifo_din),
					.fifo_full(),
					.fifo_full_n(dre_msg_fifo_full_n),
					.fifo_almost_full(),
					.fifo_almost_full_n(),
					
					.fifo_ren(dre_msg_fifo_ren),
					.fifo_dout(dre_msg_fifo_dout),
					.fifo_empty(),
					.fifo_empty_n(dre_msg_fifo_empty_n),
					.fifo_almost_empty(),
					.fifo_almost_empty_n(),
					
					.data_cnt()
				);
			end
		end
		else
		begin
			assign dre_msg_fifo_full_n = 1'b1;
			
			assign dre_msg_fifo_dout = {(clogb2(DATA_WIDTH/8-1)+1){1'bx}};
			assign dre_msg_fifo_empty_n = 1'b0;
		end
	endgenerate
	
	
	/** 预启动写突发 **/
	reg last_burst_of_req; // 写请求最后1次突发(标志)
	reg[1:0] wburst_pre_lc_ctrl_sts; // 写突发预启动流程控制状态
	reg[23:0] rmn_tn_sub1; // 剩余的传输次数 - 1
	reg[clogb2(4096/(DATA_WIDTH/8)-1):0] rmn_tn_sub1_at_4KB; // 当前4KB区间剩余的传输次数 - 1
	reg[31:0] pre_lc_addr; // 预启动写突发的突发基址
	reg[1:0] pre_lc_burst; // 预启动写突发的突发类型
	reg pre_lc_is_last_split_cmd; // 预启动写突发的"自动分割后命令包的最后1条"标志
	wire[7:0] pre_lc_len; // 预启动写突发的突发长度
	wire pre_lc_valid; // 预启动写突发的valid
	/*
	最小值比较
	
	阶段#0: 计算min(剩余的传输次数 - 1, 最大的突发长度 - 1)
	阶段#1: 计算min(阶段#0结果, 当前4KB区间剩余的传输次数 - 1)
	*/
	wire min_cmp_en; // 计算使能
	wire[23:0] min_cmp_op_a; // 操作数A
	wire[11:0] min_cmp_op_b; // 操作数B
	wire min_cmp_a_leq_b; // 比较情况(操作数A <= 操作数B)
	reg[7:0] min_cmp_res; // 计算结果
	reg min_cmp_a_leq_b_pre; // 上一次比较情况(操作数A <= 操作数B)
	
	assign in_cmd_ready = (wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & dre_msg_fifo_full_n;
	
	assign to_pre_launch_wt_burst = pre_lc_valid;
	assign wt_burst_pre_launch_baseaddr = pre_lc_addr;
	assign wt_burst_pre_launch_len_sub1 = pre_lc_len;
	assign wt_burst_pre_launch_is_fixed = pre_lc_burst != AXI_BURST_INCR;
	assign wt_burst_pre_launch_is_last_of_req = last_burst_of_req;
	assign wt_burst_pre_launch_is_last_split_cmd = pre_lc_is_last_split_cmd;
	
	assign dre_msg_fifo_wen = (wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid;
	assign dre_msg_fifo_din = in_cmd_baseaddr[clogb2(DATA_WIDTH/8-1):0];
	
	assign pre_lc_len = min_cmp_res;
	assign pre_lc_valid = wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST;
	
	assign min_cmp_en = 
		((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0) & wt_burst_item_pre_launch_permitted) | 
		// 注意: 在最小值比较阶段#1, 若突发类型为"固定", 则不必更新"计算结果"和"上一次比较情况"!
		((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1) & (pre_lc_burst == AXI_BURST_INCR));
	assign min_cmp_op_a = 
		(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0) ? 
			rmn_tn_sub1:{16'h0000, min_cmp_res};
	assign min_cmp_op_b = 
		(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0) ? 
			(((pre_lc_burst == AXI_BURST_INCR) ? MAX_BURST_LEN:((MAX_BURST_LEN >= 16) ? 12'd16:MAX_BURST_LEN)) - 12'd1):
			{{clogb2(DATA_WIDTH/8){1'b0}}, rmn_tn_sub1_at_4KB};
	assign min_cmp_a_leq_b = 
		(min_cmp_op_a <= {12'h000, min_cmp_op_b}) | 
		// 注意: 在最小值比较阶段#1, 若突发类型为"固定", 则比较情况必定是"操作数A <= 操作数B"!
		((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1) & (pre_lc_burst != AXI_BURST_INCR));
	
	// 写请求最后1次突发(标志)
	always @(posedge m_axi_aclk)
	begin
		if(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1)
			last_burst_of_req <= # SIM_DELAY min_cmp_a_leq_b_pre & min_cmp_a_leq_b;
	end
	
	// 写突发预启动流程控制状态
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wburst_pre_lc_ctrl_sts <= WBURST_PRE_LC_CTRL_STS_IDLE;
		else if(
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid & dre_msg_fifo_full_n) | 
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0) & wt_burst_item_pre_launch_permitted) | 
			(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1) | 
			(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST)
		)
			wburst_pre_lc_ctrl_sts <= # SIM_DELAY 
				({2{wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE}} & WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0) | 
				({2{wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0}} & WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1) | 
				({2{wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_1}} & WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST) | 
				({2{wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST}} & 
					(last_burst_of_req ? WBURST_PRE_LC_CTRL_STS_IDLE:WBURST_PRE_LC_CTRL_STS_GEN_BURST_MSG_0)
				);
	end
	
	// 剩余的传输次数 - 1
	always @(posedge m_axi_aclk)
	begin
		if(
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid & dre_msg_fifo_full_n) | 
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST) & (~last_burst_of_req))
		)
			rmn_tn_sub1 <= # SIM_DELAY 
				(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) ? 
					// in_cmd_trans_n - 1'b1
					(in_cmd_trans_n + 24'hff_ffff):
					// rmn_tn_sub1 - ({16'h0000, pre_lc_len} + 1'b1)
					(rmn_tn_sub1 + {16'hffff, ~pre_lc_len});
	end
	// 当前4KB区间剩余的传输次数 - 1
	always @(posedge m_axi_aclk)
	begin
		if(
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid & dre_msg_fifo_full_n) | 
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST) & (~last_burst_of_req) & (pre_lc_burst == AXI_BURST_INCR))
		)
			rmn_tn_sub1_at_4KB <= # SIM_DELAY 
				(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) ? 
					(~in_cmd_baseaddr[11:clogb2(DATA_WIDTH/8)]):
					// 注意: 这里将加法位宽拓展到12位, 截取加法结果的低(clogb2(4096/(DATA_WIDTH/8)-1) + 1)位!
					// {{clogb2(DATA_WIDTH/8){1'b0}}, rmn_tn_sub1_at_4KB} - ({4'b0000, pre_lc_len} + 1'b1)
					({{clogb2(DATA_WIDTH/8){1'b0}}, rmn_tn_sub1_at_4KB} + {4'b1111, ~pre_lc_len});
	end
	
	// 预启动写突发的突发基址
	always @(posedge m_axi_aclk)
	begin
		if(
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid & dre_msg_fifo_full_n) | 
			((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_LAUNCH_BURST) & (~last_burst_of_req) & (pre_lc_burst == AXI_BURST_INCR))
		)
			pre_lc_addr <= # SIM_DELAY 
				(wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) ? 
					{in_cmd_baseaddr[31:clogb2(DATA_WIDTH/8)], {clogb2(DATA_WIDTH/8){1'b0}}}:
					({pre_lc_addr[31:clogb2(DATA_WIDTH/8)], {clogb2(DATA_WIDTH/8){1'b0}}} + 
						(({24'h00_0000, pre_lc_len} + 1'b1) * (DATA_WIDTH/8)));
	end
	// 预启动写突发的突发类型
	always @(posedge m_axi_aclk)
	begin
		if((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid & dre_msg_fifo_full_n)
			pre_lc_burst <= # SIM_DELAY in_cmd_fixed ? AXI_BURST_FIXED:AXI_BURST_INCR;
	end
	// 预启动写突发的"自动分割后命令包的最后1条"标志
	always @(posedge m_axi_aclk)
	begin
		if((wburst_pre_lc_ctrl_sts == WBURST_PRE_LC_CTRL_STS_IDLE) & in_cmd_valid & dre_msg_fifo_full_n)
			pre_lc_is_last_split_cmd <= # SIM_DELAY in_cmd_last;
	end
	
	// 最小值比较计算结果
	always @(posedge m_axi_aclk)
	begin
		if(min_cmp_en)
			min_cmp_res <= # SIM_DELAY min_cmp_a_leq_b ? min_cmp_op_a[7:0]:min_cmp_op_b[7:0];
	end
	// 上一次比较情况(操作数A <= 操作数B)
	always @(posedge m_axi_aclk)
	begin
		if(min_cmp_en)
			min_cmp_a_leq_b_pre <= # SIM_DELAY min_cmp_a_leq_b;
	end
	
	/** AXI主机AW通道 **/
	// 当前的写突发信息
	wire[31:0] wburst_baseaddr_at_trans_stage;
	wire[7:0] wburst_len_sub1_at_trans_stage;
	wire wburst_is_fixed_at_trans_stage;
	
	assign m_axi_awaddr = wburst_baseaddr_at_trans_stage;
	assign m_axi_awburst = wburst_is_fixed_at_trans_stage ? AXI_BURST_FIXED:AXI_BURST_INCR;
	assign m_axi_awcache = 4'b0011;
	assign m_axi_awlen = wburst_len_sub1_at_trans_stage;
	assign m_axi_awprot = 3'b000;
	assign m_axi_awsize = clogb2(DATA_WIDTH/8);
	assign m_axi_awvalid = wt_burst_item_trans_permitted;
	
	assign to_start_wt_burst = m_axi_awready;
	
	assign wburst_baseaddr_at_trans_stage = 
		({32{wt_burst_start_trans_ptr[0]}} & wt_burst_baseaddr[0]) | 
		({32{wt_burst_start_trans_ptr[1]}} & wt_burst_baseaddr[1]) | 
		({32{wt_burst_start_trans_ptr[2]}} & wt_burst_baseaddr[2]) | 
		({32{wt_burst_start_trans_ptr[3]}} & wt_burst_baseaddr[3]);
	assign wburst_len_sub1_at_trans_stage = 
		({8{wt_burst_start_trans_ptr[0]}} & wt_burst_len_sub1[0]) | 
		({8{wt_burst_start_trans_ptr[1]}} & wt_burst_len_sub1[1]) | 
		({8{wt_burst_start_trans_ptr[2]}} & wt_burst_len_sub1[2]) | 
		({8{wt_burst_start_trans_ptr[3]}} & wt_burst_len_sub1[3]);
	assign wburst_is_fixed_at_trans_stage = 
		(wt_burst_start_trans_ptr[0] & wt_burst_is_fixed[0]) | 
		(wt_burst_start_trans_ptr[1] & wt_burst_is_fixed[1]) | 
		(wt_burst_start_trans_ptr[2] & wt_burst_is_fixed[2]) | 
		(wt_burst_start_trans_ptr[3] & wt_burst_is_fixed[3]);
	
	/** AXI主机W通道 **/
	// 写突发信息
	wire[7:0] wburst_trans_n_sub1_at_dprep_stage; // 当前写突发的传输次数 - 1
	wire wburst_is_last_of_req_at_dprep_stage; // 是否写请求最后1次突发
	// 写传输次数不匹配错误标志
	reg wt_trans_n_mismatched;
	// 写突发传输计数器
	reg[7:0] wburst_trans_cnt;
	// 写数据重对齐输入数据流AXIS从机
	wire[DATA_WIDTH-1:0] s_dre_axis_data;
	wire[DATA_WIDTH/8-1:0] s_dre_axis_keep;
	wire[4:0] s_dre_axis_user; // 重对齐基准字节位置
	wire s_dre_axis_last;
	wire s_dre_axis_valid;
	wire s_dre_axis_ready;
	// 写数据重对齐输入数据流AXIS主机
	wire[DATA_WIDTH-1:0] m_dre_axis_data;
	wire[DATA_WIDTH/8-1:0] m_dre_axis_keep;
	wire m_dre_axis_last;
	wire m_dre_axis_valid;
	wire m_dre_axis_ready;
	// 写数据fifo写端口
	wire[DATA_WIDTH-1:0] s_wdata_fifo_axis_data;
	wire[DATA_WIDTH/8-1:0] s_wdata_fifo_axis_keep;
	wire s_wdata_fifo_axis_last;
	wire s_wdata_fifo_axis_valid;
	wire s_wdata_fifo_axis_ready;
	// 写数据fifo读端口
	wire[DATA_WIDTH-1:0] m_wdata_fifo_axis_data;
	wire[DATA_WIDTH/8-1:0] m_wdata_fifo_axis_keep;
	wire m_wdata_fifo_axis_last;
	wire m_wdata_fifo_axis_valid;
	wire m_wdata_fifo_axis_ready;
	
	assign s_wdata_fifo_axis_data = m_dre_axis_data;
	assign s_wdata_fifo_axis_keep = m_dre_axis_keep;
	assign s_wdata_fifo_axis_last = wburst_trans_cnt == wburst_trans_n_sub1_at_dprep_stage;
	assign s_wdata_fifo_axis_valid = m_dre_axis_valid & wt_burst_item_at_data_preparation_stage;
	assign m_dre_axis_ready = s_wdata_fifo_axis_ready & wt_burst_item_at_data_preparation_stage;
	
	assign m_axi_wdata = m_wdata_fifo_axis_data;
	assign m_axi_wstrb = m_wdata_fifo_axis_keep;
	assign m_axi_wlast = m_wdata_fifo_axis_last;
	assign m_axi_wvalid = m_wdata_fifo_axis_valid;
	assign m_wdata_fifo_axis_ready = m_axi_wready;
	
	assign err_flag[0] = wt_trans_n_mismatched;
	
	assign wt_data_prepared = m_dre_axis_valid & s_wdata_fifo_axis_ready & s_wdata_fifo_axis_last;
	
	assign wburst_trans_n_sub1_at_dprep_stage = 
		({8{wt_burst_data_preparation_ptr[0]}} & wt_burst_len_sub1[0]) | 
		({8{wt_burst_data_preparation_ptr[1]}} & wt_burst_len_sub1[1]) | 
		({8{wt_burst_data_preparation_ptr[2]}} & wt_burst_len_sub1[2]) | 
		({8{wt_burst_data_preparation_ptr[3]}} & wt_burst_len_sub1[3]);
	assign wburst_is_last_of_req_at_dprep_stage = 
		(wt_burst_data_preparation_ptr[0] & wt_burst_is_last_of_req[0]) | 
		(wt_burst_data_preparation_ptr[1] & wt_burst_is_last_of_req[1]) | 
		(wt_burst_data_preparation_ptr[2] & wt_burst_is_last_of_req[2]) | 
		(wt_burst_data_preparation_ptr[3] & wt_burst_is_last_of_req[3]);
	
	// 写传输次数不匹配错误标志
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wt_trans_n_mismatched <= 1'b0;
		else if((~wt_trans_n_mismatched) & m_dre_axis_valid & m_dre_axis_ready)
			wt_trans_n_mismatched <= # SIM_DELAY 
				m_dre_axis_last ^ (s_wdata_fifo_axis_last & wburst_is_last_of_req_at_dprep_stage);
	end
	
	// 写突发传输计数器
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wburst_trans_cnt <= 8'd0;
		else if(m_dre_axis_valid & m_dre_axis_ready)
			wburst_trans_cnt <= # SIM_DELAY 
				// s_wdata_fifo_axis_last ? 8'd0:(wburst_trans_cnt + 8'd1)
				{8{~s_wdata_fifo_axis_last}} & (wburst_trans_cnt + 8'd1);
	end
	
	generate
		if(EN_UNALIGNED_TRANS == "true")
		begin
			assign s_dre_axis_data = m_s2mm_stat_axis_data;
			assign s_dre_axis_keep = m_s2mm_stat_axis_keep;
			assign s_dre_axis_user = 5'b00000 | dre_msg_fifo_dout;
			assign s_dre_axis_last = m_s2mm_stat_axis_last;
			assign s_dre_axis_valid = m_s2mm_stat_axis_valid & dre_msg_fifo_empty_n;
			assign m_s2mm_stat_axis_ready = s_dre_axis_ready & dre_msg_fifo_empty_n;
			
			assign dre_msg_fifo_ren = m_s2mm_stat_axis_valid & s_dre_axis_ready & m_s2mm_stat_axis_last;
			
			axi_dma_engine_wdata_realign #(
				.DATA_WIDTH(DATA_WIDTH),
				.SIM_DELAY(SIM_DELAY)
			)dre_u(
				.axis_aclk(s_s2mm_axis_aclk),
				.axis_aresetn(s_s2mm_axis_aresetn),
				
				.s_s2mm_axis_data(s_dre_axis_data),
				.s_s2mm_axis_keep(s_dre_axis_keep),
				.s_s2mm_axis_user(s_dre_axis_user),
				.s_s2mm_axis_last(s_dre_axis_last),
				.s_s2mm_axis_valid(s_dre_axis_valid),
				.s_s2mm_axis_ready(s_dre_axis_ready),
				
				.m_s2mm_axis_data(m_dre_axis_data),
				.m_s2mm_axis_keep(m_dre_axis_keep),
				.m_s2mm_axis_last(m_dre_axis_last),
				.m_s2mm_axis_valid(m_dre_axis_valid),
				.m_s2mm_axis_ready(m_dre_axis_ready)
			);
		end
		else
		begin
			assign m_dre_axis_data = m_s2mm_stat_axis_data;
			assign m_dre_axis_keep = m_s2mm_stat_axis_keep;
			assign m_dre_axis_last = m_s2mm_stat_axis_last;
			assign m_dre_axis_valid = m_s2mm_stat_axis_valid;
			assign m_s2mm_stat_axis_ready = m_dre_axis_ready;
			
			assign dre_msg_fifo_ren = 1'b1;
		end
	endgenerate
	
	axis_data_fifo #(
		.is_async((S_S2MM_AXIS_COMMON_CLOCK == "true") ? "false":"true"),
		.en_packet_mode("false"),
		.ram_type("bram"),
		.fifo_depth((MAX_BURST_LEN == 256) ? 1024:512),
		.data_width(DATA_WIDTH),
		.user_width(1),
		.simulation_delay(SIM_DELAY)
	)wdata_fifo(
		.s_axis_aclk(s_s2mm_axis_aclk),
		.s_axis_aresetn(s_s2mm_axis_aresetn),
		.m_axis_aclk(m_axi_aclk),
		.m_axis_aresetn(m_axi_aresetn),
		
		.s_axis_data(s_wdata_fifo_axis_data),
		.s_axis_keep(s_wdata_fifo_axis_keep),
		.s_axis_strb({(DATA_WIDTH/8){1'bx}}),
		.s_axis_user(1'bx),
		.s_axis_last(s_wdata_fifo_axis_last),
		.s_axis_valid(s_wdata_fifo_axis_valid),
		.s_axis_ready(s_wdata_fifo_axis_ready),
		
		.m_axis_data(m_wdata_fifo_axis_data),
		.m_axis_keep(m_wdata_fifo_axis_keep),
		.m_axis_strb(),
		.m_axis_user(),
		.m_axis_last(m_wdata_fifo_axis_last),
		.m_axis_valid(m_wdata_fifo_axis_valid),
		.m_axis_ready(m_wdata_fifo_axis_ready)
	);
	
	/** AXI主机B通道 **/
	// 写响应错误标志
	reg wt_resp_err;
	
	assign cmd_done = 
		m_axi_bvalid & (
			|(wt_burst_cmplt_ptr & {
				wt_burst_is_last_split_cmd[3] & wt_burst_is_last_of_req[3], 
				wt_burst_is_last_split_cmd[2] & wt_burst_is_last_of_req[2], 
				wt_burst_is_last_split_cmd[1] & wt_burst_is_last_of_req[1], 
				wt_burst_is_last_split_cmd[0] & wt_burst_is_last_of_req[0]
			})
		);
	
	assign m_axi_bready = 1'b1;
	
	assign err_flag[1] = wt_resp_err;
	
	assign to_fns_wt_burst = m_axi_bvalid;
	
	// 写响应错误标志
	always @(posedge m_axi_aclk or negedge m_axi_aresetn)
	begin
		if(~m_axi_aresetn)
			wt_resp_err <= 1'b0;
		else if((~wt_resp_err) & m_axi_bvalid)
			wt_resp_err <= # SIM_DELAY m_axi_bresp[1];
	end
	
endmodule
