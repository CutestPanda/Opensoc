`timescale 1ns / 1ps
/********************************************************************
本模块: AXIS数据fifo

描述: 
符合AXIS协议的同步/异步fifo
支持启用数据包模式(仅当写入了一个数据包或者fifo满时可读)

注意：
同步模式下仅使用从机时钟和复位(s_axis_aclk和s_axis_aresetn)
不用的信号(如keep/strb/user/last)将相应的m_axis_xxx悬空即可

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2024/09/16
********************************************************************/


module axis_data_fifo #(
	parameter is_async = "false", // 是否使用异步fifo
	parameter en_packet_mode = "false", // 是否使用数据包模式
	parameter ram_type = "bram", // RAM类型(lutram|bram)
	parameter fifo_depth = 1024, // fifo深度(必须为16|32|64|128|...)
	parameter integer data_width = 8, // 数据位宽(必须能被8整除, 且>0)
	parameter integer user_width = 1, // user信号位宽(必须>0)
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 从机时钟和复位
	input wire s_axis_aclk,
	input wire s_axis_aresetn,
	// 主机时钟和复位(同步模式下被忽略)
	input wire m_axis_aclk,
	input wire m_axis_aresetn,
	
	// AXIS从机
	input wire[data_width-1:0] s_axis_data,
	input wire[data_width/8-1:0] s_axis_keep,
	input wire[data_width/8-1:0] s_axis_strb,
	input wire[user_width-1:0] s_axis_user,
	input wire s_axis_last,
	input wire s_axis_valid,
	output wire s_axis_ready,
	
	// AXIS主机
	output wire[data_width-1:0] m_axis_data,
	output wire[data_width/8-1:0] m_axis_keep,
	output wire[data_width/8-1:0] m_axis_strb,
	output wire[user_width-1:0] m_axis_user,
	output wire m_axis_last,
	output wire m_axis_valid,
	input wire m_axis_ready
);
	
	/** 常量 **/
	localparam integer fifo_data_width = data_width + data_width/8 + data_width/8 + user_width + 1; // fifo数据位宽
	
	/** 同步/异步fifo **/
	wire[fifo_data_width-1:0] fifo_din;
	wire fifo_ren;
	wire fifo_empty_n;
	wire master_oen; // 主机输出使能
	
	assign fifo_din = {s_axis_data, s_axis_keep, s_axis_strb, s_axis_user, s_axis_last};
	
	/*
	握手条件： 使用数据包模式 -> master_oen & fifo_empty_n & m_axis_ready
			 不使用数据包模式 -> fifo_empty_n & m_axis_ready
	*/
	assign fifo_ren = m_axis_ready & ((en_packet_mode == "false") | master_oen);
	assign m_axis_valid = fifo_empty_n & ((en_packet_mode == "false") | master_oen);
	
	generate
		if(is_async == "false") // 同步
		begin
			// 同步fifo
			ram_fifo_wrapper #(
				.fwft_mode("true"),
				.ram_type(ram_type),
				.en_bram_reg("false"),
				.fifo_depth(fifo_depth),
				.fifo_data_width(fifo_data_width),
				.full_assert_polarity("low"),
				.empty_assert_polarity("low"),
				.almost_full_assert_polarity("no"),
				.almost_empty_assert_polarity("no"),
				.en_data_cnt("false"),
				.almost_full_th(),
				.almost_empty_th(),
				.simulation_delay(simulation_delay)
			)sync_fifo_u(
				.clk(s_axis_aclk),
				.rst_n(s_axis_aresetn),
				
				.fifo_wen(s_axis_valid),
				.fifo_din(fifo_din),
				.fifo_full_n(s_axis_ready),
				
				.fifo_ren(fifo_ren),
				.fifo_dout({m_axis_data, m_axis_keep, m_axis_strb, m_axis_user, m_axis_last}),
				.fifo_empty_n(fifo_empty_n)
			);
			
			// AXIS数据包统计(同步)
			axis_packet_stat_sync #(
				.fifo_depth(fifo_depth),
				.simulation_delay(simulation_delay)
			)axis_packet_stat_sync_u(
				.aclk(s_axis_aclk),
				.aresetn(s_axis_aresetn),
				
				.s_axis_last(s_axis_last),
				.s_axis_valid(s_axis_valid),
				.s_axis_ready(s_axis_ready),
				
				.m_axis_last(m_axis_last),
				.m_axis_valid(m_axis_valid),
				.m_axis_ready(m_axis_ready),
				
				.master_oen(master_oen)
			);
		end
		else // 异步
		begin
			// 异步fifo
			async_fifo_with_ram #(
				.fwft_mode("true"),
				.ram_type(ram_type),
				.depth(fifo_depth),
				.data_width(fifo_data_width),
				.simulation_delay(simulation_delay)
			)async_fifo_u(
				.clk_wt(s_axis_aclk),
				.rst_n_wt(s_axis_aresetn),
				.clk_rd(m_axis_aclk),
				.rst_n_rd(m_axis_aresetn),
				
				.fifo_wen(s_axis_valid),
				.fifo_full_n(s_axis_ready),
				.fifo_din(fifo_din),
				
				.fifo_ren(fifo_ren),
				.fifo_empty_n(fifo_empty_n),
				.fifo_dout({m_axis_data, m_axis_keep, m_axis_strb, m_axis_user, m_axis_last})
			);
			
			// AXIS数据包统计(异步)
			axis_packet_stat_async #(
				.fifo_depth(fifo_depth),
				.simulation_delay(simulation_delay)
			)axis_packet_stat_async_u(
				.s_axis_aclk(s_axis_aclk),
				.s_axis_aresetn(s_axis_aresetn),
				.m_axis_aclk(m_axis_aclk),
				.m_axis_aresetn(m_axis_aresetn),
				
				.s_axis_last(s_axis_last),
				.s_axis_valid(s_axis_valid),
				.s_axis_ready(s_axis_ready),
				
				.m_axis_last(m_axis_last),
				.m_axis_valid(m_axis_valid),
				.m_axis_ready(m_axis_ready),
				
				.master_oen(master_oen)
			);
		end
	endgenerate
	
endmodule
