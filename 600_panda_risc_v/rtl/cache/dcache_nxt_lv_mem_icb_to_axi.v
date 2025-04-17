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
本模块: 数据Cache下级存储器访问ICB到AXI转换

描述:
将访问下级存储器ICB从机转换成突发长度为CACHE_LINE_WORD_N的AXI主机

注意：
无

协议:
ICB SLAVE
AXI MASTER

作者: 陈家耀
日期: 2025/04/16
********************************************************************/


module dcache_nxt_lv_mem_icb_to_axi #(
	parameter integer CACHE_LINE_WORD_N = 8, // 每个缓存行的字数(1 | 2 | 4 | 8 | 16)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// 访问下级存储器ICB从机
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
	
	// 访问下级存储器AXI主机
	// AR通道
	output wire[31:0] m_axi_araddr,
	output wire[1:0] m_axi_arburst, // const -> 2'b01
	output wire[7:0] m_axi_arlen, // const -> CACHE_LINE_WORD_N - 1
	output wire[2:0] m_axi_arsize, // const -> 3'b010
	output wire m_axi_arvalid,
	input wire m_axi_arready,
	// R通道
	input wire[31:0] m_axi_rdata,
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_rresp,
	input wire m_axi_rlast,
	input wire m_axi_rvalid,
	output wire m_axi_rready,
	// AW通道
	output wire[31:0] m_axi_awaddr,
	output wire[1:0] m_axi_awburst, // const -> 2'b01
	output wire[7:0] m_axi_awlen, // const -> CACHE_LINE_WORD_N - 1
	output wire[2:0] m_axi_awsize, // const -> 3'b010
	output wire m_axi_awvalid,
	input wire m_axi_awready,
	// B通道
	// 2'b00 -> OKAY; 2'b01 -> EXOKAY; 2'b10 -> SLVERR; 2'b11 -> DECERR
	input wire[1:0] m_axi_bresp,
	input wire m_axi_bvalid,
	output wire m_axi_bready,
	// W通道
	output wire[31:0] m_axi_wdata,
	output wire[3:0] m_axi_wstrb,
	output wire m_axi_wlast,
	output wire m_axi_wvalid,
	input wire m_axi_wready
);
	
	reg[CACHE_LINE_WORD_N-1:0] icb_cmd_word_ofs; // ICB命令通道字节偏移码
	
	// ICB命令通道字节偏移码
	always @(posedge aclk or negedge )
	
endmodule
