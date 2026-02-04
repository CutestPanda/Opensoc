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
本模块: 返回地址堆栈

描述:
RAS采用寄存器组作为存储实体

若RAS满, 仍然可以压栈, 这时会覆盖最旧条目; 若RAS空, 仍然可以出栈, 这时会输出栈顶条目

RAS出栈的读延迟为0clk, 出栈数据始终为栈顶条目
RAS查询的读延迟为1clk, 查询结果为栈顶条目, 当查询指示信号无效时查询结果保持不变

注意：
若同时压栈和出栈, 则将待压栈的数据覆盖栈顶条目, 并弹出旧的栈顶条目, 而栈顶指针不变(除非栈是空的)

协议:
无

作者: 陈家耀
日期: 2026/01/21
********************************************************************/


module panda_risc_v_ras #(
	parameter integer RAS_ENTRY_WIDTH = 32, // 返回地址堆栈的条目位宽
	parameter integer RAS_ENTRY_N = 4, // 返回地址堆栈的条目数(2 | 4 | 8 | 16)
	parameter real SIM_DELAY = 1 // 仿真延时
)(
    // 时钟和复位
	input wire aclk,
	input wire aresetn,
	
	// RAS压栈
	input wire ras_push_req,
	input wire[RAS_ENTRY_WIDTH-1:0] ras_push_addr,
	
	// RAS出栈
	input wire ras_pop_req,
	output wire[RAS_ENTRY_WIDTH-1:0] ras_pop_addr,
	
	// RAS查询
	input wire ras_query_req,
	output wire[RAS_ENTRY_WIDTH-1:0] ras_query_addr
);
	
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/**
	RAS
	
	当RAS非空时:
		"RAS栈顶指针"指向的是待存入新项的空条目
		"RAS栈顶指针 - 1"指向的是栈顶条目
	当RAS空时:
		"RAS栈顶指针"指向的是待(覆盖)存入新项的栈顶条目
	**/
	reg[RAS_ENTRY_WIDTH-1:0] ras_reg_file[0:RAS_ENTRY_N-1]; // RAS存储寄存器组
	reg[clogb2(RAS_ENTRY_N-1)+1:0] ras_top_ptr; // RAS栈顶指针
	reg[clogb2(RAS_ENTRY_N-1)+1:0] ras_top_ptr_sub1; // RAS栈顶指针 - 1
	reg[clogb2(RAS_ENTRY_N-1)+1:0] ras_bot_ptr; // RAS栈底指针
	wire ras_empty; // RAS空标志
	wire ras_full; // RAS满标志
	reg[RAS_ENTRY_WIDTH-1:0] ras_query_addr_r; // RAS查询结果(输出寄存器)
	
	assign ras_pop_addr = 
		ras_reg_file[
			ras_empty ? 
				ras_top_ptr[clogb2(RAS_ENTRY_N-1):0]:
				ras_top_ptr_sub1[clogb2(RAS_ENTRY_N-1):0]
		];
	assign ras_query_addr = ras_query_addr_r;
	
	assign ras_empty = 
		ras_top_ptr == ras_bot_ptr;
	assign ras_full = 
		(ras_top_ptr[clogb2(RAS_ENTRY_N-1)+1] ^ ras_bot_ptr[clogb2(RAS_ENTRY_N-1)+1]) & 
		(ras_top_ptr[clogb2(RAS_ENTRY_N-1):0] == ras_bot_ptr[clogb2(RAS_ENTRY_N-1):0]);
	
	// RAS存储寄存器组
	genvar ras_reg_file_i;
	generate
		for(ras_reg_file_i = 0;ras_reg_file_i < RAS_ENTRY_N;ras_reg_file_i = ras_reg_file_i + 1)
		begin:ras_reg_file_blk
			always @(posedge aclk)
			begin
				if(
					ras_push_req & (
						(ras_pop_req & (~ras_empty)) ? 
							(ras_top_ptr[clogb2(RAS_ENTRY_N-1):0] == ((ras_reg_file_i + 1) % RAS_ENTRY_N)):
							(ras_top_ptr[clogb2(RAS_ENTRY_N-1):0] == ras_reg_file_i)
					)
				)
					ras_reg_file[ras_reg_file_i] <= # SIM_DELAY ras_push_addr;
			end
		end
	endgenerate
	
	// RAS栈顶指针, RAS栈顶指针 - 1
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
		begin
			ras_top_ptr <= 0;
			ras_top_ptr_sub1 <= {(clogb2(RAS_ENTRY_N-1)+2){1'b1}};
		end
		else if(ras_push_req ^ (ras_pop_req & (~ras_empty)))
		begin
			ras_top_ptr <= # SIM_DELAY ras_push_req ? (ras_top_ptr + 1):(ras_top_ptr - 1);
			ras_top_ptr_sub1 <= # SIM_DELAY ras_push_req ? (ras_top_ptr_sub1 + 1):(ras_top_ptr_sub1 - 1);
		end
	end
	
	// RAS栈底指针
	always @(posedge aclk or negedge aresetn)
	begin
		if(~aresetn)
			ras_bot_ptr <= 0;
		else if(ras_push_req & (~ras_pop_req) & ras_full)
			ras_bot_ptr <= # SIM_DELAY ras_bot_ptr + 1;
	end
	
	// RAS查询结果(输出寄存器)
	always @(posedge aclk)
	begin
		if(ras_query_req)
			ras_query_addr_r <= # SIM_DELAY 
				ras_push_req ? 
					ras_push_addr:(
						(ras_pop_req & (~ras_empty)) ? (
							ras_reg_file[(
								ras_top_ptr - 
								// (ras_top_ptr_sub1 == ras_bot_ptr) ? 1:2
								{ras_top_ptr_sub1 != ras_bot_ptr, ras_top_ptr_sub1 == ras_bot_ptr}
							) & {1'b0, {(clogb2(RAS_ENTRY_N-1)+1){1'b1}}}]
						):
						ras_pop_addr
					);
	end
	
endmodule
