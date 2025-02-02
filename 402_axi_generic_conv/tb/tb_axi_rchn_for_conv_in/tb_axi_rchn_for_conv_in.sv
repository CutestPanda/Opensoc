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

module tb_axi_rchn_for_conv_in();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer max_rd_btt = 4 * 512; // 最大的读传输字节数(256 | 512 | 1024 | ...)
	localparam integer axi_rchn_max_burst_len = 4; // AXI读通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	localparam integer axi_raddr_outstanding = 2; // AXI读地址缓冲深度(1 | 2 | 4)
	localparam integer axi_rdata_buffer_depth = 512; // AXI读数据buffer深度(0 -> 不启用 | 512 | 1024 | ...)
	localparam en_axi_ar_reg_slice = "true"; // 是否使能AXI读地址通道AXIS寄存器片
	// 仿真模型配置
	localparam integer memory_map_depth = 1024 * 64; // 存储映射深度(以字节计)
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(0)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(0)) s_axis_if(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(64), .bresp_width(2), .rresp_width(2))
		axi_if_inst(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		// 启动testcase
		run_test("AxiRchnForConvInCase0Test");
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
			s_axi_memory_map_model_u.memory_map[i][63:48] = (i << 2) + 3;
			s_axi_memory_map_model_u.memory_map[i][47:32] = (i << 2) + 2;
			s_axi_memory_map_model_u.memory_map[i][31:16] = (i << 2) + 1;
			s_axi_memory_map_model_u.memory_map[i][15:0] = i << 2;
		end
	end
	
	/** 待测模块 **/
	assign axi_if_inst.awvalid = 1'b0;
	assign axi_if_inst.wvalid = 1'b0;
	assign axi_if_inst.bready = 1'b1;
	
	axi_rchn_for_conv_in #(
		.max_rd_btt(max_rd_btt),
		.axi_rchn_max_burst_len(axi_rchn_max_burst_len),
		.axi_raddr_outstanding(axi_raddr_outstanding),
		.axi_rdata_buffer_depth(axi_rdata_buffer_depth),
		.en_axi_ar_reg_slice(en_axi_ar_reg_slice),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_rd_req_data(m_axis_if.data),
		.s_axis_rd_req_valid(m_axis_if.valid),
		.s_axis_rd_req_ready(m_axis_if.ready),
		
		.m_axis_ft_par_data(s_axis_if.data),
		.m_axis_ft_par_keep(s_axis_if.keep),
		.m_axis_ft_par_last(s_axis_if.last),
		.m_axis_ft_par_valid(s_axis_if.valid),
		.m_axis_ft_par_ready(s_axis_if.ready),
		
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
