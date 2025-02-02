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

module tb_axi_sdram();

	/** 配置参数 **/
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 0.0; // 仿真延时
	
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
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), .bresp_width(2), .rresp_width(2))
		axi0_if_inst(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), .bresp_width(2), .rresp_width(2))
		axi1_if_inst(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), .bresp_width(2), .rresp_width(2))
		axi2_if_inst(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt.drv", "axi_if", axi0_if_inst.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt.mon", "axi_if", axi0_if_inst.monitor);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "axi_if", axi1_if_inst.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axi_if", axi1_if_inst.monitor);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt3.drv", "axi_if", axi2_if_inst.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axi_if", axi2_if_inst.monitor);
		uvm_config_db #(int unsigned)::set(null, "uvm_test_top.env.agt.drv", "max_trans_buffer_n", 10);
		uvm_config_db #(int unsigned)::set(null, "uvm_test_top.env.agt2.drv", "max_trans_buffer_n", 10);
		uvm_config_db #(int unsigned)::set(null, "uvm_test_top.env.agt3.drv", "max_trans_buffer_n", 10);
		
		// 启动testcase
		run_test("AXISdramCase0Test");
	end
	
	/** 待测模块 **/
	top_axi_sdram dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s0_axi_if(axi0_if_inst),
		.s1_axi_if(axi1_if_inst),
		.s2_axi_if(axi2_if_inst)
	);

endmodule
