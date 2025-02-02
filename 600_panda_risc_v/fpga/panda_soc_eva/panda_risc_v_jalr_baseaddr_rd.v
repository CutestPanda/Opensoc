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
本模块: 读JALR指令基址

描述:
从专用于JALR指令的通用寄存器堆读端口获取基址

     RS1编号                 操作
        x0                 直接返回
	    x1             无RAW相关性时返回
	  x2~x31   无RAW相关性时请求通用寄存器堆读端口#0, 
			           等待读许可后返回

注意：
无

协议:
REQ/GRANT

作者: 陈家耀
日期: 2024/10/28
********************************************************************/


module panda_risc_v_jalr_baseaddr_rd #(
	parameter real simulation_delay = 1 // 仿真延时
)(
	// 时钟和复位
	input wire clk,
	input wire resetn,
	
	// 复位/冲刷状态
	input wire to_rst, // 当前正在复位
	input wire to_flush, // 当前正在冲刷
	
	// 数据相关性
	input wire rs1_raw_dpc, // RS1有RAW相关性(标志)
	
	// RS1索引
	input wire[4:0] rs1_id,
	
	// 专用于JALR指令的通用寄存器堆读端口
	input wire[31:0] jalr_x1_v, // 通用寄存器#1读结果
	// JALR指令读基址给出的通用寄存器堆读端口#0
	output wire jalr_reg_file_rd_p0_req, // 读请求
	output wire[4:0] jalr_reg_file_rd_p0_addr, // 读地址
	input wire jalr_reg_file_rd_p0_grant, // 读许可
	input wire[31:0] jalr_reg_file_rd_p0_dout, // 读数据
	
	// JALR指令基址获取控制/状态
	input wire vld_inst_gotten, // 获取到有效的指令(指示)
	input wire is_jalr_inst, // 是否JALR指令
	output wire jalr_baseaddr_vld, // JALR指令基址读完成(指示)
	output wire[31:0] jalr_baseaddr_v // 基址读结果
);
	
	/** 通用寄存器读端口#0 **/
	wire now_inst_need_baseaddr_from_p0; // 当前指令需要从通用寄存器读端口#0获取基址
	reg to_continue_req_for_reg_file_rd_p0; // 继续请求通用寄存器读端口#0
	
	assign jalr_reg_file_rd_p0_req = 
		(~(to_rst | to_flush)) & 
		(vld_inst_gotten | to_continue_req_for_reg_file_rd_p0) & 
		now_inst_need_baseaddr_from_p0 & (~rs1_raw_dpc);
	assign jalr_reg_file_rd_p0_addr = rs1_id;
	
	assign now_inst_need_baseaddr_from_p0 = is_jalr_inst & (rs1_id != 5'd0) & (rs1_id != 5'd1);
	
	// 继续请求通用寄存器读端口#0
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_continue_req_for_reg_file_rd_p0 <= 1'b0;
		else
			/*
			(~(to_rst | to_flush)) & // 处于复位/冲刷状态时中断请求
			(to_continue_req_for_reg_file_rd_p0 ? 
				(~jalr_reg_file_rd_p0_grant): // 等待读许可
				(vld_inst_gotten & now_inst_need_baseaddr_from_p0
					& (~jalr_reg_file_rd_p0_grant))) // 需要从通用寄存器读端口#0获取基址但不被立即许可, 则延长请求信号
			*/
			to_continue_req_for_reg_file_rd_p0 <= # simulation_delay 
				(~(to_rst | to_flush)) & 
				(to_continue_req_for_reg_file_rd_p0 | (vld_inst_gotten & now_inst_need_baseaddr_from_p0)) & 
				(~jalr_reg_file_rd_p0_grant);
	end
	
	/** 读通用寄存器#1 **/
	wire now_inst_need_baseaddr_from_x1; // 当前指令需要从通用寄存器#1获取基址
	reg to_continue_rd_x1; // 继续读通用寄存器#1
	
	assign now_inst_need_baseaddr_from_x1 = is_jalr_inst & (rs1_id == 5'd1);
	
	// 继续读通用寄存器#1
	always @(posedge clk or negedge resetn)
	begin
		if(~resetn)
			to_continue_rd_x1 <= 1'b0;
		else
			/*
			(~(to_rst | to_flush)) & // 处于复位/冲刷状态时中断请求
			(to_continue_rd_x1 ? 
				rs1_raw_dpc: // 等待RAW相关性解除
				(vld_inst_gotten & now_inst_need_baseaddr_from_x1
					& rs1_raw_dpc)) // 需要从通用寄存器#1获取基址但存在RAW相关性, 则继续读
			*/
			to_continue_rd_x1 <= # simulation_delay 
				(~(to_rst | to_flush)) & 
				(to_continue_rd_x1 | (vld_inst_gotten & now_inst_need_baseaddr_from_x1)) & rs1_raw_dpc;
	end
	
	/** JALR指令基址读结果 **/
	// 提示:可以把jalr_baseaddr_vld和jalr_baseaddr_v打1拍以改善时序, 只导致些许的取指性能损失!
	assign jalr_baseaddr_vld = 
		(~(to_rst | to_flush)) & 
		(vld_inst_gotten | to_continue_req_for_reg_file_rd_p0 | to_continue_rd_x1)
		& is_jalr_inst
		& (
			(rs1_id == 5'd0) | 
			((rs1_id == 5'd1) ? (~rs1_raw_dpc):
				jalr_reg_file_rd_p0_grant)
		);
	assign jalr_baseaddr_v = {32{rs1_id != 5'd0}} & (
		(rs1_id == 5'd1) ? jalr_x1_v:
			jalr_reg_file_rd_p0_dout
	);
	
endmodule
