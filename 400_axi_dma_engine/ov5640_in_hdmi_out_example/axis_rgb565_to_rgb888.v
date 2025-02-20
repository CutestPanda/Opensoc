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
本模块: AXIS RGB565转RGB888

描述:
{g[2:0], r[4:0], b[4:0], g[5:3]} -> {r[7:0], g[7:0], b[7:0]}

注意：
无

协议:
AXIS MASTER/SLAVE

作者: 陈家耀
日期: 2025/02/19
********************************************************************/


module axis_rgb565_to_rgb888(
	// AXIS时钟和复位
	input wire axis_aclk,
	input wire axis_aresetn,
	
	// RGB565像素流(AXIS从机)
	input wire[15:0] s_rgb565_axis_data,
    input wire s_rgb565_axis_last, // 行尾标志
    input wire s_rgb565_axis_valid,
    output wire s_rgb565_axis_ready,
	
	// RGB888像素流(AXIS从机)
	output wire[23:0] m_rgb888_axis_data,
    output wire m_rgb888_axis_last, // 行尾标志
    output wire m_rgb888_axis_valid,
    input wire m_rgb888_axis_ready
);
	
	wire[7:0] r;
	wire[7:0] g;
	wire[7:0] b;
	
	assign m_rgb888_axis_data = {r, g, b};
	assign m_rgb888_axis_last = s_rgb565_axis_last;
	assign m_rgb888_axis_valid = s_rgb565_axis_valid;
	assign s_rgb565_axis_ready = m_rgb888_axis_ready;
	
	assign {g[4:2], r[7:3], b[7:3], g[7:5]} = s_rgb565_axis_data;
	assign r[2:0] = 3'b000;
	assign g[1:0] = 2'b00;
	assign b[2:0] = 3'b000;
	
endmodule
