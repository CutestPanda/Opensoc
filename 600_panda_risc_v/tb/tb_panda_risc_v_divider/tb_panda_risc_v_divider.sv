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

module tb_panda_risc_v_divider();
	
	/** 配置参数 **/
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 常量 **/
	localparam integer s_axis_data_width = 72; // 从机数据位宽
	localparam integer m_axis_data_width = 32; // 主机数据位宽
	
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
		run_test("DivCase0Test");
	end
	
	/** 待测模块 **/
	// 除法器执行请求
	wire[32:0] s_div_req_op_a; // 操作数A(被除数)
	wire[32:0] s_div_req_op_b; // 操作数B(除数)
	wire s_div_req_rem_sel; // 除法/求余选择(1'b0 -> 除法, 1'b1 -> 求余)
	wire s_div_req_valid;
	wire s_div_req_ready;
	// 除法器计算结果
	wire[31:0] m_div_res_data; // 计算结果
	wire m_div_res_valid;
	wire m_div_res_ready;
	
	assign {s_div_req_rem_sel, s_div_req_op_b, s_div_req_op_a} = m_axis_if.data[66:0];
	assign s_div_req_valid = m_axis_if.valid;
	assign m_axis_if.ready = s_div_req_ready;
	
	assign s_axis_if.data = m_div_res_data;
	assign s_axis_if.valid = m_div_res_valid;
	assign m_div_res_ready = s_axis_if.ready;
	
	panda_risc_v_divider #(
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.resetn(rst_n),
		
		.s_div_req_op_a(s_div_req_op_a),
		.s_div_req_op_b(s_div_req_op_b),
		.s_div_req_rem_sel(s_div_req_rem_sel),
		.s_div_req_valid(s_div_req_valid),
		.s_div_req_ready(s_div_req_ready),
		
		.m_div_res_data(m_div_res_data),
		.m_div_res_valid(m_div_res_valid),
		.m_div_res_ready(m_div_res_ready)
	);
	
endmodule
