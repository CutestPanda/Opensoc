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

// 测试模式配置
`define TEST_STEP_1 // 测试步长为1

module tb_max_pool();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer feature_n_per_clk = 4; // 每个clk输入的特征点数量(2 | 4 | 8 | 16 | ...)
	localparam integer feature_data_width = 8; // 特征点位宽(必须能被8整除, 且>0)
	localparam integer max_feature_chn_n = 128; // 最大的特征图通道数
	localparam integer max_feature_w = 128; // 最大的特征图宽度
	localparam integer max_feature_h = 128; // 最大的特征图高度
	localparam en_out_reg_slice = "true"; // 是否使用输出寄存器片
	// 运行时参数配置
`ifdef TEST_STEP_1
	localparam step_type = 1'b0; // 步长类型(1'b0 -> 步长为1, 1'b1 -> 步长为2)
`else
	localparam step_type = 1'b1; // 步长类型(1'b0 -> 步长为1, 1'b1 -> 步长为2)
`endif
	localparam padding_vec = 4'b0101; // 外拓填充向量(仅当步长为1时可用, {上, 下, 左, 右})
	localparam integer feature_map_chn_n = 2; // 特征图通道数
`ifdef TEST_STEP_1
	localparam integer feature_map_w = 13; // 特征图宽度
`else
	localparam integer feature_map_w = 14; // 特征图宽度
`endif
	localparam integer feature_map_h = 4; // 特征图高度
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 常量 **/
	localparam integer s_axis_data_width = feature_n_per_clk*feature_data_width; // 从机数据位宽
	localparam integer m_axis_data_width = feature_n_per_clk*feature_data_width; // 主机数据位宽
	
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(s_axis_data_width), .user_width(0)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(m_axis_data_width), .user_width(0)) s_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(s_axis_data_width), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(s_axis_data_width), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(m_axis_data_width), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(m_axis_data_width), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("MaxPoolCase0Test");
	end
	
	/** 待测模块 **/
	reg blk_start;
	
	initial
	begin
		blk_start <= 1'b0;
		
		# (clk_p + simulation_delay);
		
		# (clk_p * 20);
		
		repeat(4)
		begin
			blk_start <= 1'b1;
			
			# clk_p;
			
			blk_start <= 1'b0;
			
			# (clk_p * 500);
		end
	end
	
	max_pool_mul_pix #(
		.feature_n_per_clk(feature_n_per_clk),
		.feature_data_width(feature_data_width),
		.max_feature_chn_n(max_feature_chn_n),
		.max_feature_w(max_feature_w),
		.max_feature_h(max_feature_h),
		.en_out_reg_slice(en_out_reg_slice),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.blk_start(blk_start),
		.blk_idle(),
		.blk_done(),
		
		.step_type(step_type),
		.padding_vec(padding_vec),
		.feature_map_chn_n(feature_map_chn_n - 1),
		.feature_map_w(feature_map_w - 1),
		.feature_map_h(feature_map_h - 1),
		
		.s_axis_data(m_axis_if.data),
		.s_axis_keep(m_axis_if.keep),
		.s_axis_last(m_axis_if.last),
		.s_axis_valid(m_axis_if.valid),
		.s_axis_ready(m_axis_if.ready),
		
		.m_axis_data(s_axis_if.data),
		.m_axis_keep(s_axis_if.keep),
		.m_axis_last(s_axis_if.last),
		.m_axis_valid(s_axis_if.valid),
		.m_axis_ready(s_axis_if.ready)
	);
	
endmodule
