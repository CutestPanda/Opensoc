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
本模块: AXIS数据包统计(同步)

描述: 
统计AXIS接口上的数据包个数, 以实现AXIS数据fifo的数据包模式
有数据包或者fifo满时主机可以输出

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/09/17
********************************************************************/


module axis_packet_stat_sync #(
	parameter fifo_depth = 32, // fifo深度(必须为16|32|64|128...)
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// AXIS从机
	input wire s_axis_last,
	input wire s_axis_valid,
	input wire s_axis_ready,
	
	// AXIS主机
	input wire m_axis_last,
	input wire m_axis_valid,
	input wire m_axis_ready,
	
	// 主机输出使能
	output wire master_oen
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
        for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
			bit_depth = bit_depth >> 1;
    end
    endfunction
	
	/** 数据包计数 **/
	reg[clogb2(fifo_depth):0] packet_n_cnt; // 数据包个数(计数器)
	reg no_packet; // 没有数据包(标志)
	wire packet_wen; // 写入一个数据包(指示)
	wire packet_ren; // 读取一个数据包(指示)
	
	assign master_oen = (~no_packet) | (~s_axis_ready); // 有数据包或者fifo满
	
	assign packet_wen = s_axis_valid & s_axis_ready & s_axis_last;
	assign packet_ren = m_axis_valid & m_axis_ready & m_axis_last;
	
	// 数据包个数(计数器)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			packet_n_cnt <= 0;
		else if(packet_wen ^ packet_ren)
			packet_n_cnt <= # simulation_delay packet_wen ? (packet_n_cnt + 1):(packet_n_cnt - 1);
	end
	
	// 没有数据包(标志)
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			no_packet <= 1'b1;
		else if(packet_wen ^ packet_ren)
			no_packet <= # simulation_delay packet_wen ? 1'b0:(packet_n_cnt == 1);
	end
	
endmodule
