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
本模块: 数据Cache下级存储器访问ICB接口

描述:
对读/写下级存储器ICB从机进行仲裁
支持多种ICB从机仲裁方式: 公平轮询/读优先/写优先
以一个缓存行(ICB从机上的CACHE_LINE_WORD_N次传输)作为仲裁单位

注意：
无

协议:
ICB MASTER/SLAVE

作者: 陈家耀
日期: 2025/04/16
********************************************************************/


module dcache_nxt_lv_mem_icb #(
	parameter ARB_METHOD = "round-robin", // 仲裁方式(round-robin | read-first | write-first)
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 读下级存储器ICB从机
	// 命令通道
	input wire[31:0] s_rd_icb_cmd_addr,
	input wire s_rd_icb_cmd_read,
	input wire[31:0] s_rd_icb_cmd_wdata,
	input wire[3:0] s_rd_icb_cmd_wmask,
	input wire s_rd_icb_cmd_valid,
	output wire s_rd_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_rd_icb_rsp_rdata,
	output wire s_rd_icb_rsp_err,
	output wire s_rd_icb_rsp_valid,
	input wire s_rd_icb_rsp_ready,
	
	// 写下级存储器ICB从机
	// 命令通道
	input wire[31:0] s_wt_icb_cmd_addr,
	input wire s_wt_icb_cmd_read,
	input wire[31:0] s_wt_icb_cmd_wdata,
	input wire[3:0] s_wt_icb_cmd_wmask,
	input wire s_wt_icb_cmd_valid,
	output wire s_wt_icb_cmd_ready,
	// 响应通道
	output wire[31:0] s_wt_icb_rsp_rdata,
	output wire s_wt_icb_rsp_err,
	output wire s_wt_icb_rsp_valid,
	input wire s_wt_icb_rsp_ready,
	
	// 访问下级存储器ICB主机
	// 命令通道
	output wire[31:0] m_icb_cmd_addr,
	output wire m_icb_cmd_read,
	output wire[31:0] m_icb_cmd_wdata,
	output wire[3:0] m_icb_cmd_wmask,
	output wire m_icb_cmd_valid,
	input wire m_icb_cmd_ready,
	// 响应通道
	input wire[31:0] m_icb_rsp_rdata,
	input wire m_icb_rsp_err,
	input wire m_icb_rsp_valid,
	output wire m_icb_rsp_ready
);
	
	/** 仲裁信息fifo **/
	// [fifo写端口]
	wire arb_msg_fifo_wen;
	wire arb_msg_fifo_din; // {是否选择读下级存储器ICB从机(1bit)}
	wire arb_msg_fifo_full_n;
	// [fifo读端口]
	wire arb_msg_fifo_ren;
	wire arb_msg_fifo_dout; // {是否选择读下级存储器ICB从机(1bit)}
	wire arb_msg_fifo_empty_n;
	
	fifo_based_on_regs #(
		.fwft_mode("true"),
		.low_latency_mode("false"),
		.fifo_depth(4),
		.fifo_data_width(1),
		.almost_full_th(2),
		.almost_empty_th(2),
		.simulation_delay(SIM_DELAY)
	)arb_msg_fifo_u(
		.clk(aclk),
		.rst_n(aresetn),
		
		.fifo_wen(arb_msg_fifo_wen),
		.fifo_din(arb_msg_fifo_din),
		.fifo_full_n(arb_msg_fifo_full_n),
		
		.fifo_ren(arb_msg_fifo_ren),
		.fifo_dout(arb_msg_fifo_dout),
		.fifo_empty_n(arb_msg_fifo_empty_n)
	);
	
	/** ICB接口命令通道 **/
	wire nxt_lv_mem_rd_req; // 读下级存储器请求
	wire nxt_lv_mem_wt_req; // 写下级存储器请求
	wire nxt_lv_mem_rd_grant; // 读下级存储器许可
	wire nxt_lv_mem_wt_grant; // 写下级存储器许可
	reg grant_held; // 许可保持(标志)
	reg rd_grant_latched; // 锁存的读许可
	reg wt_grant_latched; // 锁存的写许可
	reg sel_wt_when_cflt; // 冲突时选择写请求(标志)
	reg[CACHE_LINE_WORD_N-1:0] nxt_lv_mem_burst_word_id; // 下级存储器突发访问的字数据编号(独热码)
	reg nxt_lv_mem_burst_sel_wt; // 本次下级存储器突发访问选择写(标志)
	
	assign nxt_lv_mem_rd_req = arb_msg_fifo_full_n & (nxt_lv_mem_burst_word_id[0] | (~nxt_lv_mem_burst_sel_wt)) & s_rd_icb_cmd_valid;
	assign nxt_lv_mem_wt_req = arb_msg_fifo_full_n & (nxt_lv_mem_burst_word_id[0] | nxt_lv_mem_burst_sel_wt) & s_wt_icb_cmd_valid;
	
	// 握手条件: s_rd_icb_cmd_valid & m_icb_cmd_ready & (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant)
	assign s_rd_icb_cmd_ready = (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant) & m_icb_cmd_ready;
	
	// 握手条件: s_wt_icb_cmd_valid & m_icb_cmd_ready & (grant_held ? wt_grant_latched:nxt_lv_mem_wt_grant)
	assign s_wt_icb_cmd_ready = (grant_held ? wt_grant_latched:nxt_lv_mem_wt_grant) & m_icb_cmd_ready;
	
	assign m_icb_cmd_addr = (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant) ? s_rd_icb_cmd_addr:s_wt_icb_cmd_addr;
	assign m_icb_cmd_read = (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant) ? s_rd_icb_cmd_read:s_wt_icb_cmd_read;
	assign m_icb_cmd_wdata = (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant) ? s_rd_icb_cmd_wdata:s_wt_icb_cmd_wdata;
	assign m_icb_cmd_wmask = (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant) ? s_rd_icb_cmd_wmask:s_wt_icb_cmd_wmask;
	// 握手条件: (nxt_lv_mem_rd_req | nxt_lv_mem_wt_req) & m_icb_cmd_ready
	assign m_icb_cmd_valid = nxt_lv_mem_rd_req | nxt_lv_mem_wt_req;
	
	// 握手条件: (nxt_lv_mem_rd_req | nxt_lv_mem_wt_req) & m_icb_cmd_ready
	assign arb_msg_fifo_wen = (nxt_lv_mem_rd_req | nxt_lv_mem_wt_req) & m_icb_cmd_ready;
	assign arb_msg_fifo_din = (grant_held ? rd_grant_latched:nxt_lv_mem_rd_grant);
	
	// 许可保持(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			grant_held <= 1'b0;
		else if(
			grant_held ? 
				m_icb_cmd_ready:
				((nxt_lv_mem_rd_req | nxt_lv_mem_wt_req) & (~m_icb_cmd_ready))
		)
			grant_held <= # SIM_DELAY ~grant_held;
	end
	
	// 锁存的读许可, 锁存的写许可
	always @(posedge aclk)
	begin
		if((~grant_held) & (nxt_lv_mem_rd_req | nxt_lv_mem_wt_req) & (~m_icb_cmd_ready))
			{rd_grant_latched, wt_grant_latched} <= # SIM_DELAY {nxt_lv_mem_rd_grant, nxt_lv_mem_wt_grant};
	end
	
	generate
		if(ARB_METHOD == "round-robin")
		begin
			assign nxt_lv_mem_rd_grant = 
				(nxt_lv_mem_rd_req & nxt_lv_mem_wt_req) ? 
					(~sel_wt_when_cflt):
					nxt_lv_mem_rd_req;
			assign nxt_lv_mem_wt_grant = 
				(nxt_lv_mem_rd_req & nxt_lv_mem_wt_req) ? 
					sel_wt_when_cflt:
					nxt_lv_mem_wt_req;
			
			// 冲突时选择写请求(标志)
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					sel_wt_when_cflt <= 1'b0;
				else if(nxt_lv_mem_rd_req & nxt_lv_mem_wt_req & m_icb_cmd_ready)
					sel_wt_when_cflt <= # SIM_DELAY ~sel_wt_when_cflt;
			end
		end
		else if(ARB_METHOD == "write-first")
		begin
			assign nxt_lv_mem_rd_grant = (~nxt_lv_mem_wt_req) & nxt_lv_mem_rd_req;
			assign nxt_lv_mem_wt_grant = nxt_lv_mem_wt_req;
		end
		else // "read-first"
		begin
			assign nxt_lv_mem_rd_grant = nxt_lv_mem_rd_req;
			assign nxt_lv_mem_wt_grant = (~nxt_lv_mem_rd_req) & nxt_lv_mem_wt_req;
		end
	endgenerate
	
	// 下级存储器突发访问的字数据编号(独热码)
	generate
		if(CACHE_LINE_WORD_N == 1)
		begin
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					nxt_lv_mem_burst_word_id <= 1'b1;
				else if(m_icb_cmd_valid & m_icb_cmd_ready)
					nxt_lv_mem_burst_word_id <= # SIM_DELAY 1'b1;
			end
		end
		else
		begin
			always @(posedge aclk or negedge aresetn)
			begin
				if(~aresetn)
					nxt_lv_mem_burst_word_id <= {{(CACHE_LINE_WORD_N-1){1'b0}}, 1'b1};
				else if(m_icb_cmd_valid & m_icb_cmd_ready)
					nxt_lv_mem_burst_word_id <= # SIM_DELAY 
						{nxt_lv_mem_burst_word_id[CACHE_LINE_WORD_N-2:0], nxt_lv_mem_burst_word_id[CACHE_LINE_WORD_N-1]};
			end
		end
	endgenerate
	
	// 本次下级存储器突发访问选择写(标志)
	always @(posedge aclk)
	begin
		if(m_icb_cmd_valid & m_icb_cmd_ready & nxt_lv_mem_burst_word_id[0])
			nxt_lv_mem_burst_sel_wt <= # SIM_DELAY s_wt_icb_cmd_valid & s_wt_icb_cmd_ready;
	end
	
	/** ICB接口响应通道 **/
	assign s_rd_icb_rsp_rdata = m_icb_rsp_rdata;
	assign s_rd_icb_rsp_err = m_icb_rsp_err;
	// 握手条件: m_icb_rsp_valid & s_rd_icb_rsp_ready & arb_msg_fifo_empty_n & arb_msg_fifo_dout
	assign s_rd_icb_rsp_valid = m_icb_rsp_valid & arb_msg_fifo_empty_n & arb_msg_fifo_dout;
	
	assign s_wt_icb_rsp_rdata = m_icb_rsp_rdata;
	assign s_wt_icb_rsp_err = m_icb_rsp_err;
	// 握手条件: m_icb_rsp_valid & s_wt_icb_rsp_ready & arb_msg_fifo_empty_n & (~arb_msg_fifo_dout)
	assign s_wt_icb_rsp_valid = m_icb_rsp_valid & arb_msg_fifo_empty_n & (~arb_msg_fifo_dout);
	
	/*
	握手条件: 
		arb_msg_fifo_dout ? (
			(m_icb_rsp_valid & s_rd_icb_rsp_ready & arb_msg_fifo_empty_n):
			(m_icb_rsp_valid & s_wt_icb_rsp_ready & arb_msg_fifo_empty_n)
		)
	*/
	assign m_icb_rsp_ready = arb_msg_fifo_empty_n & (arb_msg_fifo_dout ? s_rd_icb_rsp_ready:s_wt_icb_rsp_ready);
	
	assign arb_msg_fifo_ren = m_icb_rsp_valid & (arb_msg_fifo_dout ? s_rd_icb_rsp_ready:s_wt_icb_rsp_ready);
	
endmodule
