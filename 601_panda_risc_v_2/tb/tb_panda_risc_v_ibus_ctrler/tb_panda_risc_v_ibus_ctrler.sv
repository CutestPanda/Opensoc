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

module tb_panda_risc_v_ibus_ctrler();
	
	/** 配置参数 **/
	// 待测模块配置
	localparam integer IBUS_ACCESS_TIMEOUT_TH = 16; // 指令总线访问超时周期数(0 -> 不设超时 | 正整数)
	localparam integer INST_ADDR_ALIGNMENT_WIDTH = 32; // 指令地址对齐位宽(16 | 32)
	localparam integer IBUS_TID_WIDTH = 8; // 指令总线事务ID位宽(1~16)
	localparam integer IBUS_OUTSTANDING_N = 4; // 指令总线滞外深度(1 | 2 | 4 | 8)
	localparam integer IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH = 2; // 指令总线访问请求附带信息的位宽(正整数)
	// 时钟和复位配置
	localparam real CLK_P = 10.0; // 时钟周期
	localparam real SIM_DELAY = 1.0; // 仿真延时
	
	/** 时钟和复位 **/
	reg clk;
	reg rst_n;
	
	initial
	begin
		clk <= 1'b1;
		
		forever
		begin
			# (CLK_P / 2) clk <= ~clk;
		end
	end
	
	initial begin
		rst_n <= 1'b0;
		
		# (CLK_P * 10 + SIM_DELAY);
		
		rst_n <= 1'b1;
	end
	
	/** 接口 **/
	AXIS #(.out_drive_t(SIM_DELAY), .data_width(32), .user_width(IBUS_TID_WIDTH)) m_req_axis_if(.clk(clk), .rst_n(rst_n));
	AXIS #(.out_drive_t(SIM_DELAY), .data_width(64), .user_width(2+IBUS_TID_WIDTH)) s_resp_axis_if(.clk(clk), .rst_n(rst_n));
	ICB #(.out_drive_t(SIM_DELAY), .addr_width(32), .data_width(32)) s_icb_if(.clk(clk), .rst_n(rst_n));
	ReqAck #(.out_drive_t(SIM_DELAY), .req_payload_width(32), .resp_payload_width(32)) clr_req_if(.clk(clk), .rst_n(rst_n));
	
	/** 主任务 **/
	initial
	begin
		// 设置虚接口
		uvm_config_db #(virtual AXIS #(.out_drive_t(SIM_DELAY), 
			.data_width(32), .user_width(IBUS_TID_WIDTH)).master)::set(null, 
			"uvm_test_top.env.agt1.drv", "axis_if", m_req_axis_if.master);
		uvm_config_db #(virtual AXIS #(.out_drive_t(SIM_DELAY), 
			.data_width(32), .user_width(IBUS_TID_WIDTH)).monitor)::set(null, 
			"uvm_test_top.env.agt1.mon", "axis_if", m_req_axis_if.monitor);
		
		uvm_config_db #(virtual ICB #(.out_drive_t(SIM_DELAY), 
			.addr_width(32), .data_width(32)).slave)::set(null, 
			"uvm_test_top.env.agt2.drv", "icb_if", s_icb_if.slave);
		uvm_config_db #(virtual ICB #(.out_drive_t(SIM_DELAY), 
			.addr_width(32), .data_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt2.mon", "icb_if", s_icb_if.monitor);
		
		uvm_config_db #(virtual AXIS #(.out_drive_t(SIM_DELAY), 
			.data_width(64), .user_width(2+IBUS_TID_WIDTH)).slave)::set(null, 
			"uvm_test_top.env.agt3.drv", "axis_if", s_resp_axis_if.slave);
		uvm_config_db #(virtual AXIS #(.out_drive_t(SIM_DELAY), 
			.data_width(64), .user_width(2+IBUS_TID_WIDTH)).monitor)::set(null, 
			"uvm_test_top.env.agt3.mon", "axis_if", s_resp_axis_if.monitor);
		
		uvm_config_db #(virtual ReqAck #(.out_drive_t(SIM_DELAY), 
			.req_payload_width(32), .resp_payload_width(32)).master)::set(null, 
			"uvm_test_top.env.agt4.drv", "req_ack_if", clr_req_if.master);
		uvm_config_db #(virtual ReqAck #(.out_drive_t(SIM_DELAY), 
			.req_payload_width(32), .resp_payload_width(32)).monitor)::set(null, 
			"uvm_test_top.env.agt4.mon", "req_ack_if", clr_req_if.monitor);
		
		// 启动testcase
		run_test("IBusCtrlerCase1Test");
	end
	
	/** 待测模块 **/
	// 清空指令缓存
	wire clr_inst_buf;
	// 指令总线访问请求
	wire[31:0] ibus_access_req_addr;
	wire[IBUS_TID_WIDTH-1:0] ibus_access_req_tid;
	wire ibus_access_req_valid;
	wire ibus_access_req_ready;
	// 指令总线访问应答
	wire[31:0] ibus_access_resp_rdata;
	wire[1:0] ibus_access_resp_err; // 错误类型(2'b00 -> 正常, 2'b01 -> 指令地址非对齐, 
								    //          2'b10 -> 指令总线访问错误, 2'b11 -> 响应超时)
	wire[31:0] ibus_access_resp_addr;
	wire[IBUS_TID_WIDTH-1:0] ibus_access_resp_tid;
	wire ibus_access_resp_valid;
	wire ibus_access_resp_ready;
	// 指令ICB主机
	// [命令通道]
	wire[31:0] m_icb_cmd_addr;
	wire m_icb_cmd_read; // const -> 1'b1
	wire[31:0] m_icb_cmd_wdata; // const -> 32'h0000_0000
	wire[3:0] m_icb_cmd_wmask; // const -> 4'b0000
	wire m_icb_cmd_valid;
	wire m_icb_cmd_ready;
	// [响应通道]
	wire[31:0] m_icb_rsp_rdata;
	wire m_icb_rsp_err;
	wire m_icb_rsp_valid;
	wire m_icb_rsp_ready;
	
	assign ibus_access_req_addr = m_req_axis_if.data;
	assign ibus_access_req_tid = m_req_axis_if.user;
	assign ibus_access_req_valid = m_req_axis_if.valid;
	assign m_req_axis_if.ready = ibus_access_req_ready;
	
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
	
	assign s_resp_axis_if.data = {ibus_access_resp_addr, ibus_access_resp_rdata};
	assign s_resp_axis_if.user = {ibus_access_resp_err, ibus_access_resp_tid};
	assign s_resp_axis_if.last = 1'b1;
	assign s_resp_axis_if.valid = ibus_access_resp_valid;
	assign ibus_access_resp_ready = s_resp_axis_if.ready;
	
	assign clr_inst_buf = clr_req_if.req;
	assign clr_req_if.ack = clr_inst_buf;
	assign clr_req_if.resp_payload = 32'h0000_0000;
	
	panda_risc_v_ibus_ctrler #(
		.IBUS_ACCESS_TIMEOUT_TH(IBUS_ACCESS_TIMEOUT_TH),
		.INST_ADDR_ALIGNMENT_WIDTH(INST_ADDR_ALIGNMENT_WIDTH),
		.IBUS_TID_WIDTH(IBUS_TID_WIDTH),
		.IBUS_OUTSTANDING_N(IBUS_OUTSTANDING_N),
		.IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH(IBUS_ACCESS_REQ_EXTRA_MSG_WIDTH),
		.PRDT_MSG_WIDTH(64),
		.SIM_DELAY(SIM_DELAY)
	)dut(
		.aclk(clk),
		.aresetn(rst_n),
		
		.clr_inst_buf(clr_inst_buf),
		.suppressing_ibus_access(),
		.clr_inst_buf_while_suppressing(),
		.ibus_timeout(),
		
		.prdt_bdcst_vld(1'b0),
		.prdt_bdcst_tid(16'h0000),
		.prdt_bdcst_msg(64'h0000_0000_0000_0000),
		
		.ibus_access_req_addr(ibus_access_req_addr),
		.ibus_access_req_tid(ibus_access_req_tid),
		.ibus_access_req_extra_msg(2),
		.ibus_access_req_valid(ibus_access_req_valid),
		.ibus_access_req_ready(ibus_access_req_ready),
		
		.ibus_access_resp_rdata(ibus_access_resp_rdata),
		.ibus_access_resp_err(ibus_access_resp_err),
		.ibus_access_resp_addr(ibus_access_resp_addr),
		.ibus_access_resp_tid(ibus_access_resp_tid),
		.ibus_access_resp_extra_msg(),
		.ibus_access_resp_pre_decoding_msg(),
		.ibus_access_resp_prdt(),
		.ibus_access_resp_valid(ibus_access_resp_valid),
		.ibus_access_resp_ready(ibus_access_resp_ready),
		
		.m_icb_cmd_addr(m_icb_cmd_addr),
		.m_icb_cmd_read(m_icb_cmd_read),
		.m_icb_cmd_wdata(m_icb_cmd_wdata),
		.m_icb_cmd_wmask(m_icb_cmd_wmask),
		.m_icb_cmd_valid(m_icb_cmd_valid),
		.m_icb_cmd_ready(m_icb_cmd_ready),
		
		.m_icb_rsp_rdata(m_icb_rsp_rdata),
		.m_icb_rsp_err(m_icb_rsp_err),
		.m_icb_rsp_valid(m_icb_rsp_valid),
		.m_icb_rsp_ready(m_icb_rsp_ready)
	);
	
endmodule
