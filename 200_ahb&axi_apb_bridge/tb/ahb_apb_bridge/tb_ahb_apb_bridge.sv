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

module tb_ahb_apb_bridge();
	
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
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) apb_if_0(.clk(clk), .rst_n(rst_n));
	APB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) apb_if_1(.clk(clk), .rst_n(rst_n));
	AHB #(.out_drive_t(simulation_delay), .slave_n(1), .addr_width(32), .data_width(32), 
		.burst_width(3), .prot_width(4), .master_width(1)) ahb_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt1.drv", "apb_if", apb_if_0.slave);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "apb_if", apb_if_0.monitor);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "apb_if", apb_if_1.slave);
		uvm_config_db #(virtual APB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "apb_if", apb_if_1.monitor);
		uvm_config_db #(virtual AHB #(.out_drive_t(simulation_delay), 
			.slave_n(1), .addr_width(32), .data_width(32), 
			.burst_width(3), .prot_width(4), .master_width(1)).master)::set(null, 
			"uvm_test_top.env.agt3.drv", "ahb_if", ahb_if.master);
		uvm_config_db #(virtual AHB #(.out_drive_t(simulation_delay), 
			.slave_n(1), .addr_width(32), .data_width(32), 
			.burst_width(3), .prot_width(4), .master_width(1)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "ahb_if", ahb_if.monitor);
		
		// 启动testcase
		run_test("AHBAPBBridgeCase0Test");
	end
	
	/** 待测模块 **/
	assign ahb_if.hsel = 1'b1;
	assign ahb_if.muxsel = 0;
	
	ahb_apb_bridge_wrapper #(
		.apb_slave_n(2),
		.apb_s0_baseaddr(0),
		.apb_s0_range(4096),
		.apb_s1_baseaddr(4096),
		.apb_s1_range(4096),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_ahb_haddr(ahb_if.haddr),
		.s_ahb_hburst(ahb_if.hburst),
		.s_ahb_hprot(ahb_if.hprot),
		.s_ahb_hrdata(ahb_if.hrdata_out[0]),
		.s_ahb_hready_in(ahb_if.hready),
		.s_ahb_hready_out(ahb_if.hready_out[0]),
		.s_ahb_hresp(ahb_if.hresp_out[0]),
		.s_ahb_hsize(ahb_if.hsize),
		.s_ahb_htrans(ahb_if.htrans),
		.s_ahb_hwdata(ahb_if.hwdata),
		.s_ahb_hwstrb(ahb_if.hwstrb),
		.s_ahb_hwrite(ahb_if.hwrite),
		.s_ahb_hsel(ahb_if.hsel),
		
		.m0_apb_paddr(apb_if_0.paddr),
		.m0_apb_penable(apb_if_0.penable),
		.m0_apb_pwrite(apb_if_0.pwrite),
		.m0_apb_pprot(apb_if_0.pprot),
		.m0_apb_psel(apb_if_0.pselx),
		.m0_apb_pstrb(apb_if_0.pstrb),
		.m0_apb_pwdata(apb_if_0.pwdata),
		.m0_apb_pready(apb_if_0.pready),
		.m0_apb_pslverr(apb_if_0.pslverr),
		.m0_apb_prdata(apb_if_0.prdata),
		
		.m1_apb_paddr(apb_if_1.paddr),
		.m1_apb_penable(apb_if_1.penable),
		.m1_apb_pwrite(apb_if_1.pwrite),
		.m1_apb_pprot(apb_if_1.pprot),
		.m1_apb_psel(apb_if_1.pselx),
		.m1_apb_pstrb(apb_if_1.pstrb),
		.m1_apb_pwdata(apb_if_1.pwdata),
		.m1_apb_pready(apb_if_1.pready),
		.m1_apb_pslverr(apb_if_1.pslverr),
		.m1_apb_prdata(apb_if_1.prdata)
	);
	
endmodule
