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
本模块: 下一PC生成

描述:
静态分支预测(对于B指令) -> 
	向后跳(跳转偏移量<0)预测为跳, 向前跳(跳转偏移量>=0)预测为不跳

生成新的PC -> 
		  取指情形          新的PC
	-----------------------------------
		  预测跳转         预测地址
			冲刷           冲刷地址
		  顺序取指        PC + 自增值
		  复位释放          复位值

注意：
复位释放后的第1个clk应产生复位请求, 以将PC更新到复位值

协议:
无

作者: 陈家耀
日期: 2025/01/23
********************************************************************/


module panda_risc_v_pc_gen(
	// 当前的PC
	input wire[31:0] now_pc,
	// 复位时的PC
	input wire[31:0] rst_pc,
	
	// 复位状态
	input wire to_rst,
	// 冲刷状态
	input wire to_flush,
	input wire[31:0] flush_addr_hold,
	
	// RS1读结果
	input wire[31:0] rs1_v,
	
	// 预译码信息
	input wire inst_len_type, // 指令长度类型(1'b0 -> 16位, 1'b1 -> 32位)
	input wire is_b_inst, // 是否B指令
	input wire is_jal_inst, // 是否JAL指令
	input wire is_jalr_inst, // 是否JALR指令
	input wire[20:0] jump_ofs_imm, // 跳转偏移量立即数
	
	// 分支预测结果
	output wire to_jump, // 是否预测跳转
	
	// 新的PC
	output wire[31:0] new_pc
);
	
	/** 静态分支预测 **/
	// 对于B指令, 向后跳(跳转偏移量<0)预测为跳, 向前跳(跳转偏移量>=0)预测为不跳
	assign to_jump = (is_b_inst & jump_ofs_imm[20]) | is_jal_inst | is_jalr_inst;
	
	/** 生成预测地址的加法器的操作数 **/
	wire[31:0] prdt_pc_add_op1; // 用于生成预测地址的加法器的操作数1
	wire[31:0] prdt_pc_add_op2; // 用于生成预测地址的加法器的操作数2
	
	assign prdt_pc_add_op1 = (is_b_inst | is_jal_inst) ? now_pc:rs1_v;
	assign prdt_pc_add_op2 = {{11{jump_ofs_imm[20]}}, jump_ofs_imm}; // 对21位跳转偏移量立即数进行符号位拓展
	
	/** 生成顺序取指地址的加法器的操作数 **/
	wire[31:0] pc_self_incr_ofs; // PC自增值
	
	assign pc_self_incr_ofs = inst_len_type ? 32'd4:32'd2;
	
	/** 生成新的PC **/
	wire[31:0] pc_add_op1; // 用于生成下一PC的加法器的操作数1
	wire[31:0] pc_add_op2; // 用于生成下一PC的加法器的操作数2
	wire[31:0] pc_nxt; // 下一PC
	
	assign new_pc = to_rst ? rst_pc: // 复位请求优先级最高
					(to_flush ? flush_addr_hold: // 冲刷请求优先级次之
						pc_nxt);
	
	assign pc_add_op1 = to_jump ? prdt_pc_add_op1:now_pc;
	assign pc_add_op2 = to_jump ? prdt_pc_add_op2:pc_self_incr_ofs;
	
	/*
		   op1(32位)  +  op2(32位)
	------------------------------------
		    当前PC     跳转偏移量立即数
		  RS1读结果       PC自增值
	*/
	assign pc_nxt = pc_add_op1 + pc_add_op2;
	
endmodule
