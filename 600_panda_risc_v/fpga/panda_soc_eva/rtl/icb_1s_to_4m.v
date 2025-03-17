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
/********************************************************************
本模块: ICB一从四主分发器

描述:
将一个ICB从机分发到四个ICB主机

注意：
未处理地址译码错误

协议:
ICB MASTER/SLAVE

作者: 陈家耀
日期: 2025/02/01
********************************************************************/


module icb_1s_to_4m #(
	parameter m0_baseaddr = 32'h1000_0000, // 主机#0基地址
	parameter integer m0_addr_range = 16 * 1024, // 主机#0地址区间长度
	parameter m1_baseaddr = 32'hF000_0000, // 主机#1基地址
	parameter integer m1_addr_range = 4 * 1024 * 1024, // 主机#1地址区间长度
	parameter m2_baseaddr = 32'hF400_0000, // 主机#2基地址
	parameter integer m2_addr_range = 64 * 1024 * 1024, // 主机#2地址区间长度
	parameter m3_baseaddr = 32'h4000_0000, // 主机#3基地址
	parameter integer m3_addr_range = 16 * 4096, // 主机#3地址区间长度
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_addr,
	input wire s_icb_cmd_read,
	input wire[31:0] s_icb_cmd_wdata,
	input wire[3:0] s_icb_cmd_wmask,
	input wire s_icb_cmd_valid,
	output wire s_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_rdata,
	output wire s_icb_rsp_err,
	output wire s_icb_rsp_valid,
	input wire s_icb_rsp_ready,
	
	// ICB主机#0
	// 命令通道
	output wire[31:0] m0_icb_cmd_addr,
	output wire m0_icb_cmd_read,
	output wire[31:0] m0_icb_cmd_wdata,
	output wire[3:0] m0_icb_cmd_wmask,
	output wire m0_icb_cmd_valid,
	input wire m0_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m0_icb_rsp_rdata,
	input wire m0_icb_rsp_err,
	input wire m0_icb_rsp_valid,
	output wire m0_icb_rsp_ready,
	
	// ICB主机#1
	// 命令通道
	output wire[31:0] m1_icb_cmd_addr,
	output wire m1_icb_cmd_read,
	output wire[31:0] m1_icb_cmd_wdata,
	output wire[3:0] m1_icb_cmd_wmask,
	output wire m1_icb_cmd_valid,
	input wire m1_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m1_icb_rsp_rdata,
	input wire m1_icb_rsp_err,
	input wire m1_icb_rsp_valid,
	output wire m1_icb_rsp_ready,
	
	// ICB主机#2
	// 命令通道
	output wire[31:0] m2_icb_cmd_addr,
	output wire m2_icb_cmd_read,
	output wire[31:0] m2_icb_cmd_wdata,
	output wire[3:0] m2_icb_cmd_wmask,
	output wire m2_icb_cmd_valid,
	input wire m2_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m2_icb_rsp_rdata,
	input wire m2_icb_rsp_err,
	input wire m2_icb_rsp_valid,
	output wire m2_icb_rsp_ready,
	
	// ICB主机#3
	// 命令通道
	output wire[31:0] m3_icb_cmd_addr,
	output wire m3_icb_cmd_read,
	output wire[31:0] m3_icb_cmd_wdata,
	output wire[3:0] m3_icb_cmd_wmask,
	output wire m3_icb_cmd_valid,
	input wire m3_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m3_icb_rsp_rdata,
	input wire m3_icb_rsp_err,
	input wire m3_icb_rsp_valid,
	output wire m3_icb_rsp_ready
);
	
	/** 地址译码 **/
	wire m0_sel;
	wire m1_sel;
	wire m2_sel;
	wire m3_sel;
	
	assign m0_sel = (s_icb_cmd_addr >= m0_baseaddr) & (s_icb_cmd_addr < (m0_baseaddr + m0_addr_range));
	assign m1_sel = (s_icb_cmd_addr >= m1_baseaddr) & (s_icb_cmd_addr < (m1_baseaddr + m1_addr_range));
	assign m2_sel = (s_icb_cmd_addr >= m2_baseaddr) & (s_icb_cmd_addr < (m2_baseaddr + m2_addr_range));
	assign m3_sel = (s_icb_cmd_addr >= m3_baseaddr) & (s_icb_cmd_addr < (m3_baseaddr + m3_addr_range));
	
	/** 分发信息fifo **/
	// fifo写端口
	wire dcd_msg_fifo_wen;
	wire[3:0] dcd_msg_fifo_din_sel;
	wire dcd_msg_fifo_full_n;
	// fifo读端口
	wire dcd_msg_fifo_ren;
	wire[3:0] dcd_msg_fifo_dout_sel;
	wire dcd_msg_fifo_empty_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(4),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(simulation_delay)
	)dcd_msg_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(dcd_msg_fifo_wen),
		.fifo_din(dcd_msg_fifo_din_sel),
		.fifo_full_n(dcd_msg_fifo_full_n),
		
		.fifo_ren(dcd_msg_fifo_ren),
		.fifo_dout(dcd_msg_fifo_dout_sel),
		.fifo_empty_n(dcd_msg_fifo_empty_n)
	);
	
	/** 命令通道选通 **/
	assign s_icb_cmd_ready = 
		dcd_msg_fifo_full_n & 
		((m0_sel & m0_icb_cmd_ready) | (m1_sel & m1_icb_cmd_ready) | (m2_sel & m2_icb_cmd_ready) | (m3_sel & m3_icb_cmd_ready));
	
	assign m0_icb_cmd_addr = s_icb_cmd_addr;
	assign m0_icb_cmd_read = s_icb_cmd_read;
	assign m0_icb_cmd_wdata = s_icb_cmd_wdata;
	assign m0_icb_cmd_wmask = s_icb_cmd_wmask;
	assign m0_icb_cmd_valid = s_icb_cmd_valid & m0_sel & dcd_msg_fifo_full_n;
	
	assign m1_icb_cmd_addr = s_icb_cmd_addr;
	assign m1_icb_cmd_read = s_icb_cmd_read;
	assign m1_icb_cmd_wdata = s_icb_cmd_wdata;
	assign m1_icb_cmd_wmask = s_icb_cmd_wmask;
	assign m1_icb_cmd_valid = s_icb_cmd_valid & m1_sel & dcd_msg_fifo_full_n;
	
	assign m2_icb_cmd_addr = s_icb_cmd_addr;
	assign m2_icb_cmd_read = s_icb_cmd_read;
	assign m2_icb_cmd_wdata = s_icb_cmd_wdata;
	assign m2_icb_cmd_wmask = s_icb_cmd_wmask;
	assign m2_icb_cmd_valid = s_icb_cmd_valid & m2_sel & dcd_msg_fifo_full_n;
	
	assign m3_icb_cmd_addr = s_icb_cmd_addr;
	assign m3_icb_cmd_read = s_icb_cmd_read;
	assign m3_icb_cmd_wdata = s_icb_cmd_wdata;
	assign m3_icb_cmd_wmask = s_icb_cmd_wmask;
	assign m3_icb_cmd_valid = s_icb_cmd_valid & m3_sel & dcd_msg_fifo_full_n;
	
	assign dcd_msg_fifo_wen = 
		s_icb_cmd_valid & 
		((m0_sel & m0_icb_cmd_ready) | (m1_sel & m1_icb_cmd_ready) | (m2_sel & m2_icb_cmd_ready) | (m3_sel & m3_icb_cmd_ready));
	assign dcd_msg_fifo_din_sel = {m3_sel, m2_sel, m1_sel, m0_sel};
	
	/** 响应通道路由 **/
	assign s_icb_rsp_rdata = 
		({32{dcd_msg_fifo_dout_sel[0]}} & m0_icb_rsp_rdata) | 
		({32{dcd_msg_fifo_dout_sel[1]}} & m1_icb_rsp_rdata) | 
		({32{dcd_msg_fifo_dout_sel[2]}} & m2_icb_rsp_rdata) | 
		({32{dcd_msg_fifo_dout_sel[3]}} & m3_icb_rsp_rdata);
	assign s_icb_rsp_err = 
		(dcd_msg_fifo_dout_sel[0] & m0_icb_rsp_err) | 
		(dcd_msg_fifo_dout_sel[1] & m1_icb_rsp_err) | 
		(dcd_msg_fifo_dout_sel[2] & m2_icb_rsp_err) | 
		(dcd_msg_fifo_dout_sel[3] & m3_icb_rsp_err);
	assign s_icb_rsp_valid = 
		dcd_msg_fifo_empty_n & 
		((dcd_msg_fifo_dout_sel[0] & m0_icb_rsp_valid) | 
		(dcd_msg_fifo_dout_sel[1] & m1_icb_rsp_valid) | 
		(dcd_msg_fifo_dout_sel[2] & m2_icb_rsp_valid) | 
		(dcd_msg_fifo_dout_sel[3] & m3_icb_rsp_valid));
	
	assign m0_icb_rsp_ready = dcd_msg_fifo_empty_n & dcd_msg_fifo_dout_sel[0] & s_icb_rsp_ready;
	assign m1_icb_rsp_ready = dcd_msg_fifo_empty_n & dcd_msg_fifo_dout_sel[1] & s_icb_rsp_ready;
	assign m2_icb_rsp_ready = dcd_msg_fifo_empty_n & dcd_msg_fifo_dout_sel[2] & s_icb_rsp_ready;
	assign m3_icb_rsp_ready = dcd_msg_fifo_empty_n & dcd_msg_fifo_dout_sel[3] & s_icb_rsp_ready;
	
	assign dcd_msg_fifo_ren = 
		s_icb_rsp_ready & 
		((dcd_msg_fifo_dout_sel[0] & m0_icb_rsp_valid) | 
		(dcd_msg_fifo_dout_sel[1] & m1_icb_rsp_valid) | 
		(dcd_msg_fifo_dout_sel[2] & m2_icb_rsp_valid) | 
		(dcd_msg_fifo_dout_sel[3] & m3_icb_rsp_valid));
	
endmodule
