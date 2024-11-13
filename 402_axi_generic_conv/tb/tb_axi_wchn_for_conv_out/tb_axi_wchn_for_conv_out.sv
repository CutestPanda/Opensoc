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

module tb_axi_wchn_for_conv_out();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer feature_data_width = 16; // 特征点位宽(8 | 16 | 32 | 64)
	localparam integer max_wt_btt = 4 * 512; // 最大的写传输字节数(256 | 512 | 1024 | ...)
	localparam integer axi_wchn_max_burst_len = 32; // AXI写通道最大突发长度(2 | 4 | 8 | 16 | 32 | 64 | 128 | 256)
	localparam integer axi_waddr_outstanding = 4; // AXI写地址缓冲深度(1 | 2 | 4)
	localparam integer axi_wdata_buffer_depth = 512; // AXI写数据buffer深度(512 | 1024 | ...)
	localparam en_axi_aw_reg_slice = "true"; // 是否使能AXI写地址通道AXIS寄存器片
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(0)) m0_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(feature_data_width), .user_width(0)) m1_axis_if(.clk(clk), .rst_n(rst_n));
	AXI #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(64), .bresp_width(2), .rresp_width(2))
		axi_if_inst(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m0_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m0_axis_if.monitor);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(feature_data_width), .user_width(0)).master)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", m1_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(feature_data_width), .user_width(0)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", m1_axis_if.monitor);
		
		// 启动testcase
		run_test("AxiWchnForConvOutCase0Test");
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
	
	/** 待测模块 **/
	assign axi_if_inst.arvalid = 1'b0;
	assign axi_if_inst.rready = 1'b1;
	
	axi_wchn_for_conv_out #(
		.feature_data_width(feature_data_width),
		.max_wt_btt(max_wt_btt),
		.axi_wchn_max_burst_len(axi_wchn_max_burst_len),
		.axi_waddr_outstanding(axi_waddr_outstanding),
		.axi_wdata_buffer_depth(axi_wdata_buffer_depth),
		.en_axi_aw_reg_slice(en_axi_aw_reg_slice),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.rst_n(rst_n),
		
		.s_axis_wt_req_data(m0_axis_if.data),
		.s_axis_wt_req_valid(m0_axis_if.valid),
		.s_axis_wt_req_ready(m0_axis_if.ready),
		
		.s_axis_res_data(m1_axis_if.data),
		.s_axis_res_last(m1_axis_if.last),
		.s_axis_res_valid(m1_axis_if.valid),
		.s_axis_res_ready(m1_axis_if.ready),
		
		.m_axi_awaddr(axi_if_inst.awaddr),
		.m_axi_awburst(axi_if_inst.awburst),
		.m_axi_awlen(axi_if_inst.awlen),
		.m_axi_awsize(axi_if_inst.awsize),
		.m_axi_awvalid(axi_if_inst.awvalid),
		.m_axi_awready(axi_if_inst.awready),
		
		.m_axi_bresp(axi_if_inst.bresp),
		.m_axi_bvalid(axi_if_inst.bvalid),
		.m_axi_bready(axi_if_inst.bready),
		
		.m_axi_wdata(axi_if_inst.wdata),
		.m_axi_wstrb(axi_if_inst.wstrb),
		.m_axi_wlast(axi_if_inst.wlast),
		.m_axi_wvalid(axi_if_inst.wvalid),
		.m_axi_wready(axi_if_inst.wready)
	);
	
endmodule
