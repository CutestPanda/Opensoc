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
本模块: 通用寄存器堆

描述:
32个32位的通用寄存器

通用寄存器#0只读且恒为32'h0000_0000

注意：
无

协议:
无

作者: 陈家耀
日期: 2024/12/09
********************************************************************/


module panda_risc_v_reg_file #(
    parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟
	input wire clk,
	
	// 通用寄存器堆写端口
	input wire reg_file_wen,
	input wire[4:0] reg_file_waddr,
	input wire[31:0] reg_file_din,
	
	// 通用寄存器堆读端口#0
	input wire[4:0] reg_file_raddr_p0,
	output wire[31:0] reg_file_dout_p0,
	// 通用寄存器堆读端口#1
	input wire[4:0] reg_file_raddr_p1,
	output wire[31:0] reg_file_dout_p1,
	
	// 通用寄存器#1的值
	output wire[31:0] x1_v
);
	
    /** 通用寄存器堆 **/
	wire[31:0] generic_reg_file[0:31];
	
	assign reg_file_dout_p0 = generic_reg_file[reg_file_raddr_p0];
	assign reg_file_dout_p1 = generic_reg_file[reg_file_raddr_p1];
	assign x1_v = generic_reg_file[1];
	
	genvar generic_reg_i;
	generate
		for(generic_reg_i = 0;generic_reg_i < 32;generic_reg_i = generic_reg_i + 1)
		begin
			if(generic_reg_i == 0)
			begin
				assign generic_reg_file[generic_reg_i] = 32'h0000_0000;
			end
			else
			begin
				reg[31:0] generic_reg;
				
				assign generic_reg_file[generic_reg_i] = generic_reg;
				
				always @(posedge clk)
				begin
					if(reg_file_wen & (reg_file_waddr == generic_reg_i))
						generic_reg <= # simulation_delay reg_file_din;
				end
			end
		end
	endgenerate
	
endmodule
