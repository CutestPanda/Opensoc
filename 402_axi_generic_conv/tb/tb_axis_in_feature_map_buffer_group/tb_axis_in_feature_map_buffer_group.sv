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

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_axis_in_feature_map_buffer_group();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer in_feature_map_buffer_n = 4; // 输入特征图缓存个数
	localparam integer in_feature_map_buffer_rd_prl_n = 2; // 读输入特征图缓存的并行个数
	localparam integer feature_data_width = 16; // 特征点位宽(8 | 16 | 32 | 64)
	localparam integer max_feature_map_w = 512; // 最大的输入特征图宽度
	localparam line_buffer_mem_type = "bram"; // 行缓存MEM类型("bram" | "lutram" | "auto")
	// 运行时参数配置
	localparam integer feature_map_w = 7; // 特征图宽度
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(2)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(feature_data_width*3*in_feature_map_buffer_rd_prl_n), .user_width(in_feature_map_buffer_rd_prl_n*3)) s_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(2)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(feature_data_width*3*in_feature_map_buffer_rd_prl_n), .user_width(in_feature_map_buffer_rd_prl_n*3)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(feature_data_width*3*in_feature_map_buffer_rd_prl_n), .user_width(in_feature_map_buffer_rd_prl_n*3)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("AxisInFtMapBufGrpCase0Test");
	end
	
	/** 待测模块 **/
	axis_in_feature_map_buffer_group #(
		.in_feature_map_buffer_n(in_feature_map_buffer_n),
		.in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n),
		.feature_data_width(feature_data_width),
		.max_feature_map_w(max_feature_map_w),
		.line_buffer_mem_type(line_buffer_mem_type),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.feature_map_w(feature_map_w - 1),
		
		.s_axis_ft_data(m_axis_if.data),
		.s_axis_ft_user(m_axis_if.user),
		.s_axis_ft_last(m_axis_if.last),
		.s_axis_ft_valid(m_axis_if.valid),
		.s_axis_ft_ready(m_axis_if.ready),
		
		.m_axis_buf_data(s_axis_if.data),
		.m_axis_buf_user(s_axis_if.user),
		.m_axis_buf_last(s_axis_if.last),
		.m_axis_buf_valid(s_axis_if.valid),
		.m_axis_buf_ready(s_axis_if.ready)
	);
	
endmodule
