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
`include "vsqr.sv"
`include "envs.sv"
`include "agents.sv"
`include "sequencers.sv"
`include "drivers.sv"
`include "monitors.sv"
`include "transactions.sv"

module tb_panda_risc_v_lsu();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer inst_id_width = 4; // 指令编号的位宽
	localparam integer dbus_access_timeout_th = 16; // 数据总线访问超时周期数(必须>=1)
	localparam icb_zero_latency_supported = "false"; // 是否支持零响应时延的ICB主机
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
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(9)) m_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(simulation_delay), .data_width(64), .user_width(16)) s_axis_if(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(simulation_delay), .addr_width(32), .data_width(32)) s_icb_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(9)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(9)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_axis_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(16)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "axis_if", s_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(simulation_delay), 
			.data_width(64), .user_width(16)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "axis_if", s_axis_if.monitor);
		
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt3.drv", "icb_if", s_icb_if.slave);
		uvm_config_db #(virtual ICB #(.out_drive_t(simulation_delay), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "icb_if", s_icb_if.monitor);
		
		uvm_config_db #(int unsigned)::set(null, 
			"uvm_test_top.env.agt3.drv", "outstanding_limit_n", 3);
		
		// 启动testcase
		run_test("LsuCase0Test");
	end
	
	/** 待测模块 **/
	// 访存请求
	wire s_req_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[2:0] s_req_ls_type; // 访存类型
	wire[4:0] s_req_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] s_req_ls_addr; // 访存地址
	wire[31:0] s_req_ls_din; // 写数据
	reg[inst_id_width-1:0] s_req_lsu_inst_id; // 指令编号
	wire s_req_valid;
	wire s_req_ready;
	// 访存结果
	wire m_resp_ls_sel; // 加载/存储选择(1'b0 -> 加载, 1'b1 -> 存储)
	wire[4:0] m_resp_rd_id_for_ld; // 用于加载的目标寄存器的索引
	wire[31:0] m_resp_dout; // 读数据
	wire[31:0] m_resp_ls_addr; // 访存地址
	wire[1:0] m_resp_err; // 错误类型
	wire[inst_id_width-1:0] m_resp_lsu_inst_id; // 指令编号
	wire m_resp_valid;
	wire m_resp_ready;
	// 指令ICB主机
	// 命令通道
	wire[31:0] m_icb_cmd_addr;
	wire m_icb_cmd_read;
	wire[31:0] m_icb_cmd_wdata;
	wire[3:0] m_icb_cmd_wmask;
	wire m_icb_cmd_valid;
	wire m_icb_cmd_ready;
	// 响应通道
	wire[31:0] m_icb_rsp_rdata;
	wire m_icb_rsp_err;
	wire m_icb_rsp_valid;
	wire m_icb_rsp_ready;
	
	assign s_req_ls_sel = m_axis_if.user[0];
	assign s_req_ls_type = m_axis_if.user[3:1];
	assign s_req_rd_id_for_ld = m_axis_if.user[8:4];
	assign s_req_ls_addr = m_axis_if.data[31:0];
	assign s_req_ls_din = m_axis_if.data[63:32];
	assign s_req_valid = m_axis_if.valid;
	assign m_axis_if.ready = s_req_ready;
	
	assign s_axis_if.user = {4'd0, m_resp_lsu_inst_id, m_resp_err, m_resp_rd_id_for_ld, m_resp_ls_sel};
	assign s_axis_if.data = {m_resp_ls_addr, m_resp_dout};
	assign s_axis_if.last = 1'b1;
	
	assign s_axis_if.valid = m_resp_valid;
	assign m_resp_ready = s_axis_if.ready;
	
	assign s_icb_if.cmd_addr = m_icb_cmd_addr;
	assign s_icb_if.cmd_read = m_icb_cmd_read;
	assign s_icb_if.cmd_wdata = m_icb_cmd_wdata;
	assign s_icb_if.cmd_wmask = m_icb_cmd_wmask;
	assign s_icb_if.cmd_valid = m_icb_cmd_valid;
	assign m_icb_cmd_ready = s_icb_if.cmd_ready;
	
	assign m_icb_rsp_rdata = s_icb_if.rsp_rdata;
	assign m_icb_rsp_err = s_icb_if.rsp_err;
	assign m_icb_rsp_valid = s_icb_if.rsp_valid;
	assign s_icb_if.rsp_ready = m_icb_rsp_ready;
	
	panda_risc_v_lsu #(
		.inst_id_width(inst_id_width),
		.dbus_access_timeout_th(dbus_access_timeout_th),
		.icb_zero_latency_supported(icb_zero_latency_supported),
		.simulation_delay(simulation_delay)
	)dut(
		.clk(clk),
		.resetn(rst_n),
		
		.lsu_idle(),
		
		.s_req_ls_sel(s_req_ls_sel),
		.s_req_ls_type(s_req_ls_type),
		.s_req_rd_id_for_ld(s_req_rd_id_for_ld),
		.s_req_ls_addr(s_req_ls_addr),
		.s_req_ls_din(s_req_ls_din),
		.s_req_lsu_inst_id(s_req_lsu_inst_id),
		.s_req_valid(s_req_valid),
		.s_req_ready(s_req_ready),
		
		.m_resp_ls_sel(m_resp_ls_sel),
		.m_resp_rd_id_for_ld(m_resp_rd_id_for_ld),
		.m_resp_dout(m_resp_dout),
		.m_resp_ls_addr(m_resp_ls_addr),
		.m_resp_err(m_resp_err),
		.m_resp_lsu_inst_id(m_resp_lsu_inst_id),
		.m_resp_valid(m_resp_valid),
		.m_resp_ready(m_resp_ready),
		
		.m_icb_cmd_addr(m_icb_cmd_addr),
		.m_icb_cmd_read(m_icb_cmd_read),
		.m_icb_cmd_wdata(m_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_wmask),
		.m_icb_cmd_valid(m_icb_cmd_valid),
		.m_icb_cmd_ready(m_icb_cmd_ready),
		
		.m_icb_rsp_rdata(m_icb_rsp_rdata),
		.m_icb_rsp_err(m_icb_rsp_err),
		.m_icb_rsp_valid(m_icb_rsp_valid),
		.m_icb_rsp_ready(m_icb_rsp_ready),
		
		.dbus_timeout()
	);
	
	/** 指令编号 **/
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			s_req_lsu_inst_id <= 0;
		else if(s_req_valid & s_req_ready)
			s_req_lsu_inst_id <= s_req_lsu_inst_id + 1;
	end
	
endmodule
