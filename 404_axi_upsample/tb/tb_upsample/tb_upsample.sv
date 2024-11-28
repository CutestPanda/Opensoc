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

module tb_upsample();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer feature_n_per_clk = 4; // 每个clk输入的特征点数量(1 | 2 | 4 | 8 | 16 | ...)
	localparam integer feature_data_width = 8; // 特征点位宽(必须能被8整除, 且>0)
	localparam integer max_feature_w = 128; // 最大的特征图宽度
	localparam integer max_feature_h = 128; // 最大的输入特征图高度
	localparam integer max_feature_chn_n = 512; // 最大的输入特征图通道数
	// 运行时参数配置
	localparam integer feature_w = 8 - 1; // 输入特征图宽度 - 1
	localparam integer feature_h = 4 - 1; // 输入特征图高度 - 1
	localparam integer feature_chn_n = 2 - 1; // 输入特征图通道数 - 1
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 常量 **/
	localparam integer s_axis_data_width = feature_n_per_clk*feature_data_width; // 从机数据位宽
	localparam integer m_axis_data_width = feature_n_per_clk*feature_data_width*2; // 主机数据位宽
	
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(s_axis_data_width), .user_width(3)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(m_axis_data_width), .user_width(3)) s_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(s_axis_data_width), .user_width(3)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(s_axis_data_width), .user_width(3)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(m_axis_data_width), .user_width(3)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(m_axis_data_width), .user_width(3)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("UpsampleCase0Test");
	end
	
	/** 待测模块 **/
	upsample #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_w(max_feature_w),
		.max_feature_h(max_feature_h),
		.max_feature_chn_n(max_feature_chn_n),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.feature_w(feature_w),
		.feature_h(feature_h),
		.feature_chn_n(feature_chn_n),
		
		.s_axis_data(m_axis_if.data),
		.s_axis_valid(m_axis_if.valid),
		.s_axis_ready(m_axis_if.ready),
		
		.m_axis_data(s_axis_if.data),
		.m_axis_user(s_axis_if.user),
		.m_axis_last(s_axis_if.last),
		.m_axis_valid(s_axis_if.valid),
		.m_axis_ready(s_axis_if.ready)
	);
	
endmodule
