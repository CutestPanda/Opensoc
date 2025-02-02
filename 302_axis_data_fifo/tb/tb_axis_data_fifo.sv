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

module tb_axis_data_fifo();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam is_async = "true"; // 是否使用异步fifo
	localparam en_packet_mode = "true"; // 是否使用数据包模式
	localparam ram_type = "bram"; // RAM类型(lutram|bram)
	localparam fifo_depth = 16; // fifo深度(必须为16|32|64|128...)
	localparam integer data_width = 8; // 数据位宽(必须能被8整除, 且>0)
	localparam integer user_width = 1; // user信号位宽(必须>0)
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 1号时钟的周期
	localparam real clk_p_2 = 12.0; // 2号时钟的周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg clk2;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (clk_p / 2) clk <= ~clk;
		end
	end
	
	initial
	begin
		clk2 <= 1'b1;
		
		forever
		begin
			# (clk_p_2 / 2) clk2 <= ~clk2;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AXIS #(.out_drive_t(simulation_delay), .data_width(data_width), .user_width(user_width)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(data_width), .user_width(user_width)) 
		s_axis_if(.clk((is_async == "true") ? clk2:clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(data_width), .user_width(user_width)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(data_width), .user_width(user_width)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(data_width), .user_width(user_width)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(data_width), .user_width(user_width)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("AxisDataFifoCase0Test");
	end
	
	/** 待测模块 **/
	axis_data_fifo #(
		.is_async(is_async),
		.en_packet_mode(en_packet_mode),
		.ram_type(ram_type),
		.fifo_depth(fifo_depth),
		.data_width(data_width),
		.user_width(user_width),
		.simulation_delay(simulation_delay)
	)dut(
		.s_axis_aclk(clk),
		.s_axis_aresetn(rst_n),
		.m_axis_aclk(clk2),
		.m_axis_aresetn(rst_n),
		
		.s_axis_data(m_axis_if.data),
		.s_axis_keep(m_axis_if.keep),
		.s_axis_strb(m_axis_if.strb),
		.s_axis_user(m_axis_if.user),
		.s_axis_last(m_axis_if.last),
		.s_axis_valid(m_axis_if.valid),
		.s_axis_ready(m_axis_if.ready),
		
		.m_axis_data(s_axis_if.data),
		.m_axis_keep(s_axis_if.keep),
		.m_axis_strb(s_axis_if.strb),
		.m_axis_user(s_axis_if.user),
		.m_axis_last(s_axis_if.last),
		.m_axis_valid(s_axis_if.valid),
		.m_axis_ready(s_axis_if.ready)
	);
	
endmodule
