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
本模块: 基于握手的跨时钟域数据接收

描述:
接收数据到某个时钟域

注意：
固定使用2级同步器

协议:
无

作者: 陈家耀
日期: 2025/01/30
********************************************************************/


module cdc_rx #(
	parameter integer DATA_WIDTH = 32, // 数据位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 握手从机
	/*
	The 4-phases handshake interface at in-side
	
	There are 4 steps required for a full transaction.
		(1) The i_vld is asserted high
		(2) The i_rdy is asserted high
		(3) The i_vld is asserted low
		(4) The i_rdy is asserted low
	*/
	input wire[DATA_WIDTH-1:0] i_dat,
	input wire i_vld_a,
	output wire i_rdy,
	
	// 握手主机
	output wire[DATA_WIDTH-1:0] o_dat,
	output wire o_vld,
	input wire o_rdy
);
	
	/** 两级同步器 **/
	reg i_vld_a_d; // 延迟1clk的前向有效标志
	reg i_vld_sync; // 延迟2clk的前向有效标志
	
	// 延迟1~2clk的前向有效标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{i_vld_sync, i_vld_a_d} <= 2'b00;
		else
			{i_vld_sync, i_vld_a_d} <= # SIM_DELAY {i_vld_a_d, i_vld_a};
	end
	
	/** 后向应答 **/
	reg i_vld_sync_r; // 延迟3clk的前向有效标志
	wire i_vld_sync_nedge; // 在前级有效标志检测到下降沿
	wire buf_rdy; // 输出数据缓存就绪标志
	reg i_rdy_r; // 前级就绪标志
	wire i_rdy_set;
	wire i_rdy_clr;
	
	assign i_rdy = i_rdy_r;
	
	assign i_vld_sync_nedge = (~i_vld_sync) & i_vld_sync_r;
	
	/*
	Because it is a 4-phases handshake, so 
		The i_rdy is set (assert to high) when the buf is ready (can save data) and incoming valid detected
		The i_rdy is clear when i_vld neg-edge is detected
	*/
	assign i_rdy_set = buf_rdy & i_vld_sync & (~i_rdy_r);
	assign i_rdy_clr = i_vld_sync_nedge;
	
	// 延迟3clk的前向有效标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			i_vld_sync_r <= 1'b0;
		else
			i_vld_sync_r <= # SIM_DELAY i_vld_sync;
	end
	
	// 前级就绪标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			i_rdy_r <= 1'b0;
		else if(i_rdy_set | i_rdy_clr)
			i_rdy_r <= # SIM_DELAY i_rdy_set | (~i_rdy_clr);
	end
	
	/** 前向传递 **/
	reg[DATA_WIDTH-1:0] buf_dat_r; // 后级数据
	reg buf_vld_r; // 后级有效标志
	wire buf_dat_ena;
	wire buf_vld_set;
	wire buf_vld_clr;
	
	assign o_dat = buf_dat_r;
	assign o_vld = buf_vld_r;
	
	assign buf_rdy = ~buf_vld_r; // The buf is ready when the buf is empty
	
	assign buf_dat_ena = i_rdy_set; // The buf is loaded with data when i_rdy is set high (i.e., 
	                                //     when the buf is ready (can save data) and incoming valid detected)
	assign buf_vld_set = buf_dat_ena; // The buf_vld is set when the buf is loaded with data
	assign buf_vld_clr = o_vld & o_rdy; // The buf_vld is clr when the buf is handshaked at the out-end
	
	// 后级数据
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buf_dat_r <= {DATA_WIDTH{1'b0}};
		else if(buf_dat_ena)
			buf_dat_r <= # SIM_DELAY i_dat;
	end
	
	// 后级有效标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			buf_vld_r <= 1'b0;
		else if(buf_vld_set | buf_vld_clr)
			buf_vld_r <= # SIM_DELAY buf_vld_set | (~buf_vld_clr);
	end
	
endmodule
