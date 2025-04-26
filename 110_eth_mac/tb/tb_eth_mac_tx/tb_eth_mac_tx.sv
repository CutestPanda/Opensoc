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

module tb_eth_mac_tx();
	
	/** 配置参数 **/
	// 时钟和复位配置
	localparam real clk1_p = 10.0; // 时钟#1周期
	localparam real clk2_p = 8.0; // 时钟#2周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk1;
	reg rst_n1;
	reg clk2;
	reg rst_n2;
	
	initial
	begin
		clk1 <= 1'b1;
		
		forever
		begin
			# (clk1_p / 2) clk1 <= ~clk1;
		end
	end
	
	initial
	begin
		clk2 <= 1'b1;
		
		forever
		begin
			# (clk2_p / 2) clk2 <= ~clk2;
		end
	end
	
	initial begin
		rst_n1 <= 1'b0;
		
		# (clk1_p * 10 + simulation_delay);
		
		rst_n1 <= 1'b1;
	end
	
	initial begin
		rst_n2 <= 1'b0;
		
		# (clk2_p * 10 + simulation_delay);
		
		rst_n2 <= 1'b1;
	end
	
	/** 接口 **/
	AXIS #(.out_drive_t(simulation_delay), .data_width(16), .user_width(0)) axis_if(.clk(clk1), .rst_n(rst_n1));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), .data_width(16), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), .data_width(16), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", axis_if.monitor);
		
		// 启动testcase
		run_test("EthMacTxCase0Test");
	end
	
	/** 待测模块 **/
	// 待发送的以太网帧数据(AXIS从机)
	wire[15:0] s_axis_data;
	wire[1:0] s_axis_keep;
	wire s_axis_last;
	wire s_axis_valid;
	wire s_axis_ready;
	
	assign s_axis_data = axis_if.data;
	assign s_axis_keep = axis_if.keep;
	assign s_axis_last = axis_if.last;
	assign s_axis_valid = axis_if.valid;
	assign axis_if.ready = s_axis_ready;
	
	eth_mac_tx #(
		.SIM_DELAY(simulation_delay)
	)dut(
		.s_axis_aclk(clk1),
		.s_axis_aresetn(rst_n1),
		.eth_tx_aclk(clk2),
		.eth_tx_aresetn(rst_n2),
		
		.s_axis_data(s_axis_data),
		.s_axis_keep(s_axis_keep),
		.s_axis_last(s_axis_last),
		.s_axis_valid(s_axis_valid),
		.s_axis_ready(s_axis_ready),
		
		.eth_tx_data(),
		.eth_tx_valid()
	);
	
endmodule
