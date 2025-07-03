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
本模块: 写回单元

描述:
简单的写回逻辑
纯组合逻辑模块

注意：
无

协议:
无

作者: 陈家耀
日期: 2025/06/26
********************************************************************/


module panda_risc_v_wbck #(
	parameter integer FU_RES_WIDTH = 32 // 执行单元结果位宽(正整数)
)(
	// 准备退休的ROB项
	input wire[4:0] rob_prep_rtr_entry_rd_id, // 目的寄存器编号
	input wire rob_prep_rtr_entry_is_csr_rw_inst, // 是否CSR读写指令
	input wire rob_prep_rtr_entry_cancel, // 取消标志
	input wire[FU_RES_WIDTH-1:0] rob_prep_rtr_entry_fu_res, // 保存的执行结果
	input wire[11:0] rob_prep_rtr_entry_csr_rw_waddr, // CSR写地址
	input wire[1:0] rob_prep_rtr_entry_csr_rw_upd_type, // CSR更新类型
	input wire[31:0] rob_prep_rtr_entry_csr_rw_upd_mask_v, // CSR更新掩码或更新值
	
	// 退休阶段ROB记录广播
	input wire rob_rtr_bdcst_vld, // 广播有效
	input wire rob_rtr_bdcst_excpt_proc_grant, // 异常处理许可
	
	// 通用寄存器堆写端口
	output wire reg_file_wen,
	output wire[4:0] reg_file_waddr,
	output wire[31:0] reg_file_din,
	
	// CSR写端口
	output wire[11:0] csr_atom_waddr, // CSR写地址
	output wire[1:0] csr_atom_upd_type, // CSR更新类型
	output wire[31:0] csr_atom_upd_mask_v, // CSR更新掩码或更新值
	output wire csr_atom_wen // CSR写使能
);
	
	assign reg_file_wen = 
		rob_rtr_bdcst_vld & (~rob_prep_rtr_entry_cancel) & (~rob_rtr_bdcst_excpt_proc_grant);
	assign reg_file_waddr = rob_prep_rtr_entry_rd_id;
	assign reg_file_din = rob_prep_rtr_entry_fu_res[31:0];
	
	assign csr_atom_waddr = rob_prep_rtr_entry_csr_rw_waddr;
	assign csr_atom_upd_type = rob_prep_rtr_entry_csr_rw_upd_type;
	assign csr_atom_upd_mask_v = rob_prep_rtr_entry_csr_rw_upd_mask_v;
	assign csr_atom_wen = 
		rob_rtr_bdcst_vld & (~rob_prep_rtr_entry_cancel) & (~rob_rtr_bdcst_excpt_proc_grant) & 
		rob_prep_rtr_entry_is_csr_rw_inst;
	
endmodule
