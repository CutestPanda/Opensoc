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

module tb_panda_risc_v_ibus_ctrler();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer imem_access_timeout_th = 16; // 指令总线访问超时周期数(必须>=1)
	localparam integer inst_addr_alignment_width = 32; // 指令地址对齐位宽(16 | 32)
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(32), .user_width(33)) m_axis_if(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_icb_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(32), .user_width(33)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(32), .user_width(33)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "icb_if", s_icb_if.slave);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "icb_if", s_icb_if.monitor);
		
		// 启动testcase
		run_test("IBusCtrlerCase0Test");
	end
	
	/** 待测模块 **/
	panda_risc_v_ibus_ctrler #(
		.imem_access_timeout_th(imem_access_timeout_th),
		.inst_addr_alignment_width(inst_addr_alignment_width),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.resetn(rst_n),
		
		.imem_access_req_addr(m_axis_if.user[32:1]),
		.imem_access_req_read(m_axis_if.user[0]),
		.imem_access_req_wdata(m_axis_if.data),
		.imem_access_req_wmask(m_axis_if.keep),
		.imem_access_req_valid(m_axis_if.valid),
		.imem_access_req_ready(m_axis_if.ready),
		
		.imem_access_resp_rdata(),
		.imem_access_resp_err(),
		.imem_access_resp_valid(),
		
		.m_icb_cmd_addr(s_icb_if.cmd_addr),
		.m_icb_cmd_read(s_icb_if.cmd_read),
		.m_icb_cmd_wdata(s_icb_if.cmd_wdata),
		.m_icb_cmd_wmask(s_icb_if.cmd_wmask),
		.m_icb_cmd_valid(s_icb_if.cmd_valid),
		.m_icb_cmd_ready(s_icb_if.cmd_ready),
		
		.m_icb_rsp_rdata(s_icb_if.rsp_rdata),
		.m_icb_rsp_err(s_icb_if.rsp_err),
		.m_icb_rsp_valid(s_icb_if.rsp_valid),
		.m_icb_rsp_ready(s_icb_if.rsp_ready)
	);
	
endmodule
