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

module tb_axis_conv_cal_3x3();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer mul_add_width = 16; // 乘加位宽(8 | 16)
	localparam integer quaz_acc = 10; // 量化精度(必须在范围[1, mul_add_width-1]内)
	localparam integer add_3_input_ext_int_width = 4; // 三输入加法器额外考虑的整数位数(必须<=(mul_add_width-quaz_acc))
	localparam integer add_3_input_ext_frac_width = 4; // 三输入加法器额外考虑的小数位数(必须<=quaz_acc)
	localparam integer in_feature_map_buffer_rd_prl_n = 4; // 读输入特征图缓存的并行个数(1 | 2 | 4 | 8 | 16)
	localparam integer kernal_pars_buffer_n = 8; // 卷积核参数缓存个数
	localparam integer kernal_prl_n = 4; // 多通道卷积核的并行个数(1 | 2 | 4 | 8 | 16)
	localparam integer max_feature_map_w = 512; // 最大的输入特征图宽度
	localparam integer max_feature_map_h = 512; // 最大的输入特征图高度
	localparam integer max_feature_map_chn_n = 512; // 最大的输入特征图通道数
	localparam integer max_kernal_n = 512; // 最大的卷积核个数
	localparam integer out_buffer_n = 8; // 多通道卷积结果缓存个数
	// 运行时参数配置
	localparam bit kernal_type = 1'b1; // 卷积核类型(1'b0 -> 1x1, 1'b1 -> 3x3)
	localparam bit[3:0] padding_en = 4'b1111; // 外拓填充使能(仅当卷积核类型为3x3时可用, {上, 下, 左, 右})
	localparam bit[15:0] feature_map_w = 16'd2; // 输入特征图宽度 - 1
	localparam bit[15:0] feature_map_h = 16'd2; // 输入特征图高度 - 1
	localparam bit[15:0] feature_map_chn_n = 16'd2; // 输入特征图通道数 - 1
	localparam bit[15:0] kernal_n = 16'd4; // 卷积核个数 - 1
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)) m0_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(1)) m1_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(mul_add_width*2), .user_width(16)) s_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m0_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(mul_add_width*3*in_feature_map_buffer_rd_prl_n), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m0_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(1)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", m1_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", m1_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(mul_add_width*2), .user_width(16)).slave)::set(null, 
			"uvm_test_top.env.agt3.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(mul_add_width*2), .user_width(16)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("AxisConvCalCase1Test");
	end
	
	/** 待测模块 **/
	// 卷积核参数缓存控制(fifo读端口)
	wire kernal_pars_buf_fifo_ren;
	wire kernal_pars_buf_fifo_empty_n;
	// 卷积核参数缓存MEM读端口
	wire kernal_pars_buf_mem_buf_ren_s0;
	wire kernal_pars_buf_mem_buf_ren_s1;
	wire[15:0] kernal_pars_buf_mem_buf_raddr; // 每个读地址对应1个单通道卷积核
	wire[kernal_prl_n*mul_add_width*9-1:0] kernal_pars_buf_mem_buf_dout; // {核#(m-1), ..., 核#1, 核#0}
	// 卷积核通道累加中间结果输出(AXIS主机)
	// {核#(m-1)结果, ..., 核#1结果, 核#0结果}
	// 每个中间结果仅低(add_3_input_ext_int_width+mul_add_width+add_3_input_ext_frac_width)位有效
	wire[mul_add_width*2*kernal_prl_n-1:0] m_axis_res_data;
	wire m_axis_res_last; // 表示行尾
	wire m_axis_res_user; // 表示当前行最后1组结果
	wire m_axis_res_valid;
	wire m_axis_res_ready;
	// 计算参数
	wire[15:0] o_ft_map_h; // 输出特征图高度 - 1
	
	axis_conv_cal_3x3 #(
		.mul_add_width(mul_add_width),
		.quaz_acc(quaz_acc),
		.add_3_input_ext_int_width(add_3_input_ext_int_width),
		.add_3_input_ext_frac_width(add_3_input_ext_frac_width),
		.in_feature_map_buffer_rd_prl_n(in_feature_map_buffer_rd_prl_n),
		.kernal_prl_n(kernal_prl_n),
		.max_feature_map_h(max_feature_map_h),
		.max_feature_map_chn_n(max_feature_map_chn_n),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)axis_conv_cal_3x3_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.rst_kernal_buf(1'b0),
		
		.en_conv_cal(1'b1),
		
		.kernal_type(kernal_type),
		.padding_en(padding_en),
		.feature_map_h(feature_map_h),
		.feature_map_chn_n(feature_map_chn_n),
		.kernal_n(kernal_n),
		
		.o_ft_map_h(o_ft_map_h),
		
		.s_axis_feature_map_data(m0_axis_if.data),
		.s_axis_feature_map_last(m0_axis_if.last),
		.s_axis_feature_map_valid(m0_axis_if.valid),
		.s_axis_feature_map_ready(m0_axis_if.ready),
		
		.kernal_pars_buf_fifo_ren(kernal_pars_buf_fifo_ren),
		.kernal_pars_buf_fifo_empty_n(kernal_pars_buf_fifo_empty_n),
		
		.kernal_pars_buf_mem_buf_ren_s0(kernal_pars_buf_mem_buf_ren_s0),
		.kernal_pars_buf_mem_buf_ren_s1(kernal_pars_buf_mem_buf_ren_s1),
		.kernal_pars_buf_mem_buf_raddr(kernal_pars_buf_mem_buf_raddr),
		.kernal_pars_buf_mem_buf_dout(kernal_pars_buf_mem_buf_dout),
		
		.m_axis_res_data(m_axis_res_data),
		.m_axis_res_last(m_axis_res_last),
		.m_axis_res_user(m_axis_res_user),
		.m_axis_res_valid(m_axis_res_valid),
		.m_axis_res_ready(m_axis_res_ready)
	);
	
	axis_conv_out_buffer #(
		.ft_ext_width(mul_add_width*2),
		.ft_vld_width(mul_add_width+add_3_input_ext_int_width+add_3_input_ext_frac_width),
		.kernal_prl_n(kernal_prl_n),
		.out_buffer_n(out_buffer_n),
		.max_feature_map_w(max_feature_map_w),
		.max_feature_map_h(max_feature_map_h),
		.max_kernal_n(max_kernal_n),
		.simulation_delay(simulation_delay)
	)axis_conv_out_buffer_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.en_conv_cal(1'b1),
		
		.kernal_type(kernal_type),
		.padding_en(padding_en[1:0]),
		.i_ft_map_w(feature_map_w),
		.o_ft_map_h(o_ft_map_h),
		.kernal_n(kernal_n),
		
		.s_axis_mid_res_data(m_axis_res_data),
		.s_axis_mid_res_last(m_axis_res_last),
		.s_axis_mid_res_user(m_axis_res_user),
		.s_axis_mid_res_valid(m_axis_res_valid),
		.s_axis_mid_res_ready(m_axis_res_ready),
		
		.m_axis_ft_out_data(s_axis_if.data),
		.m_axis_ft_out_user(s_axis_if.user),
		.m_axis_ft_out_last(s_axis_if.last),
		.m_axis_ft_out_valid(s_axis_if.valid),
		.m_axis_ft_out_ready(s_axis_if.ready)
	);
	
	axis_kernal_params_buffer #(
		.kernal_pars_buffer_n(kernal_pars_buffer_n),
		.kernal_prl_n(kernal_prl_n),
		.kernal_param_data_width(mul_add_width),
		.max_feature_map_chn_n(max_feature_map_chn_n),
		.simulation_delay(simulation_delay)
	)axis_kernal_params_buffer_u(
		.clk(clk),
		.rst_n(rst_n),
		
		.kernal_type(kernal_type),
		
		.s_axis_kernal_pars_data(m1_axis_if.data),
		.s_axis_kernal_pars_keep(m1_axis_if.keep),
		.s_axis_kernal_pars_last(m1_axis_if.last),
		.s_axis_kernal_pars_user(m1_axis_if.user),
		.s_axis_kernal_pars_valid(m1_axis_if.valid),
		.s_axis_kernal_pars_ready(m1_axis_if.ready),
		
		.kernal_pars_buf_fifo_ren(kernal_pars_buf_fifo_ren),
		.kernal_pars_buf_fifo_empty_n(kernal_pars_buf_fifo_empty_n),
		
		.kernal_pars_buf_mem_buf_ren_s0(kernal_pars_buf_mem_buf_ren_s0),
		.kernal_pars_buf_mem_buf_ren_s1(kernal_pars_buf_mem_buf_ren_s1),
		.kernal_pars_buf_mem_buf_raddr(kernal_pars_buf_mem_buf_raddr),
		.kernal_pars_buf_mem_buf_dout(kernal_pars_buf_mem_buf_dout)
	);
	
endmodule
