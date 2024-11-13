`timescale 1ns / 1ps

`include "uvm_macros.svh"

import uvm_pkg::*;

`include "test_cases.sv"
`include "vsqr.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_axis_linear_act_cal();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer xyz_quaz_acc = 10; // x/y/z变量量化精度(必须在范围[1, cal_width-1]内)
	localparam integer ab_quaz_acc = 12; // a/b系数量化精度(必须在范围[1, cal_width-1]内)
	localparam integer c_quaz_acc = 14; // c系数量化精度(必须在范围[1, cal_width-1]内)
	localparam integer cal_width = 16; // 计算位宽(对于x/y/z和a/b/c来说, 可选8 | 16)
	localparam integer xyz_ext_int_width = 4; // x/y/z额外考虑的整数位数(必须<=(cal_width-xyz_quaz_acc))
	localparam integer xyz_ext_frac_width = 4; // x/y/z额外考虑的小数位数(必须<=xyz_quaz_acc)
	localparam integer max_kernal_n = 512; // 最大的卷积核个数
	// 运行时参数配置
	localparam bit[cal_width-1:0] act_rate_c = 2 ** (c_quaz_acc - 1); // Relu激活系数c
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(cal_width*2), .user_width(16)) m0_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(cal_width*2), .user_width(0)) s_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(2)) m1_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(cal_width*2), .user_width(16)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m0_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(cal_width*2), .user_width(16)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m0_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(cal_width*2), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(cal_width*2), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(2)).master)::set(null, 
			"uvm_test_top.env.agt3.drv", "axis_if", m1_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axis_if", m1_axis_if.monitor);
		
		// 启动testcase
		run_test("AXISLnActCalCase0Test");
	end
	
	/** 待测模块 **/
	// 线性参数缓存区加载完成标志
	wire linear_pars_buf_load_completed;
	// 线性参数获取(MEM读)
	wire linear_pars_buffer_ren_s0;
	wire linear_pars_buffer_ren_s1;
	wire[15:0] linear_pars_buffer_raddr;
	wire[cal_width-1:0] linear_pars_buffer_dout_a;
	wire[cal_width-1:0] linear_pars_buffer_dout_b;
	
	axis_linear_act_cal #(
		.xyz_quaz_acc(xyz_quaz_acc),
		.ab_quaz_acc(ab_quaz_acc),
		.c_quaz_acc(c_quaz_acc),
		.cal_width(cal_width),
		.xyz_ext_int_width(xyz_ext_int_width),
		.xyz_ext_frac_width(xyz_ext_frac_width),
		.simulation_delay(simulation_delay)
	)axis_linear_act_cal_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.act_rate_c(act_rate_c),
		
		.s_axis_conv_res_data(m0_axis_if.data),
		.s_axis_conv_res_user(m0_axis_if.user),
		.s_axis_conv_res_last(m0_axis_if.last),
		.s_axis_conv_res_valid(m0_axis_if.valid),
		.s_axis_conv_res_ready(m0_axis_if.ready),
		
		.m_axis_linear_act_res_data(s_axis_if.data),
		.m_axis_linear_act_res_last(s_axis_if.last),
		.m_axis_linear_act_res_valid(s_axis_if.valid),
		.m_axis_linear_act_res_ready(s_axis_if.ready),
		
		.linear_pars_buf_load_completed(linear_pars_buf_load_completed),
		
		.linear_pars_buffer_ren_s0(linear_pars_buffer_ren_s0),
		.linear_pars_buffer_ren_s1(linear_pars_buffer_ren_s1),
		.linear_pars_buffer_raddr(linear_pars_buffer_raddr),
		.linear_pars_buffer_dout_a(linear_pars_buffer_dout_a),
		.linear_pars_buffer_dout_b(linear_pars_buffer_dout_b)
	);
	
	axis_linear_params_buffer #(
		.kernal_param_data_width(cal_width),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)axis_linear_params_buffer_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.rst_linear_pars_buf(1'b0),
		.linear_pars_buf_load_completed(linear_pars_buf_load_completed),
		
		.s_axis_linear_pars_data(m1_axis_if.data),
		.s_axis_linear_pars_keep(m1_axis_if.keep),
		.s_axis_linear_pars_last(m1_axis_if.last),
		.s_axis_linear_pars_user(m1_axis_if.user),
		.s_axis_linear_pars_valid(m1_axis_if.valid),
		.s_axis_linear_pars_ready(m1_axis_if.ready),
		
		.linear_pars_buffer_ren_s0(linear_pars_buffer_ren_s0),
		.linear_pars_buffer_ren_s1(linear_pars_buffer_ren_s1),
		.linear_pars_buffer_raddr(linear_pars_buffer_raddr),
		.linear_pars_buffer_dout_a(linear_pars_buffer_dout_a),
		.linear_pars_buffer_dout_b(linear_pars_buffer_dout_b)
	);
	
endmodule
