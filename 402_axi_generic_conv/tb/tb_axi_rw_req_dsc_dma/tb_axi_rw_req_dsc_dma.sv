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

module tb_axi_rw_req_dsc_dma();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer max_req_n = 1024; // 最大的读/写请求个数
	localparam integer axi_rchn_max_burst_len = 8; // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	localparam integer rw_req_dsc_buffer_depth = 512; // 读/写请求描述子buffer深度(256 | 512 | 1024 | ...)
	// 仿真模型配置
	localparam integer memory_map_depth = 1024;
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(0)) s_axis_if(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(64), .bresp_width(2), .rresp_width(2))
		axi_if_inst(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("AxiRdReqDscDmaCase0Test");
	end
	
	/** AXI存储映射片(仿真模型) **/
	s_axi_memory_map_model #(
		.out_drive_t(simulation_delay),
		.addr_width(32),
		.data_width(64),
		.bresp_width(2),
		.rresp_width(2),
		.memory_map_depth(memory_map_depth)
	)s_axi_memory_map_model_u(
		.s_axi_if(axi_if_inst.slave)
	);
	
	initial
	begin
		for(int i = 0;i < memory_map_depth/8-1;i++)
		begin
			s_axi_memory_map_model_u.memory_map[i] = i;
		end
	end
	
	/** 待测模块 **/
	reg blk_start;
	reg[31:0] req_buf_baseaddr; // 读请求缓存区首地址
	reg[31:0] req_n; // 读请求个数 - 1
	
	initial
	begin
		blk_start <= 1'b0;
		
		# (clk_p * 10 + simulation_delay);
		
		req_buf_baseaddr <= 32'd64;
		req_n <= 32'd15 - 32'd1;
		
		blk_start <= 1'b1;
		
		# clk_p;
		
		blk_start <= 1'b0;
		
		# (clk_p * 1000);
		
		req_buf_baseaddr <= 32'd128;
		req_n <= 32'd5 - 32'd1;
		
		blk_start <= 1'b1;
		
		# clk_p;
		
		blk_start <= 1'b0;
		
		# (clk_p * 1000);
		
		req_buf_baseaddr <= 32'd256;
		req_n <= 32'd24 - 32'd1;
		
		blk_start <= 1'b1;
		
		# clk_p;
		
		blk_start <= 1'b0;
	end
	
	assign axi_if_inst.awvalid = 1'b0;
	assign axi_if_inst.wvalid = 1'b0;
	assign axi_if_inst.bready = 1'b1;
	
	axi_rw_req_dsc_dma #(
		.max_req_n(max_req_n),
		.axi_rchn_max_burst_len(axi_rchn_max_burst_len),
		.rw_req_dsc_buffer_depth(rw_req_dsc_buffer_depth),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.req_buf_baseaddr(req_buf_baseaddr),
		.req_n(req_n),
		
		.blk_start(blk_start),
		.blk_idle(),
		.blk_done(),
		
		.m_axis_dsc_data(s_axis_if.data),
		.m_axis_dsc_valid(s_axis_if.valid),
		.m_axis_dsc_ready(s_axis_if.ready),
		
		.m_axi_araddr(axi_if_inst.araddr),
		.m_axi_arburst(axi_if_inst.arburst),
		.m_axi_arlen(axi_if_inst.arlen),
		.m_axi_arsize(axi_if_inst.arsize),
		.m_axi_arvalid(axi_if_inst.arvalid),
		.m_axi_arready(axi_if_inst.arready),
		
		.m_axi_rdata(axi_if_inst.rdata),
		.m_axi_rresp(axi_if_inst.rresp),
		.m_axi_rlast(axi_if_inst.rlast),
		.m_axi_rvalid(axi_if_inst.rvalid),
		.m_axi_rready(axi_if_inst.rready)
	);
	
endmodule
