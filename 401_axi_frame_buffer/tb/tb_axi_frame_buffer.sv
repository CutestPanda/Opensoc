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

module tb_axi_frame_buffer();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam en_4KB_boundary_protect = "false"; // 是否启用4KB边界保护
    localparam en_reg_slice_at_m_axi_ar = "true"; // 是否在AXI主机的AR通道插入寄存器片
    localparam en_reg_slice_at_m_axi_aw = "true"; // 是否在AXI主机的AW通道插入寄存器片
    localparam en_reg_slice_at_m_axi_r = "true"; // 是否在AXI主机的R通道插入寄存器片
    localparam en_reg_slice_at_m_axi_w = "true"; // 是否在AXI主机的W通道插入寄存器片
    localparam en_reg_slice_at_m_axi_b = "true"; // 是否在AXI主机的B通道插入寄存器片
    localparam integer frame_n = 4; // 缓冲区帧个数(必须在范围[3, 16]内)
    localparam integer frame_buffer_baseaddr = 4000; // 帧缓冲区首地址(必须能被4整除)
    localparam integer img_n = 20; // 图像大小(以像素个数计)
    localparam integer pix_data_width = 24; // 像素位宽(必须能被8整除)
    localparam integer pix_per_clk_for_wt = 1; // 每clk写的像素个数
	localparam integer pix_per_clk_for_rd = 1; // 每clk读的像素个数
    localparam integer axi_raddr_outstanding = 2; // AXI读地址缓冲深度(1 | 2 | 4 | 8 | 16)
    localparam integer axi_rchn_max_burst_len = 4; // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    localparam integer axi_waddr_outstanding = 2; // AXI写地址缓冲深度(1 | 2 | 4 | 8 | 16)
    localparam integer axi_wchn_max_burst_len = 4; // AXI写通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
    localparam integer axi_wchn_data_buffer_depth = 512; // AXI写通道数据buffer深度(0 | 16 | 32 | 64 | ..., 设为0时表示不使用)
    localparam integer axi_rchn_data_buffer_depth = 512; // AXI读通道数据buffer深度(0 | 16 | 32 | 64 | ..., 设为0时表示不使用)
	// 仿真模型配置
	localparam integer memory_map_depth = 1024 * 64; // 存储映射深度(以字节计)
	// 时钟和复位配置
	localparam real clk_p = 10.0; // 时钟周期
	localparam real simulation_delay = 1.0; // 仿真延时
	
	/** 常量 **/
	localparam integer s_axis_data_width = pix_data_width*pix_per_clk_for_wt; // 从机数据位宽
	localparam integer m_axis_data_width = pix_data_width*pix_per_clk_for_rd; // 主机数据位宽
	
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(m_axis_data_width), .user_width(8)) s_axis_if(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
		.bresp_width(2), .rresp_width(2)) axi_if(.clk(clk), .rst_n(rst_n));
	
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
			.data_width(m_axis_data_width), .user_width(8)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(m_axis_data_width), .user_width(8)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		uvm_config_db #(virtual AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32), 
			.bresp_width(2), .rresp_width(2)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axi_if", axi_if.monitor);
		
		// 启动testcase
		run_test("AXIFrameBufferCase0Test");
	end
	
	/** 待测模块 **/
	axi_frame_buffer #(
		.en_4KB_boundary_protect(en_4KB_boundary_protect),
		.en_reg_slice_at_m_axi_ar(en_reg_slice_at_m_axi_ar),
		.en_reg_slice_at_m_axi_aw(en_reg_slice_at_m_axi_aw),
		.en_reg_slice_at_m_axi_r(en_reg_slice_at_m_axi_r),
		.en_reg_slice_at_m_axi_w(en_reg_slice_at_m_axi_w),
		.en_reg_slice_at_m_axi_b(en_reg_slice_at_m_axi_b),
		.frame_n(frame_n),
		.frame_buffer_baseaddr(frame_buffer_baseaddr),
		.img_n(img_n),
		.pix_data_width(pix_data_width),
		.pix_per_clk_for_wt(pix_per_clk_for_wt),
		.pix_per_clk_for_rd(pix_per_clk_for_rd),
		.axi_raddr_outstanding(axi_raddr_outstanding),
		.axi_rchn_max_burst_len(axi_rchn_max_burst_len),
		.axi_waddr_outstanding(axi_waddr_outstanding),
		.axi_wchn_max_burst_len(axi_wchn_max_burst_len),
		.axi_wchn_data_buffer_depth(axi_wchn_data_buffer_depth),
		.axi_rchn_data_buffer_depth(axi_rchn_data_buffer_depth),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.disp_suspend(1'b0),
		.rd_new_frame(),
		
		.s_axis_pix_data(m_axis_if.data),
		.s_axis_pix_valid(m_axis_if.valid),
		.s_axis_pix_ready(m_axis_if.ready),
		
		.m_axis_pix_data(s_axis_if.data),
		.m_axis_pix_user(s_axis_if.user),
		.m_axis_pix_last(s_axis_if.last),
		.m_axis_pix_valid(s_axis_if.valid),
		.m_axis_pix_ready(s_axis_if.ready),
		
		.m_axi_araddr(axi_if.araddr),
		.m_axi_arburst(axi_if.arburst),
		.m_axi_arlen(axi_if.arlen),
		.m_axi_arsize(axi_if.arsize),
		.m_axi_arvalid(axi_if.arvalid),
		.m_axi_arready(axi_if.arready),
		.m_axi_rdata(axi_if.rdata),
		.m_axi_rresp(axi_if.rresp),
		.m_axi_rlast(axi_if.rlast),
		.m_axi_rvalid(axi_if.rvalid),
		.m_axi_rready(axi_if.rready),
		.m_axi_awaddr(axi_if.awaddr),
		.m_axi_awburst(axi_if.awburst),
		.m_axi_awlen(axi_if.awlen),
		.m_axi_awsize(axi_if.awsize),
		.m_axi_awvalid(axi_if.awvalid),
		.m_axi_awready(axi_if.awready),
		.m_axi_bresp(axi_if.bresp),
		.m_axi_bvalid(axi_if.bvalid),
		.m_axi_bready(axi_if.bready),
		.m_axi_wdata(axi_if.wdata),
		.m_axi_wstrb(axi_if.wstrb),
		.m_axi_wlast(axi_if.wlast),
		.m_axi_wvalid(axi_if.wvalid),
		.m_axi_wready(axi_if.wready)
	);
	
	s_axi_memory_map_model #(
		.out_drive_t(simulation_delay),
		.addr_width(32),
		.data_width(32),
		.bresp_width(2),
		.rresp_width(2),
		.memory_map_depth(memory_map_depth)
	)s_axi_memory_map_model_u(
		.s_axi_if(axi_if.slave)
	);
	
endmodule
