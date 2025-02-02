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
本模块: 总线控制单元

描述:
CPU核内指令ICB从机 --------------------- 指令ICB主机
                                              |
											  |
        |--------------------------------------
		|
CPU核内数据ICB从机 --------------------- 数据ICB主机

CPU核内指令ICB总线只能访问外部的指令ICB总线
CPU核内数据ICB总线可以根据地址区间访问外部的指令/数据ICB总线

注意：
无

协议:
ICB MASTER/SLAVE

作者: 陈家耀
日期: 2025/01/15
********************************************************************/


module panda_risc_v_biu #(
	parameter imem_baseaddr = 32'h0000_0000, // 指令存储器基址
	parameter integer imem_addr_range = 16 * 1024, // 指令存储器地址区间长度
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// CPU核内指令ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_inst_addr,
	input wire s_icb_cmd_inst_read,
	input wire[31:0] s_icb_cmd_inst_wdata,
	input wire[3:0] s_icb_cmd_inst_wmask,
	input wire s_icb_cmd_inst_valid,
	output wire s_icb_cmd_inst_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_inst_rdata,
	output wire s_icb_rsp_inst_err,
	output wire s_icb_rsp_inst_valid,
	input wire s_icb_rsp_inst_ready,
	
	// CPU核内数据ICB从机
	// 命令通道
	input wire[31:0] s_icb_cmd_data_addr,
	input wire s_icb_cmd_data_read,
	input wire[31:0] s_icb_cmd_data_wdata,
	input wire[3:0] s_icb_cmd_data_wmask,
	input wire s_icb_cmd_data_valid,
	output wire s_icb_cmd_data_ready,
	// 响应通道
	output wire[31:0] s_icb_rsp_data_rdata,
	output wire s_icb_rsp_data_err,
	output wire s_icb_rsp_data_valid,
	input wire s_icb_rsp_data_ready,
	
	// 指令ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_inst_addr,
	output wire m_icb_cmd_inst_read,
	output wire[31:0] m_icb_cmd_inst_wdata,
	output wire[3:0] m_icb_cmd_inst_wmask,
	output wire m_icb_cmd_inst_valid,
	input wire m_icb_cmd_inst_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_inst_rdata,
	input wire m_icb_rsp_inst_err,
	input wire m_icb_rsp_inst_valid,
	output wire m_icb_rsp_inst_ready,
	
	// 数据ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_data_addr,
	output wire m_icb_cmd_data_read,
	output wire[31:0] m_icb_cmd_data_wdata,
	output wire[3:0] m_icb_cmd_data_wmask,
	output wire m_icb_cmd_data_valid,
	input wire m_icb_cmd_data_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_data_rdata,
	input wire m_icb_rsp_data_err,
	input wire m_icb_rsp_data_valid,
	output wire m_icb_rsp_data_ready
);
	
	/** 数据ICB主机的命令通道 **/
	// 数据总线地址译码信息fifo满标志
	wire dbus_addr_dcd_msg_fifo_full_n;
	// 数据总线地址译码
	wire dbus_access_imem; // 数据总线访问指令存储器(标志)
	wire dbus_access_peripherals; // 数据总线访问外设(标志)
	
	assign dbus_access_imem = (s_icb_cmd_data_addr >= imem_baseaddr) & (s_icb_cmd_data_addr < (imem_baseaddr + imem_addr_range));
	assign dbus_access_peripherals = ~dbus_access_imem;
	
	assign m_icb_cmd_data_addr = s_icb_cmd_data_addr;
	assign m_icb_cmd_data_read = s_icb_cmd_data_read;
	assign m_icb_cmd_data_wdata = s_icb_cmd_data_wdata;
	assign m_icb_cmd_data_wmask = s_icb_cmd_data_wmask;
	assign m_icb_cmd_data_valid = s_icb_cmd_data_valid & dbus_access_peripherals & dbus_addr_dcd_msg_fifo_full_n;
	
	/** 指令ICB主机的命令通道 **/
	// CPU核内指令总线给出的指令ICB主机命令通道
	wire[31:0] s_inst_to_ibus_addr;
	wire s_inst_to_ibus_read;
	wire[31:0] s_inst_to_ibus_wdata;
	wire[3:0] s_inst_to_ibus_wmask;
	wire s_inst_to_ibus_valid;
	wire s_inst_to_ibus_ready;
	// CPU核内数据总线给出的指令ICB主机命令通道
	wire[31:0] s_data_to_ibus_addr;
	wire s_data_to_ibus_read;
	wire[31:0] s_data_to_ibus_wdata;
	wire[3:0] s_data_to_ibus_wmask;
	wire s_data_to_ibus_valid;
	wire s_data_to_ibus_ready;
	// IMEM访问仲裁信息fifo满标志
	wire imem_access_arb_msg_fifo_full_n;
	// IMEM访问仲裁
	wire ibus_req_from_inst; // 来自CPU核内指令总线的IMEM访问请求
	wire ibus_req_from_data; // 来自CPU核内数据总线的IMEM访问请求
	wire ibus_grant_to_inst; // CPU核内指令总线的IMEM访问许可
	wire ibus_grant_to_data; // CPU核内数据总线的IMEM访问许可
	
	assign s_inst_to_ibus_addr = s_icb_cmd_inst_addr;
	assign s_inst_to_ibus_read = s_icb_cmd_inst_read;
	assign s_inst_to_ibus_wdata = s_icb_cmd_inst_wdata;
	assign s_inst_to_ibus_wmask = s_icb_cmd_inst_wmask;
	assign s_inst_to_ibus_valid = 
		s_icb_cmd_inst_valid & imem_access_arb_msg_fifo_full_n;
	assign s_icb_cmd_inst_ready = s_inst_to_ibus_ready;
	
	assign s_data_to_ibus_addr = s_icb_cmd_data_addr;
	assign s_data_to_ibus_read = s_icb_cmd_data_read;
	assign s_data_to_ibus_wdata = s_icb_cmd_data_wdata;
	assign s_data_to_ibus_wmask = s_icb_cmd_data_wmask;
	assign s_data_to_ibus_valid = 
		s_icb_cmd_data_valid & dbus_access_imem & dbus_addr_dcd_msg_fifo_full_n & imem_access_arb_msg_fifo_full_n;
	assign s_icb_cmd_data_ready = 
		(dbus_access_imem & dbus_addr_dcd_msg_fifo_full_n & imem_access_arb_msg_fifo_full_n & s_data_to_ibus_ready) | 
		(dbus_access_peripherals & dbus_addr_dcd_msg_fifo_full_n & m_icb_cmd_data_ready);
	
	assign m_icb_cmd_inst_addr = 
		({32{ibus_grant_to_inst}} & s_inst_to_ibus_addr) | 
		({32{ibus_grant_to_data}} & s_data_to_ibus_addr);
	assign m_icb_cmd_inst_read = 
		(ibus_grant_to_inst & s_inst_to_ibus_read) | 
		(ibus_grant_to_data & s_data_to_ibus_read);
	assign m_icb_cmd_inst_wdata = 
		({32{ibus_grant_to_inst}} & s_inst_to_ibus_wdata) | 
		({32{ibus_grant_to_data}} & s_data_to_ibus_wdata);
	assign m_icb_cmd_inst_wmask = 
		({4{ibus_grant_to_inst}} & s_inst_to_ibus_wmask) | 
		({4{ibus_grant_to_data}} & s_data_to_ibus_wmask);
	assign m_icb_cmd_inst_valid = s_inst_to_ibus_valid | s_data_to_ibus_valid;
	
	assign s_inst_to_ibus_ready = ibus_grant_to_inst & m_icb_cmd_inst_ready;
	assign s_data_to_ibus_ready = ibus_grant_to_data & m_icb_cmd_inst_ready;
	
	assign ibus_req_from_inst = s_inst_to_ibus_valid;
	assign ibus_req_from_data = s_data_to_ibus_valid;
	
	// Round-Robin仲裁器
	round_robin_arbitrator #(
		.chn_n(2),
		.simulation_delay(simulation_delay)
	)round_robin_arbitrator_u(
		.clk(clk),
		.rst_n(resetn),
		
		.req({ibus_req_from_inst, ibus_req_from_data}),
		.grant({ibus_grant_to_inst, ibus_grant_to_data})
	);
	
	/** 数据总线地址译码信息fifo **/
	// fifo写端口
	wire dbus_addr_dcd_msg_fifo_wen;
	wire dbus_addr_dcd_msg_fifo_din;
	// fifo读端口
	wire dbus_addr_dcd_msg_fifo_ren;
	wire dbus_addr_dcd_msg_fifo_dout;
	wire dbus_addr_dcd_msg_fifo_empty_n;
	
	assign dbus_addr_dcd_msg_fifo_wen = s_icb_cmd_data_valid & s_icb_cmd_data_ready;
	assign dbus_addr_dcd_msg_fifo_din = dbus_access_imem;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(1),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(simulation_delay)
	)dbus_addr_dcd_msg_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(dbus_addr_dcd_msg_fifo_wen),
		.fifo_din(dbus_addr_dcd_msg_fifo_din),
		.fifo_full_n(dbus_addr_dcd_msg_fifo_full_n),
		
		.fifo_ren(dbus_addr_dcd_msg_fifo_ren),
		.fifo_dout(dbus_addr_dcd_msg_fifo_dout),
		.fifo_empty_n(dbus_addr_dcd_msg_fifo_empty_n)
	);
	
	/** IMEM访问仲裁信息fifo **/
	// fifo写端口
	wire imem_access_arb_msg_fifo_wen;
	wire imem_access_arb_msg_fifo_din;
	// fifo读端口
	wire imem_access_arb_msg_fifo_ren;
	wire imem_access_arb_msg_fifo_dout;
	wire imem_access_arb_msg_fifo_empty_n;
	
	assign imem_access_arb_msg_fifo_wen = m_icb_cmd_inst_valid & m_icb_cmd_inst_ready;
	assign imem_access_arb_msg_fifo_din = ibus_grant_to_inst;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(1),
		.almost_full_th(1),
		.almost_empty_th(1),
		.simulation_delay(simulation_delay)
	)imem_access_arb_msg_fifo(
		.clk(clk),
		.rst_n(resetn),
		
		.fifo_wen(imem_access_arb_msg_fifo_wen),
		.fifo_din(imem_access_arb_msg_fifo_din),
		.fifo_full_n(imem_access_arb_msg_fifo_full_n),
		
		.fifo_ren(imem_access_arb_msg_fifo_ren),
		.fifo_dout(imem_access_arb_msg_fifo_dout),
		.fifo_empty_n(imem_access_arb_msg_fifo_empty_n)
	);
	
	/** 指令/数据ICB主机的响应分发 **/
	assign s_icb_rsp_inst_rdata = m_icb_rsp_inst_rdata;
	assign s_icb_rsp_inst_err = m_icb_rsp_inst_err;
	assign s_icb_rsp_inst_valid = m_icb_rsp_inst_valid & imem_access_arb_msg_fifo_empty_n & imem_access_arb_msg_fifo_dout;
	assign m_icb_rsp_inst_ready = 
		imem_access_arb_msg_fifo_empty_n & 
		(imem_access_arb_msg_fifo_dout ? 
			s_icb_rsp_inst_ready:
			(dbus_addr_dcd_msg_fifo_empty_n & dbus_addr_dcd_msg_fifo_dout & s_icb_rsp_data_ready));
	
	assign s_icb_rsp_data_rdata = dbus_addr_dcd_msg_fifo_dout ? m_icb_rsp_inst_rdata:m_icb_rsp_data_rdata;
	assign s_icb_rsp_data_err = dbus_addr_dcd_msg_fifo_dout ? m_icb_rsp_inst_err:m_icb_rsp_data_err;
	assign s_icb_rsp_data_valid = 
		dbus_addr_dcd_msg_fifo_empty_n & 
		(dbus_addr_dcd_msg_fifo_dout ? 
			(imem_access_arb_msg_fifo_empty_n & (~imem_access_arb_msg_fifo_dout) & m_icb_rsp_inst_valid):
			m_icb_rsp_data_valid);
	assign m_icb_rsp_data_ready = dbus_addr_dcd_msg_fifo_empty_n & (~dbus_addr_dcd_msg_fifo_dout) & s_icb_rsp_data_ready;
	
	assign dbus_addr_dcd_msg_fifo_ren = 
		s_icb_rsp_data_ready & 
		(dbus_addr_dcd_msg_fifo_dout ? 
			(imem_access_arb_msg_fifo_empty_n & (~imem_access_arb_msg_fifo_dout) & m_icb_rsp_inst_valid):
			m_icb_rsp_data_valid);
	assign imem_access_arb_msg_fifo_ren = 
		m_icb_rsp_inst_valid & 
		(imem_access_arb_msg_fifo_dout ? 
			s_icb_rsp_inst_ready:
			(dbus_addr_dcd_msg_fifo_empty_n & dbus_addr_dcd_msg_fifo_dout & s_icb_rsp_data_ready));
	
endmodule
