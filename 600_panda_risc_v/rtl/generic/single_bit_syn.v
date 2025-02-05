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
本模块: 单bit同步器

描述:
使用寄存器链将单bit信号打n拍以消除亚稳态

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/02/04
********************************************************************/


module single_bit_syn #(
	parameter integer SYN_STAGE = 2, // 同步器级数(必须>=1)
	parameter PRESET_V = 1'b0, // 复位值
	parameter real SIM_DELAY = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire rst_n,
	
	// 单bit信号输入
	input wire single_bit_in,
	// 单bit信号输出
	output wire single_bit_out
);
	
	reg[SYN_STAGE-1:0] dffs;
	
	assign single_bit_out = dffs[SYN_STAGE-1];
	
	genvar dff_i;
	generate
		for(dff_i = 0;dff_i < SYN_STAGE;dff_i = dff_i + 1)
		begin
			always @(posedge clk or negedge rst_n)
			begin
				if(~rst_n)
					dffs[dff_i] <= PRESET_V;
				else
					dffs[dff_i] <= # SIM_DELAY (dff_i == 0) ? single_bit_in:dffs[dff_i-1];
			end
		end
	endgenerate
	
endmodule
