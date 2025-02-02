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

module tb_axi_fsmc();
	
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
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), 
		.data_width(32), .bresp_width(2), .rresp_width(2)) axi_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), 
			.data_width(32), .bresp_width(2), .rresp_width(2)).master)::set(null, 
			"uvm_test_top.env.agt.drv", "axi_if", axi_if.master);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), 
			.data_width(32), .bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt.mon", "axi_if", axi_if.monitor);
		
		// 启动testcase
		run_test("AXIFsmcCase0Test");
	end
	
	/** 待测模块 **/
	wire[15:0] fsmc_data_i;
	wire[15:0] fsmc_data_o;
	wire[15:0] fsmc_data_t;
	
	tri1[15:0] fsmc_data_io;
	
	genvar fsmc_data_io_id;
	generate
		for(fsmc_data_io_id = 0;fsmc_data_io_id < 16;fsmc_data_io_id = fsmc_data_io_id + 1)
		begin
			assign fsmc_data_io[fsmc_data_io_id] = fsmc_data_t[fsmc_data_io_id] ? 1'bz:fsmc_data_o[fsmc_data_io_id];
			assign fsmc_data_i[fsmc_data_io_id] = fsmc_data_io[fsmc_data_io_id];
		end
	endgenerate
	
	assign axi_if.rlast = 1'b1;
	
	axi_fsmc #(
		.simulation_delay(simulation_delay)
	)dut(
		.s_axi_clk(clk),
		.s_axi_resetn(rst_n),
		
		.s_axi_araddr(axi_if.araddr),
		.s_axi_arsize(axi_if.arsize),
		.s_axi_arvalid(axi_if.arvalid),
		.s_axi_arready(axi_if.arready),
		.s_axi_awaddr(axi_if.awaddr),
		.s_axi_awsize(axi_if.awsize),
		.s_axi_awvalid(axi_if.awvalid),
		.s_axi_awready(axi_if.awready),
		.s_axi_bresp(axi_if.bresp),
		.s_axi_bvalid(axi_if.bvalid),
		.s_axi_bready(axi_if.bready),
		.s_axi_rdata(axi_if.rdata),
		.s_axi_rresp(axi_if.rresp),
		.s_axi_rvalid(axi_if.rvalid),
		.s_axi_rready(axi_if.rready),
		.s_axi_wdata(axi_if.wdata),
		.s_axi_wstrb(axi_if.wstrb),
		.s_axi_wvalid(axi_if.wvalid),
		.s_axi_wready(axi_if.wready),
		
		.fsmc_nbl(),
		.fsmc_addr(),
		.fsmc_nwe(),
		.fsmc_noe(),
		.fsmc_ne(),
		.fsmc_data_i(fsmc_data_i),
		.fsmc_data_o(fsmc_data_o),
		.fsmc_data_t(fsmc_data_t)
	);
	
endmodule
