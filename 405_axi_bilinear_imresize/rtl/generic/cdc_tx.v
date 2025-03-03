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
本模块: 基于握手的跨时钟域数据发送

描述:
从某个时钟域发送数据出去

注意：
固定使用2级同步器

协议:
无

作者: 陈家耀
日期: 2025/01/30
********************************************************************/


module cdc_tx #(
	parameter integer DATA_WIDTH = 32, // 数据位宽
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 握手从机
	input wire[DATA_WIDTH-1:0] i_dat,
	input wire i_vld,
	output wire i_rdy,
	
	// 握手主机
	/*
	The 4-phases handshake interface at out-side
	
	There are 4 steps required for a full transaction.
		(1) The i_vld is asserted high
		(2) The i_rdy is asserted high
		(3) The i_vld is asserted low
		(4) The i_rdy is asserted low
	*/
	output wire[DATA_WIDTH-1:0] o_dat,
	output wire o_vld,
	input wire o_rdy_a
);
	
	/** 两级同步器 **/
	reg o_rdy_a_d; // 延迟1clk的后级就绪标志
	reg o_rdy_sync; // 延迟2clk的后级就绪标志
	
	// 延迟1~2clk的后级就绪标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			{o_rdy_sync, o_rdy_a_d} <= 2'b00;
		else
			{o_rdy_sync, o_rdy_a_d} <= # SIM_DELAY {o_rdy_a_d, o_rdy_a};
	end
	
	/** 前向传递 **/
	reg[DATA_WIDTH-1:0] dat_r; // 后级数据
	reg vld_r; // 后级有效标志
	wire vld_set;
	wire vld_clr;
	
	assign o_dat = dat_r;
	assign o_vld = vld_r;
	
	assign vld_set = i_vld & i_rdy; // Valid set when it is handshaked
	assign vld_clr = o_vld & o_rdy_sync; // Valid clr when the TX o_rdy is high
	
	// 后级数据
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			dat_r <= {DATA_WIDTH{1'b0}};
		else if(vld_set)
			dat_r <= # SIM_DELAY i_dat;
	end
	
	// 后级有效标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			vld_r <= 1'b0;
		else if(vld_set | vld_clr)
			vld_r <= # SIM_DELAY vld_set | (~vld_clr);
	end
	
	/** 后向应答 **/
	reg o_rdy_sync_r; // 延迟3clk的后级就绪标志
	wire o_rdy_nedge; // 在后级就绪标志检测到下降沿
	reg nrdy_r; // Not-ready indication
	wire nrdy_set;
	wire nrdy_clr;
	
	assign i_rdy = (~nrdy_r) | nrdy_clr; // The input is ready when the Not-ready indication is low or under clearing
	
	assign o_rdy_nedge = (~o_rdy_sync) & o_rdy_sync_r; // Detect the neg-edge
	
	assign nrdy_set = vld_set; // Not-ready is set when the vld_r is set
	assign nrdy_clr = o_rdy_nedge; // Not-ready is clr when the o_rdy neg-edge is detected
	
	// 延迟3clk的后级就绪标志
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			o_rdy_sync_r <= 1'b0;
		else
			o_rdy_sync_r <= # SIM_DELAY o_rdy_sync;
	end
	
	// Not-ready indication
	always @(posedge clk or negedge rst_n)
	begin
		if(~rst_n)
			nrdy_r <= 1'b0;
		else if(nrdy_set | nrdy_clr)
			nrdy_r <= # SIM_DELAY nrdy_set | (~nrdy_clr);
	end
	
endmodule
