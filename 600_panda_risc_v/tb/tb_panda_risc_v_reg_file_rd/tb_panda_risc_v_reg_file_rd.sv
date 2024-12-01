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

module tb_panda_risc_v_reg_file_rd();
	
	/** 配置参数 **/
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(16), .user_width(0)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(0)) s_axis_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(16), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(16), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("PandaRiscVRegFileRdCase0Test");
	end
	
	/** 待测模块 **/
	// 复位/冲刷请求
	reg sys_reset_req; // 系统复位请求
	reg flush_req; // 冲刷请求
	// 数据相关性
	reg rs1_raw_dpc; // RS1有RAW相关性(标志)
	reg rs2_raw_dpc; // RS2有RAW相关性(标志)
	// 译码器给出的通用寄存器堆读端口#0
	wire dcd_reg_file_rd_p0_req; // 读请求
	wire dcd_reg_file_rd_p0_grant; // 读许可
	wire[31:0] dcd_reg_file_rd_p0_dout; // 读数据
	// 译码器给出的通用寄存器堆读端口#1
	wire dcd_reg_file_rd_p1_req; // 读请求
	wire dcd_reg_file_rd_p1_grant; // 读许可
	wire[31:0] dcd_reg_file_rd_p1_dout; // 读数据
	
	// RS1有RAW相关性(标志)
	initial
	begin
		rs1_raw_dpc <= 1'b0;
		
		forever
		begin
			@(posedge clk iff rst_n);
			
			randcase
				5: rs1_raw_dpc <= # simulation_delay 1'b0;
				3: rs1_raw_dpc <= # simulation_delay 1'b1;
			endcase
		end
	end
	// RS2有RAW相关性(标志)
	initial
	begin
		rs2_raw_dpc <= 1'b0;
		
		forever
		begin
			@(posedge clk iff rst_n);
			
			randcase
				5: rs2_raw_dpc <= # simulation_delay 1'b0;
				3: rs2_raw_dpc <= # simulation_delay 1'b1;
			endcase
		end
	end
	
	// 软件复位/冲刷请求
	initial
	begin
		sys_reset_req <= 1'b0;
		flush_req <= 1'b0;
		
		# simulation_delay;
		
		# (clk_p * 40);
		
		flush_req <= 1'b1;
		
		# clk_p;
		
		flush_req <= 1'b0;
	end
	
	panda_risc_v_reg_file_rd #(
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.resetn(rst_n),
		
		.sys_reset_req(sys_reset_req),
		.flush_req(flush_req),
		
		.raw_dpc_check_rs1_id(),
		.rs1_raw_dpc(rs1_raw_dpc),
		.raw_dpc_check_rs2_id(),
		.rs2_raw_dpc(rs2_raw_dpc),
		
		.s_reg_file_rd_req_rs1_id(m_axis_if.data[4:0]),
		.s_reg_file_rd_req_rs2_id(m_axis_if.data[9:5]),
		.s_reg_file_rd_req_rs1_vld(m_axis_if.data[10]),
		.s_reg_file_rd_req_rs2_vld(m_axis_if.data[11]),
		.s_reg_file_rd_req_valid(m_axis_if.valid),
		.s_reg_file_rd_req_ready(m_axis_if.ready),
		
		.m_reg_file_rd_res_rs1_v(s_axis_if.data[31:0]),
		.m_reg_file_rd_res_rs2_v(s_axis_if.data[63:32]),
		.m_reg_file_rd_res_valid(s_axis_if.valid),
		.m_reg_file_rd_res_ready(s_axis_if.ready),
		
		.dcd_reg_file_rd_p0_req(dcd_reg_file_rd_p0_req),
		.dcd_reg_file_rd_p0_addr(),
		.dcd_reg_file_rd_p0_grant(dcd_reg_file_rd_p0_grant),
		.dcd_reg_file_rd_p0_dout(dcd_reg_file_rd_p0_dout),
		
		.dcd_reg_file_rd_p1_req(dcd_reg_file_rd_p1_req),
		.dcd_reg_file_rd_p1_addr(),
		.dcd_reg_file_rd_p1_grant(dcd_reg_file_rd_p1_grant),
		.dcd_reg_file_rd_p1_dout(dcd_reg_file_rd_p1_dout)
	);
	
	/** 仿真模型 **/
	req_grant_model #(
		.payload_width(32),
		.simulation_delay(simulation_delay)
	)req_grant_model_u0(
		.clk(clk),
		.rst_n(rst_n),
		
		.req(dcd_reg_file_rd_p0_req),
		.grant(dcd_reg_file_rd_p0_grant),
		.payload(dcd_reg_file_rd_p0_dout)
	);
	
	req_grant_model #(
		.payload_width(32),
		.simulation_delay(simulation_delay)
	)req_grant_model_u1(
		.clk(clk),
		.rst_n(rst_n),
		
		.req(dcd_reg_file_rd_p1_req),
		.grant(dcd_reg_file_rd_p1_grant),
		.payload(dcd_reg_file_rd_p1_dout)
	);
	
endmodule
